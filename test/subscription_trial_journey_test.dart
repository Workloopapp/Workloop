import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/legal_document_screen.dart';
import 'package:workloop/features/subscription/store_purchase_service.dart';
import 'package:workloop/features/subscription/subscription_access.dart';
import 'package:workloop/features/subscription/subscription_gate.dart';
import 'package:workloop/features/subscription/subscription_plan_widgets.dart';
import 'package:workloop/features/subscription/subscription_screen.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

import 'support/subscription_fakes.dart';

class _JourneyStore extends StorePurchaseService {
  _JourneyStore(SubscriptionBackend backend, FakeSubscriptionStore store)
    : super(backend.client, subscriptionUser, onVerified: () {}, store: store);

  int loads = 0, restores = 0;
  final checkouts = <ProductDetails>[];

  @override
  Future<void> load() async => loads++;
  @override
  Future<void> buy(ProductDetails product) async => checkouts.add(product);
  @override
  Future<void> restore() async => restores++;
}

final _now = DateTime.utc(2026, 9, 12);
final _renewal = DateTime.utc(2026, 10, 12);

SubscriptionAccess _access({
  String state = 'trial_available',
  bool sales = true,
  bool? renews,
  bool reminders = false,
  bool billingRetry = false,
  DateTime? end,
}) => SubscriptionAccess(
  state: state,
  hasAccess: {
    'store_trial',
    'subscribed',
    'beta_lifetime',
    'beta',
    'trial',
  }.contains(state),
  serverNow: _now,
  trialEndsAt: {'store_trial', 'trial'}.contains(state)
      ? end ?? _renewal
      : null,
  paidUntil: {'store_trial', 'subscribed'}.contains(state)
      ? end ?? _renewal
      : null,
  renewsAt: renews == true ? end ?? _renewal : null,
  autoRenews: renews,
  appleSalesEnabled: sales,
  billingRemindersEnabled: reminders,
  inBillingRetry: billingRetry,
  productId: {'store_trial', 'subscribed'}.contains(state)
      ? WorkloopPlans.monthlyId
      : null,
  platform: {'store_trial', 'subscribed'}.contains(state) ? 'apple' : null,
);

ProductDetails _euroProduct() => ProductDetails(
  id: WorkloopPlans.monthlyId,
  title: 'Workloop monthly',
  description: 'Your business, connected.',
  price: '€17.99',
  rawPrice: 17.99,
  currencyCode: 'EUR',
);

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _reach(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await _pump(tester);
}

Finder _primary(String label) => find.byWidgetPredicate(
  (widget) => widget is WorkloopPrimaryButton && widget.label == label,
);

void _testJourney(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );

void main() {
  late SubscriptionBackend backend;
  late FakeSubscriptionStore native;
  late _JourneyStore store;
  setUp(() async {
    backend = SubscriptionBackend();
    await backend.account();
    native = FakeSubscriptionStore();
    store = _JourneyStore(backend, native);
  });
  tearDown(() async {
    store.dispose();
    await native.events.close();
    await backend.client.dispose();
  });

  StorePurchaseState offerState({
    StoreTrialEligibility eligibility = StoreTrialEligibility.eligible,
    bool busy = false,
    bool approval = false,
    bool verification = false,
  }) => StorePurchaseState(
    available: true,
    busy: busy,
    awaitingApproval: approval,
    awaitingVerification: verification,
    products: [_euroProduct(), subscriptionProduct(WorkloopPlans.yearlyId)],
    trialOffers: {
      WorkloopPlans.monthlyId: StoreTrialOffer(status: eligibility),
    },
  );

  ProviderContainer container(FutureOr<SubscriptionAccess> Function() load) =>
      ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(backend.client),
          subscriptionAccessProvider(
            subscriptionUser,
          ).overrideWith((ref) => load()),
          storePurchaseServiceProvider(
            subscriptionUser,
          ).overrideWithValue(store),
        ],
      );

  Widget app(
    ProviderContainer providers, {
    Widget? child,
    bool dark = false,
    double scale = 1,
  }) => UncontrolledProviderScope(
    container: providers,
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child ?? const SubscriptionScreen(canClose: false),
    ),
  );

  _testJourney(
    'eligible trial states local monthly price, automatic renewal and cancellation before checkout',
    (tester) async {
      store.state.value = offerState();
      final c = container(() => _access(reminders: true));
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      await _reach(tester, find.byType(SubscriptionOfferCard));
      final renewalPrice = find.text('€17.99 / month');
      final trialTerms = find.text(
        '1 month free, then billed monthly. Automatically renews unless cancelled.',
      );
      expect(renewalPrice, findsOneWidget);
      expect(trialTerms, findsOneWidget);
      expect(
        tester.widget<Text>(renewalPrice).style!.fontSize,
        greaterThan(tester.widget<Text>(trialTerms).style!.fontSize!),
      );
      expect(find.textContaining('£149.99'), findsNothing);
      expect(find.textContaining('£14.99'), findsNothing);
      await _reach(tester, find.text('Start my 1-month free trial'));
      await tester.tap(find.text('Start my 1-month free trial'));
      await _pump(tester);
      expect(store.checkouts.single.id, WorkloopPlans.monthlyId);
      await _reach(
        tester,
        find.textContaining('7 and 3 days before the first charge'),
      );
      expect(
        find.textContaining('7 and 3 days before the first charge'),
        findsOneWidget,
      );
      await _reach(
        tester,
        find.textContaining('at least 24 hours before the trial ends'),
      );
      expect(
        find.textContaining('at least 24 hours before the trial ends'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final eligibility in [
    StoreTrialEligibility.unknown,
    StoreTrialEligibility.ineligible,
    StoreTrialEligibility.notConfigured,
  ]) {
    _testJourney('${eligibility.name} eligibility never promises free access', (
      tester,
    ) async {
      store.state.value = offerState(eligibility: eligibility);
      final c = container(() => _access());
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      await _reach(tester, find.byType(SubscriptionOfferCard));
      expect(find.text('€17.99 / month'), findsOneWidget);
      expect(find.text('1 month free'), findsNothing);
      expect(find.byType(SubscriptionTrialTimeline), findsNothing);
      expect(_primary('Start my 1-month free trial'), findsNothing);
      expect(_primary('Continue with monthly plan'), findsOneWidget);
      expect(
        find.textContaining('Review the price and any available offer'),
        findsOneWidget,
      );
    });
  }

  _testJourney('access loading and errors cannot expose cached checkout', (
    tester,
  ) async {
    store.state.value = offerState();
    final pending = Completer<SubscriptionAccess>();
    final c = container(() => pending.future);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await _pump(tester);
    expect(find.byType(SubscriptionOfferCard), findsNothing);
    expect(store.loads, 0);
    pending.completeError(StateError('offline'));
    await _pump(tester);
    expect(find.text('Let’s check your plan'), findsOneWidget);
    expect(find.byType(SubscriptionOfferCard), findsNothing);
    expect(store.loads, 0);
  });

  _testJourney(
    'sales being disabled removes previously loaded purchase controls',
    (tester) async {
      store.state.value = offerState();
      final c = container(() => _access(sales: false));
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      await _reach(tester, find.text('MONTHLY MEMBERSHIP'));
      expect(find.byType(SubscriptionOfferCard), findsNothing);
      expect(store.loads, 0);
      expect(
        find.textContaining('Purchasing is not available yet.'),
        findsOneWidget,
      );
    },
  );

  _testJourney(
    'resuming refreshes account access before making the cached offer purchasable again',
    (tester) async {
      store.state.value = offerState();
      final refreshed = Completer<SubscriptionAccess>();
      var checks = 0;
      final c = container(() => ++checks == 1 ? _access() : refreshed.future);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      expect(store.loads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pump(tester);
      expect(checks, 2);
      expect(find.byType(SubscriptionOfferCard), findsNothing);
      refreshed.complete(_access());
      await _pump(tester);
      expect(store.loads, 2);
      await _reach(tester, find.byType(SubscriptionOfferCard));
      expect(_primary('Start my 1-month free trial'), findsOneWidget);
    },
  );

  for (final pending in ['approval', 'verification']) {
    _testJourney(
      'pending $pending disables checkout and keeps restore usable',
      (tester) async {
        store.state.value = offerState(
          approval: pending == 'approval',
          verification: pending == 'verification',
        );
        final c = container(() => _access());
        addTearDown(c.dispose);
        await tester.pumpWidget(app(c));
        await _pump(tester);
        await _reach(tester, _primary('Start my 1-month free trial'));
        expect(
          tester
              .widget<WorkloopPrimaryButton>(
                _primary('Start my 1-month free trial'),
              )
              .onPressed,
          isNull,
        );
        await _reach(tester, find.text('Restore purchases'));
        await tester.tap(find.text('Restore purchases'));
        await _pump(tester);
        expect(store.restores, 1);
        expect(store.checkouts, isEmpty);
      },
    );
  }

  for (final renewal in [true, false, null]) {
    _testJourney(
      'active store trial discloses ${renewal == null
          ? 'unknown'
          : renewal
          ? 'enabled'
          : 'cancelled'} renewal correctly',
      (tester) async {
        store.state.value = offerState();
        final c = container(
          () => _access(state: 'store_trial', renews: renewal, reminders: true),
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(app(c));
        await _pump(tester);
        expect(find.text('YOUR FREE MONTH'), findsOneWidget);
        expect(find.textContaining('Monday, October 12, 2026'), findsOneWidget);
        expect(find.byType(SubscriptionOfferCard), findsNothing);
        expect(
          find.text(
            'Current monthly price: €17.99. Apple confirms your renewal amount in subscription settings.',
          ),
          findsOneWidget,
        );
        if (renewal == false) {
          expect(find.textContaining('Renewal is off.'), findsOneWidget);
          expect(find.textContaining('Trial reminders go to'), findsNothing);
          expect(
            find.textContaining(
              'Your monthly subscription renews automatically after the trial.',
            ),
            findsNothing,
          );
        } else if (renewal == true) {
          expect(
            find.textContaining(
              'Your monthly subscription renews automatically after the trial.',
            ),
            findsOneWidget,
          );
          await _reach(tester, find.textContaining('Trial reminders go to'));
          expect(
            find.textContaining('7 and 3 days before renewal.'),
            findsOneWidget,
          );
        } else {
          expect(
            find.textContaining('Check your renewal and cancellation status'),
            findsOneWidget,
          );
          expect(find.textContaining('Trial reminders go to'), findsNothing);
        }
        await _reach(tester, find.text('Manage store subscription'));
        expect(
          find.text('Manage store subscription').hitTestable(),
          findsOneWidget,
        );
      },
    );
  }

  for (final renews in [true, false]) {
    _testJourney(
      'paid membership ${renews ? 'shows next renewal' : 'retains access until expiry after cancellation'}',
      (tester) async {
        final c = container(() => _access(state: 'subscribed', renews: renews));
        addTearDown(c.dispose);
        await tester.pumpWidget(app(c));
        await _pump(tester);
        expect(find.text('Monthly plan'), findsOneWidget);
        expect(
          find.textContaining(
            renews
                ? 'Next renewal: Monday, October 12, 2026.'
                : 'You can keep using Workloop until Monday, October 12, 2026.',
          ),
          findsOneWidget,
        );
        expect(find.byType(SubscriptionOfferCard), findsNothing);
      },
    );
  }

  _testJourney(
    'billing retry explains how to retain access without another checkout',
    (tester) async {
      final c = container(
        () => _access(state: 'subscribed', renews: true, billingRetry: true),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      expect(
        find.textContaining(
          'Update your billing details in Apple subscriptions.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SubscriptionOfferCard), findsNothing);
    },
  );

  _testJourney(
    'reminders are promised only while the delivery flag is enabled',
    (tester) async {
      store.state.value = offerState();
      final c = container(() => _access());
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      await _reach(tester, find.byType(SubscriptionTrialTimeline));
      expect(find.text('A reminder before you pay'), findsNothing);
      expect(
        find.textContaining('We’ll email your account address'),
        findsNothing,
      );
    },
  );

  for (final dark in [false, true]) {
    _testJourney(
      'trial journey remains usable at 320px and 2x text in ${dark ? 'dark' : 'light'} appearance',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        store.state.value = offerState();
        final c = container(() => _access(reminders: true));
        addTearDown(c.dispose);
        await tester.pumpWidget(app(c, dark: dark, scale: 2));
        await _pump(tester);
        for (final label in [
          'Start my 1-month free trial',
          'Restore purchases',
          'Manage store subscription',
          'Terms of use',
          'Privacy policy',
          'Export data or delete account',
          'Manage account or sign out',
          'Help & support',
        ]) {
          await _reach(tester, find.text(label));
          expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
          expect(tester.takeException(), isNull, reason: label);
        }
      },
    );
  }

  _testJourney(
    'terms and privacy can be read before authorising a subscription',
    (tester) async {
      final c = container(() => _access(sales: false));
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      for (final (label, document) in [
        ('Terms of use', WorkloopLegalDocument.terms),
        ('Privacy policy', WorkloopLegalDocument.privacy),
      ]) {
        await _reach(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen))
              .document,
          document,
        );
        Navigator.of(tester.element(find.byType(LegalDocumentScreen))).pop();
        await tester.pumpAndSettle();
      }
      expect(store.checkouts, isEmpty);
    },
  );

  _testJourney(
    'store trial expiry protects private records while current access reloads',
    (tester) async {
      var checks = 0;
      final recheck = Completer<SubscriptionAccess>();
      final c = container(
        () => ++checks == 1
            ? _access(
                state: 'store_trial',
                renews: false,
                end: _now.add(const Duration(seconds: 2)),
              )
            : recheck.future,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          c,
          child: const SubscriptionGate(
            userId: subscriptionUser,
            child: Scaffold(body: Text('Private client records')),
          ),
        ),
      );
      await _pump(tester);
      expect(find.text('Private client records'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await _pump(tester);
      expect(checks, 2);
      final guard = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(SubscriptionGate),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(guard.ignoring, isTrue);
      recheck.complete(_access(state: 'expired', sales: false));
      await _pump(tester);
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      expect(find.text('Private client records').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _testJourney(
    'server-confirmed trial opens the business journey and confirms success once',
    (tester) async {
      var activated = false;
      final c = container(
        () => activated
            ? _access(state: 'store_trial', renews: true)
            : _access(sales: false),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          c,
          child: const SubscriptionGate(
            userId: subscriptionUser,
            child: Scaffold(body: Text('Set up your business')),
          ),
        ),
      );
      await _pump(tester);
      expect(find.text('Set up your business'), findsNothing);
      activated = true;
      c.invalidate(subscriptionAccessProvider(subscriptionUser));
      await _pump(tester);
      expect(find.text('Set up your business'), findsOneWidget);
      expect(
        find.text('Your free month has started. Welcome to Workloop.'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      c.invalidate(subscriptionAccessProvider(subscriptionUser));
      await _pump(tester);
      expect(
        find.text('Your free month has started. Welcome to Workloop.'),
        findsNothing,
      );
      expect(find.text('Set up your business'), findsOneWidget);
    },
  );

  _testJourney(
    'missing renewal product metadata preserves access and management controls',
    (tester) async {
      final c = container(
        () => SubscriptionAccess(
          state: 'subscribed',
          hasAccess: true,
          serverNow: _now,
          paidUntil: _renewal,
        ),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await _pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Current monthly price:'), findsNothing);
      expect(find.byType(SubscriptionOfferCard), findsNothing);
      await _reach(tester, find.text('Manage store subscription'));
      expect(
        find.text('Manage store subscription').hitTestable(),
        findsOneWidget,
      );
    },
  );
}
