import '../../shared/models/slate_models.dart';
import 'report_models.dart';
import 'cashflow_forecast.dart';

class _Cash {
  final Payment payment;
  final DateTime day;
  final int pence;
  const _Cash(this.payment, this.day, this.pence);
}

/// Pure calculation layer. Round each stored movement to pennies before summing.
BusinessReport buildBusinessReport({
  required ReportSource source,
  required ReportKind kind,
  required ReportRange range,
  required DateTime now,
  CashflowAssumptions forecast = const CashflowAssumptions(),
}) {
  if (kind == ReportKind.forecast) {
    return buildCashflowForecast(
      source: source,
      now: now,
      assumptions: forecast,
    ).report;
  }
  final today = reportDay(source.civil(now));
  final previous = range.previous;
  final cash = <_Cash>[
    for (final payment in source.payments)
      for (final receipt in payment.cashReceipts)
        if (reportPence(receipt.amount) != 0 &&
            !source.receiptDay(payment, receipt).isAfter(today))
          _Cash(
            payment,
            source.receiptDay(payment, receipt),
            reportPence(receipt.amount),
          ),
  ];
  final selectedCash = cash.where((c) => range.contains(c.day)).toList()
    ..sort((a, b) => b.day.compareTo(a.day));
  final expenses =
      source.expenses
          .where(
            (e) =>
                range.contains(e.expenseDate) &&
                !reportDay(e.expenseDate).isAfter(today),
          )
          .toList()
        ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
  final bookings =
      source.bookings
          .where((b) => range.contains(source.civil(b.startTime)))
          .toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
  final completed = bookings.where((b) => b.status == 'completed').toList();
  final collected = selectedCash.fold<int>(0, (sum, c) => sum + c.pence);
  final spent = expenses.fold<int>(0, (sum, e) => sum + reportPence(e.amount));
  final priorCash = cash
      .where((c) => previous.contains(c.day))
      .fold<int>(0, (sum, c) => sum + c.pence);
  final priorSpent = source.expenses
      .where(
        (e) =>
            previous.contains(e.expenseDate) &&
            !reportDay(e.expenseDate).isAfter(today),
      )
      .fold<int>(0, (sum, e) => sum + reportPence(e.amount));
  final priorBookings = source.bookings
      .where((b) => previous.contains(source.civil(b.startTime)))
      .length;
  final clientsById = {for (final c in source.clients) c.id: c};
  final bookingsById = {for (final b in source.bookings) b.id: b};
  String clientName(String? id, String? fallback) =>
      clientsById[id]?.name ??
      fallback ??
      (id == null ? 'No client linked' : 'Client no longer saved');
  String? paymentClientId(Payment p) =>
      p.contactId ?? bookingsById[p.appointmentId]?.contactId;
  String paymentClientName(Payment p) =>
      clientName(paymentClientId(p), p.clientName);
  String change(int value, int prior) =>
      '${value == prior ? 'Same as' : '${reportMoney((value - prior).abs())} ${value > prior ? 'more' : 'less'} than'} ${previous.label}';
  String countChange(int value, int prior) =>
      '${value == prior ? 'Same as' : '${(value - prior).abs()} ${value > prior ? 'more' : 'fewer'} than'} ${previous.label}';
  final moneyBasis =
      'Money received is what customers paid, with refunds taken off. We use the date each payment or refund was recorded; older payments may have just one payment date. Expenses use the date you entered. Money left after expenses is the difference between the two, before tax. It does not show your bank balance. Future-dated amounts are left out.';

  switch (kind) {
    case ReportKind.forecast:
      throw StateError('Forecast handled above.');
    case ReportKind.overview:
      final months = <String, List<int>>{};
      List<int> month(DateTime date) =>
          months.putIfAbsent(reportDate(date).substring(0, 7), () => [0, 0, 0]);
      for (final c in selectedCash) {
        month(c.day)[0] += c.pence;
      }
      for (final e in expenses) {
        month(e.expenseDate)[1] += reportPence(e.amount);
      }
      for (final b in bookings) {
        month(source.civil(b.startTime))[2]++;
      }
      final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
      return BusinessReport(
        kind: kind,
        basis:
            '$moneyBasis Bookings are counted on the day they start. We compare with the same number of days immediately before your chosen dates (${previous.label}). The monthly breakdown shows months with activity.',
        metrics: [
          ReportMetric(
            'Money received after refunds',
            reportMoney(collected),
            change(collected, priorCash),
          ),
          ReportMetric(
            'Expenses',
            reportMoney(spent),
            change(spent, priorSpent),
          ),
          ReportMetric(
            'Money left after expenses',
            reportMoney(collected - spent),
            change(collected - spent, priorCash - priorSpent),
          ),
          ReportMetric(
            'Bookings',
            '${bookings.length}',
            countChange(bookings.length, priorBookings),
          ),
          ReportMetric('Completed bookings', '${completed.length}'),
          ReportMetric(
            'Clients added',
            '${source.clients.where((c) => c.createdAt != null && range.contains(source.civil(c.createdAt!))).length}',
          ),
        ],
        columns: [
          'Month',
          'Money received after refunds GBP',
          'Expenses GBP',
          'Money left after expenses GBP',
          'Bookings',
        ],
        rows: [
          for (final key in keys)
            [
              key,
              months[key]![0] / 100,
              months[key]![1] / 100,
              (months[key]![0] - months[key]![1]) / 100,
              months[key]![2],
            ],
        ],
        emptyMessage:
            'Your reports will take shape as you record payments, expenses and bookings.',
      );
    case ReportKind.cash:
      final receipts = selectedCash
          .where((c) => c.pence > 0)
          .fold<int>(0, (sum, c) => sum + c.pence);
      final refunds = selectedCash
          .where((c) => c.pence < 0)
          .fold<int>(0, (sum, c) => sum - c.pence);
      return BusinessReport(
        kind: kind,
        basis:
            'This lists customer payments, part-payments and refunds on the dates they were recorded. Money received after refunds is the amount paid in, less money returned to customers. Older payments may have a single recorded date. Payments with future dates are left out. Comparisons use the same number of days immediately before your chosen dates.',
        metrics: [
          ReportMetric('Customer payments', reportMoney(receipts)),
          ReportMetric('Money refunded', reportMoney(refunds)),
          ReportMetric(
            'Money received after refunds',
            reportMoney(collected),
            change(collected, priorCash),
          ),
        ],
        columns: [
          'Date',
          'Client',
          'Reference',
          'Payment or refund',
          'Amount GBP',
          'Payment ID',
        ],
        rows: [
          for (final c in selectedCash)
            [
              reportDate(c.day),
              paymentClientName(c.payment),
              c.payment.number,
              c.pence < 0 ? 'Refund' : 'Payment received',
              c.pence / 100,
              c.payment.id,
            ],
        ],
      );
    case ReportKind.expenses:
      final categories = <String, int>{};
      for (final e in expenses) {
        categories.update(
          e.category,
          (v) => v + reportPence(e.amount),
          ifAbsent: () => reportPence(e.amount),
        );
      }
      final sorted = categories.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return BusinessReport(
        kind: kind,
        basis:
            'This adds up expenses dated within your chosen period. Refunds or corrections reduce the total; future expenses are left out. Each expense counts once, even when a receipt is attached. Mileage allowances are separate. These totals show spending, not which costs you can claim against tax.',
        metrics: [
          ReportMetric(
            'Total spending',
            reportMoney(spent),
            change(spent, priorSpent),
          ),
          ReportMetric('Expenses recorded', '${expenses.length}'),
          for (final c in sorted) ReportMetric(c.key, reportMoney(c.value)),
        ],
        columns: ['Date', 'Category', 'Amount GBP', 'Notes', 'Expense ID'],
        rows: [
          for (final e in expenses)
            [
              reportDate(e.expenseDate),
              e.category,
              reportPence(e.amount) / 100,
              e.notes ?? '',
              e.id,
            ],
        ],
      );
    case ReportKind.bookings:
      final cancelled = bookings.where((b) => b.status == 'cancelled').length;
      final noShows = bookings.where((b) => b.status == 'no_show').length;
      final resolved = completed.length + cancelled + noShows;
      final value = completed.fold<int>(
        0,
        (sum, b) => sum + reportPence(b.price),
      );
      final minutes = completed.fold<int>(
        0,
        (sum, b) =>
            sum +
            (b.endTime == null
                ? 0
                : b.endTime!
                      .difference(b.startTime)
                      .inMinutes
                      .clamp(0, 525600)),
      );
      return BusinessReport(
        kind: kind,
        basis:
            'Bookings are included on the day they start, using your business timezone. Completed means you have marked the booking done. Completion rate compares completed bookings with completed, cancelled and missed bookings; work still scheduled is left out of that percentage. Value uses the booking price, whether or not you have been paid. Hours need both a start and end time.',
        metrics: [
          ReportMetric(
            'Total bookings',
            '${bookings.length}',
            countChange(bookings.length, priorBookings),
          ),
          ReportMetric('Completed', '${completed.length}'),
          ReportMetric('Cancelled', '$cancelled'),
          ReportMetric('No-shows', '$noShows'),
          ReportMetric(
            'Completion rate',
            resolved == 0
                ? '—'
                : '${(completed.length * 100 / resolved).toStringAsFixed(1)}%',
          ),
          ReportMetric('Value of completed work', reportMoney(value)),
          ReportMetric(
            'Hours of completed work',
            (minutes / 60).toStringAsFixed(1),
          ),
        ],
        columns: [
          'Date',
          'Client',
          'Service',
          'Status',
          'Booking price GBP',
          'Booking ID',
        ],
        rows: [
          for (final b in bookings)
            [
              reportDate(source.civil(b.startTime)),
              clientName(b.contactId, b.clientName),
              b.serviceName ?? b.title ?? 'Booking',
              reportStatus(b.status),
              reportPence(b.price) / 100,
              b.id,
            ],
        ],
      );
    case ReportKind.services:
      final serviceRows =
          <
            String,
            ({String name, String type, int count, int pence, int minutes})
          >{};
      void add(String key, String name, String type, int pence, int minutes) {
        final old = serviceRows[key];
        serviceRows[key] = (
          name: name,
          type: type,
          count: (old?.count ?? 0) + 1,
          pence: (old?.pence ?? 0) + pence,
          minutes: (old?.minutes ?? 0) + minutes,
        );
      }
      for (final b in completed) {
        if (b.serviceItems.isEmpty) {
          add(
            'service:${b.serviceId ?? b.serviceName ?? b.title ?? 'unlabelled'}',
            b.serviceName ?? b.title ?? 'Unlabelled service',
            'Service',
            reportPence(b.price),
            b.endTime == null
                ? 0
                : b.endTime!.difference(b.startTime).inMinutes.clamp(0, 525600),
          );
        } else {
          for (final item in b.serviceItems) {
            add(
              item.isAddOn
                  ? 'add_on:${item.sourceAddOnId ?? item.name}'
                  : 'service:${item.sourceServiceId ?? item.name}',
              item.name,
              item.isAddOn ? 'Add-on' : 'Service',
              reportPence(item.price),
              item.durationMins.clamp(0, 525600),
            );
          }
        }
      }
      final sorted = serviceRows.values.toList()
        ..sort((a, b) => b.pence.compareTo(a.pence));
      return BusinessReport(
        kind: kind,
        basis:
            'This shows services from bookings marked completed, grouped by their start date. A booking with several services counts once for each service or extra. Values use the prices saved for those services; older single-service bookings use the booking price. They show the value of the work, not what customers paid. Booking-level discounts may differ.',
        metrics: [
          ReportMetric('Completed bookings', '${completed.length}'),
          ReportMetric('Services and extras', '${sorted.length}'),
          ReportMetric(
            'Value of completed services',
            reportMoney(sorted.fold<int>(0, (sum, s) => sum + s.pence)),
          ),
        ],
        columns: [
          'Service',
          'Type',
          'Times booked',
          'Value of completed services GBP',
          'Average price GBP',
          'Hours',
        ],
        rows: [
          for (final s in sorted)
            [
              s.name,
              s.type,
              s.count,
              s.pence / 100,
              (s.pence / s.count).round() / 100,
              (s.minutes / 60).toStringAsFixed(1),
            ],
        ],
      );
    case ReportKind.clients:
      final priorCompleted = <String>{
        for (final b in source.bookings)
          if (b.contactId != null &&
              b.status == 'completed' &&
              reportDay(source.civil(b.startTime)).isBefore(range.start))
            b.contactId!,
      };
      final completedIds = <String>{
        for (final b in completed)
          if (b.contactId != null) b.contactId!,
      };
      final returning = completedIds.intersection(priorCompleted).length;
      final newClients = source.clients
          .where(
            (c) =>
                c.createdAt != null &&
                range.contains(source.civil(c.createdAt!)),
          )
          .toList();
      final stats =
          <
            String,
            ({
              String name,
              int bookings,
              int completed,
              int received,
              bool newRecord,
            })
          >{};
      void add(
        String id,
        String name, {
        int bookings = 0,
        int completed = 0,
        int received = 0,
        bool newRecord = false,
      }) {
        final old = stats[id];
        stats[id] = (
          name: name,
          bookings: (old?.bookings ?? 0) + bookings,
          completed: (old?.completed ?? 0) + completed,
          received: (old?.received ?? 0) + received,
          newRecord: (old?.newRecord ?? false) || newRecord,
        );
      }
      for (final c in newClients) {
        add(c.id, c.name, newRecord: true);
      }
      for (final b in bookings) {
        add(
          b.contactId ?? 'unlinked-booking:${b.id}',
          clientName(b.contactId, b.clientName),
          bookings: 1,
          completed: b.status == 'completed' ? 1 : 0,
        );
      }
      for (final c in selectedCash) {
        add(
          paymentClientId(c.payment) ?? 'unlinked-payment:${c.payment.id}',
          paymentClientName(c.payment),
          received: c.pence,
        );
      }
      final sorted = stats.entries.toList()
        ..sort((a, b) => b.value.received.compareTo(a.value.received));
      return BusinessReport(
        kind: kind,
        basis:
            'Includes clients with a booking or payment in these dates, plus clients you added. A returning client completed work in this period and before it. “Clients who came back” is their share of clients served here, not a long-term retention rate. Added clients may have used your business before. Entries without a linked client appear separately and are not counted as individual clients served.',
        metrics: [
          ReportMetric('Clients added', '${newClients.length}'),
          ReportMetric('Clients served', '${completedIds.length}'),
          ReportMetric('Returning clients', '$returning'),
          ReportMetric(
            'Clients who came back',
            completedIds.isEmpty
                ? '—'
                : '${(returning * 100 / completedIds.length).toStringAsFixed(1)}%',
          ),
        ],
        columns: [
          'Client',
          'Bookings',
          'Completed',
          'Money received after refunds GBP',
          'Added in these dates',
          'Client / record ID',
        ],
        rows: [
          for (final entry in sorted)
            [
              entry.value.name,
              entry.value.bookings,
              entry.value.completed,
              entry.value.received / 100,
              entry.value.newRecord ? 'Yes' : 'No',
              entry.key,
            ],
        ],
      );
    case ReportKind.outstanding:
      final payments =
          source.payments
              .where((p) => reportPence(p.outstandingAmount) > 0)
              .toList()
            ..sort(
              (a, b) => (a.dueDate ?? a.issueDate).compareTo(
                b.dueDate ?? b.issueDate,
              ),
            );
      final buckets = <String, int>{
        'Not yet overdue': 0,
        '1–30 days overdue': 0,
        '31–60 days overdue': 0,
        '61–90 days overdue': 0,
        'Over 90 days overdue': 0,
      };
      String bucket(Payment p) {
        final days = today
            .difference(reportDay(p.dueDate ?? p.issueDate))
            .inDays;
        return days <= 0
            ? 'Not yet overdue'
            : days <= 30
            ? '1–30 days overdue'
            : days <= 60
            ? '31–60 days overdue'
            : days <= 90
            ? '61–90 days overdue'
            : 'Over 90 days overdue';
      }
      for (final p in payments) {
        buckets[bucket(p)] =
            buckets[bucket(p)]! + reportPence(p.outstandingAmount);
      }
      final total = buckets.values.fold<int>(0, (a, b) => a + b);
      return BusinessReport(
        kind: kind,
        basis:
            'This is what customers still owe you today (${reportFriendlyDate(today)}), after payments already recorded. It always shows today’s position, whatever dates you used in another report. Cancelled and declined payments are left out. Overdue days run from the due date, or the date the payment was created if no due date was added.',
        metrics: [
          ReportMetric('Total still owed', reportMoney(total)),
          ReportMetric(
            'Past the due date',
            reportMoney(total - buckets['Not yet overdue']!),
          ),
          for (final b in buckets.entries)
            ReportMetric(b.key, reportMoney(b.value)),
        ],
        columns: [
          'Client',
          'Reference',
          'Due date / created date',
          'How long overdue',
          'Still owed GBP',
          'Payment ID',
        ],
        rows: [
          for (final p in payments)
            [
              paymentClientName(p),
              p.number,
              p.dueDate == null
                  ? '${reportFriendlyDate(p.issueDate)} (no due date set)'
                  : reportDate(p.dueDate!),
              bucket(p),
              reportPence(p.outstandingAmount) / 100,
              p.id,
            ],
        ],
        emptyMessage:
            'You’re all paid up. No payments are waiting to be collected.',
      );
    case ReportKind.tasks:
      final tasks =
          source.tasks
              .where((t) => t.dueDate != null && range.contains(t.dueDate!))
              .toList()
            ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      final done = tasks.where((t) => t.status == 'done').length;
      final overdue = tasks
          .where(
            (t) => t.status != 'done' && reportDay(t.dueDate!).isBefore(today),
          )
          .length;
      return BusinessReport(
        kind: kind,
        basis:
            'These tasks have a due date within your chosen dates. Their status shows where they stand now: “Marked done” does not mean they were finished during this period. Tasks without a due date are counted separately across all your work, so they are not forgotten.',
        metrics: [
          ReportMetric('Tasks due', '${tasks.length}'),
          ReportMetric('Marked done', '$done'),
          ReportMetric('Still to do', '${tasks.length - done}'),
          ReportMetric('Past the due date', '$overdue'),
          ReportMetric(
            'To do without a due date',
            '${source.tasks.where((t) => t.dueDate == null && t.status != 'done').length}',
          ),
        ],
        columns: [
          'Task',
          'Due date',
          'Client',
          'Status',
          'Priority',
          'Task ID',
        ],
        rows: [
          for (final t in tasks)
            [
              t.title,
              reportDate(t.dueDate!),
              clientName(t.contactId, t.clientName),
              reportStatus(t.status),
              reportStatus(t.priority),
              t.id,
            ],
        ],
      );
  }
}

String reportStatus(String status) => switch (status) {
  'no_show' => 'Client did not attend',
  'done' => 'Done',
  'open' => 'To do',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  'scheduled' => 'Scheduled',
  'confirmed' => 'Confirmed',
  'high' => 'High',
  'medium' => 'Medium',
  'low' => 'Low',
  _ =>
    status.isEmpty
        ? 'Not set'
        : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}',
};
