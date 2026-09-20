import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/slate_models.dart';
import '../repositories/slate_repositories.dart';
import 'appointments_provider.dart';
import 'business_clock_provider.dart';
import 'finance_provider.dart';
import 'tasks_provider.dart';
import 'workspace_provider.dart';

final clientsProvider = FutureProvider<List<Client>>((ref) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return [];

  return ref.watch(clientsRepositoryProvider).list(workspaceId);
});

final clientCrmRecordsProvider = FutureProvider<List<ClientCrmRecord>>((
  ref,
) async {
  final now = ref.watch(businessNowProvider);
  final clientsFuture = ref.watch(clientsProvider.future);
  final appointmentsFuture = ref.watch(appointmentsProvider.future);
  final paymentsFuture = ref.watch(invoicesProvider.future);
  final tasksFuture = ref.watch(allTasksProvider.future);

  final (clients, appointments, payments, tasks) = await (
    clientsFuture,
    appointmentsFuture,
    paymentsFuture,
    tasksFuture,
  ).wait;

  return buildClientCrmRecords(
    clients: clients,
    appointments: appointments.map(Appointment.fromMap),
    payments: payments,
    tasks: tasks,
    now: now,
  );
});

List<ClientCrmRecord> buildClientCrmRecords({
  required Iterable<Client> clients,
  required Iterable<Appointment> appointments,
  required Iterable<Payment> payments,
  required Iterable<SlateTask> tasks,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final appointmentsByContact = _groupByContactId(
    appointments,
    (item) => item.contactId,
  );
  final paymentsByContact = _groupByContactId(
    payments,
    (item) => item.contactId,
  );
  final tasksByContact = _groupByContactId(tasks, (item) => item.contactId);

  return clients.map((client) {
    final clientAppointments =
        appointmentsByContact[client.id] ?? const <Appointment>[];
    final clientPayments = paymentsByContact[client.id] ?? const <Payment>[];
    final clientTasks = tasksByContact[client.id] ?? const <SlateTask>[];

    return ClientCrmRecord(
      client: client,
      bookingCount: clientAppointments.length,
      completedBookingCount: clientAppointments
          .where((item) => item.status == 'completed')
          .length,
      nextBooking: _nextBooking(clientAppointments, current),
      lastBooking: _lastBooking(clientAppointments, current),
      lifetimeValue: clientPayments.fold<double>(
        0,
        (sum, item) => sum + item.collectedAmount,
      ),
      outstandingBalance: clientPayments.fold<double>(
        0,
        (sum, item) => sum + item.outstandingAmount,
      ),
      openTaskCount: clientTasks.where((item) => item.status != 'done').length,
      overdueTaskCount: clientTasks
          .where(
            (item) =>
                item.status != 'done' && _isOverdue(item.dueDate, current),
          )
          .length,
      evaluatedAt: current,
    );
  }).toList();
}

Map<String, List<T>> _groupByContactId<T>(
  Iterable<T> items,
  String? Function(T item) contactIdOf,
) {
  final grouped = <String, List<T>>{};
  for (final item in items) {
    final contactId = contactIdOf(item);
    if (contactId == null) continue;
    (grouped[contactId] ??= <T>[]).add(item);
  }
  return grouped;
}

class ClientCrmRecord {
  final Client client;
  final int bookingCount;
  final int completedBookingCount;
  final Appointment? nextBooking;
  final Appointment? lastBooking;
  final double lifetimeValue;
  final double outstandingBalance;
  final int openTaskCount;
  final int overdueTaskCount;
  final DateTime? evaluatedAt;

  const ClientCrmRecord({
    required this.client,
    required this.bookingCount,
    required this.completedBookingCount,
    required this.nextBooking,
    required this.lastBooking,
    required this.lifetimeValue,
    required this.outstandingBalance,
    required this.openTaskCount,
    required this.overdueTaskCount,
    this.evaluatedAt,
  });

  bool get needsAttention =>
      overdueTaskCount > 0 || outstandingBalance > 0 || client.status == 'lead';

  bool get isLead => client.status == 'lead';

  bool get isActive => client.status == 'active';

  bool get isInactive => client.status == 'inactive';

  bool get isDormant {
    final bookingDate = lastBooking?.startTime;
    final activityDate = client.lastActivityAt ?? client.createdAt;
    final latest = bookingDate == null
        ? activityDate
        : activityDate != null && activityDate.isAfter(bookingDate)
        ? activityDate
        : bookingDate;
    if (latest == null) return false;
    return (evaluatedAt ?? DateTime.now()).difference(latest).inDays >= 60;
  }

  String get segment {
    if (client.status == 'lead') return 'Lead';
    if (outstandingBalance > 0 || overdueTaskCount > 0) return 'Attention';
    if (isDormant) return 'Dormant';
    if (completedBookingCount >= 3) return 'Regular';
    return 'Active';
  }

  int get attentionScore {
    var score = 0;
    if (client.status == 'lead') score += 4;
    if (overdueTaskCount > 0) score += 5;
    if (outstandingBalance > 0) score += 3;
    if (nextBooking != null) score += 1;
    if (isDormant) score += 2;
    return score;
  }
}

Appointment? _nextBooking(List<Appointment> appointments, DateTime now) {
  final future =
      appointments
          .where(
            (item) =>
                !item.startTime.isBefore(now) &&
                !_terminalBookingStatuses.contains(item.status.toLowerCase()),
          )
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
  return future.isEmpty ? null : future.first;
}

Appointment? _lastBooking(List<Appointment> appointments, DateTime now) {
  final past =
      appointments.where((item) => item.startTime.isBefore(now)).toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
  return past.isEmpty ? null : past.first;
}

bool _isOverdue(DateTime? date, DateTime now) {
  if (date == null) return false;
  final todayOnly = DateTime(now.year, now.month, now.day);
  final dueOnly = DateTime(date.year, date.month, date.day);
  return dueOnly.isBefore(todayOnly);
}

const _terminalBookingStatuses = {'cancelled', 'no_show', 'completed'};
