import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attachments/record_attachment.dart';
import '../attachments/record_attachments_repository.dart';
import '../models/slate_models.dart';
import 'repository_pagination.dart';
import 'supabase_client_provider.dart';

final clientsRepositoryProvider = Provider<ClientsRepository>((ref) {
  return ClientsRepository(ref.watch(supabaseClientProvider));
});

class ClientsRepository {
  final SupabaseClient _client;
  const ClientsRepository(this._client);

  Future<List<Client>> list(String workspaceId) async {
    final rows = await fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async {
        final page = await _client
            .from('contacts')
            .select()
            .eq('workspace_id', workspaceId)
            .order('name', ascending: true)
            .order('id', ascending: true)
            .range(from, to);
        return List<Map<String, dynamic>>.from(page);
      },
    );
    return rows.map<Client>(Client.fromMap).toList();
  }

  Future<List<Client>> followUpsForBusinessFeed(
    String workspaceId, {
    required DateTime leadBefore,
    required DateTime inactiveBefore,
    int limitPerGroup = 80,
  }) async {
    Future<List<dynamic>> load({
      required bool leads,
      required DateTime before,
    }) {
      final cutoff = before.toUtc().toIso8601String();
      var query = _client
          .from('contacts')
          .select()
          .eq('workspace_id', workspaceId);
      query = leads ? query.eq('status', 'lead') : query.eq('status', 'active');
      return query
          .or(
            'last_activity_at.lt.$cutoff,'
            'and(last_activity_at.is.null,created_at.lt.$cutoff)',
          )
          .order('last_activity_at', ascending: false)
          .order('id', ascending: true)
          .limit(limitPerGroup);
    }

    final results = await Future.wait([
      load(leads: true, before: leadBefore),
      load(leads: false, before: inactiveBefore),
    ]);
    final clients = results
        .expand((rows) => rows)
        .map<Client>(
          (row) => Client.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    clients.sort((a, b) {
      final aDate = a.lastActivityAt ?? a.createdAt;
      final bDate = b.lastActivityAt ?? b.createdAt;
      if (aDate == null) return bDate == null ? 0 : 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return clients.take(limitPerGroup).toList();
  }

  Future<Client?> getById(String id) async {
    final row = await _client
        .from('contacts')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Client.fromMap(Map<String, dynamic>.from(row));
  }

  Future<String> create({
    required String workspaceId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? importantNotes,
    String status = 'active',
    String preferredContactMethod = 'phone',
    String? source,
    DateTime? birthday,
    List<String> tags = const [],
  }) async {
    final row = await _client
        .from('contacts')
        .insert({
          'workspace_id': workspaceId,
          'name': name.trim(),
          'phone': phone?.trim().isEmpty ?? true ? null : phone!.trim(),
          'email': email?.trim().isEmpty ?? true ? null : email!.trim(),
          'address': address?.trim().isEmpty ?? true ? null : address!.trim(),
          'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
          'important_notes': importantNotes?.trim().isEmpty ?? true
              ? null
              : importantNotes!.trim(),
          'status': status,
          'preferred_contact_method': preferredContactMethod,
          'source': source?.trim().isEmpty ?? true ? null : source!.trim(),
          'birthday': birthday?.toIso8601String().split('T').first,
          'tags': tags
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList(),
          'last_activity_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> update(String clientId, Map<String, dynamic> values) async {
    await _client
        .from('contacts')
        .update({
          ...values,
          'last_activity_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', clientId);
  }

  Future<void> delete(String clientId) async {
    final client = await _client
        .from('contacts')
        .select('workspace_id')
        .eq('id', clientId)
        .maybeSingle();
    if (client == null) return;
    final workspaceId = client['workspace_id'] as String;
    await RecordAttachmentsRepository(_client).deleteForTarget(
      workspaceId: workspaceId,
      target: AttachmentTarget.client(clientId),
    );
    await _client
        .from('contacts')
        .delete()
        .eq('workspace_id', workspaceId)
        .eq('id', clientId);
  }
}
