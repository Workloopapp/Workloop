import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only backends for legacy auth persistence and onboarding draft storage.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/main.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';

const _firstWorkspace = <String, dynamic>{'id': 'workspace-one'};

class _Draft extends StatefulWidget {
  final VoidCallback onDispose;
  const _Draft({required this.onDispose});

  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final controller = TextEditingController();

  @override
  void dispose() {
    widget.onDispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: TextField(controller: controller)),
  );
}

class _WorkspaceLabel extends ConsumerWidget {
  const _WorkspaceLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Text('Workspace: ${ref.watch(workspaceProvider).value?['id']}'),
  );
}

class _NoOnboardingDraft extends OnboardingNotifier {
  @override
  Future<void> clearDraft() async {}
}

class _DelayedDraftCleanup extends OnboardingNotifier {
  final pending = Completer<void>();
  int calls = 0;

  @override
  Future<void> clearDraft() {
    calls++;
    return pending.future;
  }
}

class _PendingSignOut implements AuthRepository {
  final pending = Completer<void>();
  int calls = 0;

  @override
  String? get currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  Future<void> signOutLocal({String? expectedUserId}) {
    calls++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _setAccount(
  String id, {
  bool emitSameUserEvent = false,
  bool verifiedEmail = true,
}) async {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'exp': 4102444800, 'sub': id, 'aal': 'aal1'})}.fixture';
  final session = jsonEncode({
    'access_token': token,
    'refresh_token': 'fixture-refresh',
    'token_type': 'bearer',
    'user': {
      'id': id,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': '$id@example.test',
      if (verifiedEmail) 'email_confirmed_at': '2026-01-01T00:00:00Z',
      if (!verifiedEmail) ...{
        'phone': '447700900123',
        'phone_confirmed_at': '2026-01-01T00:00:00Z',
      },
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
  if (emitSameUserEvent) {
    await Supabase.instance.client.auth.setInitialSession(session);
  } else {
    await Supabase.instance.client.auth.recoverSession(session);
  }
}

Future<ProviderContainer> _show(
  WidgetTester tester, {
  required Widget child,
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fixture-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    SharedPreferencesAsyncPlatform.instance = null;
  });
  setUp(() => _setAccount('user-one'));

  testWidgets(
    'old invalid-account cleanup cannot sign out a newly verified account',
    (tester) async {
      final cleanup = _DelayedDraftCleanup();
      final signOut = _PendingSignOut();
      await _show(
        tester,
        child: const AuthGate(authenticatedChild: _WorkspaceLabel()),
        overrides: [
          sessionIntegrityProvider.overrideWith(
            (ref) async =>
                Supabase.instance.client.auth.currentUser?.id == 'user-two',
          ),
          workspaceProvider.overrideWith(
            (ref) async => {
              'id':
                  'workspace-${Supabase.instance.client.auth.currentUser?.id}',
            },
          ),
          onboardingProvider.overrideWith(() => cleanup),
          authRepositoryProvider.overrideWithValue(signOut),
        ],
      );
      expect(cleanup.calls, 1);
      expect(signOut.calls, 0);
      expect(find.byType(_WorkspaceLabel), findsNothing);

      await _setAccount('user-two');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Workspace: workspace-user-two'), findsOneWidget);

      cleanup.pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(signOut.calls, 0);
      expect(Supabase.instance.client.auth.currentUser?.id, 'user-two');
      expect(find.text('Workspace: workspace-user-two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone identity verifies contact email before opening workspace',
    (tester) async {
      await _setAccount('phone-user', verifiedEmail: false);
      var workspaceReads = 0;
      await _show(
        tester,
        child: const AuthGate(authenticatedChild: Text('Private workspace')),
        overrides: [
          sessionIntegrityProvider.overrideWith((ref) async => true),
          workspaceProvider.overrideWith((ref) async {
            workspaceReads++;
            return _firstWorkspace;
          }),
        ],
      );
      expect(find.text('Add your account email'), findsOneWidget);
      expect(find.text('Private workspace'), findsNothing);
      expect(workspaceReads, 0);

      // Only a server-confirmed SDK user unlocks the existing workspace route.
      await _setAccount('phone-user', emitSameUserEvent: true);
      await tester.pumpAndSettle();
      expect(find.text('Add your account email'), findsNothing);
      expect(find.text('Private workspace'), findsOneWidget);
      expect(workspaceReads, 1);
    },
  );

  testWidgets('workspace refresh failure keeps a draft blocked until retry', (
    tester,
  ) async {
    var calls = 0;
    var disposed = 0;
    final pending = Completer<Map<String, dynamic>?>();
    final container = await _show(
      tester,
      child: WorkspaceGate(child: _Draft(onDispose: () => disposed++)),
      overrides: [
        workspaceProvider.overrideWith((ref) {
          calls++;
          return calls == 2 ? pending.future : Future.value(_firstWorkspace);
        }),
      ],
    );
    await tester.enterText(find.byType(TextField), 'Booking details to keep');
    final draft = tester.state<_DraftState>(find.byType(_Draft));

    // These are the workspace invalidation and eventual transport failure
    // produced by the app-level resume refresh.
    container.invalidate(workspaceProvider);
    await tester.pump();
    pending.completeError(StateError('offline after switching apps'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not open your workspace'), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsNothing);
    expect(disposed, 0);
    expect(draft.controller.text, 'Booking details to keep');

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not open your workspace'), findsNothing);
    expect(tester.state<_DraftState>(find.byType(_Draft)), same(draft));
    expect(find.text('Booking details to keep'), findsOneWidget);
  });

  testWidgets('a different verified workspace resets the old draft', (
    tester,
  ) async {
    var workspace = _firstWorkspace;
    var disposed = 0;
    final container = await _show(
      tester,
      child: WorkspaceGate(child: _Draft(onDispose: () => disposed++)),
      overrides: [workspaceProvider.overrideWith((ref) async => workspace)],
    );
    await tester.enterText(find.byType(TextField), 'Private to workspace one');
    workspace = {'id': 'workspace-two'};
    container.invalidate(workspaceProvider);
    await tester.pump();
    await tester.pump();
    expect(disposed, 1);
    expect(find.text('Private to workspace one'), findsNothing);
    expect(tester.state<_DraftState>(find.byType(_Draft)).controller.text, '');
  });

  testWidgets(
    'session refresh error preserves draft but invalid identity removes it',
    (tester) async {
      var checks = 0;
      var disposed = 0;
      final pending = Completer<bool>();
      final signOut = _PendingSignOut();
      final container = await _show(
        tester,
        child: AuthGate(
          authenticatedChild: _Draft(onDispose: () => disposed++),
        ),
        overrides: [
          workspaceProvider.overrideWith((ref) async => _firstWorkspace),
          sessionIntegrityProvider.overrideWith((ref) {
            checks++;
            if (checks == 2) return pending.future;
            return Future.value(checks < 4);
          }),
          onboardingProvider.overrideWith(_NoOnboardingDraft.new),
          authRepositoryProvider.overrideWithValue(signOut),
        ],
      );
      await tester.enterText(find.byType(TextField), 'Unsent customer note');
      final draft = tester.state<_DraftState>(find.byType(_Draft));
      container.invalidate(sessionIntegrityProvider);
      await tester.pump();
      pending.completeError(StateError('identity service temporarily offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not open your workspace'), findsOneWidget);
      expect(find.byType(TextField).hitTestable(), findsNothing);
      expect(disposed, 0);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state<_DraftState>(find.byType(_Draft)), same(draft));
      expect(draft.controller.text, 'Unsent customer note');

      container.invalidate(sessionIntegrityProvider);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(_Draft), findsNothing);
      expect(disposed, 1);
      expect(signOut.calls, 1);
    },
  );

  testWidgets(
    'changed user cannot see old workspace during failed verification',
    (tester) async {
      var disposed = 0;
      var reads = 0;
      final pending = Completer<Map<String, dynamic>?>();
      await _show(
        tester,
        child: AuthGate(
          authenticatedChild: _Draft(onDispose: () => disposed++),
        ),
        overrides: [
          sessionIntegrityProvider.overrideWith((ref) async => true),
          workspaceProvider.overrideWith((ref) {
            reads++;
            return reads == 1 ? Future.value(_firstWorkspace) : pending.future;
          }),
        ],
      );
      await tester.enterText(find.byType(TextField), 'Private to user one');
      await _setAccount('user-two');
      await tester.pump();
      await tester.pump();
      expect(find.byType(_Draft), findsNothing);
      expect(disposed, 1);

      pending.completeError(StateError('new account workspace unavailable'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not open your workspace'), findsOneWidget);
      expect(find.byType(_Draft), findsNothing);
      expect(find.text('Private to user one'), findsNothing);
    },
  );

  testWidgets(
    'app auth listener clears old account before a fresh gate opens',
    (tester) async {
      var workspaceReads = 0;
      var accountChanges = 0;
      final nextWorkspace = Completer<Map<String, dynamic>?>();
      final container = ProviderContainer(
        overrides: [
          sessionIntegrityProvider.overrideWith((ref) async => true),
          workspaceProvider.overrideWith((ref) {
            workspaceReads++;
            return workspaceReads == 1
                ? Future.value(_firstWorkspace)
                : nextWorkspace.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      // This is the subscription used by WorkloopApp, installed before any
      // route-level gate and kept alive even when all gates are unmounted.
      final subscription = listenForWorkloopAuthChanges(
        Supabase.instance.client.auth,
        onAccountChanged: () {
          accountChanges++;
          container.invalidate(sessionIntegrityProvider, asReload: true);
          container.invalidate(workspaceProvider, asReload: true);
        },
        onPasswordRecovery: () {},
      );
      addTearDown(subscription.cancel);
      Future<void> show(Widget child) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(theme: AppTheme.light, home: child),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await show(const AuthGate(authenticatedChild: _WorkspaceLabel()));
      expect(find.text('Workspace: workspace-one'), findsOneWidget);
      await _setAccount('user-one', emitSameUserEvent: true);
      await tester.pump();
      expect(accountChanges, 0);
      expect(workspaceReads, 1);

      await show(const SizedBox.shrink());
      await _setAccount('user-two');
      await tester.pump();
      expect(accountChanges, 1);
      await show(const AuthGate(authenticatedChild: _WorkspaceLabel()));
      expect(find.byType(_WorkspaceLabel), findsNothing);
      expect(find.text('Workspace: workspace-one'), findsNothing);
      expect(workspaceReads, 2);

      nextWorkspace.completeError(StateError('second account offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not open your workspace'), findsOneWidget);
      expect(find.byType(_WorkspaceLabel), findsNothing);
      expect(find.text('Workspace: workspace-one'), findsNothing);
    },
  );
}
