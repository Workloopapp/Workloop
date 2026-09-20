import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';
import '../utils/working_hours.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(supabaseClientProvider));
});

class OnboardingRepository {
  final SupabaseClient _client;
  const OnboardingRepository(this._client);

  Future<String?> complete({
    required String firstName,
    required String businessName,
    required String industry,
    required String handle,
    required List<Map<String, dynamic>> services,
    required Map<String, dynamic> workingHours,
    required double revenueTarget,
    Map<String, dynamic>? firstBooking,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final workspaceId = await _client.rpc(
      'complete_onboarding',
      params: buildOnboardingRpcParams(
        businessName: businessName,
        industry: industry,
        handle: handle,
        services: services,
        workingHours: workingHours,
        revenueTarget: revenueTarget,
        firstBooking: firstBooking,
      ),
    );

    if (workspaceId == null || workspaceId.toString().trim().isEmpty) {
      throw StateError('Workspace was not created');
    }

    void requireOriginalAccount() {
      if (_client.auth.currentUser?.id != user.id) {
        throw const AuthException('Your account changed. Open Workloop again.');
      }
    }

    requireOriginalAccount();
    // The workspace transaction has committed. Optional profile metadata must
    // not report a failed setup or keep the completion screen waiting forever.
    try {
      await _client.auth
          .updateUser(UserAttributes(data: {'first_name': firstName.trim()}))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // The owner can update their name in Settings; their business is saved.
    }
    requireOriginalAccount();

    return workspaceId.toString();
  }
}

Map<String, dynamic> buildOnboardingRpcParams({
  required String businessName,
  required String industry,
  required String handle,
  required List<Map<String, dynamic>> services,
  required Map<String, dynamic> workingHours,
  required double revenueTarget,
  Map<String, dynamic>? firstBooking,
}) {
  final hoursErrors = validateWorkingHours(workingHours);
  if (hoursErrors.isNotEmpty) {
    throw FormatException(hoursErrors.values.first);
  }
  final serviceRows = services
      .map((service) {
        final description = service['description']?.toString().trim();
        return <String, dynamic>{
          'name': service['name']?.toString().trim(),
          'description': description == null || description.isEmpty
              ? null
              : description,
          'duration_mins': (service['duration'] as num?)?.toInt() ?? 60,
          'price': (service['price'] as num?)?.toDouble() ?? 0,
        };
      })
      .toList(growable: false);

  Map<String, dynamic>? firstBookingValue;
  if (firstBooking != null) {
    final dateParts = (firstBooking['date'] as String).split('-');
    final serviceName = firstBooking['serviceName']?.toString().trim();
    final matchingService = serviceRows
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (service) => service?['name'] == serviceName,
          orElse: () => null,
        );
    final durationMins =
        (matchingService?['duration_mins'] as num?)?.toInt() ?? 60;
    final start = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      (firstBooking['hour'] as num).toInt(),
      (firstBooking['minute'] as num).toInt(),
    );
    firstBookingValue = {
      'client_name': firstBooking['clientName']?.toString().trim(),
      'service_name': serviceName,
      'start_time': start.toUtc().toIso8601String(),
      'end_time': start
          .add(Duration(minutes: durationMins))
          .toUtc()
          .toIso8601String(),
    };
  }

  return {
    'business_name': businessName.trim(),
    'industry_name': industry.trim(),
    'profile_handle': handle.trim().toLowerCase(),
    'service_rows': serviceRows,
    'working_hours_value': workingHours,
    'revenue_target_value': revenueTarget,
    'first_booking_value': firstBookingValue,
  };
}
