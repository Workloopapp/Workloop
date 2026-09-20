import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/slate_models.dart';
import '../utils/appointment_recurrence.dart';
import '../utils/booking_time.dart';
import '../utils/working_hours.dart';
import 'repository_pagination.dart';
import 'repository_schema_compatibility.dart';
import 'supabase_client_provider.dart';

const _legacyAppointmentSelect = '*, contacts(name), services(name)';
const _appointmentSelect =
    '$_legacyAppointmentSelect, '
    'appointment_items(id, workspace_id, item_kind, source_service_id, source_add_on_id, name, duration_mins, price, position)';

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  return AppointmentsRepository(ref.watch(supabaseClientProvider));
});

class AppointmentsRepository {
  final SupabaseClient _client;
  const AppointmentsRepository(this._client);

  /// Read a single current booking without trusting a retained screen snapshot.
  Future<Appointment?> getById(String workspaceId, String id) async {
    Future<Map<String, dynamic>?> load(String select) async {
      return await _client
          .from('appointments')
          .select(select)
          .eq('workspace_id', workspaceId)
          .eq('id', id)
          .maybeSingle();
    }

    final row = await loadWithPostgrestSchemaFallback(
      objectName: 'appointment_items',
      loadCurrent: () => load(_appointmentSelect),
      loadLegacy: () => load(_legacyAppointmentSelect),
    );
    return row == null ? null : Appointment.fromMap(row);
  }

  Future<void> ensureScheduleAvailable({
    required String workspaceId,
    required DateTime startTime,
    required DateTime endTime,
    Map<String, dynamic>? workingHours,
    String? workingHoursTimezone,
    String? excludeAppointmentId,
    String? recurrenceRule,
    int repeatOccurrences = 1,
    bool enforceWorkingHours = true,
    bool enforceConflicts = true,
  }) async {
    final duration = endTime.difference(startTime);
    for (var index = 0; index < repeatOccurrences.clamp(1, 24); index++) {
      final occurrenceStart = appointmentOccurrenceStart(
        startTime,
        recurrenceRule,
        index,
        timezoneName: workingHoursTimezone,
      );
      final occurrenceEnd = occurrenceStart.add(duration);
      if (enforceWorkingHours &&
          workingHours != null &&
          workingHours.isNotEmpty) {
        final localStart = workingHoursTimezone == null
            ? occurrenceStart.toLocal()
            : bookingTimeInZone(occurrenceStart, workingHoursTimezone);
        final localEnd = workingHoursTimezone == null
            ? occurrenceEnd.toLocal()
            : bookingTimeInZone(occurrenceEnd, workingHoursTimezone);
        if (!isWallClockWithinWorkingHours(
          hours: workingHours,
          start: localStart,
          end: localEnd,
        )) {
          throw AppointmentScheduleException(
            '${weekdayName(localStart)} is outside your working hours.',
            issue: AppointmentScheduleIssue.workingHours,
          );
        }
      }

      final rows = enforceConflicts
          ? await conflicts(
              workspaceId: workspaceId,
              startTime: occurrenceStart,
              endTime: occurrenceEnd,
              excludeAppointmentId: excludeAppointmentId,
            )
          : const <Map<String, dynamic>>[];
      if (rows.isNotEmpty) {
        throw AppointmentScheduleException(
          rows.length == 1
              ? 'This overlaps an existing booking.'
              : 'This overlaps ${rows.length} existing bookings.',
          issue: AppointmentScheduleIssue.conflict,
        );
      }
    }
  }

  Future<AppointmentScheduleReview> reviewSchedule({
    required String workspaceId,
    required DateTime startTime,
    required DateTime endTime,
    Map<String, dynamic>? workingHours,
    String? workingHoursTimezone,
    String? excludeAppointmentId,
    String? recurrenceRule,
    int repeatOccurrences = 1,
  }) async {
    final duration = endTime.difference(startTime);
    var outsideWorkingHoursCount = 0;
    var conflictCount = 0;
    for (var index = 0; index < repeatOccurrences.clamp(1, 24); index++) {
      final occurrenceStart = appointmentOccurrenceStart(
        startTime,
        recurrenceRule,
        index,
        timezoneName: workingHoursTimezone,
      );
      final occurrenceEnd = occurrenceStart.add(duration);
      if (workingHours != null &&
          workingHours.isNotEmpty &&
          !isWallClockWithinWorkingHours(
            hours: workingHours,
            start: workingHoursTimezone == null
                ? occurrenceStart.toLocal()
                : bookingTimeInZone(occurrenceStart, workingHoursTimezone),
            end: workingHoursTimezone == null
                ? occurrenceEnd.toLocal()
                : bookingTimeInZone(occurrenceEnd, workingHoursTimezone),
          )) {
        outsideWorkingHoursCount++;
      }
      conflictCount += (await conflicts(
        workspaceId: workspaceId,
        startTime: occurrenceStart,
        endTime: occurrenceEnd,
        excludeAppointmentId: excludeAppointmentId,
      )).length;
    }
    return AppointmentScheduleReview(
      outsideWorkingHoursCount: outsideWorkingHoursCount,
      conflictCount: conflictCount,
    );
  }

  Future<List<Appointment>> list(String workspaceId) async {
    final rows = await loadWithPostgrestSchemaFallback(
      objectName: 'appointment_items',
      loadCurrent: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadAppointmentPage(
          select: _appointmentSelect,
          workspaceId: workspaceId,
          from: from,
          to: to,
        ),
      ),
      loadLegacy: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadAppointmentPage(
          select: _legacyAppointmentSelect,
          workspaceId: workspaceId,
          from: from,
          to: to,
        ),
      ),
    );
    return rows.map<Appointment>(Appointment.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> _loadAppointmentPage({
    required String select,
    required String workspaceId,
    required int from,
    required int to,
  }) async {
    final page = await _client
        .from('appointments')
        .select(select)
        .eq('workspace_id', workspaceId)
        .order('start_time', ascending: true)
        .order('id', ascending: true)
        .range(from, to);
    return List<Map<String, dynamic>>.from(page);
  }

  Future<List<Map<String, dynamic>>> listRows(String workspaceId) async {
    return loadWithPostgrestSchemaFallback(
      objectName: 'appointment_items',
      loadCurrent: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadAppointmentPage(
          select: _appointmentSelect,
          workspaceId: workspaceId,
          from: from,
          to: to,
        ),
      ),
      loadLegacy: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadAppointmentPage(
          select: _legacyAppointmentSelect,
          workspaceId: workspaceId,
          from: from,
          to: to,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> listRowsForBusinessFeed(
    String workspaceId, {
    required DateTime from,
    required DateTime to,
    int limit = 80,
  }) async {
    final rows = await loadWithPostgrestSchemaFallback(
      objectName: 'appointment_items',
      loadCurrent: () => _loadBusinessFeedRows(
        select: _appointmentSelect,
        workspaceId: workspaceId,
        from: from,
        to: to,
        limit: limit,
      ),
      loadLegacy: () => _loadBusinessFeedRows(
        select: _legacyAppointmentSelect,
        workspaceId: workspaceId,
        from: from,
        to: to,
        limit: limit,
      ),
    );
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _loadBusinessFeedRows({
    required String select,
    required String workspaceId,
    required DateTime from,
    required DateTime to,
    required int limit,
  }) async {
    final rows = await _client
        .from('appointments')
        .select(select)
        .eq('workspace_id', workspaceId)
        .gte('start_time', from.toUtc().toIso8601String())
        .lt('start_time', to.toUtc().toIso8601String())
        .neq('status', 'cancelled')
        .neq('status', 'no_show')
        .order('start_time', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> conflicts({
    required String workspaceId,
    required DateTime startTime,
    required DateTime endTime,
    String? excludeAppointmentId,
  }) async {
    return loadWithPostgrestSchemaFallback(
      objectName: 'appointment_items',
      loadCurrent: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadConflictPage(
          select: _appointmentSelect,
          workspaceId: workspaceId,
          startTime: startTime,
          endTime: endTime,
          excludeAppointmentId: excludeAppointmentId,
          from: from,
          to: to,
        ),
      ),
      loadLegacy: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadConflictPage(
          select: _legacyAppointmentSelect,
          workspaceId: workspaceId,
          startTime: startTime,
          endTime: endTime,
          excludeAppointmentId: excludeAppointmentId,
          from: from,
          to: to,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadConflictPage({
    required String select,
    required String workspaceId,
    required DateTime startTime,
    required DateTime endTime,
    required String? excludeAppointmentId,
    required int from,
    required int to,
  }) async {
    var query = _client
        .from('appointments')
        .select(select)
        .eq('workspace_id', workspaceId)
        .neq('status', 'cancelled')
        .lt('start_time', endTime.toUtc().toIso8601String())
        .gt('end_time', startTime.toUtc().toIso8601String());
    if (excludeAppointmentId != null) {
      query = query.neq('id', excludeAppointmentId);
    }
    final page = await query
        .order('start_time', ascending: true)
        .order('id', ascending: true)
        .range(from, to);
    return List<Map<String, dynamic>>.from(page);
  }

  Future<List<Map<String, dynamic>>> forClientRows(String clientId) async {
    return loadWithPostgrestSchemaFallback(
      objectName: 'appointment_items',
      loadCurrent: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadClientAppointmentPage(
          select: _appointmentSelect,
          clientId: clientId,
          from: from,
          to: to,
        ),
      ),
      loadLegacy: () => fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) => _loadClientAppointmentPage(
          select: _legacyAppointmentSelect,
          clientId: clientId,
          from: from,
          to: to,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadClientAppointmentPage({
    required String select,
    required String clientId,
    required int from,
    required int to,
  }) async {
    final page = await _client
        .from('appointments')
        .select(select)
        .eq('contact_id', clientId)
        .order('start_time', ascending: false)
        .order('id', ascending: true)
        .range(from, to);
    return List<Map<String, dynamic>>.from(page);
  }

  Future<List<Appointment>> upcoming(
    String workspaceId, {
    int limit = 5,
  }) async {
    final rows = await loadWithPostgrestSchemaFallback(
      objectName: 'appointment_items',
      loadCurrent: () => _loadUpcomingRows(
        select: _appointmentSelect,
        workspaceId: workspaceId,
        limit: limit,
      ),
      loadLegacy: () => _loadUpcomingRows(
        select: _legacyAppointmentSelect,
        workspaceId: workspaceId,
        limit: limit,
      ),
    );
    return rows
        .map<Appointment>(
          (row) => Appointment.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadUpcomingRows({
    required String select,
    required String workspaceId,
    required int limit,
  }) async {
    final rows = await _client
        .from('appointments')
        .select(select)
        .eq('workspace_id', workspaceId)
        .gte('start_time', DateTime.now().toUtc().toIso8601String())
        .neq('status', 'cancelled')
        .order('start_time', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<String>> create({
    required String workspaceId,
    required String contactId,
    String? serviceId,
    required DateTime startTime,
    required DateTime endTime,
    required double price,
    String? title,
    String? notes,
    String? location,
    String? recurrenceRule,
    int repeatOccurrences = 1,
  }) async {
    final duration = endTime.difference(startTime);
    final safeTitle = title?.trim().isEmpty ?? true ? 'Booking' : title!.trim();
    final rows = List.generate(repeatOccurrences.clamp(1, 24), (index) {
      final occurrenceStart = appointmentOccurrenceStart(
        startTime,
        recurrenceRule,
        index,
      );
      return {
        'workspace_id': workspaceId,
        'contact_id': contactId,
        'service_id': serviceId,
        'title': safeTitle,
        'start_time': occurrenceStart.toUtc().toIso8601String(),
        'end_time': occurrenceStart.add(duration).toUtc().toIso8601String(),
        'price': price,
        'status': 'scheduled',
        'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
        'location': location?.trim().isEmpty ?? true ? null : location!.trim(),
        'recurrence_rule': ?recurrenceRule,
      };
    });

    final inserted = await _client
        .from('appointments')
        .insert(rows)
        .select('id');
    return List<Map<String, dynamic>>.from(
      inserted,
    ).map((row) => row['id'] as String).toList();
  }

  Future<List<String>> createBookingWorkflow({
    required String workspaceId,
    required String idempotencyKey,
    String? contactId,
    String? newContactName,
    String? newContactPhone,
    String? newContactEmail,
    String? newContactAddress,
    String? newContactNotes,
    bool reuseContactByPhone = false,
    String? bookingRequestId,
    String? serviceId,
    required DateTime startTime,
    required DateTime endTime,
    required double price,
    String? title,
    String? notes,
    String? location,
    String? recurrenceRule,
    String? recurrenceTimezone,
    int repeatOccurrences = 1,
    List<String> taskTitles = const [],
    DateTime? taskDueDate,
    bool createPaymentDue = false,
    String? paymentNote,
    String notificationTitle = 'New booking created',
    String notificationBody = 'A booking was added to your schedule.',
    bool allowOverlap = false,
    List<String> addOnIds = const [],
    List<String> serviceIds = const [],
  }) async {
    final payload = buildBookingWorkflowPayload(
      workspaceId: workspaceId,
      idempotencyKey: idempotencyKey,
      contactId: contactId,
      newContactName: newContactName,
      newContactPhone: newContactPhone,
      newContactEmail: newContactEmail,
      newContactAddress: newContactAddress,
      newContactNotes: newContactNotes,
      reuseContactByPhone: reuseContactByPhone,
      bookingRequestId: bookingRequestId,
      serviceId: serviceId,
      startTime: startTime,
      endTime: endTime,
      price: price,
      title: title,
      notes: notes,
      location: location,
      recurrenceRule: recurrenceRule,
      recurrenceTimezone: recurrenceTimezone,
      repeatOccurrences: repeatOccurrences,
      taskTitles: taskTitles,
      taskDueDate: taskDueDate,
      createPaymentDue: createPaymentDue,
      paymentNote: paymentNote,
      notificationTitle: notificationTitle,
      notificationBody: notificationBody,
      allowOverlap: allowOverlap,
      addOnIds: addOnIds,
      serviceIds: serviceIds,
    );
    return createBookingWorkflowFromPayload(payload);
  }

  /// Retries must use the exact submitted payload and idempotency key, even
  /// when the first response was lost after the transaction committed.
  Future<List<String>> createBookingWorkflowFromPayload(
    Map<String, dynamic> payload,
  ) async {
    late final dynamic response;
    try {
      response = await _client.rpc(
        payload['recurrence_timezone'] == null
            ? 'create_booking_workflow'
            : 'create_recurring_booking_workflow',
        params: {'p_payload': payload},
      );
    } on PostgrestException catch (error) {
      if (isAppointmentConflictError(
        code: error.code,
        message: error.message,
      )) {
        throw const AppointmentScheduleException(
          'This time now overlaps an existing booking. Choose another time.',
          issue: AppointmentScheduleIssue.conflict,
        );
      }
      rethrow;
    }
    final result = Map<String, dynamic>.from(response as Map);
    final ids = result['appointment_ids'];
    if (ids is! List) {
      throw const FormatException(
        'Booking workflow returned an invalid appointment list.',
      );
    }
    return ids.map((id) => id.toString()).toList(growable: false);
  }

  Future<void> completeBookingWorkflow({
    required String workspaceId,
    required String appointmentId,
    required String idempotencyKey,
    required String paymentMode,
    String? linkedPaymentId,
    DateTime? paymentDate,
  }) async {
    await _client.rpc(
      'complete_booking_workflow',
      params: {
        'p_payload': buildCompletionWorkflowPayload(
          workspaceId: workspaceId,
          appointmentId: appointmentId,
          idempotencyKey: idempotencyKey,
          paymentMode: paymentMode,
          linkedPaymentId: linkedPaymentId,
          paymentDate: paymentDate,
        ),
      },
    );
  }

  Future<void> update(String appointmentId, Map<String, dynamic> values) async {
    await _client.from('appointments').update(values).eq('id', appointmentId);
  }

  /// The booking and the service snapshot must commit together. Returning the
  /// saved row also keeps the open detail screen and its invoice prefill current.
  Future<Map<String, dynamic>> editBookingWorkflow({
    required String appointmentId,
    required Map<String, dynamic> values,
    required bool replaceServiceItems,
  }) async {
    try {
      final result = await _client.rpc(
        'edit_booking_workflow',
        params: {
          'p_appointment_id': appointmentId,
          'p_values': values,
          'p_replace_service_items': replaceServiceItems,
        },
      );
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (error) {
      if (error.code == '22023') {
        throw AppointmentScheduleException(error.message);
      }
      rethrow;
    }
  }

  Future<void> updateStatus(
    String appointmentId,
    String status, {
    String? notes,
  }) async {
    await update(appointmentId, {'status': status, 'notes': ?notes});
  }
}

/// A known database rejection means the first attempt rolled back. Transport
/// failures, response parsing failures and in-progress retries remain unknown.
bool bookingWorkflowDefinitelyRejected(Object error) {
  if (error is AppointmentScheduleException) return true;
  if (error is! PostgrestException) return false;
  final code = error.code ?? '';
  return code.startsWith('22') ||
      code.startsWith('23') ||
      code.startsWith('28') ||
      code.startsWith('42') ||
      code == 'P0001' ||
      code == 'PGRST202';
}

Map<String, dynamic> buildBookingWorkflowPayload({
  required String workspaceId,
  required String idempotencyKey,
  String? contactId,
  String? newContactName,
  String? newContactPhone,
  String? newContactEmail,
  String? newContactAddress,
  String? newContactNotes,
  bool reuseContactByPhone = false,
  String? bookingRequestId,
  String? serviceId,
  required DateTime startTime,
  required DateTime endTime,
  required double price,
  String? title,
  String? notes,
  String? location,
  String? recurrenceRule,
  String? recurrenceTimezone,
  int repeatOccurrences = 1,
  List<String> taskTitles = const [],
  DateTime? taskDueDate,
  bool createPaymentDue = false,
  String? paymentNote,
  required String notificationTitle,
  required String notificationBody,
  bool allowOverlap = false,
  List<String> addOnIds = const [],
  List<String> serviceIds = const [],
}) {
  final duration = endTime.difference(startTime);
  final occurrences = List.generate(repeatOccurrences.clamp(1, 24), (index) {
    final occurrenceStart = appointmentOccurrenceStart(
      startTime,
      recurrenceRule,
      index,
      timezoneName: recurrenceTimezone,
    );
    return {
      'start_time': occurrenceStart.toUtc().toIso8601String(),
      'end_time': occurrenceStart.add(duration).toUtc().toIso8601String(),
      'payment_date': _dateOnly(
        recurrenceTimezone == null
            ? occurrenceStart.toLocal()
            : bookingTimeInZone(occurrenceStart, recurrenceTimezone),
      ),
    };
  }, growable: false);
  return {
    'workspace_id': workspaceId,
    'idempotency_key': idempotencyKey,
    'contact_id': ?contactId,
    if (contactId == null)
      'new_contact': {
        'name': newContactName,
        'phone': newContactPhone,
        'email': newContactEmail,
        'address': newContactAddress,
        'notes': newContactNotes,
      },
    'reuse_contact_by_phone': reuseContactByPhone,
    'booking_request_id': ?bookingRequestId,
    'service_id': ?serviceId,
    'title': title,
    'price': price,
    'notes': notes,
    'location': location,
    'recurrence_rule': ?recurrenceRule,
    'recurrence_timezone': ?recurrenceTimezone,
    'appointments': occurrences,
    'task_titles': taskTitles,
    if (taskDueDate != null) 'task_due_date': _dateOnly(taskDueDate),
    'create_payment_due': createPaymentDue,
    'payment_note': paymentNote,
    'notification_title': notificationTitle,
    'notification_body': notificationBody,
    'allow_overlap': allowOverlap,
    if (addOnIds.isNotEmpty) 'add_on_ids': addOnIds,
    if (serviceIds.length > 1) 'service_ids': serviceIds,
  };
}

String _dateOnly(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

Map<String, dynamic> buildCompletionWorkflowPayload({
  required String workspaceId,
  required String appointmentId,
  required String idempotencyKey,
  required String paymentMode,
  String? linkedPaymentId,
  DateTime? paymentDate,
}) {
  return {
    'workspace_id': workspaceId,
    'appointment_id': appointmentId,
    'idempotency_key': idempotencyKey,
    'payment_mode': paymentMode,
    'linked_payment_id': ?linkedPaymentId,
    if (paymentDate != null) 'payment_date': _dateOnly(paymentDate),
  };
}

enum AppointmentScheduleIssue { workingHours, conflict, other }

class AppointmentScheduleReview {
  final int outsideWorkingHoursCount;
  final int conflictCount;

  const AppointmentScheduleReview({
    required this.outsideWorkingHoursCount,
    required this.conflictCount,
  });

  bool get hasWarnings => outsideWorkingHoursCount > 0 || conflictCount > 0;

  String get title {
    if (outsideWorkingHoursCount > 0 && conflictCount > 0) {
      return 'Check this booking';
    }
    if (conflictCount > 0) return 'Overlapping booking';
    return 'Outside working hours';
  }

  String get detail {
    final parts = <String>[];
    if (conflictCount > 0) {
      parts.add(
        'It overlaps $conflictCount existing booking${conflictCount == 1 ? '' : 's'}.',
      );
    }
    if (outsideWorkingHoursCount > 0) {
      parts.add(
        outsideWorkingHoursCount == 1
            ? 'It is outside your saved working hours.'
            : '$outsideWorkingHoursCount bookings are outside your saved working hours.',
      );
    }
    return '${parts.join(' ')} You can still save it if this is intentional.';
  }
}

class AppointmentScheduleException implements Exception {
  final String message;
  final AppointmentScheduleIssue issue;

  const AppointmentScheduleException(
    this.message, {
    this.issue = AppointmentScheduleIssue.other,
  });

  @override
  String toString() => message;
}

bool isAppointmentConflictError({
  required String? code,
  required String message,
}) {
  return code == '23P01' || message.toLowerCase().contains('overlap');
}
