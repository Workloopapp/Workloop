import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/auth/auth_contact_email_screen.dart';
import 'package:workloop/features/auth/auth_methods.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/auth/auth_validation.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';

void main() {
  test(
    'mobile callbacks reach Supabase without competing Flutter deep links',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      for (final host in ['auth-callback', 'reset-password']) {
        expect(
          RegExp(
            'android:host="$host"\\s+android:scheme="workloop"',
          ).hasMatch(manifest),
          isTrue,
        );
      }
      expect(
        RegExp(
          r'android:name="flutter_deeplinking_enabled"\s+android:value="false"',
        ).hasMatch(manifest),
        isTrue,
      );
      expect(
        RegExp(
          r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>',
        ).hasMatch(plist),
        isTrue,
      );
      expect(plist, contains('<string>workloop</string>'));
    },
  );
  test(
    'external activation cannot bypass release or SMS verification gates',
    () {
      final settings = {
        'external': {'email': true, 'phone': true, 'apple': true},
        'phone_autoconfirm': false,
        'disable_signup': false,
      };
      final unreleased = AuthMethods.fromSettings(settings);
      expect(unreleased.email, isTrue);
      expect(unreleased.phone, isFalse);
      expect(unreleased.appleOAuth, isFalse);
      final released = AuthMethods.fromSettings(
        settings,
        phoneReleased: true,
        appleOAuthReleased: true,
      );
      expect(released.phone, isTrue);
      expect(released.appleOAuth, isTrue);
      expect(
        AuthMethods.fromSettings({
          ...settings,
          'phone_autoconfirm': true,
        }, phoneReleased: true).phone,
        isFalse,
      );
      expect(
        AuthMethods.fromSettings(
          {...settings, 'external': <String, bool>{}},
          phoneReleased: true,
          appleOAuthReleased: true,
        ).phone,
        isFalse,
      );
    },
  );

  test('failed capability lookup is an error, never assumed support', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/v1/settings');
      expect(request.headers['apikey'], 'public-test-key');
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response('temporarily unavailable', 503);
    });
    addTearDown(client.close);
    await expectLater(
      loadAuthMethods(
        client: client,
        projectUrl: Uri.parse('https://example.supabase.co'),
        publishableKey: 'public-test-key',
      ),
      throwsFormatException,
    );
  });

  test('phone formatting requires explicit country code and valid length', () {
    expect(normalizedAuthPhone('+44 (7700) 900-123'), '+447700900123');
    for (final invalid in [
      '07700900123',
      '447700900123',
      '+0123456789',
      '+447700900123 ext 2',
      '+123',
      '+1234567890123456',
    ]) {
      expect(normalizedAuthPhone(invalid), isNull, reason: invalid);
    }
  });

  test(
    'passwordless sign-in never creates accounts implicitly; signup carries notice',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/otp');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          if (body.containsKey('email')) {
            expect(
              request.url.queryParameters['redirect_to'],
              workloopOAuthRedirect,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      final repository = AuthRepository(client);
      await repository.sendEmailSignInLink(
        email: ' owner@example.com ',
        createAccount: false,
      );
      await repository.sendEmailSignInLink(
        email: 'new@example.com',
        createAccount: true,
        emailUpdates: false,
      );
      await repository.sendPhoneSignInCode(
        phone: '+447700900123',
        createAccount: false,
      );
      expect(requests[0]['email'], 'owner@example.com');
      expect(requests[0]['create_user'], false);
      expect(requests[0]['data'], isEmpty);
      expect(requests[1]['create_user'], true);
      expect(requests[1]['data']['workloop_email_updates'], false);
      expect(requests[1]['data']['workloop_email_notice'], isNotEmpty);
      expect(requests[2]['phone'], '+447700900123');
      expect(requests[2]['channel'], 'sms');
      expect(requests[2]['create_user'], false);
    },
  );

  test(
    'phone code verification uses SMS and rejects an absent session',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/verify');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['phone'], '+447700900123');
          expect(body['token'], '123456');
          expect(body['type'], 'sms');
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        AuthRepository(
          client,
        ).verifyPhoneSignInCode(phone: '+447700900123', code: ' 123456 '),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'phone identity requires a real verified email before workspace access',
    () {
      User user({String? email, String? verified}) => User(
        id: 'owner',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-05T00:00:00Z',
        email: email,
        emailConfirmedAt: verified,
        phone: '+447700900123',
        phoneConfirmedAt: '2026-09-05T00:00:00Z',
      );
      expect(accountNeedsVerifiedEmail(user()), isTrue);
      expect(
        accountNeedsVerifiedEmail(user(email: 'owner@example.com')),
        isTrue,
      );
      expect(
        accountNeedsVerifiedEmail(
          user(email: 'owner@example.com', verified: '2026-09-05T00:00:00Z'),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'more options hides unconfigured phone and preserves email recovery',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authMethodsProvider.overrideWith(
              (ref) async => const AuthMethods(
                email: true,
                phone: false,
                appleOAuth: false,
                signup: true,
              ),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('auth-more-methods')),
      );
      await tester.tap(find.byKey(const ValueKey('auth-more-methods')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-phone')), findsNothing);
      expect(find.byKey(const ValueKey('auth-apple-oauth')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('auth-email-link')));
      await tester.pumpAndSettle();
      expect(find.text('Email me a sign-in link'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsNothing);
      expect(find.widgetWithText(TextField, 'Email address'), findsOneWidget);
    },
  );

  testWidgets(
    'contact email gate stays blocked until server confirms verification',
    (tester) async {
      final repository = (await tester.runAsync(
        () async => _ContactEmailRepository(),
      ))!;
      addTearDown(() => tester.runAsync(repository.client.dispose));
      var openedWorkspace = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: AuthContactEmailScreen(
              onVerified: () => openedWorkspace = true,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-contact-email')),
        'owner@example.com',
      );
      await tester.tap(find.text('Send verification email'));
      await tester.pumpAndSettle();
      expect(repository.requested, 'owner@example.com');
      await tester.tap(find.text('I have verified my email'));
      await tester.pumpAndSettle();
      expect(openedWorkspace, isFalse);
      expect(
        find.text(
          'Open the verification link in your email first, then try again.',
        ),
        findsOneWidget,
      );
      repository.verified = true;
      await tester.tap(find.text('I have verified my email'));
      await tester.pumpAndSettle();
      expect(openedWorkspace, isTrue);
    },
  );
}

class _ContactEmailRepository extends AuthRepository {
  final SupabaseClient client;
  _ContactEmailRepository()
    : this._(
        SupabaseClient(
          'https://example.supabase.co',
          'public-test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  _ContactEmailRepository._(this.client) : super(client);
  String? requested;
  bool verified = false;
  @override
  Future<void> requestContactEmailVerification(String email) async =>
      requested = email;
  @override
  Future<bool> refreshContactEmailVerification() async => verified;
}
