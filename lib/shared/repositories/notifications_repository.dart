import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/slate_models.dart';
import '../notifications/notification_route.dart';
import 'repository_pagination.dart';
import 'supabase_client_provider.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(ref.watch(supabaseClientProvider));
});

class NotificationsRepository {
  final SupabaseClient _client;
  const NotificationsRepository(this._client);

  Future<List<SlateNotification>> list(String workspaceId) async {
    final rows = await _client
        .from('notifications')
        .select()
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map<SlateNotification>(
          (row) => SlateNotification.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<int> unreadCount(String workspaceId) async {
    final rows = await fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async {
        final page = await _client
            .from('notifications')
            .select('id')
            .eq('workspace_id', workspaceId)
            .eq('read', false)
            .order('id', ascending: true)
            .range(from, to);
        return List<Map<String, dynamic>>.from(page);
      },
    );
    return rows.length;
  }

  Future<Map<String, dynamic>?> preferences(String workspaceId) async {
    final prefs = await _client
        .from('notification_preferences')
        .select()
        .eq('workspace_id', workspaceId)
        .maybeSingle();
    return prefs == null ? null : Map<String, dynamic>.from(prefs);
  }

  Future<void> upsertPreferences(
    String workspaceId,
    Map<String, dynamic> values,
  ) async {
    await _client.from('notification_preferences').upsert({
      'workspace_id': workspaceId,
      ...values,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'workspace_id');
  }

  Future<void> markRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('id', notificationId);
  }

  Future<void> markAllRead(String workspaceId) async {
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('workspace_id', workspaceId)
        .eq('read', false);
  }

  Future<void> create({
    required String workspaceId,
    required String type,
    required String title,
    required String body,
    String? deepLink,
  }) async {
    final prefs = await preferences(workspaceId);
    if (!_allowedByPreferences(type, prefs)) return;

    try {
      await _client.from('notifications').insert({
        'workspace_id': workspaceId,
        'type': type,
        'title': title,
        'body': body,
        'deep_link': workloopNotificationRoute(deepLink),
      });
    } catch (_) {
      // Notification support is additive; primary workflows should continue.
    }
  }

  bool _allowedByPreferences(String type, Map<String, dynamic>? prefs) {
    if (prefs == null) return true;
    if (prefs['all_notifications'] == false) return false;
    final key = switch (type) {
      'payment_received' || 'payment' => 'payment_received',
      'new_booking' || 'booking' => 'new_booking',
      'booking_request' => 'booking_request',
      'invoice_overdue' => 'invoice_overdue',
      'no_show' => 'no_show',
      'task_due' || 'task' => 'task_due_morning',
      'lead_followup' => 'lead_followup',
      _ => null,
    };
    if (key == null) return true;
    return prefs[key] as bool? ?? true;
  }
}
