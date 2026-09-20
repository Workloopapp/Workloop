import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/slate_models.dart';
import '../utils/client_follow_up.dart';
import 'appointments_provider.dart';
import 'business_clock_provider.dart';
import 'workspace_settings_provider.dart';
import 'workspace_provider.dart';

typedef ClientFollowUpScope = ({String userId, String workspaceId});

abstract class ClientFollowUpSnoozeStore {
  Future<Map<String, DateTime>> read(ClientFollowUpScope scope);
  Future<void> write(ClientFollowUpScope scope, Map<String, DateTime> values);
}

class LocalClientFollowUpSnoozeStore implements ClientFollowUpSnoozeStore {
  final SharedPreferencesAsync preferences;
  LocalClientFollowUpSnoozeStore({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();

  String _key(ClientFollowUpScope scope) =>
      'workloop.client-follow-up.${scope.userId}.${scope.workspaceId}';

  @override
  Future<Map<String, DateTime>> read(ClientFollowUpScope scope) async {
    final raw = await preferences.getString(_key(scope));
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        if (entry.value is String && DateTime.tryParse(entry.value) != null)
          entry.key: DateTime.parse(entry.value),
    };
  }

  @override
  Future<void> write(ClientFollowUpScope scope, Map<String, DateTime> values) =>
      preferences.setString(
        _key(scope),
        jsonEncode({
          for (final entry in values.entries)
            entry.key: entry.value.toUtc().toIso8601String(),
        }),
      );
}

final clientFollowUpSnoozeStoreProvider = Provider<ClientFollowUpSnoozeStore>(
  (_) => LocalClientFollowUpSnoozeStore(),
);

final clientFollowUpSnoozesProvider =
    FutureProvider.family<Map<String, DateTime>, ClientFollowUpScope>(
      (ref, scope) => ref.watch(clientFollowUpSnoozeStoreProvider).read(scope),
    );

Future<void> snoozeClientFollowUp({
  required ClientFollowUpSnoozeStore store,
  required ClientFollowUpScope scope,
  required String clientId,
  required DateTime now,
}) async {
  final values = await store.read(scope);
  values.removeWhere((_, until) => !until.isAfter(now));
  values[clientId] = now.toUtc().add(const Duration(days: 7));
  await store.write(scope, values);
}

final tomorrowBriefProvider = FutureProvider<TomorrowBrief>((ref) async {
  final now = ref.watch(businessNowProvider);
  final results = await Future.wait<Object?>([
    ref.watch(workspaceIdProvider.future),
    ref.watch(workspaceSettingsProvider.future),
    ref.watch(appointmentsProvider.future),
  ]);
  final workspaceId = results[0] as String?;
  if (workspaceId == null) throw StateError('Workspace unavailable');
  final settings = results[1] as Map<String, dynamic>?;
  final timezone = settings?['timezone'] as String?;
  if (timezone == null || timezone.trim().isEmpty) {
    throw StateError('Booking time zone unavailable');
  }
  return buildTomorrowBrief(
    appointments: (results[2]! as List<Map<String, dynamic>>)
        .map(Appointment.fromMap).toList(),
    now: now,
    timezone: timezone,
    workspaceId: workspaceId,
  );
});
