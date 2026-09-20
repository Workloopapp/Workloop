import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/supabase/supabase_config.dart';

// These methods also require live provider activation. Keep them out of a
// release until the external credentials and the complete journey are tested.
const workloopPhoneAuthEnabled = bool.fromEnvironment(
  'WORKLOOP_PHONE_AUTH_ENABLED',
);
const workloopAppleOAuthEnabled = bool.fromEnvironment(
  'WORKLOOP_APPLE_OAUTH_ENABLED',
);

class AuthMethods {
  final bool email;
  final bool phone;
  final bool appleOAuth;
  final bool signup;

  const AuthMethods({
    required this.email,
    required this.phone,
    required this.appleOAuth,
    required this.signup,
  });

  factory AuthMethods.fromSettings(
    Map<String, dynamic> settings, {
    bool phoneReleased = workloopPhoneAuthEnabled,
    bool appleOAuthReleased = workloopAppleOAuthEnabled,
  }) {
    final external = settings['external'];
    if (external is! Map) {
      throw const FormatException('Auth settings are unavailable.');
    }
    return AuthMethods(
      email: external['email'] == true,
      // Autoconfirm bypasses delivery and must never be treated as real SMS.
      phone:
          phoneReleased &&
          external['phone'] == true &&
          settings['phone_autoconfirm'] == false,
      appleOAuth: appleOAuthReleased && external['apple'] == true,
      signup: settings['disable_signup'] == false,
    );
  }
}

Future<AuthMethods> loadAuthMethods({
  required http.Client client,
  required Uri projectUrl,
  required String publishableKey,
}) async {
  final response = await client
      .get(
        projectUrl.resolve('/auth/v1/settings'),
        headers: {'apikey': publishableKey},
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw const FormatException('Auth settings could not be loaded.');
  }
  return AuthMethods.fromSettings(
    Map<String, dynamic>.from(jsonDecode(response.body) as Map),
  );
}

final authMethodsProvider = FutureProvider.autoDispose<AuthMethods>((
  ref,
) async {
  final client = http.Client();
  // The send action reads this future after the options sheet has closed.
  // Keep only that in-flight request alive even without a visible listener.
  final pending = ref.keepAlive();
  ref.onDispose(client.close);
  try {
    return await loadAuthMethods(
      client: client,
      projectUrl: Uri.parse(SupabaseConfig.supabaseUrl),
      publishableKey: SupabaseConfig.supabasePublishableKey,
    );
  } finally {
    pending.close();
  }
});
