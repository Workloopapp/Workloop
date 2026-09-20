import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/widgets/settings_account_tab.dart';
import 'package:workloop/features/subscription/store_purchase_service.dart';
import 'package:workloop/features/subscription/subscription_access.dart';
import 'package:workloop/features/subscription/subscription_gate.dart';
import 'package:workloop/features/subscription/subscription_screen.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';

import 'support/subscription_fakes.dart';

SubscriptionAccess _access(
  String state, {
  bool sales = false,
  int seconds = 3600,
}) => SubscriptionAccess(
  state: state,
  hasAccess: state != 'expired',
  serverNow: DateTime.utc(2026, 9, 7),
  trialEndsAt: state == 'trial'
      ? DateTime.utc(2026, 9, 7).add(Duration(seconds: seconds))
      : null,
  paidUntil: state == 'subscribed'
      ? DateTime.utc(2026, 9, 7).add(Duration(seconds: seconds))
      : null,
  appleSalesEnabled: sales,
  productId: state == 'subscribed' ? WorkloopPlans.monthlyId : null,
  platform: state == 'subscribed' ? 'apple' : null,
);

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _reach(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await _pump(tester);
}

Future<void> _networkPump(WidgetTester tester) async {
  // The real Supabase client was initialised by setUp outside the widget clock;
  // allow its HTTP stream work and the widget microtasks to alternate.
  for (var i = 0; i < 4; i++) {
    await _pump(tester);
    await tester.runAsync(flushStoreEvents);
  }
  await _pump(tester);
}

void main() {
  late SubscriptionBackend backend;
  late FakeSubscriptionStore store;
  late StorePurchaseService service;
  setUp(() async {
    backend = SubscriptionBackend();
    await backend.account();
    store = FakeSubscriptionStore();
    service = StorePurchaseService(
      backend.client,
      subscriptionUser,
      onVerified: () {},
      store: store,
    );
  });
  tearDown(() async {
    service.dispose();
    await store.events.close();
    await backend.client.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  void freshService() {
    service.dispose();
    service = StorePurchaseService(
      backend.client,
      subscriptionUser,
      onVerified: () {},
      store: store,
    );
  }

  ProviderContainer container(FutureOr<SubscriptionAccess> Function() load) {
    freshService();
    return ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(backend.client),
        subscriptionAccessProvider(
          subscriptionUser,
        ).overrideWith((ref) => load()),
        storePurchaseServiceProvider(
          subscriptionUser,
        ).overrideWithValue(service),
      ],
    );
  }

  Widget app(ProviderContainer container, Widget child, {double scale = 1}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        ),
      );

  test('access parser rejects an unknown state or missing explicit access', () {
    for (final data in [
      {
        'state': 'forged',
        'has_access': true,
        'server_now': '2026-09-07T00:00:00Z',
      },
      {'state': 'subscribed', 'server_now': '2026-09-07T00:00:00Z'},
    ]) {
      expect(() => SubscriptionAccess.fromJson(data), throwsFormatException);
    }
    expect(_access('trial', seconds: 1).trialDaysRemaining, 1);
    expect(_access('trial', seconds: 30 * 86400).trialDaysRemaining, 30);
    expect(_access('trial', seconds: -1).trialDaysRemaining, 0);
  });

  test(
    'access repository rejects an account change while the RPC is outstanding',
    () async {
      final c = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(backend.client)],
      );
      addTearDown(c.dispose);
      final httpResponse = Completer<void>();
      backend.respond = (_) async {
        await httpResponse.future;
        return jsonResponse({
          'state': 'beta_lifetime',
          'has_access': true,
          'server_now': '2026-09-07T00:00:00Z',
        });
      };
      final access = c.read(
        subscriptionAccessProvider(subscriptionUser).future,
      );
      // Install the rejection matcher before resolving the pending HTTP request.
      final assertion = expectLater(access, throwsStateError);
      await flushStoreEvents();
      await backend.account(otherSubscriptionUser);
      httpResponse.complete();
      await assertion;
    },
  );

  testWidgets(
    'initial loading and retry errors never mount private records',
    (tester) async {
      final pending = Completer<SubscriptionAccess>();
      var calls = 0;
      final c = container(
        () => ++calls == 1 ? pending.future : _access('beta_lifetime'),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          c,
          const SubscriptionGate(
            userId: subscriptionUser,
            child: Scaffold(body: Text('Private records')),
          ),
        ),
      );
      expect(find.text('Private records'), findsNothing);
      pending.completeError(StateError('network offline'));
      await _pump(tester);
      expect(find.text('Private records'), findsNothing);
      expect(find.text('Manage account or sign out'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await _pump(tester);
      expect(find.text('Private records'), findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'cached trial access expires while open and blocks stale content during refresh',
    (tester) async {
      final pending = Completer<SubscriptionAccess>();
      var calls = 0, taps = 0;
      final c = container(
        () => ++calls == 1 ? _access('trial', seconds: 2) : pending.future,
      );
      addTearDown(c.dispose);
      await c.read(subscriptionAccessProvider(subscriptionUser).future);
      await tester.pumpWidget(
        app(
          c,
          SubscriptionGate(
            userId: subscriptionUser,
            child: Scaffold(
              body: TextButton(
                onPressed: () => taps++,
                child: const Text('Private records'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Private records'));
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 3));
      await _pump(tester);
      expect(calls, 2);
      final guarded = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(SubscriptionGate),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(guarded.ignoring, isTrue);
      pending.complete(_access('expired'));
      await _pump(tester);
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      await _reach(tester, find.text('Export data or delete account'));
      expect(find.text('Export data or delete account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a user change discards the previous account subtree before new access resolves',
    (tester) async {
      freshService();
      final next = Completer<SubscriptionAccess>();
      final c = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(backend.client),
          subscriptionAccessProvider(
            subscriptionUser,
          ).overrideWith((ref) => _access('beta_lifetime')),
          subscriptionAccessProvider(
            otherSubscriptionUser,
          ).overrideWith((ref) => next.future),
          storePurchaseServiceProvider(
            subscriptionUser,
          ).overrideWithValue(service),
          storePurchaseServiceProvider(
            otherSubscriptionUser,
          ).overrideWithValue(service),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          c,
          const SubscriptionGate(
            userId: subscriptionUser,
            child: Scaffold(body: Text('First owner records')),
          ),
        ),
      );
      await _pump(tester);
      expect(find.text('First owner records'), findsOneWidget);
      await backend.account(otherSubscriptionUser);
      await tester.pumpWidget(
        app(
          c,
          const SubscriptionGate(
            userId: otherSubscriptionUser,
            child: Scaffold(body: Text('Second owner records')),
          ),
        ),
      );
      expect(find.text('First owner records'), findsNothing);
      expect(find.text('Second owner records'), findsNothing);
      next.complete(_access('beta_lifetime'));
      await _pump(tester);
      expect(find.text('Second owner records'), findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'expired plan keeps privacy and account destinations accessible at320px and2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = container(() => _access('expired'));
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(c, const SubscriptionScreen(canClose: false), scale: 2),
      );
      await _pump(tester);
      await _reach(tester, find.text('Export data or delete account'));
      await tester.tap(find.text('Export data or delete account'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsAccountTab>(find.byType(SettingsAccountTab))
            .showDataOnly,
        isTrue,
      );
      expect(find.text('Export your data'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(SettingsAccountTab))).pop();
      await tester.pumpAndSettle();
      await _reach(tester, find.text('Manage account or sign out'));
      await tester.tap(find.text('Manage account or sign out'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsAccountTab>(find.byType(SettingsAccountTab))
            .showDataOnly,
        isFalse,
      );
      await _reach(tester, find.text('Sign out'));
      expect(find.text('Sign out').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'lifetime account is never offered a purchase and restore remains available',
    (tester) async {
      final c = container(() => _access('beta_lifetime', sales: true));
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c, const SubscriptionScreen()));
      await _pump(tester);
      expect(store.queries, 0);
      expect(find.text('Lifetime beta access'), findsOneWidget);
      expect(find.text('£14.99 / month'), findsNothing);
      await tester.ensureVisible(find.text('Restore purchases'));
      await tester.tap(find.text('Restore purchases'));
      await _pump(tester);
      expect(store.restores, [subscriptionUser]);
      expect(service.state.value.message, contains('No additional purchases'));
      await _reach(tester, find.textContaining('No additional purchases'));
      expect(find.textContaining('No additional purchases'), findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'enabled plans use store prices and pending approval keeps restore reachable',
    (tester) async {
      final c = container(() => _access('expired', sales: true));
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(c, const SubscriptionScreen(canClose: false)),
      );
      await _pump(tester);
      expect(find.text('£14.99 / month'), findsOneWidget);
      expect(find.text('£149.99 / year'), findsNothing);
      await _reach(tester, find.text('Continue with monthly plan'));
      await tester.tap(find.text('Continue with monthly plan'));
      await _pump(tester);
      expect(store.buys, hasLength(1));
      store.events.add([subscriptionPurchase(status: PurchaseStatus.pending)]);
      await _pump(tester);
      await _reach(tester, find.text('Restore purchases'));
      expect(find.text('Restore purchases').hitTestable(), findsOneWidget);
      expect(
        find.textContaining('Waiting for payment approval'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
  testWidgets(
    'only a server-verified store event reopens the expired app',
    (tester) async {
      var paid = false, acceptReceipt = false;
      backend.respond = (request) {
        if (request.url.path == '/functions/v1/workloop-subscription') {
          paid = acceptReceipt;
          return jsonResponse({
            'verified': acceptReceipt,
            'environment': 'Production',
          });
        }
        if (request.url.path != '/rest/v1/rpc/get_workloop_access') {
          throw StateError('Unexpected fixture endpoint: ${request.url.path}');
        }
        return jsonResponse({
          'state': paid ? 'subscribed' : 'expired',
          'has_access': paid,
          'server_now': '2026-09-07T00:00:00Z',
          'paid_until': paid ? '2026-10-07T00:00:00Z' : null,
          'product_id': paid ? WorkloopPlans.monthlyId : null,
          'platform': paid ? 'apple' : null,
        });
      };
      service.dispose();
      late ProviderContainer c;
      service = StorePurchaseService(
        backend.client,
        subscriptionUser,
        onVerified: () =>
            c.invalidate(subscriptionAccessProvider(subscriptionUser)),
        store: store,
      );
      c = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(backend.client),
          storePurchaseServiceProvider(
            subscriptionUser,
          ).overrideWithValue(service),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          c,
          const SubscriptionGate(
            userId: subscriptionUser,
            child: Scaffold(body: Text('Verified business records')),
          ),
        ),
      );
      await _networkPump(tester);
      expect(find.text('Verified business records'), findsNothing);
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      store.events.add([subscriptionPurchase()]);
      await _networkPump(tester);
      expect(store.completions, isEmpty);
      expect(find.text('Verified business records'), findsNothing);
      acceptReceipt = true;
      store.events.add([subscriptionPurchase(status: PurchaseStatus.restored)]);
      await _networkPump(tester);
      expect(
        store.completions,
        hasLength(1),
        reason:
            '${service.state.value.message}; requests=${backend.requests.map((r) => r.url.path).toList()} paid=$paid',
      );
      expect(
        find.text('Verified business records'),
        findsOneWidget,
        reason:
            '${c.read(subscriptionAccessProvider(subscriptionUser))}; paid=$paid; requests=${backend.requests.map((r) => r.url.path).toList()}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
