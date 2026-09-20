import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/supabase_client_provider.dart';

const accountEmailNoticeVersion = 'workloop-account-emails-2026-09-v1';
const accountEmailNotice =
    'As you try Workloop, we will email getting-started help, practical business tips, product updates and occasional reminders to return. Unsubscribe at any time.';
const _socialChoiceKey = 'workloop.pending-social-email-choice.v1';

final emailPreferencesRepositoryProvider = Provider(
  (ref) => EmailPreferencesRepository(ref.watch(supabaseClientProvider)),
);
final accountEmailPreferenceProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(emailPreferencesRepositoryProvider).get(),
);
final setAccountEmailPreferenceProvider = Provider<Future<void> Function(bool)>(
  (ref) {
    final repository = ref.watch(emailPreferencesRepositoryProvider);
    return (enabled) async {
      await repository.setEnabled(enabled);
      if (ref.mounted) ref.invalidate(accountEmailPreferenceProvider);
    };
  },
);

class EmailPreferencesRepository {
  final SupabaseClient _client;
  const EmailPreferencesRepository(this._client);

  Future<Map<String, dynamic>> get() async => Map<String, dynamic>.from(
    await _client.rpc('get_account_email_preference') as Map,
  );

  Future<void> setEnabled(bool enabled) async {
    await _client.rpc(
      'record_account_email_choice',
      params: {
        'p_enabled': enabled,
        'p_notice_version': accountEmailNoticeVersion,
        'p_offered_at': DateTime.now().toUtc().toIso8601String(),
        'p_source': 'settings',
      },
    );
  }

  Future<void> saveSocialSignupChoice(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_socialChoiceKey, [
      DateTime.now().toUtc().toIso8601String(),
      enabled.toString(),
    ]);
  }

  Future<void> clearSocialSignupChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_socialChoiceKey);
  }

  Future<void> recordActivity() async {
    final user = _client.auth.currentUser;
    if (user == null || user.emailConfirmedAt == null) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_socialChoiceKey);
    if (pending != null && pending.length == 2) {
      final offered = DateTime.tryParse(pending[0]);
      if (offered != null &&
          DateTime.now().difference(offered) < const Duration(days: 1)) {
        // Server checks creation time, verified address, MFA and existing opt-outs.
        await _client.rpc(
          'record_account_email_choice',
          params: {
            'p_enabled': pending[1] == 'true',
            'p_notice_version': accountEmailNoticeVersion,
            'p_offered_at': offered.toUtc().toIso8601String(),
            'p_source': 'signup',
          },
        );
      }
      await prefs.remove(_socialChoiceKey);
    }
    await _client.rpc('touch_workloop_email_activity');
  }
}
