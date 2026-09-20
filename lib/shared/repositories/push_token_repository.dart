import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';

final pushTokenRepositoryProvider = Provider<PushTokenRepository>((ref) {
  return PushTokenRepository(ref.watch(supabaseClientProvider));
});

class PushTokenRepository {
  final SupabaseClient _client;

  const PushTokenRepository(this._client);

  Future<String> register({
    required String workspaceId,
    required String token,
    required String platform,
    required String appBuild,
    String? apnsEnvironment,
  }) async {
    if (platform == 'ios' &&
        apnsEnvironment != 'production' &&
        apnsEnvironment != 'sandbox') {
      throw ArgumentError(
        'iOS push registration requires its signing environment',
      );
    }
    if (platform != 'ios' && apnsEnvironment != null) {
      throw ArgumentError('APNs environment applies only to iOS');
    }
    final result = await _client.rpc(
      'register_push_token',
      params: {
        'p_workspace_id': workspaceId,
        'p_token': token,
        'p_platform': platform,
        'p_app_build': appBuild,
        'p_apns_environment': apnsEnvironment,
      },
    );
    final id = result?.toString().trim() ?? '';
    if (id.isEmpty) throw StateError('Push token registration failed');
    return id;
  }

  Future<void> unregister(String token) async {
    if (_client.auth.currentSession == null || token.trim().isEmpty) return;
    await _client.rpc(
      'unregister_push_token',
      params: {'p_token': token.trim()},
    );
  }
}
