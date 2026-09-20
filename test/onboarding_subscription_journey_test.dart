import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only backing for the existing account-scoped onboarding draft store.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/getting_started/getting_started_guide.dart';
import 'package:workloop/features/getting_started/getting_started_store.dart';
import 'package:workloop/features/onboarding/onboarding_screen.dart';
import 'package:workloop/features/subscription/store_purchase_service.dart';
import 'package:workloop/features/subscription/subscription_access.dart';
import 'package:workloop/features/subscription/subscription_gate.dart';
import 'package:workloop/features/subscription/subscription_screen.dart';
import 'package:workloop/main.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';

import 'support/subscription_fakes.dart';

class _OnboardingDraft extends OnboardingNotifier {
  int restores = 0;

  @override
  Future<void> restore() async => restores++;
}

class _GuideStore extends GettingStartedStore {
  int reads = 0;

  @override
  Future<GettingStartedProgress> read(GettingStartedScope scope) async {
    reads++;
    return const GettingStartedProgress(pendingIntroduction: true);
  }

  @override
  Future<void> write(
    GettingStartedScope scope,
    GettingStartedProgress progress,
  ) async {}
}

SubscriptionAccess _access(String state, {required bool hasAccess}) =>
    SubscriptionAccess(
      state: state,
      hasAccess: hasAccess,
      serverNow: DateTime.utc(2026, 9, 12),
      paidUntil: state == 'store_trial' ? DateTime.utc(2026, 10, 12) : null,
    );

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  late SubscriptionBackend backend;
  late FakeSubscriptionStore store;
  late StorePurchaseService service;
  late _OnboardingDraft draft;
  late _GuideStore guide;

  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDownAll(() => SharedPreferencesAsyncPlatform.instance = null);

  setUp(() async {
    backend = SubscriptionBackend();
    await backend.account();
    store = FakeSubscriptionStore();
    service = StorePurchaseService(
      backend.client,
      subscriptionUser,
      store: store,
      onVerified: () {},
    );
    draft = _OnboardingDraft();
    guide = _GuideStore();
  });

  tearDown(() async {
    service.dispose();
    await store.events.close();
    await backend.client.dispose();
  });

  Future<ProviderContainer> show(
    WidgetTester tester, {
    required FutureOr<SubscriptionAccess> Function() loadAccess,
    Map<String, dynamic>? workspace,
    bool subscriptionsEnabled = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            AuthRepository(backend.client),
          ),
          supabaseClientProvider.overrideWithValue(backend.client),
          workspaceProvider.overrideWith((ref) async => workspace),
          subscriptionsEnabledProvider.overrideWithValue(subscriptionsEnabled),
          subscriptionAccessProvider(
            subscriptionUser,
          ).overrideWith((ref) => loadAccess()),
          storePurchaseServiceProvider(
            subscriptionUser,
          ).overrideWithValue(service),
          onboardingProvider.overrideWith(() => draft),
          gettingStartedStoreProvider.overrideWithValue(guide),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const WorkspaceGate()),
      ),
    );
    await _pump(tester);
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  testWidgets('new owner authorises the trial before business setup starts', (
    tester,
  ) async {
    var access = _access('trial_available', hasAccess: false);
    final container = await show(tester, loadAccess: () => access);
    expect(find.byType(SubscriptionScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(draft.restores, 0);
    expect(guide.reads, 0);

    // Refreshed server access after receipt verification opens the existing
    // setup flow without creating the workspace or consuming the guide early.
    access = _access('store_trial', hasAccess: true);
    container.invalidate(subscriptionAccessProvider(subscriptionUser));
    await _pump(tester);
    expect(find.byType(SubscriptionScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-get-started')),
      findsOneWidget,
    );
    expect(draft.restores, 1);
    expect(guide.reads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed access check keeps setup private and supports retry', (
    tester,
  ) async {
    var fails = true;
    await show(
      tester,
      loadAccess: () {
        if (fails) throw StateError('access unavailable');
        return _access('trial_available', hasAccess: false);
      },
    );
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(draft.restores, 0);
    expect(find.text('Try again'), findsOneWidget);
    fails = false;
    await tester.tap(find.text('Try again'));
    await _pump(tester);
    expect(find.byType(SubscriptionScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(draft.restores, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('billing recheck preserves an opened onboarding draft', (
    tester,
  ) async {
    var fails = false;
    final container = await show(
      tester,
      loadAccess: () {
        if (fails) throw StateError('temporary connection failure');
        return _access('store_trial', hasAccess: true);
      },
    );
    final state = tester.state(find.byType(OnboardingScreen));
    expect(draft.restores, 1);
    fails = true;
    container.invalidate(subscriptionAccessProvider(subscriptionUser));
    await _pump(tester);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.state(find.byType(OnboardingScreen)), same(state));
    expect(
      find.byKey(const ValueKey('onboarding-get-started')).hitTestable(),
      findsNothing,
    );
    fails = false;
    await tester.tap(find.text('Try again'));
    await _pump(tester);
    expect(tester.state(find.byType(OnboardingScreen)), same(state));
    expect(draft.restores, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unpaid workspace does not consume its first-use guide', (
    tester,
  ) async {
    await show(
      tester,
      workspace: {'id': 'new-workspace'},
      loadAccess: () => _access('trial_available', hasAccess: false),
    );
    expect(find.byType(SubscriptionScreen), findsOneWidget);
    expect(find.byType(FirstUseGuideGate), findsNothing);
    expect(find.byType(MainShell), findsNothing);
    expect(guide.reads, 0);
  });

  for (final state in ['beta', 'beta_lifetime']) {
    testWidgets('$state owners continue directly into setup', (tester) async {
      await show(tester, loadAccess: () => _access(state, hasAccess: true));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(SubscriptionScreen), findsNothing);
      expect(draft.restores, 1);
      expect(store.buys, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled subscription rollout preserves the setup route', (
    tester,
  ) async {
    var accessReads = 0;
    await show(
      tester,
      subscriptionsEnabled: false,
      loadAccess: () {
        accessReads++;
        return _access('trial_available', hasAccess: false);
      },
    );
    expect(find.byType(SubscriptionGate), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(draft.restores, 1);
    expect(accessReads, 0);
  });
}
