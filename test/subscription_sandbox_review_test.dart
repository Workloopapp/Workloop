import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/subscription/store_purchase_service.dart';
import 'package:workloop/features/subscription/subscription_access.dart';
import 'package:workloop/features/subscription/subscription_gate.dart';
import 'package:workloop/features/subscription/subscription_plan_widgets.dart';
import 'package:workloop/features/subscription/subscription_screen.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';

import 'support/subscription_fakes.dart';

final _now = DateTime.utc(2026, 9, 12);
final _trialEnd = DateTime.utc(2026, 10, 12);

Map<String, dynamic> _payload({
  bool tester = true,
  bool access = true,
  String? environment = 'Sandbox',
  DateTime? permissionEnd,
}) => {
  'state': access
      ? environment == 'Production'
            ? 'subscribed'
            : 'store_trial'
      : 'trial_available',
  'has_access': access,
  'server_now': _now.toIso8601String(),
  'trial_ends_at': access && environment == 'Sandbox'
      ? _trialEnd.toIso8601String()
      : null,
  'paid_until': access ? (permissionEnd ?? _trialEnd).toIso8601String() : null,
  'product_id': access ? WorkloopPlans.monthlyId : null,
  'platform': access ? 'apple' : null,
  'auto_renews': access ? true : null,
  'apple_sales_enabled': tester,
  'is_sandbox_tester': tester,
  'sandbox_test_expires_at': tester
      ? (permissionEnd ?? _trialEnd).toIso8601String()
      : null,
  'store_environment': environment,
  'billing_reminders_enabled': false,
};

void _iosTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _networkPump(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await _pump(tester);
    await tester.runAsync(flushStoreEvents);
  }
  await _pump(tester);
}

void main() {
  test(
    'review permission is separate from signed store environment and access',
    () {
      final permission = SubscriptionAccess.fromJson(
        _payload(access: false, environment: null),
      );
      expect(permission.isSandboxTester, isTrue);
      expect(permission.sandboxTestExpiresAt, _trialEnd);
      expect(permission.appleSalesEnabled, isTrue);
      expect(permission.hasAccess, isFalse);
      expect(permission.isSandboxSubscription, isFalse);
      final sandbox = SubscriptionAccess.fromJson(_payload());
      expect(sandbox.hasAccess, isTrue);
      expect(sandbox.isSandboxSubscription, isTrue);
      final production = SubscriptionAccess.fromJson(
        _payload(environment: 'Production'),
      );
      expect(production.isSandboxTester, isTrue);
      expect(production.storeEnvironment, 'Production');
      expect(production.isSandboxSubscription, isFalse);
    },
  );

  test('older access responses stay compatible without review metadata', () {
    final old = SubscriptionAccess.fromJson({
      'state': 'subscribed',
      'has_access': true,
      'server_now': _now.toIso8601String(),
      'paid_until': _trialEnd.toIso8601String(),
    });
    expect(old.isSandboxTester, isFalse);
    expect(old.sandboxTestExpiresAt, isNull);
    expect(old.storeEnvironment, isNull);
    expect(old.isSandboxSubscription, isFalse);
  });

  for (final invalid in [
    'sandbox',
    'Xcode',
    'unknown',
    1,
    <String, dynamic>{},
  ]) {
    test('unexpected store environment $invalid fails closed', () {
      expect(
        () => SubscriptionAccess.fromJson({
          ..._payload(),
          'store_environment': invalid,
        }),
        throwsFormatException,
      );
    });
  }

  test('invalid permission expiry is not silently accepted', () {
    expect(
      () => SubscriptionAccess.fromJson({
        ..._payload(),
        'sandbox_test_expires_at': 'not-a-date',
      }),
      throwsFormatException,
    );
  });

  for (final environment in ['Sandbox', 'Production']) {
    _iosTest(
      'status identifies actual $environment even on an authorised tester account',
      (tester) async {
        final access = SubscriptionAccess.fromJson(
          _payload(environment: environment),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SubscriptionStatusCard(
                  access: access,
                  product: subscriptionProduct(),
                ),
              ),
            ),
          ),
        );
        await _pump(tester);
        if (environment == 'Sandbox') {
          expect(find.text('TEST SUBSCRIPTION'), findsOneWidget);
          expect(find.text('Apple Sandbox purchase'), findsOneWidget);
          expect(
            find.textContaining('No real payment was taken.'),
            findsOneWidget,
          );
          expect(find.textContaining('Test access ends on'), findsOneWidget);
          expect(find.textContaining('To avoid a charge'), findsNothing);
          expect(find.textContaining('Current monthly price:'), findsNothing);
        } else {
          expect(find.text('Apple Sandbox purchase'), findsNothing);
          expect(
            find.textContaining('No real payment was taken.'),
            findsNothing,
          );
          expect(
            find.textContaining('Current monthly price: £14.99.'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  late SubscriptionBackend backend;
  late FakeSubscriptionStore native;
  StorePurchaseService? service;
  setUp(() async {
    backend = SubscriptionBackend();
    await backend.account();
    native = FakeSubscriptionStore();
    service = null;
  });
  tearDown(() async {
    service?.dispose();
    await native.events.close();
    await backend.client.dispose();
  });

  ProviderContainer createProviders({
    FutureOr<SubscriptionAccess> Function()? access,
  }) {
    late ProviderContainer providers;
    service = StorePurchaseService(
      backend.client,
      subscriptionUser,
      onVerified: () =>
          providers.invalidate(subscriptionAccessProvider(subscriptionUser)),
      store: native,
    );
    providers = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(backend.client),
        storePurchaseServiceProvider(
          subscriptionUser,
        ).overrideWithValue(service!),
        if (access != null)
          subscriptionAccessProvider(
            subscriptionUser,
          ).overrideWith((ref) => access()),
      ],
    );
    return providers;
  }

  Widget app(ProviderContainer providers, {Widget? child}) =>
      UncontrolledProviderScope(
        container: providers,
        child: MaterialApp(
          theme: AppTheme.light,
          home:
              child ??
              const SubscriptionGate(
                userId: subscriptionUser,
                child: Scaffold(body: Text('Verified business records')),
              ),
        ),
      );

  _iosTest(
    'testing permission does not promise free payment before native confirmation',
    (tester) async {
      final c = createProviders(
        access: () => SubscriptionAccess.fromJson(
          _payload(access: false, environment: null),
        ),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(c, child: const SubscriptionScreen(canClose: false)),
      );
      await _pump(tester);
      await tester.scrollUntilVisible(
        find.byType(SubscriptionOfferCard),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('£14.99 / month'), findsOneWidget);
      expect(find.text('Continue with monthly plan'), findsOneWidget);
      expect(find.textContaining('No real payment'), findsNothing);
      expect(find.text('Apple Sandbox purchase'), findsNothing);
      expect(find.text('1 month free'), findsNothing);
      expect(native.queries, 1);
    },
  );

  for (final allowed in [true, false]) {
    _iosTest(
      'verified Sandbox receipt ${allowed ? 'opens allowed review account' : 'cannot override denied server access'}',
      (tester) async {
        var confirmed = false;
        backend.respond = (request) {
          if (request.url.path == '/functions/v1/workloop-subscription') {
            confirmed = true;
            return jsonResponse({'verified': true, 'environment': 'Sandbox'});
          }
          if (request.url.path == '/rest/v1/rpc/get_workloop_access') {
            return jsonResponse(
              _payload(
                tester: allowed,
                access: confirmed && allowed,
                environment: confirmed && allowed ? 'Sandbox' : null,
              ),
            );
          }
          throw StateError('Unexpected request: ${request.url.path}');
        };
        final c = createProviders();
        addTearDown(c.dispose);
        await tester.pumpWidget(app(c));
        await _networkPump(tester);
        expect(find.text('Verified business records'), findsNothing);
        native.events.add([subscriptionPurchase()]);
        await _networkPump(tester);
        expect(native.completions, hasLength(1));
        expect(
          service!.state.value.message,
          contains('Test purchase verified'),
        );
        expect(
          find.text('Verified business records'),
          allowed ? findsOneWidget : findsNothing,
        );
        expect(
          c.read(subscriptionAccessProvider(subscriptionUser)).value!.hasAccess,
          allowed,
        );
        if (allowed) {
          expect(
            c
                .read(subscriptionAccessProvider(subscriptionUser))
                .value!
                .isSandboxSubscription,
            isTrue,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  _iosTest(
    'restore retains Production access selected by server despite Sandbox callback',
    (tester) async {
      backend.respond = (request) => jsonResponse(
        request.url.path == '/functions/v1/workloop-subscription'
            ? {'verified': true, 'environment': 'Sandbox'}
            : _payload(environment: 'Production'),
      );
      final c = createProviders();
      addTearDown(c.dispose);
      native.restored = [subscriptionPurchase(status: PurchaseStatus.restored)];
      await tester.pumpWidget(app(c));
      await _networkPump(tester);
      final restoring = service!.restore();
      await _networkPump(tester);
      await restoring;
      expect(native.completions, hasLength(1));
      final access = c
          .read(subscriptionAccessProvider(subscriptionUser))
          .value!;
      expect(access.storeEnvironment, 'Production');
      expect(access.isSandboxSubscription, isFalse);
      expect(find.text('Verified business records'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _iosTest(
    'permission expiry closes Sandbox access at server cap before Apple trial ends',
    (tester) async {
      final cappedEnd = _now.add(const Duration(seconds: 2));
      final recheck = Completer<SubscriptionAccess>();
      var calls = 0;
      final c = createProviders(
        access: () => ++calls == 1
            ? SubscriptionAccess.fromJson(
                _payload(permissionEnd: cappedEnd),
                elapsedSinceCheck: Stopwatch(),
              )
            : recheck.future,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      expect(find.text('Verified business records'), findsOneWidget);
      expect(
        c.read(subscriptionAccessProvider(subscriptionUser)).value!.trialEndsAt,
        _trialEnd,
      );
      await tester.pump(const Duration(seconds: 3));
      await _pump(tester);
      expect(calls, 2);
      final guard = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(SubscriptionGate),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(guard.ignoring, isTrue);
      recheck.complete(
        SubscriptionAccess.fromJson(
          _payload(tester: false, access: false, environment: null),
        ),
      );
      await _pump(tester);
      expect(
        find.text('Verified business records').hitTestable(),
        findsNothing,
      );
      expect(find.byType(SubscriptionScreen), findsOneWidget);
    },
  );

  _iosTest(
    'resume reflects revoked Sandbox permission without a client fallback',
    (tester) async {
      var allowed = true;
      backend.respond = (_) => jsonResponse(
        _payload(
          tester: allowed,
          access: allowed,
          environment: allowed ? 'Sandbox' : null,
        ),
      );
      final c = createProviders();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _networkPump(tester);
      expect(find.text('Verified business records'), findsOneWidget);
      allowed = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _networkPump(tester);
      expect(
        find.text('Verified business records').hitTestable(),
        findsNothing,
      );
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      expect(
        c.read(subscriptionAccessProvider(subscriptionUser)).value!.hasAccess,
        isFalse,
      );
    },
  );
}
