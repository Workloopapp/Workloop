import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/privacy_repository.dart';

import 'support/subscription_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SubscriptionBackend backend;
  setUp(() async {
    backend = SubscriptionBackend();
    await backend.account();
  });
  tearDown(() => backend.client.dispose());

  test(
    'native deletion obtains fresh code without signing in or changing identity',
    () async {
      final nonces = <String>[];
      final repository = AuthRepository(
        backend.client,
        appleDeletionCredential: (nonce) async {
          nonces.add(nonce);
          return const AuthorizationCredentialAppleID(
            userIdentifier: null,
            givenName: null,
            familyName: null,
            email: null,
            identityToken: null,
            state: null,
            authorizationCode: 'fresh-code-fixture',
          );
        },
      );
      final originalSession = backend.client.auth.currentSession;
      expect(
        await repository.requestAppleDeletionAuthorization(),
        'fresh-code-fixture',
      );
      expect(
        await repository.requestAppleDeletionAuthorization(),
        'fresh-code-fixture',
      );
      expect(backend.client.auth.currentSession, same(originalSession));
      expect(backend.requests, isEmpty);
      expect(nonces.toSet().length, 2);
      expect(
        nonces.every((n) => RegExp(r'^[a-f0-9]{64}$').hasMatch(n)),
        isTrue,
      );
    },
  );

  test(
    'Apple cancellation retains Workloop account and performs no deletion request',
    () async {
      final repository = AuthRepository(
        backend.client,
        appleDeletionCredential: (_) async {
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'cancelled',
          );
        },
      );
      await expectLater(
        repository.requestAppleDeletionAuthorization(),
        throwsA(
          isA<AppleDeletionAuthorizationException>().having(
            (e) => e.cancelled,
            'cancelled',
            isTrue,
          ),
        ),
      );
      expect(repository.currentUserId, subscriptionUser);
      expect(backend.requests, isEmpty);
    },
  );

  test(
    'account change while Apple sheet is open discards the one-use code',
    () async {
      final pending = Completer<AuthorizationCredentialAppleID>();
      final repository = AuthRepository(
        backend.client,
        appleDeletionCredential: (_) => pending.future,
      );
      final operation = repository.requestAppleDeletionAuthorization();
      final assertion = expectLater(
        operation,
        throwsA(isA<AppleDeletionAuthorizationException>()),
      );
      await backend.account(otherSubscriptionUser);
      pending.complete(
        const AuthorizationCredentialAppleID(
          userIdentifier: null,
          givenName: null,
          familyName: null,
          email: null,
          identityToken: null,
          state: null,
          authorizationCode: 'unused-fixture',
        ),
      );
      await assertion;
      expect(repository.currentUserId, otherSubscriptionUser);
      expect(backend.requests, isEmpty);
    },
  );

  test(
    'empty Apple code fails without changing the existing account',
    () async {
      final repository = AuthRepository(
        backend.client,
        appleDeletionCredential: (_) async =>
            const AuthorizationCredentialAppleID(
              userIdentifier: null,
              givenName: null,
              familyName: null,
              email: null,
              identityToken: null,
              state: null,
              authorizationCode: '',
            ),
      );
      await expectLater(
        repository.requestAppleDeletionAuthorization(),
        throwsA(isA<AppleDeletionAuthorizationException>()),
      );
      expect(repository.currentUserId, subscriptionUser);
    },
  );

  test(
    'pre-onboarding deletion sends no workspace or client identity override',
    () async {
      backend.respond = (_) => jsonResponse({
        'ok': true,
        'accessLocked': true,
        'appleRevocation': 'not_applicable',
      });
      final result = await PrivacyRepository(
        backend.client,
      ).requestAccountDeletion();
      final request = backend.requests.single;
      expect(jsonDecode(request.body), isEmpty);
      expect(request.headers['authorization'], startsWith('Bearer '));
      expect(result.needsAppleUnlink, isFalse);
    },
  );

  test(
    'fresh Apple code travels only in the authenticated deletion body',
    () async {
      backend.respond = (_) => jsonResponse({
        'ok': true,
        'accessLocked': true,
        'appleRevocation': 'revoked',
      });
      final result = await PrivacyRepository(backend.client)
          .requestAccountDeletion(
            workspaceId: 'workspace-fixture',
            appleAuthorizationCode: 'one-use-fixture',
          );
      expect(jsonDecode(backend.requests.single.body), {
        'workspaceId': 'workspace-fixture',
        'appleAuthorizationCode': 'one-use-fixture',
      });
      expect(backend.requests.single.url.query, isEmpty);
      expect(result.appleRevocation, AppleAccountRevocation.revoked);
    },
  );

  for (final status in ['manual_action_required', 'unexpected', null]) {
    test('revocation result $status retains manual unlink guidance', () async {
      backend.respond = (_) => jsonResponse({
        'ok': true,
        'accessLocked': true,
        'appleRevocation': status,
      });
      final result = await PrivacyRepository(
        backend.client,
      ).requestAccountDeletion();
      expect(result.needsAppleUnlink, isTrue);
    });
  }

  for (final data in <Object>[
    {},
    {'ok': false, 'accessLocked': true},
    {'ok': true, 'accessLocked': false},
    'bad-response',
  ]) {
    test(
      'unconfirmed or unlocked deletion response never succeeds: $data',
      () async {
        backend.respond = (_) => jsonResponse(data);
        await expectLater(
          PrivacyRepository(backend.client).requestAccountDeletion(),
          throwsA(isA<AccountDeletionException>()),
        );
        expect(backend.client.auth.currentUser?.id, subscriptionUser);
      },
    );
  }

  test(
    'different Apple identity is reported safely without clearing Workloop session',
    () async {
      backend.respond = (_) =>
          jsonResponse({'error': 'apple_identity_mismatch'}, 409);
      await expectLater(
        PrivacyRepository(backend.client).requestAccountDeletion(
          appleAuthorizationCode: 'wrong-account-fixture',
        ),
        throwsA(
          isA<AccountDeletionException>().having(
            (e) => e.appleIdentityMismatch,
            'identity mismatch',
            isTrue,
          ),
        ),
      );
      expect(backend.client.auth.currentUser?.id, subscriptionUser);
    },
  );

  test('signout waits for explicit persistent session cleanup', () async {
    backend.respond = (_) => jsonResponse({});
    final pending = Completer<void>();
    var cleared = false;
    final repository = AuthRepository(
      backend.client,
      afterSignOut: () async {
        await pending.future;
        cleared = true;
      },
    );
    var done = false;
    final logout = repository
        .signOutLocal(expectedUserId: subscriptionUser)
        .then((_) => done = true);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(done, isFalse);
    pending.complete();
    await logout;
    expect(cleared, isTrue);
    expect(repository.currentUserId, isNull);
  });
}
