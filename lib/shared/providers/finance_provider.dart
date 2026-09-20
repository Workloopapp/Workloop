import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/slate_models.dart';
import '../repositories/slate_repositories.dart';
import 'business_clock_provider.dart';
import 'workspace_provider.dart';
import 'workspace_settings_provider.dart';

final invoicesProvider = FutureProvider<List<Payment>>((ref) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return [];

  return ref.watch(paymentsRepositoryProvider).list(workspaceId);
});

final expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return [];

  return ref.watch(expensesRepositoryProvider).list(workspaceId);
});

final appointmentPaymentsProvider = FutureProvider.autoDispose
    .family<List<Payment>, String>((ref, appointmentId) async {
      final payments = await ref.watch(invoicesProvider.future);
      return payments
          .where((item) => item.appointmentId == appointmentId)
          .toList();
    });

final financeSummaryProvider = FutureProvider<FinanceSummary>((ref) async {
  final today = ref.watch(businessTodayProvider);
  final (payments, expenses, settings) = await (
    ref.watch(invoicesProvider.future),
    ref.watch(expensesProvider.future),
    ref.watch(workspaceSettingsProvider.future),
  ).wait;
  final monthlyTarget = (settings?['revenue_target'] as num?)?.toDouble() ?? 0;
  return FinanceSummary.from(
    payments: payments,
    expenses: expenses,
    monthlyTarget: monthlyTarget,
    now: today,
  );
});

enum MoneyStatus { paid, unpaid, overdue }

class MoneyPeriodRange {
  final DateTime start;
  final DateTime end;
  final String label;

  const MoneyPeriodRange({
    required this.start,
    required this.end,
    required this.label,
  });
}

DateTime startOfWeek(DateTime now) {
  final day = startOfDay(now);
  return addBusinessCalendarDays(day, -(day.weekday - 1));
}

DateTime startOfDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime addBusinessCalendarDays(DateTime date, int days) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day + days);
}

MoneyStatus moneyStatusFor(Payment payment, {DateTime? now}) {
  if (payment.status == 'paid') return MoneyStatus.paid;
  final today = startOfDay(now ?? DateTime.now());
  final dueDate = payment.dueDate ?? payment.issueDate;
  final dueDay = startOfDay(dueDate);
  return dueDay.isBefore(today) ? MoneyStatus.overdue : MoneyStatus.unpaid;
}

double receivedAmountFor(Payment payment) {
  return payment.collectedAmount;
}

/// Calendar-month receipts shared by the dashboard and Money's target. A
/// selected history period must not change progress towards a monthly goal.
double receivedIncomeForMonth(
  Iterable<Payment> payments,
  DateTime date, {
  DateTime? now,
}) {
  final local = date.toLocal();
  return _sumPaymentsInRange(
    payments,
    DateTime(local.year, local.month, 1),
    DateTime(local.year, local.month + 1, 1),
    now: now ?? DateTime.now(),
  );
}

double outstandingAmountFor(Payment payment) {
  return payment.outstandingAmount;
}

DateTime displayReceivedDate(Payment payment, {DateTime? now}) {
  return payment.receivedDate;
}

class PeriodMoneySummary {
  final String label;
  final double paid;
  final double unpaid;
  final double overdue;
  final double expenses;
  final Map<String, double> categoryTotals;

  const PeriodMoneySummary({
    required this.label,
    required this.paid,
    required this.unpaid,
    required this.overdue,
    required this.expenses,
    required this.categoryTotals,
  });

  double get toCollect => unpaid + overdue;
  double get profit => paid - expenses;

  factory PeriodMoneySummary.from({
    required List<Payment> payments,
    required List<Expense> expenses,
    required MoneyPeriodRange range,
    DateTime? now,
  }) {
    bool inRange(DateTime date) =>
        !date.isBefore(range.start) && date.isBefore(range.end);

    final today = (now ?? DateTime.now()).toLocal();
    final paid = _sumPaymentsInRange(
      payments,
      range.start,
      range.end,
      now: today,
    );
    final unpaid = payments
        .where(
          (payment) =>
              moneyStatusFor(payment, now: today) == MoneyStatus.unpaid,
        )
        .where((payment) => inRange(payment.dueDate ?? payment.issueDate))
        .fold<double>(0, (sum, payment) => sum + outstandingAmountFor(payment));
    final overdue = payments
        .where(
          (payment) =>
              moneyStatusFor(payment, now: today) == MoneyStatus.overdue,
        )
        .where((payment) => inRange(payment.dueDate ?? payment.issueDate))
        .fold<double>(0, (sum, payment) => sum + outstandingAmountFor(payment));
    final categoryTotals = <String, double>{};
    final expenseTotal = expenses
        .where((expense) => inRange(expense.expenseDate))
        .fold<double>(0, (sum, expense) {
          categoryTotals.update(
            expense.category,
            (value) => value + expense.amount,
            ifAbsent: () => expense.amount,
          );
          return sum + expense.amount;
        });

    return PeriodMoneySummary(
      label: range.label,
      paid: paid,
      unpaid: unpaid,
      overdue: overdue,
      expenses: expenseTotal,
      categoryTotals: categoryTotals,
    );
  }
}

class FinanceSummary {
  final double monthlyTarget;
  final double weeklyTarget;
  final double thisWeekPaid;
  final double lastWeekPaid;
  final double thisMonthPaid;
  final double lastMonthPaid;
  final double unpaid;
  final double overdue;
  final double thisWeekExpenses;
  final double thisMonthExpenses;
  final double thisWeekNet;
  final double thisMonthNet;
  final PeriodMoneySummary thisWeekSummary;
  final PeriodMoneySummary thisMonthSummary;

  const FinanceSummary({
    required this.monthlyTarget,
    required this.weeklyTarget,
    required this.thisWeekPaid,
    required this.lastWeekPaid,
    required this.thisMonthPaid,
    required this.lastMonthPaid,
    required this.unpaid,
    required this.overdue,
    required this.thisWeekExpenses,
    required this.thisMonthExpenses,
    required this.thisWeekNet,
    required this.thisMonthNet,
    required this.thisWeekSummary,
    required this.thisMonthSummary,
  });

  double get weeklyProgress {
    if (weeklyTarget <= 0) return 0;
    return (thisWeekPaid / weeklyTarget).clamp(0, 1);
  }

  double get weekDelta => thisWeekPaid - lastWeekPaid;

  double get weekDeltaPercent {
    if (lastWeekPaid <= 0) return thisWeekPaid > 0 ? 1 : 0;
    return weekDelta / lastWeekPaid;
  }

  double get monthDelta => thisMonthPaid - lastMonthPaid;

  factory FinanceSummary.from({
    required List<Payment> payments,
    required List<Expense> expenses,
    required double monthlyTarget,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toLocal();
    final thisWeekStart = startOfWeek(current);
    final nextWeekStart = addBusinessCalendarDays(thisWeekStart, 7);
    final lastWeekStart = addBusinessCalendarDays(thisWeekStart, -7);
    final thisMonthStart = DateTime(current.year, current.month, 1);
    final nextMonthStart = DateTime(current.year, current.month + 1, 1);
    final lastMonthStart = DateTime(current.year, current.month - 1, 1);
    final thisWeekRange = MoneyPeriodRange(
      start: thisWeekStart,
      end: nextWeekStart,
      label: 'This week',
    );
    final thisMonthRange = MoneyPeriodRange(
      start: thisMonthStart,
      end: nextMonthStart,
      label: 'This month',
    );

    final thisWeekPaid = _sumPaymentsInRange(
      payments,
      thisWeekStart,
      nextWeekStart,
      now: current,
    );
    final lastWeekPaid = _sumPaymentsInRange(
      payments,
      lastWeekStart,
      thisWeekStart,
      now: current,
    );
    final thisMonthPaid = receivedIncomeForMonth(
      payments,
      current,
      now: current,
    );
    final lastMonthPaid = _sumPaymentsInRange(
      payments,
      lastMonthStart,
      thisMonthStart,
      now: current,
    );
    final unpaid = payments
        .where(
          (item) => moneyStatusFor(item, now: current) == MoneyStatus.unpaid,
        )
        .fold<double>(0, (sum, item) => sum + outstandingAmountFor(item));
    final overdue = payments
        .where(
          (item) => moneyStatusFor(item, now: current) == MoneyStatus.overdue,
        )
        .fold<double>(0, (sum, item) => sum + outstandingAmountFor(item));
    final thisWeekExpenses = _sumExpensesInRange(
      expenses,
      thisWeekStart,
      nextWeekStart,
    );
    final thisMonthExpenses = _sumExpensesInRange(
      expenses,
      thisMonthStart,
      nextMonthStart,
    );

    return FinanceSummary(
      monthlyTarget: monthlyTarget,
      weeklyTarget: monthlyTarget > 0 ? monthlyTarget / 4.345 : 0,
      thisWeekPaid: thisWeekPaid,
      lastWeekPaid: lastWeekPaid,
      thisMonthPaid: thisMonthPaid,
      lastMonthPaid: lastMonthPaid,
      unpaid: unpaid,
      overdue: overdue,
      thisWeekExpenses: thisWeekExpenses,
      thisMonthExpenses: thisMonthExpenses,
      thisWeekNet: thisWeekPaid - thisWeekExpenses,
      thisMonthNet: thisMonthPaid - thisMonthExpenses,
      thisWeekSummary: PeriodMoneySummary.from(
        range: thisWeekRange,
        payments: payments,
        expenses: expenses,
        now: current,
      ),
      thisMonthSummary: PeriodMoneySummary.from(
        range: thisMonthRange,
        payments: payments,
        expenses: expenses,
        now: current,
      ),
    );
  }
}

double _sumPaymentsInRange(
  Iterable<Payment> payments,
  DateTime start,
  DateTime end, {
  required DateTime now,
}) {
  // Received dates are calendar dates: include today, exclude future records.
  final tomorrow = addBusinessCalendarDays(startOfDay(now), 1);
  final receivedEnd = end.isBefore(tomorrow) ? end : tomorrow;
  return payments.fold<double>(
    0,
    (sum, item) => sum + item.receivedAmountBetween(start, receivedEnd),
  );
}

double _sumExpensesInRange(
  Iterable<Expense> expenses,
  DateTime start,
  DateTime end,
) {
  return expenses
      .where(
        (item) =>
            !item.expenseDate.isBefore(start) && item.expenseDate.isBefore(end),
      )
      .fold<double>(0, (sum, item) => sum + item.amount);
}
