import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/notifications/local_reminder_bootstrap.dart';
import 'package:workloop/shared/notifications/local_reminder_plan.dart';
import 'package:workloop/shared/notifications/local_reminder_service.dart';
import 'package:workloop/shared/notifications/remote_push_bootstrap.dart';
import 'package:workloop/shared/notifications/remote_push_registration.dart';
import 'package:workloop/shared/notifications/remote_push_service.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/push_token_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Remote implements RemotePushService {
  final routes = StreamController<String>.broadcast(sync: true);
  final foreground = StreamController<void>.broadcast();
  final permissions = StreamController<void>.broadcast();
  String? pendingRoute;
  int tokenCalls = 0;
  int initialFailures = 0;
  RemotePushPermission permission = RemotePushPermission.granted;
  Completer<String?>? pendingToken;
  @override
  Stream<String> get selectedRoutes => routes.stream;
  @override
  Stream<void> get foregroundMessages => foreground.stream;
  @override
  Stream<void> get permissionChanges => permissions.stream;
  @override
  String get platformName => 'android';
  @override
  String? get apnsEnvironment => null;
  @override
  Future<void> initialize() async {
    if (initialFailures > 0) {
      initialFailures--;
      throw StateError('temporary');
    }
  }

  @override
  String? takePendingLaunchRoute() {
    final route = pendingRoute;
    pendingRoute = null;
    return route;
  }

  @override
  Future<String?> registrationToken() async {
    tokenCalls++;
    if (permission != RemotePushPermission.granted) return null;
    return pendingToken == null ? 'fixture-token' : pendingToken!.future;
  }

  @override
  Future<RemotePushPermission> permissionStatus() async => permission;
  @override
  Future<void> dispose() async {
    await routes.close();
    await foreground.close();
    await permissions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PushTokens implements PushTokenRepository {
  final workspaces = <String>[];
  int failures = 0;
  @override
  Future<String> register({
    required String workspaceId,
    required String token,
    required String platform,
    required String appBuild,
    String? apnsEnvironment,
  }) async {
    workspaces.add(workspaceId);
    if (failures > 0) {
      failures--;
      throw StateError('temporary network failure');
    }
    return 'registration-id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local implements LocalReminderService {
  final routes = StreamController<String>.broadcast(sync: true);
  final permissions = StreamController<void>.broadcast();
  final calls = <List<LocalReminderPlan>>[];
  final contexts = <bool Function()?>[];
  int failures = 0;
  Completer<void>? firstPending;
  @override
  Stream<String> get selectedRoutes => routes.stream;
  @override
  Stream<void> get permissionChanges => permissions.stream;
  @override
  Future<void> initialize() async {}
  @override
  String? takePendingLaunchRoute() => null;
  @override
  Future<LocalReminderSyncResult> reconcile(
    List<LocalReminderPlan> plans, {
    bool Function()? isCurrent,
  }) async {
    calls.add(plans);
    contexts.add(isCurrent);
    if (calls.length == 1 && firstPending != null) await firstPending!.future;
    final failed = failures > 0 ? 1 : 0;
    if (failures > 0) failures--;
    return LocalReminderSyncResult(
      scheduled: plans.length,
      cancelled: 0,
      failed: failed,
    );
  }

  @override
  Future<void> dispose() async {
    await routes.close();
    await permissions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _account(String id) async {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'exp': 4102444800, 'sub': id, 'aal': 'aal1'})}.fixture';
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'user': {
        'id': id,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': '$id@example.test',
        'email_confirmed_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<ProviderContainer> _show(
  WidgetTester tester, {
  required List<Override> overrides,
  bool remote = true,
}) async {
  final router = GoRouter(
    observers: [WorkloopNavigationObserver()],
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/booking-requests',
        builder: (_, _) => const Scaffold(body: Text('Requests destination')),
      ),
      GoRoute(
        path: '/tasks/:taskId',
        builder: (_, state) =>
            TasksScreen(initialTaskId: state.pathParameters['taskId']),
      ),
      GoRoute(
        path: '/notes/:noteId',
        builder: (_, state) =>
            NotesScreen(initialNoteId: state.pathParameters['noteId']),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => remote
            ? WorkloopRemotePushBootstrap(router: router, child: child!)
            : WorkloopLocalReminderBootstrap(router: router, child: child!),
      ),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

List<Override> _workspaceOverrides() => [
  workspaceIdProvider.overrideWith((ref) async {
    final id = Supabase.instance.client.auth.currentSession?.user.id;
    if (id == 'user-b') {
      throw StateError('new workspace temporarily unavailable');
    }
    return id == null ? null : 'workspace-a';
  }),
  allTasksProvider.overrideWith(
    (_) async => [
      SlateTask(
        id: '11000000-0000-4000-8000-000000000001',
        workspaceId: 'workspace-a',
        title: 'Task',
        dueDate: DateTime.now().add(const Duration(days: 2)),
        reminderTiming: 'today',
      ),
    ],
  ),
  appointmentsProvider.overrideWith((_) async => []),
  clientsProvider.overrideWith((_) async => []),
  taskChecklistProvider.overrideWith((ref, id) async => []),
  allNotesProvider.overrideWith(
    (_) async => const [
      SlateNote(
        id: '11000000-0000-4000-8000-000000000001',
        workspaceId: 'workspace-a',
        title: 'Original note',
        body: 'Original body',
      ),
      SlateNote(
        id: '11000000-0000-4000-8000-000000000002',
        workspaceId: 'workspace-a',
        title: 'Different note',
        body: 'Different body',
      ),
    ],
  ),
  notificationPreferencesProvider.overrideWith(
    (_) async => {'appointment_reminder_15': false},
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fixture-key',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  setUp(
    () async =>
        Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
  );
  tearDownAll(() => Supabase.instance.dispose());

  for (final remote in [true, false]) {
    final kind = remote ? 'push' : 'local reminder';
    testWidgets('$kind reopens the exact task after its detail was closed', (
      tester,
    ) async {
      await _account('user-a');
      final push = _Remote();
      final local = _Local();
      await _show(
        tester,
        remote: remote,
        overrides: [
          ..._workspaceOverrides(),
          workloopFirebaseReadyProvider.overrideWithValue(true),
          remotePushServiceProvider.overrideWithValue(push),
          localReminderServiceProvider.overrideWithValue(local),
          pushTokenRepositoryProvider.overrideWithValue(_PushTokens()),
        ],
      );
      final routes = remote ? push.routes : local.routes;
      const path = '/tasks/11000000-0000-4000-8000-000000000001';
      routes.add(path);
      await tester.pumpAndSettle();
      expect(find.text('Mark Complete'), findsOneWidget);
      Navigator.of(tester.element(find.text('Mark Complete'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Mark Complete'), findsNothing);
      routes.add(path);
      await tester.pumpAndSettle();
      expect(find.text('Mark Complete'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await push.dispose();
      await local.dispose();
    });

    testWidgets('$kind repeat tap preserves an already open note draft', (
      tester,
    ) async {
      await _account('user-a');
      final push = _Remote();
      final local = _Local();
      await _show(
        tester,
        remote: remote,
        overrides: [
          ..._workspaceOverrides(),
          workloopFirebaseReadyProvider.overrideWithValue(true),
          remotePushServiceProvider.overrideWithValue(push),
          localReminderServiceProvider.overrideWithValue(local),
          pushTokenRepositoryProvider.overrideWithValue(_PushTokens()),
        ],
      );
      final routes = remote ? push.routes : local.routes;
      const path = '/notes/11000000-0000-4000-8000-000000000001';
      routes.add(path);
      await tester.pumpAndSettle();
      final editor = find.byType(TextField);
      expect(editor, findsOneWidget);
      await tester.enterText(editor, 'Unsaved heading\nKeep this unsaved text');
      final controller = tester.widget<TextField>(editor).controller!;
      routes.add(path);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editor).controller, same(controller));
      expect(controller.text, 'Unsaved heading\nKeep this unsaved text');
      await tester.pumpWidget(const SizedBox());
      await push.dispose();
      await local.dispose();
    });

    testWidgets(
      '$kind opens A above B without losing B draft on A parent URL',
      (tester) async {
        await _account('user-a');
        final push = _Remote();
        final local = _Local();
        await _show(
          tester,
          remote: remote,
          overrides: [
            ..._workspaceOverrides(),
            workloopFirebaseReadyProvider.overrideWithValue(true),
            remotePushServiceProvider.overrideWithValue(push),
            localReminderServiceProvider.overrideWithValue(local),
            pushTokenRepositoryProvider.overrideWithValue(_PushTokens()),
          ],
        );
        final routes = remote ? push.routes : local.routes;
        const path = '/notes/11000000-0000-4000-8000-000000000001';
        routes.add(path);
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(TextField))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Different note'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Different note\nUnsaved changes to keep',
        );
        final draft = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        routes.add(path);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Original note\nOriginal body',
        );
        // Close A's native editor and then its newly pushed parent page.
        Navigator.of(tester.element(find.byType(TextField))).pop();
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(NotesScreen))).pop();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller,
          same(draft),
        );
        expect(draft.text, 'Different note\nUnsaved changes to keep');
        await tester.pumpWidget(const SizedBox());
        await push.dispose();
        await local.dispose();
      },
    );

    testWidgets('$kind queued tap is dropped if the account changes first', (
      tester,
    ) async {
      await _account('user-a');
      final push = _Remote();
      final local = _Local();
      final container = await _show(
        tester,
        remote: remote,
        overrides: [
          ..._workspaceOverrides(),
          workloopFirebaseReadyProvider.overrideWithValue(true),
          remotePushServiceProvider.overrideWithValue(push),
          localReminderServiceProvider.overrideWithValue(local),
          pushTokenRepositoryProvider.overrideWithValue(_PushTokens()),
        ],
      );
      (remote ? push.routes : local.routes).add(
        '/tasks/11000000-0000-4000-8000-000000000001',
      );
      await _account('user-b');
      container.invalidate(workspaceIdProvider);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Mark Complete'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await push.dispose();
      await local.dispose();
    });
  }

  testWidgets(
    'login registers and opens deferred cold-start destination without an app resume',
    (tester) async {
      final service = _Remote()..pendingRoute = '/booking-requests';
      final tokens = _PushTokens();
      final container = await _show(
        tester,
        overrides: [
          ..._workspaceOverrides(),
          workloopFirebaseReadyProvider.overrideWithValue(true),
          remotePushServiceProvider.overrideWithValue(service),
          pushTokenRepositoryProvider.overrideWithValue(tokens),
        ],
      );
      expect(tokens.workspaces, isEmpty);
      expect(find.text('Home'), findsOneWidget);
      await _account('user-a');
      await _settle(tester);
      expect(tokens.workspaces, ['workspace-a']);
      await tester.pumpAndSettle();
      expect(find.text('Requests destination'), findsOneWidget);
      expect(
        container.read(remotePushRegistrationStatusProvider),
        RemotePushRegistrationStatus.registered,
      );
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );

  testWidgets(
    'registration retries a transient server failure and token refresh renews it',
    (tester) async {
      await _account('user-a');
      final service = _Remote()
        ..initialFailures = 1
        ..pendingRoute = '/booking-requests';
      final tokens = _PushTokens()..failures = 1;
      final container = await _show(
        tester,
        overrides: [
          ..._workspaceOverrides(),
          workloopFirebaseReadyProvider.overrideWithValue(true),
          remotePushServiceProvider.overrideWithValue(service),
          pushTokenRepositoryProvider.overrideWithValue(tokens),
        ],
      );
      expect(tokens.workspaces, ['workspace-a']);
      expect(
        container.read(remotePushRegistrationStatusProvider),
        RemotePushRegistrationStatus.retrying,
      );
      expect(find.text('Requests destination'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(tokens.workspaces, ['workspace-a', 'workspace-a']);
      expect(
        container.read(remotePushRegistrationStatusProvider),
        RemotePushRegistrationStatus.registered,
      );
      service.permissions.add(null);
      await _settle(tester);
      expect(tokens.workspaces, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );

  testWidgets(
    'token lookup finishing after signout never registers the prior account',
    (tester) async {
      await _account('user-a');
      final service = _Remote()..pendingToken = Completer<String?>();
      final tokens = _PushTokens();
      final container = await _show(
        tester,
        overrides: [
          ..._workspaceOverrides(),
          workloopFirebaseReadyProvider.overrideWithValue(true),
          remotePushServiceProvider.overrideWithValue(service),
          pushTokenRepositoryProvider.overrideWithValue(tokens),
        ],
      );
      expect(service.tokenCalls, 1);
      await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
      );
      service.pendingToken!.complete('fixture-token');
      await _settle(tester);
      expect(tokens.workspaces, isEmpty);
      expect(
        container.read(remotePushRegistrationStatusProvider),
        RemotePushRegistrationStatus.idle,
      );
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );

  testWidgets(
    'grant through a local task starts push registration without app resume',
    (tester) async {
      await _account('user-a');
      final local = _Local();
      final service = _Remote()..permission = RemotePushPermission.denied;
      final tokens = _PushTokens();
      final container = await _show(
        tester,
        overrides: [
          ..._workspaceOverrides(),
          workloopFirebaseReadyProvider.overrideWithValue(true),
          localReminderServiceProvider.overrideWithValue(local),
          remotePushServiceProvider.overrideWithValue(service),
          pushTokenRepositoryProvider.overrideWithValue(tokens),
        ],
      );
      expect(tokens.workspaces, isEmpty);
      expect(
        container.read(remotePushRegistrationStatusProvider),
        RemotePushRegistrationStatus.idle,
      );
      service.permission = RemotePushPermission.granted;
      local.permissions.add(null);
      await _settle(tester);
      expect(tokens.workspaces, ['workspace-a']);
      expect(
        container.read(remotePushRegistrationStatusProvider),
        RemotePushRegistrationStatus.registered,
      );
      await tester.pumpWidget(const SizedBox());
      await local.dispose();
      await service.dispose();
    },
  );

  testWidgets(
    'partially failed local sync is retried without changing any task',
    (tester) async {
      await _account('user-a');
      final service = _Local()..failures = 1;
      await _show(
        tester,
        remote: false,
        overrides: [
          ..._workspaceOverrides(),
          localReminderServiceProvider.overrideWithValue(service),
        ],
      );
      expect(service.calls, hasLength(1));
      expect(service.calls.single, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(service.calls, hasLength(2));
      expect(service.calls.last.single.key, service.calls.first.single.key);
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );

  testWidgets(
    'account change interrupts old local plans and clears them even if new workspace fails',
    (tester) async {
      await _account('user-a');
      final service = _Local()..firstPending = Completer<void>();
      final container = await _show(
        tester,
        remote: false,
        overrides: [
          ..._workspaceOverrides(),
          localReminderServiceProvider.overrideWithValue(service),
        ],
      );
      expect(service.calls.single, hasLength(1));
      await _account('user-b');
      // WorkloopApp invalidates workspace providers on identity change.
      container.invalidate(workspaceIdProvider);
      await _settle(tester);
      expect(service.contexts.first!(), isFalse);
      service.firstPending!.complete();
      await _settle(tester);
      expect(service.calls.last, isEmpty);
      expect(container.read(workspaceIdProvider).hasError, isTrue);
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );

  testWidgets(
    'signed-out cold start clears previously scheduled OS reminders',
    (tester) async {
      final service = _Local();
      await _show(
        tester,
        remote: false,
        overrides: [
          ..._workspaceOverrides(),
          localReminderServiceProvider.overrideWithValue(service),
        ],
      );
      expect(service.calls, [<LocalReminderPlan>[]]);
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );
}
