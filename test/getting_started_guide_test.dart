import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Test-only in-memory backend for SharedPreferencesAsync.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/getting_started/getting_started_guide.dart';
import 'package:workloop/features/getting_started/getting_started_store.dart';

const _scope = (userId: 'owner-a', workspaceId: 'business-a');

Future<void> _pumpGuideHost(
  WidgetTester tester,
  GettingStartedStore store, {
  bool compact = false,
}) async {
  if (compact) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => FirstUseGuideGate(
          userId: _scope.userId,
          workspaceId: _scope.workspaceId,
          child: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showWorkloopGettingStartedGuide(
                  context,
                  userId: _scope.userId,
                  workspaceId: _scope.workspaceId,
                ),
                child: const Text('Open guide'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/clients/new',
        builder: (_, _) => const Scaffold(body: Text('Real client editor')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gettingStartedStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(compact ? 2 : 1)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test(
    'guide progress is local, ordered and isolated by owner and business',
    () async {
      final store = LocalGettingStartedStore();
      await store.prepareIntroduction(_scope);
      expect((await store.read(_scope)).pendingIntroduction, isTrue);
      await Future.wait([
        store.write(_scope, const GettingStartedProgress(nextStep: 1)),
        store.write(_scope, const GettingStartedProgress(nextStep: 3)),
      ]);
      final restarted = LocalGettingStartedStore();
      expect((await restarted.read(_scope)).nextStep, 3);
      expect((await restarted.read(_scope)).pendingIntroduction, isFalse);
      expect(
        (await restarted.read((
          userId: 'owner-b',
          workspaceId: 'business-a',
        ))).nextStep,
        0,
      );
      expect(
        (await restarted.read((
          userId: 'owner-a',
          workspaceId: 'business-b',
        ))).nextStep,
        0,
      );
    },
  );

  testWidgets('existing accounts are not interrupted by a new tutorial', (
    tester,
  ) async {
    await _pumpGuideHost(tester, LocalGettingStartedStore());
    expect(find.text('Getting started'), findsNothing);
    expect(find.text('Open guide'), findsOneWidget);
  });

  testWidgets(
    'new account can skip and resume without another automatic prompt',
    (tester) async {
      final store = LocalGettingStartedStore();
      await store.prepareIntroduction(_scope);
      await _pumpGuideHost(tester, store);
      expect(find.text('Know what needs you next'), findsOneWidget);
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Keep each client together'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip for now'));
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect((await store.read(_scope)).nextStep, 1);
      expect((await store.read(_scope)).pendingIntroduction, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpGuideHost(tester, LocalGettingStartedStore());
      expect(find.text('Getting started'), findsNothing);
      await tester.tap(find.text('Open guide'));
      await tester.pumpAndSettle();
      expect(find.text('Keep each client together'), findsOneWidget);
    },
  );

  testWidgets(
    'client shortcut opens a real editor and retains next guide step',
    (tester) async {
      final store = LocalGettingStartedStore();
      await store.write(
        _scope,
        const GettingStartedProgress(nextStep: 1, pendingIntroduction: true),
      );
      await _pumpGuideHost(tester, store);
      await tester.ensureVisible(find.text('Add a client'));
      await tester.tap(find.text('Add a client'));
      await tester.pumpAndSettle();
      expect(find.text('Real client editor'), findsOneWidget);
      expect((await store.read(_scope)).nextStep, 2);
      expect((await store.read(_scope)).pendingIntroduction, isFalse);
    },
  );

  testWidgets(
    'completed guide stays dismissed and can be replayed at large text',
    (tester) async {
      final store = LocalGettingStartedStore();
      await store.write(
        _scope,
        const GettingStartedProgress(nextStep: 4, pendingIntroduction: true),
      );
      await _pumpGuideHost(tester, store, compact: true);
      await tester.ensureVisible(find.text('Finish guide'));
      await tester.tap(find.text('Finish guide'));
      await tester.pumpAndSettle();
      expect((await store.read(_scope)).completed, isTrue);
      await tester.tap(find.text('Open guide'));
      await tester.pumpAndSettle();
      expect(find.text('Know what needs you next'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip for now'));
      expect(tester.takeException(), isNull);
    },
  );
}
