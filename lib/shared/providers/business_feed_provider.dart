import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/business_feed_item.dart';
import '../models/slate_models.dart';
import '../repositories/slate_repositories.dart';
import '../utils/currency_format.dart';
import 'finance_provider.dart';
import 'workspace_provider.dart';
import 'workspace_settings_provider.dart';

final businessFeedProvider = FutureProvider<List<BusinessFeedItem>>((
  ref,
) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return const [];

  final current = DateTime.now().toLocal();
  final today = startOfDay(current);
  final weekAgo = addBusinessCalendarDays(today, -7);
  final appointmentsFuture = ref
      .watch(appointmentsRepositoryProvider)
      .listRowsForBusinessFeed(
        workspaceId,
        from: today,
        to: addBusinessCalendarDays(today, 91),
      );
  final paymentsFuture = ref
      .watch(paymentsRepositoryProvider)
      .listForBusinessFeed(
        workspaceId,
        recentPaidFrom: weekAgo,
        openDueThrough: addBusinessCalendarDays(today, 7),
      );
  final expensesFuture = ref
      .watch(expensesRepositoryProvider)
      .listForBusinessFeed(workspaceId, from: weekAgo);
  final tasksFuture = ref
      .watch(tasksRepositoryProvider)
      .dueOpenForBusinessFeed(workspaceId, through: today);
  final notesFuture = ref
      .watch(notesRepositoryProvider)
      .recentForBusinessFeed(workspaceId, from: weekAgo);
  final clientsFuture = ref
      .watch(clientsRepositoryProvider)
      .followUpsForBusinessFeed(
        workspaceId,
        leadBefore: current.subtract(const Duration(days: 7)),
        inactiveBefore: current.subtract(const Duration(days: 42)),
      );
  final bookingRequestsFuture = ref
      .watch(profileRepositoryProvider)
      .pendingBookingRequestsForBusinessFeed(workspaceId);
  final settingsFuture = ref.watch(workspaceSettingsProvider.future);

  final results = await Future.wait<Object?>([
    appointmentsFuture,
    paymentsFuture,
    expensesFuture,
    tasksFuture,
    notesFuture,
    clientsFuture,
    bookingRequestsFuture,
    settingsFuture,
  ]);
  final appointments = results[0]! as List<Map<String, dynamic>>;
  final payments = results[1]! as List<Payment>;
  final expenses = results[2]! as List<Expense>;
  final tasks = results[3]! as List<SlateTask>;
  final notes = results[4]! as List<SlateNote>;
  final clients = results[5]! as List<Client>;
  final bookingRequests = results[6]! as List<BookingRequest>;
  final settings = results[7] as Map<String, dynamic>?;
  final finance = FinanceSummary.from(
    payments: payments,
    expenses: expenses,
    monthlyTarget: (settings?['revenue_target'] as num?)?.toDouble() ?? 0,
    now: current,
  );

  return buildBusinessFeedItems(
    appointments: appointments,
    payments: payments,
    expenses: expenses,
    tasks: tasks,
    notes: notes,
    clients: clients,
    bookingRequests: bookingRequests,
    finance: finance,
    now: current,
  );
});

List<BusinessFeedItem> buildBusinessFeedItems({
  required List<Map<String, dynamic>> appointments,
  required List<Payment> payments,
  required List<Expense> expenses,
  required List<SlateTask> tasks,
  required List<SlateNote> notes,
  required List<Client> clients,
  required List<BookingRequest> bookingRequests,
  required FinanceSummary finance,
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = _startOfDay(current);
  final tomorrow = addBusinessCalendarDays(today, 1);
  final weekAgo = addBusinessCalendarDays(today, -7);
  final typedAppointments = appointments
      .map(Appointment.fromMap)
      .where((item) => item.startTime.year > 1970)
      .toList();
  final upcomingContactIds = typedAppointments
      .where(
        (item) =>
            item.contactId != null &&
            item.startTime.isAfter(current) &&
            !_cancelledStatuses.contains(item.status.toLowerCase()),
      )
      .map((item) => item.contactId!)
      .toSet();
  final items = <BusinessFeedItem>[];

  final activeToday = typedAppointments.where((item) {
    final start = item.startTime.toLocal();
    return !_cancelledStatuses.contains(item.status.toLowerCase()) &&
        !start.isBefore(today) &&
        start.isBefore(tomorrow);
  }).toList();
  final expectedToday = activeToday.fold<double>(
    0,
    (sum, item) => sum + item.price,
  );
  final dueTasks = tasks.where((task) {
    final due = task.dueDate;
    if (task.status == 'done' || due == null) return false;
    return !_startOfDay(due).isAfter(today);
  }).toList();
  final overdueTasks = dueTasks
      .where((task) => _startOfDay(task.dueDate!).isBefore(today))
      .toList();
  final overduePayments = payments.where((payment) {
    return moneyStatusFor(payment, now: current) == MoneyStatus.overdue &&
        outstandingAmountFor(payment) > 0;
  }).toList();
  final pendingRequests = bookingRequests
      .where((request) => request.status == 'pending')
      .toList();

  items.add(
    BusinessFeedItem(
      id: 'daily-summary-${_dateKey(today)}',
      type: BusinessFeedItemType.dailySummary,
      title: _dailySummaryTitle(
        appointmentCount: activeToday.length,
        expectedToday: expectedToday,
        dueTaskCount: dueTasks.length,
        overduePaymentCount: overduePayments.length,
      ),
      subtitle: _primaryRecommendation(
        overduePayments: overduePayments,
        overdueTasks: overdueTasks,
        pendingRequests: pendingRequests,
        activeToday: activeToday,
      ),
      timestamp: current,
      priority: overduePayments.isNotEmpty || overdueTasks.isNotEmpty
          ? BusinessFeedPriority.attention
          : BusinessFeedPriority.normal,
      sourceType: BusinessFeedSourceType.system,
      actionLabel: overduePayments.isNotEmpty
          ? 'Open Money'
          : overdueTasks.isNotEmpty
          ? 'Open Tasks'
          : activeToday.isNotEmpty
          ? 'Review bookings'
          : null,
      routeTarget: overduePayments.isNotEmpty
          ? '/payments'
          : overdueTasks.isNotEmpty
          ? '/tasks'
          : activeToday.isNotEmpty
          ? '/work'
          : null,
      icon: 'sparkles',
      moduleKey: 'home',
    ),
  );

  _addBookingItems(items, typedAppointments, current, today, tomorrow);
  _addPaymentItems(items, payments, today, weekAgo);
  _addExpenseItems(items, expenses, weekAgo, today);
  _addTaskItems(items, tasks, today);
  _addNoteItems(items, notes, weekAgo);
  _addClientFollowUps(items, clients, upcomingContactIds, current);
  _addBookingRequestItems(items, pendingRequests, current);
  _addQuietDayItem(items, activeToday, current, today);
  _addWeeklyProgressItem(items, finance, current);

  items.sort((a, b) {
    final priority = _priorityRank(
      a.priority,
    ).compareTo(_priorityRank(b.priority));
    if (priority != 0) return priority;
    return b.timestamp.compareTo(a.timestamp);
  });
  return _dedupeById(items).take(80).toList();
}

List<BusinessFeedItem> filteredBusinessFeedItems(
  List<BusinessFeedItem> items,
  BusinessFeedFilter filter,
) {
  return items.where((item) => item.matchesFilter(filter)).toList();
}

void _addBookingItems(
  List<BusinessFeedItem> items,
  List<Appointment> appointments,
  DateTime current,
  DateTime today,
  DateTime tomorrow,
) {
  final upcomingLimit = current.add(const Duration(days: 14));
  for (final appointment in appointments) {
    final start = appointment.startTime.toLocal();
    final status = appointment.status.toLowerCase();
    if (_cancelledStatuses.contains(status)) continue;

    final isToday = !start.isBefore(today) && start.isBefore(tomorrow);
    final isUpcoming = start.isAfter(tomorrow) && start.isBefore(upcomingLimit);
    if (!isToday && !isUpcoming) continue;

    items.add(
      BusinessFeedItem(
        id: 'booking-${appointment.id}',
        type: isToday
            ? BusinessFeedItemType.bookingToday
            : BusinessFeedItemType.bookingUpcoming,
        title: isToday
            ? '${appointment.clientName ?? 'Booking'} today'
            : '${appointment.clientName ?? 'Booking'} is coming up',
        subtitle:
            '${_timeLabel(start)} · ${appointment.serviceName ?? appointment.title ?? 'Booking'}',
        timestamp: start,
        priority: isToday
            ? BusinessFeedPriority.normal
            : BusinessFeedPriority.positive,
        sourceType: BusinessFeedSourceType.booking,
        sourceId: appointment.id,
        actionLabel: 'Open bookings',
        routeTarget: '/work',
        icon: 'calendar',
        moduleKey: 'bookings',
      ),
    );
  }
}

void _addPaymentItems(
  List<BusinessFeedItem> items,
  List<Payment> payments,
  DateTime today,
  DateTime weekAgo,
) {
  for (final payment in payments) {
    final due = _startOfDay(payment.dueDate ?? payment.issueDate);
    if (payment.sourceDocumentId != null) {
      for (final receipt in payment.cashReceipts) {
        if (receipt.receivedAt.isBefore(weekAgo) || receipt.amount == 0) {
          continue;
        }
        items.add(
          BusinessFeedItem(
            id: 'payment-receipt-${receipt.id}',
            type: BusinessFeedItemType.paymentReceived,
            title: receipt.amount < 0 ? 'Refund recorded' : 'Payment received',
            subtitle:
                '${formatPounds(receipt.amount.abs())}${payment.clientName == null ? '' : ' · ${payment.clientName}'} · ${payment.number}',
            timestamp: receipt.receivedAt,
            priority: BusinessFeedPriority.normal,
            sourceType: BusinessFeedSourceType.payment,
            sourceId: payment.id,
            actionLabel: 'View payment',
            routeTarget: '/payments/${payment.id}',
            icon: 'banknote',
            moduleKey: 'money',
          ),
        );
      }
      if (payment.status == 'paid') continue;
    } else if (payment.status == 'paid') {
      final received = receivedAmountFor(payment);
      if (received <= 0) continue;
      final paidDay = _startOfDay(payment.receivedDate);
      if (paidDay.isBefore(weekAgo)) continue;
      items.add(
        BusinessFeedItem(
          id: 'payment-paid-${payment.id}',
          type: BusinessFeedItemType.paymentReceived,
          title: 'Paid payment',
          subtitle:
              '${formatPounds(received)}${payment.clientName == null ? '' : ' from ${payment.clientName}'} · Business date ${_businessDateLabel(paidDay, today)}',
          timestamp: payment.receivedDate,
          priority: BusinessFeedPriority.positive,
          sourceType: BusinessFeedSourceType.payment,
          sourceId: payment.id,
          actionLabel: 'Open Money',
          routeTarget: '/payments',
          icon: 'banknote',
          moduleKey: 'money',
        ),
      );
      continue;
    }

    final outstanding = outstandingAmountFor(payment);
    if (outstanding <= 0) continue;
    if (due.isBefore(today)) {
      final days = today.difference(due).inDays;
      items.add(
        BusinessFeedItem(
          id: 'payment-overdue-${payment.id}',
          type: BusinessFeedItemType.invoiceOverdue,
          title: 'Invoice overdue',
          subtitle:
              '${formatPounds(outstanding)}${payment.clientName == null ? '' : ' from ${payment.clientName}'} was due $days day${days == 1 ? '' : 's'} ago',
          timestamp: due,
          priority: BusinessFeedPriority.attention,
          sourceType: BusinessFeedSourceType.payment,
          sourceId: payment.id,
          actionLabel: 'Send reminder',
          routeTarget: '/payments',
          icon: 'alert',
          moduleKey: 'money',
        ),
      );
    } else if (!due.isAfter(addBusinessCalendarDays(today, 7))) {
      items.add(
        BusinessFeedItem(
          id: 'payment-unpaid-${payment.id}',
          type: BusinessFeedItemType.invoiceUnpaid,
          title: 'Payment still open',
          subtitle:
              '${formatPounds(outstanding)}${payment.clientName == null ? '' : ' from ${payment.clientName}'} due ${_relativeDay(due, today)}',
          timestamp: due,
          priority: BusinessFeedPriority.normal,
          sourceType: BusinessFeedSourceType.payment,
          sourceId: payment.id,
          actionLabel: 'Open Money',
          routeTarget: '/payments',
          icon: 'clock',
          moduleKey: 'money',
        ),
      );
    }
  }
}

void _addExpenseItems(
  List<BusinessFeedItem> items,
  List<Expense> expenses,
  DateTime weekAgo,
  DateTime today,
) {
  final recentExpenses = expenses
      .where((expense) => !expense.expenseDate.isBefore(weekAgo))
      .take(12);
  for (final expense in recentExpenses) {
    items.add(
      BusinessFeedItem(
        id: 'expense-${expense.id}',
        type: BusinessFeedItemType.expenseRecorded,
        title: 'Expense logged',
        subtitle:
            '${formatPounds(expense.amount)} · ${expense.category} · Business date ${_businessDateLabel(expense.expenseDate, today)}',
        timestamp: expense.expenseDate,
        priority: BusinessFeedPriority.normal,
        sourceType: BusinessFeedSourceType.expense,
        sourceId: expense.id,
        actionLabel: 'Open Money',
        routeTarget: '/payments',
        icon: 'receipt',
        moduleKey: 'money',
      ),
    );
  }
}

void _addTaskItems(
  List<BusinessFeedItem> items,
  List<SlateTask> tasks,
  DateTime today,
) {
  for (final task in tasks) {
    final due = task.dueDate;
    if (task.status == 'done' || due == null) continue;
    final dueDay = _startOfDay(due);
    final isOverdue = dueDay.isBefore(today);
    if (!isOverdue && dueDay.isAfter(today)) continue;

    items.add(
      BusinessFeedItem(
        id: 'task-${task.id}',
        type: isOverdue
            ? BusinessFeedItemType.taskOverdue
            : BusinessFeedItemType.taskDue,
        title: task.title,
        subtitle: isOverdue
            ? 'Overdue${task.clientName == null ? '' : ' · ${task.clientName}'}'
            : 'Due today${task.clientName == null ? '' : ' · ${task.clientName}'}',
        timestamp: dueDay,
        priority: isOverdue
            ? BusinessFeedPriority.attention
            : BusinessFeedPriority.normal,
        sourceType: BusinessFeedSourceType.task,
        sourceId: task.id,
        actionLabel: 'Open Tasks',
        routeTarget: '/tasks',
        icon: isOverdue ? 'alert' : 'check',
        moduleKey: 'tasks',
      ),
    );
  }
}

void _addNoteItems(
  List<BusinessFeedItem> items,
  List<SlateNote> notes,
  DateTime weekAgo,
) {
  final recentNotes =
      notes
          .map(
            (note) => _FeedNote(
              note: note,
              timestamp: note.updatedAt ?? note.createdAt,
            ),
          )
          .where(
            (entry) =>
                entry.timestamp != null && !entry.timestamp!.isBefore(weekAgo),
          )
          .toList()
        ..sort((a, b) => b.timestamp!.compareTo(a.timestamp!));

  for (final entry in recentNotes.take(10)) {
    final note = entry.note;
    final timestamp = entry.timestamp!;
    items.add(
      BusinessFeedItem(
        id: 'note-${note.id}',
        type: BusinessFeedItemType.noteCreated,
        title: note.pinned ? 'Pinned note: ${note.title}' : note.title,
        subtitle: note.clientName ?? 'Recent note',
        timestamp: timestamp,
        priority: note.pinned
            ? BusinessFeedPriority.positive
            : BusinessFeedPriority.normal,
        sourceType: BusinessFeedSourceType.note,
        sourceId: note.id,
        actionLabel: 'Open Notes',
        routeTarget: '/notes',
        icon: 'note',
        moduleKey: 'notes',
      ),
    );
  }
}

void _addClientFollowUps(
  List<BusinessFeedItem> items,
  List<Client> clients,
  Set<String> upcomingContactIds,
  DateTime current,
) {
  for (final client in clients) {
    if (client.status != 'active' && client.status != 'lead') continue;
    final latest = client.lastActivityAt ?? client.createdAt;
    if (latest == null || upcomingContactIds.contains(client.id)) continue;
    final days = current.difference(latest).inDays;
    final isLead = client.status == 'lead';
    if (!isLead && days < 42) continue;
    if (isLead && days < 7) continue;
    items.add(
      BusinessFeedItem(
        id: 'client-follow-up-${client.id}',
        type: BusinessFeedItemType.clientFollowUp,
        title: '${client.name} is due a follow-up',
        subtitle: isLead
            ? 'Lead waiting $days day${days == 1 ? '' : 's'}'
            : 'No booking in ${days ~/ 7} week${days ~/ 7 == 1 ? '' : 's'}',
        timestamp: latest,
        priority: BusinessFeedPriority.attention,
        sourceType: BusinessFeedSourceType.client,
        sourceId: client.id,
        actionLabel: 'Open Clients',
        routeTarget: '/clients',
        icon: 'user',
        moduleKey: 'clients',
      ),
    );
  }
}

void _addBookingRequestItems(
  List<BusinessFeedItem> items,
  List<BookingRequest> requests,
  DateTime current,
) {
  for (final request in requests.take(8)) {
    final timestamp = request.createdAt ?? current;
    items.add(
      BusinessFeedItem(
        id: 'booking-request-${request.id}',
        type: BusinessFeedItemType.bookingRequestNew,
        title: 'New booking request',
        subtitle:
            '${request.name}${request.preferredTimeText == null ? '' : ' requested ${request.preferredTimeText}'}',
        timestamp: timestamp,
        priority: BusinessFeedPriority.attention,
        sourceType: BusinessFeedSourceType.bookingRequest,
        sourceId: request.id,
        actionLabel: 'Review request',
        routeTarget: '/booking-requests',
        icon: 'inbox',
        moduleKey: 'bookings',
      ),
    );
  }
}

void _addQuietDayItem(
  List<BusinessFeedItem> items,
  List<Appointment> activeToday,
  DateTime current,
  DateTime today,
) {
  final afternoonStart = DateTime(today.year, today.month, today.day, 14);
  final hasAfternoonBooking = activeToday.any(
    (item) => !item.startTime.toLocal().isBefore(afternoonStart),
  );
  if (current.isAfter(afternoonStart) || hasAfternoonBooking) return;
  items.add(
    BusinessFeedItem(
      id: 'quiet-afternoon-${_dateKey(today)}',
      type: BusinessFeedItemType.quietDayDetected,
      title: 'Quiet afternoon detected',
      subtitle: 'No bookings after 2pm today',
      timestamp: afternoonStart,
      priority: BusinessFeedPriority.normal,
      sourceType: BusinessFeedSourceType.system,
      actionLabel: 'Open Bookings',
      routeTarget: '/work',
      icon: 'clock',
      moduleKey: 'home',
    ),
  );
}

void _addWeeklyProgressItem(
  List<BusinessFeedItem> items,
  FinanceSummary finance,
  DateTime current,
) {
  if (finance.weeklyTarget <= 0) return;
  final percent = (finance.weeklyProgress * 100).round();
  items.add(
    BusinessFeedItem(
      id: 'weekly-target-${_dateKey(_startOfWeek(current))}',
      type: BusinessFeedItemType.weeklyTargetProgress,
      title: '$percent% of weekly target reached',
      subtitle:
          '${formatPounds(finance.thisWeekPaid)} of ${formatPounds(finance.weeklyTarget)}',
      timestamp: current,
      priority: finance.weeklyProgress >= 1
          ? BusinessFeedPriority.positive
          : BusinessFeedPriority.normal,
      sourceType: BusinessFeedSourceType.system,
      actionLabel: 'Open Money',
      routeTarget: '/payments',
      icon: 'target',
      moduleKey: 'money',
    ),
  );
}

String _dailySummaryTitle({
  required int appointmentCount,
  required double expectedToday,
  required int dueTaskCount,
  required int overduePaymentCount,
}) {
  final parts = <String>[
    '$appointmentCount booking${appointmentCount == 1 ? '' : 's'}',
    '${formatPounds(expectedToday)} expected',
    '$dueTaskCount task${dueTaskCount == 1 ? '' : 's'} due',
  ];
  if (overduePaymentCount > 0) {
    parts.add(
      '$overduePaymentCount payment${overduePaymentCount == 1 ? '' : 's'} overdue',
    );
  }
  return 'Today: ${parts.join(', ')}.';
}

String _primaryRecommendation({
  required List<Payment> overduePayments,
  required List<SlateTask> overdueTasks,
  required List<BookingRequest> pendingRequests,
  required List<Appointment> activeToday,
}) {
  if (overduePayments.isNotEmpty) return 'Send overdue payment reminder';
  if (pendingRequests.isNotEmpty) return 'Review new booking request';
  if (overdueTasks.isNotEmpty) return 'Clear overdue tasks';
  if (activeToday.isNotEmpty) return 'Review today\'s bookings';
  return 'No urgent actions today';
}

List<BusinessFeedItem> _dedupeById(List<BusinessFeedItem> items) {
  final seen = <String>{};
  return items.where((item) => seen.add(item.id)).toList();
}

DateTime _startOfDay(DateTime date) => startOfDay(date);

DateTime _startOfWeek(DateTime now) => startOfWeek(now);

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _timeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _relativeDay(DateTime date, DateTime today) {
  final day = _startOfDay(date);
  if (day == today) return 'today';
  if (day == addBusinessCalendarDays(today, -1)) return 'yesterday';
  if (day == addBusinessCalendarDays(today, 1)) return 'tomorrow';
  return _dateKey(day);
}

String _businessDateLabel(DateTime date, DateTime today) {
  final day = _startOfDay(date);
  if (day == today) return 'today';
  if (day == addBusinessCalendarDays(today, -1)) return 'yesterday';
  if (day == addBusinessCalendarDays(today, 1)) return 'tomorrow';
  return _dateKey(day);
}

class _FeedNote {
  final SlateNote note;
  final DateTime? timestamp;

  const _FeedNote({required this.note, required this.timestamp});
}

int _priorityRank(BusinessFeedPriority priority) {
  return switch (priority) {
    BusinessFeedPriority.attention => 0,
    BusinessFeedPriority.positive => 1,
    BusinessFeedPriority.normal => 2,
  };
}

const _cancelledStatuses = {'cancelled', 'no_show'};
