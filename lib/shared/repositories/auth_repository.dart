import 'dart:convert';
import '../email/email_preferences_repository.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/remote_push_service.dart';
import 'push_token_repository.dart';
import 'supabase_client_provider.dart';

const workloopPasswordRecoveryRedirect = 'workloop://reset-password';
const workloopOAuthRedirect = 'workloop://auth-callback';

final clearPersistedAuthProvider = Provider<Future<void> Function()?>(
  (ref) => null,
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(supabaseClientProvider),
    afterSignOut: ref.watch(clearPersistedAuthProvider),
    beforeSignOut: () async {
      try {
        final push = ref.read(remotePushServiceProvider);
        // Registration belongs to the signed-in bootstrap. Logout should not
        // start a new device-token lookup or wait for a permission flow.
        final token = push.cachedToken;
        if (token != null) {
          await ref.read(pushTokenRepositoryProvider).unregister(token);
        }
      } catch (_) {
        // Push cleanup is best effort. A transport outage must never trap the
        // owner in an authenticated session they explicitly asked to close.
      }
    },
  );
});

String? firstNameFromUserMetadata(Map<String, dynamic>? metadata) {
  for (final key in const ['first_name', 'full_name', 'display_name', 'name']) {
    final value = metadata?[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value.split(RegExp(r'\s+')).first;
    }
  }
  return null;
}

bool accountNeedsVerifiedEmail(User user) =>
    (user.email?.trim().isEmpty ?? true) || user.emailConfirmedAt == null;

class AppleDeletionAuthorizationException implements Exception {
  const AppleDeletionAuthorizationException({this.cancelled = false});
  final bool cancelled;
}

class AuthRepository {
  final SupabaseClient _client;
  final Future<void> Function()? beforeSignOut;
  final Future<void> Function()? afterSignOut;
  final Future<AuthorizationCredentialAppleID> Function(String nonce)?
  appleDeletionCredential;

  const AuthRepository(
    this._client, {
    this.beforeSignOut,
    this.afterSignOut,
    this.appleDeletionCredential,
  });

  String get currentEmail => _client.auth.currentUser?.email ?? '—';

  String? get currentUserId => _client.auth.currentUser?.id;

  bool get hasAppleIdentity =>
      _client.auth.currentUser?.identities?.any(
        (identity) => identity.provider == 'apple',
      ) ??
      false;

  /// A fresh, one-use code for server-side revocation. This deliberately never
  /// signs in to Supabase, links an identity or changes the current account.
  Future<String> requestAppleDeletionAuthorization() async {
    final accountId = currentUserId;
    if (accountId == null) throw const AppleDeletionAuthorizationException();
    final nonce = sha256
        .convert(utf8.encode(_client.auth.generateRawNonce()))
        .toString();
    try {
      final credential =
          await (appleDeletionCredential?.call(nonce) ??
              SignInWithApple.getAppleIDCredential(
                scopes: const [],
                nonce: nonce,
              ));
      if (currentUserId != accountId || credential.authorizationCode.isEmpty) {
        throw const AppleDeletionAuthorizationException();
      }
      return credential.authorizationCode;
    } on SignInWithAppleAuthorizationException catch (error) {
      throw AppleDeletionAuthorizationException(
        cancelled: error.code == AuthorizationErrorCode.canceled,
      );
    } catch (_) {
      throw const AppleDeletionAuthorizationException();
    }
  }

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  String? get currentFirstName =>
      firstNameFromUserMetadata(_client.auth.currentUser?.userMetadata);

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    bool emailUpdates = false,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'workloop_email_notice': accountEmailNoticeVersion,
        'workloop_email_updates': emailUpdates,
      },
      emailRedirectTo: kIsWeb ? null : workloopOAuthRedirect,
    );
  }

  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : workloopOAuthRedirect,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  Future<bool> signInWithAppleOAuth() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kIsWeb ? null : workloopOAuthRedirect,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  Future<void> sendEmailSignInLink({
    required String email,
    required bool createAccount,
    bool emailUpdates = false,
  }) {
    return _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: createAccount,
      emailRedirectTo: kIsWeb ? null : workloopOAuthRedirect,
      data: createAccount
          ? {
              'workloop_email_notice': accountEmailNoticeVersion,
              'workloop_email_updates': emailUpdates,
            }
          : null,
    );
  }

  Future<void> sendPhoneSignInCode({
    required String phone,
    required bool createAccount,
    bool emailUpdates = false,
  }) {
    return _client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: createAccount,
      data: createAccount
          ? {
              'workloop_email_notice': accountEmailNoticeVersion,
              'workloop_email_updates': emailUpdates,
            }
          : null,
    );
  }

  Future<void> verifyPhoneSignInCode({
    required String phone,
    required String code,
  }) async {
    final response = await _client.auth.verifyOTP(
      phone: phone,
      token: code.trim(),
      type: OtpType.sms,
    );
    if (response.session == null) {
      throw const AuthException('Sign in could not be completed.');
    }
  }

  Future<void> requestContactEmailVerification(String email) async {
    await _client.auth.updateUser(
      UserAttributes(email: email.trim()),
      emailRedirectTo: kIsWeb ? null : workloopOAuthRedirect,
    );
  }

  Future<bool> refreshContactEmailVerification() async {
    final response = await _client.auth.refreshSession();
    return response.user != null && !accountNeedsVerifiedEmail(response.user!);
  }

  Future<AuthResponse> signInWithApple() async {
    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('Apple did not return an identity token.');
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    final nameParts = <String>[
      if (credential.givenName?.trim().isNotEmpty ?? false)
        credential.givenName!.trim(),
      if (credential.familyName?.trim().isNotEmpty ?? false)
        credential.familyName!.trim(),
    ];
    if (nameParts.isNotEmpty) {
      try {
        await _client.auth.updateUser(
          UserAttributes(
            data: {
              'first_name': nameParts.first,
              'full_name': nameParts.join(' '),
              'given_name': credential.givenName?.trim(),
              'family_name': credential.familyName?.trim(),
            },
          ),
        );
      } catch (_) {
        // Authentication already succeeded. An optional display-name update
        // must not report a failed sign-in or tempt the owner to create again.
      }
    }
    return response;
  }

  Future<MfaSecurityState> getMfaSecurityState() async {
    final factors = await _client.auth.mfa.listFactors();
    final assurance = _client.auth.mfa.getAuthenticatorAssuranceLevel();
    return MfaSecurityState(
      factors: factors.totp,
      currentLevel: assurance.currentLevel,
      nextLevel: assurance.nextLevel,
    );
  }

  Future<AuthMFAEnrollResponse> enrollTotp() {
    return _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Workloop',
      friendlyName: 'Authenticator app',
    );
  }

  Future<void> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    await _client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  Future<void> removeMfaFactor(String factorId) async {
    await _client.auth.mfa.unenroll(factorId);
    await _client.auth.refreshSession();
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: workloopPasswordRecoveryRedirect,
    );
  }

  Future<void> requestPasswordReauthentication() {
    return _client.auth.reauthenticate();
  }

  Future<void> updatePassword(String password, {String? nonce}) async {
    await _client.auth.updateUser(
      UserAttributes(password: password, nonce: nonce),
    );
  }

  Future<void> updateFirstName(String firstName) async {
    final value = firstName.trim();
    if (value.isEmpty) return;
    await _client.auth.updateUser(UserAttributes(data: {'first_name': value}));
  }

  Future<void> _prepareSignOut() async {
    try {
      await beforeSignOut?.call().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Unregistering push is best effort; the local session must still close
      // when the network is offline or the request never completes.
    }
  }

  Future<void> signOut() async {
    await _prepareSignOut();
    await _client.auth.signOut();
    if (currentUserId == null) await afterSignOut?.call();
  }

  Future<void> signOutLocal({String? expectedUserId}) async {
    bool accountChanged() =>
        expectedUserId != null && currentUserId != expectedUserId;
    if (accountChanged()) return;
    await _prepareSignOut();
    // Invalid-session cleanup may overlap a new sign-in callback while push
    // cleanup is pending. Never discard the newly established account.
    if (accountChanged()) return;
    await _client.auth.signOut(scope: SignOutScope.local);
    if (currentUserId == null) await afterSignOut?.call();
  }

  Future<bool> validateCurrentSession() async {
    var session = _client.auth.currentSession;
    if (session == null) return false;
    try {
      if (session.isExpired) {
        final refreshed = await _client.auth.refreshSession();
        session = refreshed.session ?? _client.auth.currentSession;
        if (session == null) return false;
      }

      final response = await _client.auth.getUser(session.accessToken);
      if (response.user?.id != session.user.id) return false;
      final deletionPending = await _client.rpc(
        'current_account_deletion_pending',
      );
      return deletionPending != true;
    } on AuthException catch (error) {
      if (isRefreshableExpiredAccessTokenFailure(
        statusCode: error.statusCode,
        code: error.code,
        message: error.message,
      )) {
        try {
          final refreshed = await _client.auth.refreshSession();
          session = refreshed.session ?? _client.auth.currentSession;
          if (session == null) return false;
          final response = await _client.auth.getUser(session.accessToken);
          if (response.user?.id != session.user.id) return false;
          final deletionPending = await _client.rpc(
            'current_account_deletion_pending',
          );
          return deletionPending != true;
        } on AuthException catch (refreshError) {
          if (isTerminalSessionFailure(
            statusCode: refreshError.statusCode,
            code: refreshError.code,
          )) {
            return false;
          }
          rethrow;
        }
      }
      if (isTerminalSessionFailure(
        statusCode: error.statusCode,
        code: error.code,
      )) {
        return false;
      }
      rethrow;
    }
  }
}

bool isRefreshableExpiredAccessTokenFailure({
  String? statusCode,
  String? code,
  String? message,
}) {
  if (statusCode != '401' && statusCode != '403') return false;
  final normalized = message?.toLowerCase() ?? '';
  return normalized.contains('token') && normalized.contains('expired');
}

bool isTerminalSessionFailure({String? statusCode, String? code}) {
  // An access-token 401/403 can race the mobile client's automatic refresh
  // when the app resumes. Only explicit session/user/refresh-token failures
  // justify deleting the locally persisted session.
  return const {
    'refresh_token_not_found',
    'session_not_found',
    'user_not_found',
  }.contains(code);
}

class MfaSecurityState {
  final List<Factor> factors;
  final AuthenticatorAssuranceLevels? currentLevel;
  final AuthenticatorAssuranceLevels? nextLevel;

  const MfaSecurityState({
    required this.factors,
    required this.currentLevel,
    required this.nextLevel,
  });

  bool get isEnabled => factors.isNotEmpty;

  bool get needsChallenge =>
      currentLevel == AuthenticatorAssuranceLevels.aal1 &&
      nextLevel == AuthenticatorAssuranceLevels.aal2;
}
