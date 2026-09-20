import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/slate_models.dart';
import '../utils/currency_format.dart';
import '../utils/client_follow_up.dart';
import '../repositories/slate_repositories.dart';
import 'client_follow_up_provider.dart';
import 'appointments_provider.dart';
import 'business_clock_provider.dart';
import 'booking_requests_provider.dart';
import 'clients_provider.dart';
import 'finance_provider.dart';
import 'notes_provider.dart';
import 'notifications_provider.dart';
import 'setup_checklist_provider.dart';
import 'tasks_provider.dart';

const dashboardUnpaidThreshold = Duration(days: 3);
const dashboardUncontactedThreshold = Duration(days: 7);
const dashboardClientFollowUpThreshold = Duration(days: 42);

class DashboardRevenue {
  final double weekTotal;
  final double monthTotal;
  final double weekExpenses;
  final double monthExpenses;
  final double outstanding;
  final double revenueTarget;

  const DashboardRevenue({
    required this.weekTotal,
    required this.monthTotal,
    required this.weekExpenses,
    required this.monthExpenses,
    required this.outstanding,
    required this.revenueTarget,
  });
}

class DashboardFocus {
  final Map<String, dynamic>? nextAppointment;
  final int pendingBookingRequests;
  final int overduePayments;
  final double overdueTotal;

  const DashboardFocus({
    required this.nextAppointment,
    required this.pendingBookingRequests,
    required this.overduePayments,
    required this.overdueTotal,
  });

  bool get hasAttention =>
      pendingBookingRequests > 0 ||
      overduePayments > 0 ||
      nextAppointment != null;
}

DashboardRevenue dashboardRevenueFromFinance(FinanceSummary summary) {
  return DashboardRevenue(
    weekTotal: summary.thisWeekPaid,
    monthTotal: summary.thisMonthPaid,
    weekExpenses: summary.thisWeekExpenses,
    monthExpenses: summary.thisMonthExpenses,
    outstanding: summary.unpaid + summary.overdue,
    revenueTarget: summary.monthlyTarget,
  );
}

DashboardFocus dashboardFocusFrom({
  required Map<String, dynamic>? nextAppointment,
  required int pendingBookingRequests,
  required List<Payment> payments,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final overdue = payments
      .where(
        (payment) =>
            moneyStatusFor(payment, now: current) == MoneyStatus.overdue &&
            outstandingAmountFor(payment) > 0,
      )
      .toList();
  return DashboardFocus(
    nextAppointment: nextAppointment,
    pendingBookingRequests: pendingBookingRequests,
    overduePayments: overdue.length,
    overdueTotal: overdue.fold<double>(
      0,
      (sum, payment) => sum + outstandingAmountFor(payment),
    ),
  );
}

final dashboardRevenueProvider = FutureProvider<DashboardRevenue>((ref) async {
  final summary = await ref.watch(financeSummaryProvider.future);
  return dashboardRevenueFromFinance(summary);
});

final todayAppointmentsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final today = ref.watch(businessTodayProvider);
  final tomorrow = addBusinessCalendarDays(today, 1);
  final rows = await ref.watch(appointmentsProvider.future);
  return rows.where((row) {
    final start = Appointment.fromMap(row).startTime;
    return !start.isBefore(today) && start.isBefore(tomorrow);
  }).toList();
});

final dashboardFocusProvider = FutureProvider<DashboardFocus>((ref) async {
  final now = ref.watch(businessNowProvider);
  final (appointments, requests, payments) = await (
    ref.watch(appointmentsProvider.future),
    ref.watch(bookingRequestsProvider.future),
    ref.watch(invoicesProvider.future),
  ).wait;
  final upcoming =
      appointments.where((row) {
        final item = Appointment.fromMap(row);
        return !item.startTime.isBefore(now) &&
            !const {
              'cancelled',
              'completed',
              'no_show',
            }.contains(item.status.toLowerCase());
      }).toList()..sort(
        (a, b) => Appointment.fromMap(
          a,
        ).startTime.compareTo(Appointment.fromMap(b).startTime),
      );

  return dashboardFocusFrom(
    nextAppointment: upcoming.firstOrNull,
    pendingBookingRequests: requests.where((item) => item.needsDecision).length,
    payments: payments,
    now: now,
  );
});

enum DashboardAttentionType {
  bookingRequest,
  unpaid,
  overdueTask,
  clientFollowUp,
}

class DashboardAttentionItem {
  final DashboardAttentionType type;
  final String title;
  final String detail;
  final Object source;
  final DateTime sortTime;

  const DashboardAttentionItem({
    required this.type,
    required this.title,
    required this.detail,
    required this.source,
    required this.sortTime,
  });

  /// A row opens the entity it describes; a count or mismatched source cannot
  /// identify a record and must never be used to guess a destination.
  String? get entityRoute {
    final target = switch ((type, source)) {
      (DashboardAttentionType.bookingRequest, BookingRequest(:final id)) => (
        'booking-requests',
        id,
      ),
      (DashboardAttentionType.unpaid, Payment(:final id)) => ('payments', id),
      (DashboardAttentionType.overdueTask, SlateTask(:final id)) => (
        'tasks',
        id,
      ),
      (DashboardAttentionType.clientFollowUp, Client(:final id)) => (
        'clients',
        id,
      ),
      _ => null,
    };
    if (target == null || target.$2.trim().isEmpty) return null;
    return Uri(pathSegments: ['', target.$1, target.$2]).toString();
  }
}

final dashboardAttentionProvider = FutureProvider<List<DashboardAttentionItem>>(
  (ref) async {
    final now = ref.watch(businessNowProvider);
    final paymentsFuture = ref.watch(invoicesProvider.future);
    final tasksFuture = ref.watch(allTasksProvider.future);
    final appointmentsFuture = ref.watch(appointmentsProvider.future);
    final clientsFuture = ref.watch(clientsProvider.future);
    final requestsFuture = ref.watch(bookingRequestsProvider.future);

    final results = await Future.wait<Object?>([
      paymentsFuture,
      tasksFuture,
      appointmentsFuture,
      clientsFuture,
      requestsFuture,
    ]);
    final payments = results[0]! as List<Payment>;
    final tasks = results[1]! as List<SlateTask>;
    final appointments = results[2]! as List<Map<String, dynamic>>;
    final clients = results[3]! as List<Client>;
    final requests = results[4]! as List<BookingRequest>;
    var snoozes = <String, DateTime>{};
    if (clients.isNotEmpty) {
      final userId = ref.watch(authRepositoryProvider).currentUserId;
      if (userId != null) {
        snoozes = await ref.watch(
          clientFollowUpSnoozesProvider((
            userId: userId,
            workspaceId: clients.first.workspaceId,
          )).future,
        );
      }
    }

    return buildDashboardAttentionItems(
      bookingRequests: requests,
      payments: payments,
      tasks: tasks,
      appointments: appointments,
      clients: clients,
      now: now,
      snoozedClientFollowUps: snoozes,
    );
  },
);

/// Settles every async value rendered on the first Today frame.
///
/// Individual feature providers remain reusable and independently refreshable,
/// but opening the app must not briefly combine loaded schedule data with
/// placeholder money, task, note, or notification values.
final dashboardInitialDataProvider = FutureProvider<void>((ref) async {
  await Future.wait<Object?>([
    ref.watch(appointmentsProvider.future),
    ref.watch(dashboardAttentionProvider.future),
    ref.watch(financeSummaryProvider.future),
    ref.watch(allTasksProvider.future),
    ref.watch(allNotesProvider.future),
    ref.watch(unreadNotificationsProvider.future),
    ref.watch(setupChecklistDismissedProvider.future),
  ]);
});

List<DashboardAttentionItem> buildDashboardAttentionItems({
  required List<BookingRequest> bookingRequests,
  required List<Payment> payments,
  required List<SlateTask> tasks,
  required List<Map<String, dynamic>> appointments,
  required List<Client> clients,
  DateTime? now,
  Map<String, DateTime> snoozedClientFollowUps = const {},
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = startOfDay(current);
  final items = <DashboardAttentionItem>[];

  for (final request in bookingRequests) {
    if (!request.needsDecision || request.id.trim().isEmpty) continue;
    final name = request.name.trim();
    final service = request.serviceName?.trim() ?? '';
    items.add(
      DashboardAttentionItem(
        type: DashboardAttentionType.bookingRequest,
        title: name.isEmpty
            ? 'Review booking request'
            : 'Review $name’s request',
        detail: service.isEmpty
            ? 'Awaiting a booking decision'
            : '$service · Awaiting decision',
        source: request,
        sortTime: request.createdAt ?? current,
      ),
    );
  }

  for (final payment in payments) {
    if (payment.status == 'paid') continue;
    final outstanding = outstandingAmountFor(payment);
    if (outstanding <= 0) continue;
    final dueDate = payment.dueDate ?? payment.issueDate;
    final dueDay = startOfDay(dueDate);
    // Calendar-day comparisons stay correct across daylight-saving changes.
    if (!dueDay.isBefore(
      addBusinessCalendarDays(today, -dashboardUnpaidThreshold.inDays),
    )) {
      continue;
    }
    items.add(
      DashboardAttentionItem(
        type: DashboardAttentionType.unpaid,
        title: 'Collect ${formatPounds(outstanding)}',
        detail: payment.clientName ?? payment.number,
        source: payment,
        sortTime: dueDate,
      ),
    );
  }

  for (final task in tasks) {
    final due = task.dueDate;
    if (task.status == 'done' || due == null) continue;
    final dueDay = startOfDay(due);
    if (!dueDay.isBefore(today)) continue;
    items.add(
      DashboardAttentionItem(
        type: DashboardAttentionType.overdueTask,
        title: task.title,
        detail: task.clientName ?? 'Overdue task',
        source: task,
        sortTime: due,
      ),
    );
  }

  for (final followUp in clientFollowUps(
    clients: clients,
    appointments: appointments.map(Appointment.fromMap).toList(),
    requests: bookingRequests,
    tasks: tasks,
    now: current,
    snoozedUntil: snoozedClientFollowUps,
  )) {
    final client = followUp.client;
    final isLead = client.status == 'lead';
    items.add(
      DashboardAttentionItem(
        type: DashboardAttentionType.clientFollowUp,
        title: isLead
            ? 'Contact ${client.name}'
            : 'Check in with ${client.name}',
        detail: isLead
            ? 'Lead waiting ${followUp.daysSinceVisit}d'
            : '${followUp.daysSinceVisit} days since last visit · Usually ${followUp.usualDays} days',
        source: client,
        sortTime: followUp.lastVisit,
      ),
    );
  }

  items.sort((a, b) {
    final priority = _dashboardAttentionPriority(
      a.type,
    ).compareTo(_dashboardAttentionPriority(b.type));
    if (priority != 0) return priority;
    return a.sortTime.compareTo(b.sortTime);
  });
  return items;
}

/// Preserve the category coverage of the former request summary while giving
/// each visible row one exact target. Input is already in priority/time order.
List<DashboardAttentionItem> selectDashboardAttentionPreview(
  List<DashboardAttentionItem> items, {
  int limit = 4,
}) {
  if (limit <= 0) return const [];
  final selected = <int>{};
  final types = <DashboardAttentionType>{};
  for (
    var index = 0;
    index < items.length && selected.length < limit;
    index++
  ) {
    if (types.add(items[index].type)) selected.add(index);
  }
  for (
    var index = 0;
    index < items.length && selected.length < limit;
    index++
  ) {
    selected.add(index);
  }
  final indexes = selected.toList()..sort();
  return [for (final index in indexes) items[index]];
}

int _dashboardAttentionPriority(DashboardAttentionType type) {
  return switch (type) {
    DashboardAttentionType.bookingRequest => 0,
    DashboardAttentionType.overdueTask => 1,
    DashboardAttentionType.unpaid => 2,
    DashboardAttentionType.clientFollowUp => 3,
  };
}
