import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Test-only platform storage, matching the app's asynchronous preferences API.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/getting_started/getting_started_guide.dart';
import 'package:workloop/features/getting_started/getting_started_store.dart';
import 'package:workloop/features/onboarding/screens/ob_complete.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/onboarding_repository.dart';

User _user(String id) => User(
  id: id,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-09-05T00:00:00Z',
  email: '$id@example.com',
  emailConfirmedAt: '2026-09-05T00:00:00Z',
);

class _SignupRepository implements AuthRepository {
  final events = StreamController<AuthState>.broadcast();
  @override
  Stream<AuthState> get authChanges => events.stream;
  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    bool emailUpdates = false,
  }) async => AuthResponse(user: _user('owner-a'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MetadataAuth implements GoTrueClient {
  User? user = _user('owner-a');
  int updates = 0;
  bool failUpdate = false;
  Future<void>? waitForUpdate;
  @override
  User? get currentUser => user;
  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    updates++;
    if (waitForUpdate case final waiting?) await waiting;
    if (failUpdate) throw const AuthException('Temporary metadata failure');
    return UserResponse.fromJson({'user': user?.toJson()});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OnboardingClient implements SupabaseClient {
  @override
  final _MetadataAuth auth;
  @override
  late final PostgrestClient rest;
  int commits = 0;
  final Future<void> Function()? beforeCommitResponse;
  _OnboardingClient(this.auth, {this.beforeCommitResponse}) {
    rest = PostgrestClient(
      'https://example.supabase.co/rest/v1',
      httpClient: MockClient((request) async {
        expectSync(request.url.path, '/rest/v1/rpc/complete_onboarding');
        commits++;
        await beforeCommitResponse?.call();
        return http.Response('"saved-workspace"', 200, request: request);
      }),
    );
  }
  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    get = false,
  }) => rest.rpc<T>(fn, params: params, get: get);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<String?> _complete(OnboardingRepository repository) =>
    repository.complete(
      firstName: 'Alex',
      businessName: 'Alex Services',
      industry: 'Gardener',
      handle: 'alex-services',
      services: const [],
      workingHours: const {},
      revenueTarget: 0,
    );

class _FailingSetup implements OnboardingRepository {
  @override
  Future<String?> complete({
    required String firstName,
    required String businessName,
    required String industry,
    required String handle,
    required List<Map<String, dynamic>> services,
    required Map<String, dynamic> workingHours,
    required double revenueTarget,
    Map<String, dynamic>? firstBooking,
  }) async =>
      throw const PostgrestException(message: 'Handle is already taken');
}

class _Draft extends OnboardingNotifier {
  @override
  OnboardingState build() => const OnboardingState(
    firstName: 'Alex',
    businessName: 'Alex Services',
    handle: 'alex-services',
  );
}

class _DelayedGuideStore extends GettingStartedStore {
  final oldAccount = Completer<GettingStartedProgress>();
  final writes = <GettingStartedScope>[];
  @override
  Future<GettingStartedProgress> read(GettingStartedScope scope) =>
      scope.userId == 'owner-a'
      ? oldAccount.future
      : Future.value(const GettingStartedProgress());
  @override
  Future<void> write(
    GettingStartedScope scope,
    GettingStartedProgress progress,
  ) async {
    writes.add(scope);
  }
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  testWidgets(
    'confirmation from direct auth route enters the app and ignores recovery events',
    (tester) async {
      final repository = _SignupRepository();
      addTearDown(repository.events.close);
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Verified app route')),
          ),
          GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('auth-mode-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('auth-mode-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Email address'),
        'owner@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'SecurePassword1!',
      );
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('If a new account was created,'),
        findsOneWidget,
      );
      final session = Session(
        accessToken: 'test-token',
        tokenType: 'bearer',
        user: _user('owner-a'),
      );
      repository.events.add(
        AuthState(AuthChangeEvent.passwordRecovery, session),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verified app route'), findsNothing);
      repository.events.add(AuthState(AuthChangeEvent.signedIn, session));
      await tester.pumpAndSettle();
      expect(find.text('Verified app route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('optional metadata failure keeps committed setup successful', () async {
    final auth = _MetadataAuth()..failUpdate = true;
    final client = _OnboardingClient(auth);
    expect(await _complete(OnboardingRepository(client)), 'saved-workspace');
    expect(client.commits, 1);
    expect(auth.updates, 1);
  });

  test(
    'account changed during setup never updates the next account or returns old workspace',
    () async {
      final auth = _MetadataAuth();
      final client = _OnboardingClient(
        auth,
        beforeCommitResponse: () async {
          auth.user = _user('owner-b');
        },
      );
      await expectLater(
        _complete(OnboardingRepository(client)),
        throwsA(isA<AuthException>()),
      );
      expect(client.commits, 1);
      expect(auth.updates, 0);
    },
  );

  test(
    'account changed during optional metadata cannot enter old workspace',
    () async {
      final pendingMetadata = Completer<void>();
      final auth = _MetadataAuth()..waitForUpdate = pendingMetadata.future;
      final client = _OnboardingClient(auth);
      final completion = _complete(OnboardingRepository(client));
      final result = expectLater(completion, throwsA(isA<AuthException>()));
      await Future<void>.delayed(Duration.zero);
      expect(auth.updates, 1);
      auth.user = _user('owner-b');
      pendingMetadata.complete();
      await result;
    },
  );

  testWidgets('unresponsive optional metadata cannot trap committed setup', (
    tester,
  ) async {
    final auth = _MetadataAuth()..waitForUpdate = Completer<void>().future;
    final client = _OnboardingClient(auth);
    String? workspace;
    unawaited(
      _complete(OnboardingRepository(client)).then((value) {
        workspace = value;
      }),
    );
    await tester.pump();
    expect(auth.updates, 1);
    expect(workspace, isNull);
    await tester.pump(const Duration(seconds: 8));
    expect(workspace, 'saved-workspace');
    expect(client.commits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'persistent setup failure lets the owner review and correct inputs',
    (tester) async {
      var reviewed = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingProvider.overrideWith(_Draft.new),
            onboardingRepositoryProvider.overrideWithValue(_FailingSetup()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ObComplete(onReviewSetup: () => reviewed = true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      await tester.ensureVisible(find.text('Review setup'));
      await tester.tap(find.text('Review setup'));
      expect(reviewed, isTrue);
      expect(find.text('Your workspace\nis ready.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delayed tutorial lookup from previous account never opens over current account',
    (tester) async {
      final store = _DelayedGuideStore();
      var owner = 'owner-a';
      late StateSetter updateHost;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gettingStartedStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                updateHost = setState;
                return FirstUseGuideGate(
                  userId: owner,
                  workspaceId: 'business-$owner',
                  child: Scaffold(body: Text(owner)),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      updateHost(() => owner = 'owner-b');
      await tester.pumpAndSettle();
      store.oldAccount.complete(
        const GettingStartedProgress(pendingIntroduction: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('owner-b'), findsOneWidget);
      expect(find.text('Getting started'), findsNothing);
      expect(store.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
