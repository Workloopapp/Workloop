import 'report_models.dart';

/// Scenario inputs stay on this screen; they never change business records.
class CashflowAssumptions {
  final int days;
  final int? startingCashPence;
  final int? weeklyCostsPence;
  final bool includeBookings;
  final bool includeOverdue;
  final int paymentDelayDays;

  const CashflowAssumptions({
    this.days = 30,
    this.startingCashPence,
    this.weeklyCostsPence,
    this.includeBookings = true,
    this.includeOverdue = false,
    this.paymentDelayDays = 0,
  });
}

class CashflowDay {
  final DateTime date;
  final int paymentPence;
  final int bookingPence;
  final int expensePence;
  final int extraCostPence;
  final int cumulativeChangePence;
  final int? closingCashPence;
  const CashflowDay({
    required this.date,
    required this.paymentPence,
    required this.bookingPence,
    required this.expensePence,
    required this.extraCostPence,
    required this.cumulativeChangePence,
    required this.closingCashPence,
  });
}

class CashflowForecast {
  final ReportRange range;
  final BusinessReport report;
  final List<CashflowDay> days;
  final DateTime? firstNegativeDate;
  final int? lowestCashPence;
  const CashflowForecast({
    required this.range,
    required this.report,
    required this.days,
    this.firstNegativeDate,
    this.lowestCashPence,
  });
}

CashflowForecast buildCashflowForecast({
  required ReportSource source,
  required DateTime now,
  CashflowAssumptions assumptions = const CashflowAssumptions(),
}) {
  if (assumptions.days < 1 ||
      assumptions.days > 366 ||
      (assumptions.weeklyCostsPence ?? 0) < 0 ||
      assumptions.paymentDelayDays < 0 ||
      assumptions.paymentDelayDays > 90) {
    throw ArgumentError(
      'Choose a valid forecast length, cost and payment delay.',
    );
  }
  final today = reportDay(source.civil(now));
  final range = ReportRange(today, today.add(Duration(days: assumptions.days)));
  final payments = List<int>.filled(assumptions.days, 0);
  final bookings = List<int>.filled(assumptions.days, 0);
  final expenses = List<int>.filled(assumptions.days, 0);
  var undatedOrOverdue = 0;
  var recovered = 0;
  final linkedBookings = {
    for (final payment in source.payments)
      if (payment.appointmentId != null) payment.appointmentId!,
  };

  void schedulePayment(int amount, DateTime? due) {
    if (amount <= 0) return;
    DateTime date;
    if (due == null || reportDay(due).isBefore(today)) {
      undatedOrOverdue += amount;
      if (!assumptions.includeOverdue) return;
      // Uncertain collections are moved to today only by an explicit scenario choice.
      date = today;
    } else {
      date = reportDay(due);
    }
    date = date.add(Duration(days: assumptions.paymentDelayDays));
    if (range.contains(date)) {
      payments[date.difference(today).inDays] += amount;
      if (due == null || reportDay(due).isBefore(today)) recovered += amount;
    }
  }

  for (final payment in source.payments) {
    if (!const {
      'sent',
      'pending',
      'overdue',
      'partially_paid',
      'unpaid',
    }.contains(payment.status)) {
      continue;
    }
    final remaining = reportPence(payment.outstandingAmount);
    if (remaining <= 0) continue;
    final deposit = reportPence(
      payment.depositOutstandingAmount,
    ).clamp(0, remaining);
    if (deposit > 0) {
      schedulePayment(deposit, payment.depositDueDate ?? payment.dueDate);
    }
    schedulePayment(remaining - deposit, payment.dueDate);
  }
  if (assumptions.includeBookings) {
    for (final booking in source.bookings) {
      if (!const {'scheduled', 'confirmed'}.contains(booking.status) ||
          linkedBookings.contains(booking.id) ||
          booking.startTime.isBefore(now)) {
        continue;
      }
      final day = reportDay(
        source.civil(booking.startTime),
      ).add(Duration(days: assumptions.paymentDelayDays));
      if (range.contains(day)) {
        bookings[day.difference(today).inDays] += reportPence(
          booking.price,
        ).clamp(0, 1 << 62);
      }
    }
  }
  for (final expense in source.expenses) {
    final day = reportDay(expense.expenseDate);
    if (day.isAfter(today) && range.contains(day)) {
      // Negative corrections are not a promise of a future cash refund.
      expenses[day.difference(today).inDays] += reportPence(
        expense.amount,
      ).clamp(0, 1 << 62);
    }
  }

  final days = <CashflowDay>[];
  var cumulative = 0;
  var totalPayments = 0;
  var totalBookings = 0;
  var totalCosts = 0;
  var totalDatedExpenses = 0;
  var totalExtraCosts = 0;
  int? lowest = assumptions.startingCashPence;
  DateTime? firstNegative = lowest != null && lowest < 0 ? today : null;
  for (var index = 0; index < assumptions.days; index++) {
    // Difference of rounded cumulative amounts preserves every penny in full weeks.
    final weekly = assumptions.weeklyCostsPence ?? 0;
    final extra =
        (weekly * (index + 1) / 7).round() - (weekly * index / 7).round();
    cumulative += payments[index] + bookings[index] - expenses[index] - extra;
    totalPayments += payments[index];
    totalBookings += bookings[index];
    totalDatedExpenses += expenses[index];
    totalExtraCosts += extra;
    totalCosts += expenses[index] + extra;
    final closing = assumptions.startingCashPence == null
        ? null
        : assumptions.startingCashPence! + cumulative;
    final date = today.add(Duration(days: index));
    if (closing != null) {
      if (lowest == null || closing < lowest) lowest = closing;
      if (closing < 0) firstNegative ??= date;
    }
    days.add(
      CashflowDay(
        date: date,
        paymentPence: payments[index],
        bookingPence: bookings[index],
        expensePence: expenses[index],
        extraCostPence: extra,
        cumulativeChangePence: cumulative,
        closingCashPence: closing,
      ),
    );
  }

  final rows = <List<Object>>[];
  for (var index = 0; index < days.length; index += 7) {
    final week = days.skip(index).take(7).toList();
    final incoming = week.fold<int>(
      0,
      (sum, d) => sum + d.paymentPence + d.bookingPence,
    );
    final outgoing = week.fold<int>(
      0,
      (sum, d) => sum + d.expensePence + d.extraCostPence,
    );
    rows.add([
      '${reportFriendlyDate(week.first.date)} – ${reportFriendlyDate(week.last.date)}',
      week.fold<int>(0, (sum, d) => sum + d.paymentPence) / 100,
      week.fold<int>(0, (sum, d) => sum + d.bookingPence) / 100,
      outgoing / 100,
      (incoming - outgoing) / 100,
      (week.last.closingCashPence ?? week.last.cumulativeChangePence) / 100,
    ]);
  }
  final warnings = <String>[
    if (assumptions.weeklyCostsPence == null)
      'Add your expected weekly costs for a more useful forecast. For now, spending includes only future-dated expenses already saved in Workloop.',
    if (assumptions.startingCashPence == null)
      'Add the cash you have available now to see an estimated balance. Until then, this shows the expected change in cash.',
    if (undatedOrOverdue > 0)
      assumptions.includeOverdue
          ? '${reportMoney(undatedOrOverdue)} is overdue or has no due date. You have chosen to assume collection ${assumptions.paymentDelayDays == 0 ? 'today' : 'in ${assumptions.paymentDelayDays} days'}; this is not a confirmed payment.'
          : '${reportMoney(undatedOrOverdue)} is overdue or has no due date. It is left out until you choose to include it in your assumptions.',
    if (firstNegative != null)
      'Cash could be below £0 on ${reportFriendlyDate(firstNegative)}. Review payment timing and upcoming costs.',
  ];
  final basis = [
    'This is an estimate for ${range.label}, not a bank balance or a promise of payment.',
    'Unpaid payments are expected on their due dates. Where a deposit date is saved, the unpaid deposit and remaining balance are counted separately.',
    assumptions.includeBookings
        ? 'Upcoming scheduled and confirmed bookings without a linked payment are estimated at their booking price on the booking date. Any linked payment replaces that booking estimate, so keep its remaining balance up to date.'
        : 'Upcoming bookings without a linked payment are left out.',
    'Payment timing: ${assumptions.paymentDelayDays == 0 ? 'on the expected date' : '${assumptions.paymentDelayDays} days after the expected date'}.',
    assumptions.includeOverdue
        ? 'Overdue and undated payments are assumed to arrive today, plus your chosen delay.'
        : 'Overdue and undated payments are left out.',
    'Spending includes positive future-dated expenses (${reportMoney(totalDatedExpenses)}) plus ${assumptions.weeklyCostsPence == null ? 'no extra weekly costs yet' : '${reportMoney(assumptions.weeklyCostsPence!)} a week, spread evenly by day (${reportMoney(totalExtraCosts)} in this forecast)'}. Extra weekly costs are added on top: leave out costs already entered with a future date.',
    assumptions.startingCashPence == null
        ? 'No starting cash was entered, so no cash balance is shown.'
        : 'Starting cash is the ${reportMoney(assumptions.startingCashPence!)} you entered for today, after transactions already made.',
    'Daily balances assume that day’s incoming and outgoing money has cleared; payments arriving later in the day can still leave a temporary shortfall. New bookings, unrecorded bills, tax and owner withdrawals are included only if you allow for them in your inputs. Changes here are for this forecast only and are not saved to your business records.',
  ].join(' ');
  final report = BusinessReport(
    kind: ReportKind.forecast,
    basis: basis,
    notices: warnings,
    metrics: [
      ReportMetric(
        'Expected money in',
        reportMoney(totalPayments + totalBookings),
      ),
      ReportMetric('From unpaid payments', reportMoney(totalPayments)),
      if (assumptions.includeBookings)
        ReportMetric('From upcoming bookings', reportMoney(totalBookings)),
      if (recovered > 0)
        ReportMetric(
          'Overdue / undated included above',
          reportMoney(recovered),
        ),
      ReportMetric('Expected money out', reportMoney(totalCosts)),
      ReportMetric('Expected change in cash', reportMoney(cumulative)),
      if (assumptions.startingCashPence != null) ...[
        ReportMetric(
          'Cash available now',
          reportMoney(assumptions.startingCashPence!),
        ),
        ReportMetric(
          'Estimated cash at the end',
          reportMoney(days.last.closingCashPence!),
        ),
        ReportMetric('Lowest estimated cash', reportMoney(lowest!)),
      ],
    ],
    columns: [
      'Week',
      'Unpaid payments GBP',
      'Booking estimates GBP',
      'Expected spending GBP',
      'Change this week GBP',
      assumptions.startingCashPence == null
          ? 'Total cash change GBP'
          : 'Estimated cash at week end GBP',
    ],
    rows: rows,
  );
  return CashflowForecast(
    range: range,
    report: report,
    days: days,
    firstNegativeDate: firstNegative,
    lowestCashPence: lowest,
  );
}

int? forecastInputPence(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  if (!RegExp(r'^-?\d{1,9}(\.\d{1,2})?$').hasMatch(text)) {
    throw const FormatException(
      'Enter an amount with up to two decimal places.',
    );
  }
  final negative = text.startsWith('-');
  final parts = text.replaceFirst('-', '').split('.');
  final pence =
      int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return negative ? -pence : pence;
}
