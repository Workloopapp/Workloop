import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import '../utils/working_hours.dart';

final workspaceSettingsRepositoryProvider =
    Provider<WorkspaceSettingsRepository>((ref) {
      return WorkspaceSettingsRepository(ref.watch(supabaseClientProvider));
    });

class WorkspaceSettingsRepository {
  final SupabaseClient _client;
  const WorkspaceSettingsRepository(this._client);

  Future<Map<String, dynamic>?> get(String workspaceId) async {
    final row = await _client
        .from('workspace_settings')
        .select()
        .eq('workspace_id', workspaceId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> update(String workspaceId, Map<String, dynamic> values) async {
    if (values.containsKey('working_hours')) {
      final hours = values['working_hours'];
      if (hours is! Map<String, dynamic>) {
        throw const FormatException('Working hours must be an object.');
      }
      final errors = validateWorkingHours(hours);
      if (errors.isNotEmpty) throw FormatException(errors.values.first);
    }
    await _client
        .from('workspace_settings')
        .update(values)
        .eq('workspace_id', workspaceId);
  }
}
