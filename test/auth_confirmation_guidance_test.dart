import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/auth/auth_validation.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Auth extends Fake implements AuthRepository {
  final List<UserIdentity> identities;
  _Auth(this.identities);

  @override
  Stream<AuthState> get authChanges => const Stream.empty();

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    bool emailUpdates = false,
  }) async => AuthResponse(
    user: User(
      id: 'fictional',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-09-08T00:00:00Z',
      identities: identities,
    ),
  );

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async => throw const AuthException('User is banned');
}

Future<void> _show(WidgetTester tester, _Auth auth) async {
  final router = GoRouter(
    initialLocation: '/auth',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Signed in')),
      ),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _credentials(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Email address'),
    'fictional@example.invalid',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Password'),
    'SecurePassword1!',
  );
}

void main() {
  for (final hasIdentity in [true, false]) {
    testWidgets(
      'signup guidance stays conditional for identity response $hasIdentity',
      (tester) async {
        await _show(
          tester,
          _Auth(
            hasIdentity
                ? [
                    const UserIdentity(
                      id: 'fictional',
                      userId: 'fictional',
                      identityId: 'identity',
                      identityData: {},
                      provider: 'email',
                      createdAt: '2026-09-08T00:00:00Z',
                      lastSignInAt: '2026-09-08T00:00:00Z',
                      updatedAt: '2026-09-08T00:00:00Z',
                    ),
                  ]
                : [],
          ),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('auth-mode-toggle')),
        );
        await tester.tap(find.byKey(const ValueKey('auth-mode-toggle')));
        await tester.pumpAndSettle();
        await _credentials(tester);
        await tester.ensureVisible(find.text('Create account'));
        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        final guidance = find.textContaining('If a new account was created,');
        expect(guidance, findsOneWidget);
        final message = tester.widget<Text>(guidance).data!;
        expect(message, contains('inbox and spam'));
        expect(message, contains('Already registered? Sign in instead.'));
        expect(
          message,
          contains(
            'If you requested account deletion, wait for the completion email',
          ),
        );
        expect(find.textContaining('email sent'), findsNothing);
        expect(find.text('Signed in'), findsNothing);
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Password'))
              .controller!
              .text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unavailable account sign-in explains deletion and support conditionally',
    (tester) async {
      await _show(tester, _Auth([]));
      await _credentials(tester);
      final button = find.widgetWithText(SlateButton, 'Sign in');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This account is currently unavailable.'),
        findsOneWidget,
      );
      expect(find.textContaining('If you requested deletion,'), findsOneWidget);
      expect(
        find.textContaining('Otherwise, contact Workloop support.'),
        findsOneWidget,
      );
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('banned code does not assert that deletion is the cause', () {
    expect(
      friendlyAuthErrorMessage('user_banned'),
      contains('If you requested deletion,'),
    );
    expect(
      friendlyAuthErrorMessage('unrelated backend detail'),
      'We could not complete that request. Check your details and try again.',
    );
  });
}
