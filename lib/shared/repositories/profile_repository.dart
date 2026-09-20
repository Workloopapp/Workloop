import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/slate_models.dart';
import '../models/public_booking_availability.dart';
import '../utils/booking_time.dart';
import 'appointments_repository.dart';
import 'repository_pagination.dart';
import 'repository_schema_compatibility.dart';
import 'supabase_client_provider.dart';

const _legacyBookingRequestSelect = '*, services(name, duration_mins, price)';
const _bookingRequestSelect =
    '$_legacyBookingRequestSelect, '
    'booking_request_items(id, workspace_id, item_kind, source_service_id, source_add_on_id, name, duration_mins, price, position)';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

class ProfileRepository {
  final SupabaseClient _client;
  const ProfileRepository(this._client);

  /// Older public requests omitted a zone. Resolve it from their workspace,
  /// never from the phone or an unrelated currently selected workspace.
  Future<String> bookingRequestTimezone(BookingRequest request) async {
    var zone = request.requestedTimezone?.trim();
    if (zone == null || zone.isEmpty) {
      final userId = _client.auth.currentUser?.id;
      final settings = await _client
          .from('workspace_settings')
          .select('timezone')
          .eq('workspace_id', request.workspaceId)
          .maybeSingle();
      if (_client.auth.currentUser?.id != userId) {
        throw const FormatException('Booking account changed');
      }
      zone = (settings?['timezone'] as String?)?.trim();
    }
    if (zone == null || zone.isEmpty) {
      throw const FormatException('Booking time zone unavailable');
    }
    bookingTimeLocation(zone);
    return zone;
  }

  Future<bool> isHandleAvailable(String handle) async {
    return await getPublicProfile(handle.trim().toLowerCase()) == null;
  }

  Future<PublicProfile?> getPublicProfile(String handle) async {
    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'get-public-profile',
        body: {'handle': handle},
      );
    } on FunctionException catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final profileMap = Map<String, dynamic>.from(data['profile'] as Map);
    final businessProfile = BusinessProfile.fromMap(profileMap);
    final services = List<dynamic>.from(data['services'] as List? ?? []);
    final timezone = data['timezone'] as String? ?? 'Europe/London';
    bookingTimeLocation(timezone);

    return PublicProfile(
      profile: businessProfile,
      businessName: data['businessName'] as String? ?? 'Business',
      logoUrl: data['logoUrl'] as String?,
      industry: data['industry'] as String?,
      workingHours: Map<String, dynamic>.from(
        data['workingHours'] as Map? ?? {},
      ),
      timezone: timezone,
      services: services
          .map<Service>(
            (row) => Service.fromMap(Map<String, dynamic>.from(row)),
          )
          .toList(),
    );
  }

  Future<PublicBookingAvailability> getPublicBookingAvailability({
    required String handle,
    required String serviceId,
    List<String> addOnIds = const [],
    List<String> serviceIds = const [],
  }) async {
    final response = await _client.functions.invoke(
      'get-public-booking-availability',
      body: {
        'handle': handle.trim().toLowerCase(),
        'serviceId': serviceId,
        'addOnIds': addOnIds,
        if (serviceIds.length > 1) 'serviceIds': serviceIds,
      },
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid public availability response');
    }
    return PublicBookingAvailability.fromMap(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<BusinessProfile?> getWorkspaceProfile(String workspaceId) async {
    final profile = await _client
        .from('business_profiles')
        .select()
        .eq('workspace_id', workspaceId)
        .maybeSingle();
    if (profile == null) return null;
    return BusinessProfile.fromMap(Map<String, dynamic>.from(profile));
  }

  Future<void> updateWorkspaceProfile({
    required String workspaceId,
    required Map<String, dynamic> values,
  }) async {
    await _client.from('business_profiles').upsert({
      'workspace_id': workspaceId,
      ...values,
    }, onConflict: 'workspace_id');
  }

  Future<void> createBookingRequest({
    required String handle,
    required String name,
    required String phone,
    required String email,
    required String requestToken,
    String? serviceId,
    List<String> addOnIds = const [],
    List<String> serviceIds = const [],
    DateTime? requestedFor,
    String? requestedTimezone,
    String? preferredTimeText,
    String? message,
  }) async {
    await _client.functions.invoke(
      'create-booking-request',
      body: buildPublicBookingRequestPayload(
        handle: handle,
        name: name,
        phone: phone,
        email: email,
        requestToken: requestToken,
        serviceId: serviceId,
        addOnIds: addOnIds,
        serviceIds: serviceIds,
        requestedFor: requestedFor,
        requestedTimezone: requestedTimezone,
        preferredTimeText: preferredTimeText,
        message: message,
      ),
    );
  }

  Future<List<BookingRequest>> bookingRequests(String workspaceId) async {
    final rows = await loadWithPostgrestSchemaFallback(
      objectName: 'booking_request_items',
      loadCurrent: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadBookingRequestPage(
          select: _bookingRequestSelect,
          workspaceId: workspaceId,
          from: from,
          to: to,
        ),
      ),
      loadLegacy: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadBookingRequestPage(
          select: _legacyBookingRequestSelect,
          workspaceId: workspaceId,
          from: from,
          to: to,
        ),
      ),
    );
    return rows.map<BookingRequest>(BookingRequest.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> _loadBookingRequestPage({
    required String select,
    required String workspaceId,
    required int from,
    required int to,
  }) async {
    final page = await _client
        .from('booking_requests')
        .select(select)
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .order('id', ascending: true)
        .range(from, to);
    return List<Map<String, dynamic>>.from(page);
  }

  Future<List<BookingRequest>> pendingBookingRequestsForBusinessFeed(
    String workspaceId, {
    int limit = 8,
  }) async {
    final rows = await loadWithPostgrestSchemaFallback(
      objectName: 'booking_request_items',
      loadCurrent: () => _loadPendingBookingRequests(
        select: _bookingRequestSelect,
        workspaceId: workspaceId,
        limit: limit,
      ),
      loadLegacy: () => _loadPendingBookingRequests(
        select: _legacyBookingRequestSelect,
        workspaceId: workspaceId,
        limit: limit,
      ),
    );
    return rows
        .map<BookingRequest>(
          (row) => BookingRequest.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadPendingBookingRequests({
    required String select,
    required String workspaceId,
    required int limit,
  }) async {
    final rows = await _client
        .from('booking_requests')
        .select(select)
        .eq('workspace_id', workspaceId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .order('id', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> updateBookingRequestStatus({
    required String requestId,
    required String workspaceId,
    required String status,
  }) async {
    final sourceStatuses = bookingRequestSourceStatusesFor(status);
    final updated = await _client
        .from('booking_requests')
        .update({'status': status})
        .eq('id', requestId)
        .eq('workspace_id', workspaceId)
        .inFilter('status', sourceStatuses)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw const BookingRequestStateException(
        'This request changed elsewhere. Refresh it before trying again.',
      );
    }
  }

  Future<BookingRequestConfirmationOutcome> confirmBookingRequest({
    required BookingRequest request,
    required DateTime startTime,
    required int durationMins,
    required double price,
    String? clientName,
    String? clientPhone,
    String? clientEmail,
    String? serviceTitle,
    String? location,
    String? extraNotes,
    bool createPaymentDue = false,
    bool enforceWorkingHours = true,
    bool allowOverlap = false,
  }) async {
    final alreadyConfirmed = await _bookingRequestAlreadyConfirmed(request);
    final endTime = startTime.add(Duration(minutes: durationMins));
    final title = serviceTitle?.trim().isNotEmpty == true
        ? serviceTitle!.trim()
        : request.serviceName?.trim().isNotEmpty == true
        ? request.serviceName!.trim()
        : 'Booking request';
    final notes = [
      if (request.preferredTimeText?.trim().isNotEmpty == true)
        'Requested time: ${request.preferredTimeText!.trim()}',
      if (request.message?.trim().isNotEmpty == true) request.message!.trim(),
      if (extraNotes?.trim().isNotEmpty == true) extraNotes!.trim(),
    ].join('\n\n');
    final serviceId = alreadyConfirmed
        ? request.serviceId
        : await _validServiceIdForRequest(request);
    final settings = alreadyConfirmed
        ? null
        : await _client
              .from('workspace_settings')
              .select('working_hours, timezone')
              .eq('workspace_id', request.workspaceId)
              .maybeSingle();
    final workingHours = settings?['working_hours'] is Map
        ? Map<String, dynamic>.from(settings!['working_hours'] as Map)
        : <String, dynamic>{};
    final startUtc = startTime.toUtc();
    final endUtc = endTime.toUtc();

    // A previous attempt may have committed before its response was lost.
    // The server's idempotency result must be allowed to resolve that retry;
    // otherwise its own new booking would fail this client's overlap check.
    if (!alreadyConfirmed) {
      await AppointmentsRepository(_client).ensureScheduleAvailable(
        workspaceId: request.workspaceId,
        startTime: startUtc,
        endTime: endUtc,
        workingHours: workingHours,
        workingHoursTimezone: _settingsTimezone(settings),
        enforceWorkingHours: enforceWorkingHours,
        enforceConflicts: !allowOverlap,
      );
    }

    final phone = clientPhone?.trim().isNotEmpty == true
        ? clientPhone!.trim()
        : request.phone.trim();
    final name = clientName?.trim().isNotEmpty == true
        ? clientName!.trim()
        : request.name.trim();
    final email = clientEmail?.trim().isNotEmpty == true
        ? clientEmail!.trim()
        : request.email.trim();
    final contactNotes = [
      'Created from public booking request.',
      if (request.preferredTimeText?.trim().isNotEmpty == true)
        'Requested time: ${request.preferredTimeText!.trim()}',
      if (request.message?.trim().isNotEmpty == true) request.message!.trim(),
    ].join('\n\n');

    final payload = buildBookingWorkflowPayload(
      workspaceId: request.workspaceId,
      idempotencyKey: bookingRequestConfirmationIdempotencyKey(request.id),
      newContactName: name.isEmpty ? 'New client' : name,
      newContactPhone: phone,
      newContactEmail: email.isEmpty ? null : email,
      newContactNotes: contactNotes,
      reuseContactByPhone: true,
      bookingRequestId: request.id,
      serviceId: serviceId,
      startTime: startUtc,
      endTime: endUtc,
      price: price,
      title: title,
      notes: notes.isEmpty ? null : notes,
      location: location?.trim().isNotEmpty == true ? location!.trim() : null,
      createPaymentDue: createPaymentDue,
      paymentNote: createPaymentDue ? 'Payment due for $title' : null,
      notificationTitle: 'Booking request confirmed',
      notificationBody: '${request.name} has been added to your calendar.',
      allowOverlap: allowOverlap,
    );
    try {
      final response = await _client.functions.invoke(
        'confirm-booking-request',
        body: {'payload': payload},
      );
      return BookingRequestConfirmationOutcome.fromResponse(response.data);
    } on FunctionException catch (error) {
      final details = error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : const <String, dynamic>{};
      final code = details['code']?.toString();
      final message = details['error']?.toString() ?? '';
      if (isAppointmentConflictError(code: code, message: message)) {
        throw const AppointmentScheduleException(
          'This time now overlaps an existing booking. Choose another time.',
          issue: AppointmentScheduleIssue.conflict,
        );
      }
      if (isBookingRequestStateError(code: code, message: message)) {
        throw const BookingRequestStateException(
          'This request was already handled or is no longer available.',
        );
      }
      rethrow;
    }
  }

  Future<AppointmentScheduleReview> reviewBookingRequestSchedule({
    required BookingRequest request,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (await _bookingRequestAlreadyConfirmed(request)) {
      return const AppointmentScheduleReview(
        outsideWorkingHoursCount: 0,
        conflictCount: 0,
      );
    }
    final settings = await _client
        .from('workspace_settings')
        .select('working_hours, timezone')
        .eq('workspace_id', request.workspaceId)
        .maybeSingle();
    final workingHours = settings?['working_hours'] is Map
        ? Map<String, dynamic>.from(settings!['working_hours'] as Map)
        : <String, dynamic>{};
    return AppointmentsRepository(_client).reviewSchedule(
      workspaceId: request.workspaceId,
      startTime: startTime,
      endTime: endTime,
      workingHours: workingHours,
      workingHoursTimezone: _settingsTimezone(settings),
    );
  }

  Future<bool> _bookingRequestAlreadyConfirmed(BookingRequest request) async {
    final current = await _client
        .from('booking_requests')
        .select('status')
        .eq('workspace_id', request.workspaceId)
        .eq('id', request.id)
        .maybeSingle();
    final status = current?['status'];
    if (status == 'confirmed') return true;
    if (status != 'pending' && status != 'contacted') {
      throw const BookingRequestStateException(
        'This request was already handled or is no longer available.',
      );
    }
    return false;
  }

  String _settingsTimezone(Map<String, dynamic>? settings) {
    final zone = settings?['timezone']?.toString().trim() ?? '';
    // Matches the existing legacy workspace-timezone fallback at the public
    // booking boundary. A nonempty invalid zone is rejected by the time helper.
    return zone.isEmpty ? 'Europe/London' : zone;
  }

  Future<String?> _validServiceIdForRequest(BookingRequest request) async {
    final serviceId = request.serviceId;
    if (serviceId == null || serviceId.trim().isEmpty) return null;
    final service = await _client
        .from('services')
        .select('id')
        .eq('id', serviceId)
        .eq('workspace_id', request.workspaceId)
        .maybeSingle();
    return service == null ? null : serviceId;
  }
}

Map<String, dynamic> buildPublicBookingRequestPayload({
  required String handle,
  required String name,
  required String phone,
  required String email,
  required String requestToken,
  String? serviceId,
  List<String> addOnIds = const [],
  List<String> serviceIds = const [],
  DateTime? requestedFor,
  String? requestedTimezone,
  String? preferredTimeText,
  String? message,
}) => {
  'handle': handle,
  'name': name,
  'phone': phone,
  'email': email,
  'requestToken': requestToken,
  'serviceId': serviceId,
  if (addOnIds.isNotEmpty) 'addOnIds': addOnIds,
  if (serviceIds.length > 1) 'serviceIds': serviceIds,
  if (requestedFor != null)
    'requestedFor': requestedFor.toUtc().toIso8601String(),
  if (requestedTimezone?.trim().isNotEmpty == true)
    'requestedTimezone': requestedTimezone!.trim(),
  'preferredTimeText': preferredTimeText,
  'message': message,
};

bool isValidBookingRequestEmail(String value) {
  final email = value.trim();
  if (email.isEmpty || email.length > 254) return false;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

enum BookingRequestConfirmationEmailStatus {
  sent,
  pending,
  failed,
  notApplicable,
}

class BookingRequestConfirmationOutcome {
  final BookingRequestConfirmationEmailStatus confirmationEmailStatus;

  const BookingRequestConfirmationOutcome({
    required this.confirmationEmailStatus,
  });

  factory BookingRequestConfirmationOutcome.fromResponse(Object? value) {
    final response = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    if (response.isEmpty) {
      throw const FormatException(
        'Booking confirmation returned an empty response.',
      );
    }
    final confirmationEmail = response['confirmationEmail'] is Map
        ? Map<String, dynamic>.from(response['confirmationEmail'] as Map)
        : const <String, dynamic>{};
    final status = switch (confirmationEmail['status']) {
      'sent' => BookingRequestConfirmationEmailStatus.sent,
      'pending' => BookingRequestConfirmationEmailStatus.pending,
      'failed' => BookingRequestConfirmationEmailStatus.failed,
      'not_applicable' => BookingRequestConfirmationEmailStatus.notApplicable,
      null => BookingRequestConfirmationEmailStatus.notApplicable,
      _ => BookingRequestConfirmationEmailStatus.failed,
    };
    return BookingRequestConfirmationOutcome(confirmationEmailStatus: status);
  }
}

List<String> bookingRequestSourceStatusesFor(String targetStatus) {
  return switch (targetStatus) {
    'contacted' => const ['pending', 'contacted'],
    'declined' => const ['pending', 'contacted'],
    _ => throw ArgumentError.value(
      targetStatus,
      'targetStatus',
      'Only contacted and declined are direct request transitions.',
    ),
  };
}

String bookingRequestConfirmationIdempotencyKey(String requestId) =>
    'booking-request-confirm:$requestId';

bool isBookingRequestStateError({
  required String? code,
  required String message,
}) {
  final normalizedMessage = message.toLowerCase();
  return (code == '23505' &&
          normalizedMessage.contains('booking request') &&
          normalizedMessage.contains('no longer')) ||
      (code == 'P0002' &&
          normalizedMessage.contains('booking request') &&
          normalizedMessage.contains('not found'));
}

class BookingRequestStateException implements Exception {
  final String message;

  const BookingRequestStateException(this.message);

  @override
  String toString() => message;
}

class PublicProfile {
  final BusinessProfile profile;
  final String businessName;
  final String? logoUrl;
  final String? industry;
  final Map<String, dynamic> workingHours;
  final List<Service> services;
  final String timezone;

  const PublicProfile({
    required this.profile,
    required this.businessName,
    required this.workingHours,
    required this.services,
    this.industry,
    this.timezone = 'Europe/London',
    this.logoUrl,
  });
}
