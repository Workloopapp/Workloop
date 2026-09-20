import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/slate_models.dart';
import 'repository_pagination.dart';
import 'repository_schema_compatibility.dart';
import 'supabase_client_provider.dart';

final servicesRepositoryProvider = Provider<ServicesRepository>((ref) {
  return ServicesRepository(ref.watch(supabaseClientProvider));
});

const minServiceDurationMinutes = 5;
const maxServiceDurationMinutes = 24 * 60;

void validateServiceDurationMinutes(int durationMins) {
  if (durationMins < minServiceDurationMinutes ||
      durationMins > maxServiceDurationMinutes) {
    throw ArgumentError.value(
      durationMins,
      'durationMins',
      'Service duration must be between 5 minutes and 24 hours.',
    );
  }
}

class ServicesRepository {
  final SupabaseClient _client;
  const ServicesRepository(this._client);

  Future<List<Map<String, dynamic>>> listRows(String workspaceId) async {
    return fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async {
        final page = await _client
            .from('services')
            .select()
            .eq('workspace_id', workspaceId)
            .order('name', ascending: true)
            .order('id', ascending: true)
            .range(from, to);
        return List<Map<String, dynamic>>.from(page);
      },
    );
  }

  Future<void> create({
    required String workspaceId,
    required String name,
    required double price,
    required int durationMins,
    String? description,
    bool showOnProfile = true,
    bool active = true,
  }) async {
    validateServiceDurationMinutes(durationMins);
    await _client.from('services').insert({
      'workspace_id': workspaceId,
      'name': name.trim(),
      'price': price,
      'duration_mins': durationMins,
      'description': description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      'show_on_profile': showOnProfile,
      'active': active,
    });
  }

  Future<void> update(String serviceId, Map<String, dynamic> values) async {
    final durationMins = values['duration_mins'];
    if (durationMins != null) {
      if (durationMins is! int) {
        throw ArgumentError.value(
          durationMins,
          'duration_mins',
          'Service duration must be a whole number of minutes.',
        );
      }
      validateServiceDurationMinutes(durationMins);
    }
    await _client.from('services').update(values).eq('id', serviceId);
  }

  Future<void> delete(String serviceId) async {
    await _client.from('services').delete().eq('id', serviceId);
  }

  Future<List<ServiceAddOn>> listAddOns({
    required String workspaceId,
    required String serviceId,
    bool includeInactive = true,
  }) async {
    return loadWithPostgrestSchemaFallback(
      objectName: 'service_add_ons',
      loadCurrent: () => fetchAllRepositoryPages<ServiceAddOn>(
        loadPage: (from, to) async {
          var query = _client
              .from('service_add_ons')
              .select()
              .eq('workspace_id', workspaceId)
              .eq('service_id', serviceId);
          if (!includeInactive) query = query.eq('active', true);
          final page = await query
              .order('position', ascending: true)
              .order('id', ascending: true)
              .range(from, to);
          return List<Map<String, dynamic>>.from(
            page,
          ).map(ServiceAddOn.fromMap).toList(growable: false);
        },
      ),
      loadLegacy: () async => const <ServiceAddOn>[],
    );
  }

  Future<ServiceAddOn> createAddOn({
    required String workspaceId,
    required String serviceId,
    required String name,
    required int durationMins,
    required double price,
    String? description,
    bool active = true,
    int position = 0,
  }) async {
    final row = await _client
        .from('service_add_ons')
        .insert({
          'workspace_id': workspaceId,
          'service_id': serviceId,
          'name': name.trim(),
          'description': description?.trim().isEmpty ?? true
              ? null
              : description!.trim(),
          'duration_mins': durationMins,
          'price': price,
          'active': active,
          'position': position,
        })
        .select()
        .single();
    return ServiceAddOn.fromMap(Map<String, dynamic>.from(row));
  }

  Future<ServiceAddOn> updateAddOn({
    required String workspaceId,
    required String serviceId,
    required String addOnId,
    required String name,
    required int durationMins,
    required double price,
    String? description,
    required bool active,
    required int position,
  }) async {
    final row = await _client
        .from('service_add_ons')
        .update({
          'name': name.trim(),
          'description': description?.trim().isEmpty ?? true
              ? null
              : description!.trim(),
          'duration_mins': durationMins,
          'price': price,
          'active': active,
          'position': position,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('workspace_id', workspaceId)
        .eq('service_id', serviceId)
        .eq('id', addOnId)
        .select()
        .single();
    return ServiceAddOn.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> deleteAddOn({
    required String workspaceId,
    required String serviceId,
    required String addOnId,
  }) async {
    await _client
        .from('service_add_ons')
        .delete()
        .eq('workspace_id', workspaceId)
        .eq('service_id', serviceId)
        .eq('id', addOnId);
  }
}
