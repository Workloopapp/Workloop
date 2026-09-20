import 'dart:math' as math;

import '../../shared/models/slate_models.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/utils/currency_format.dart';
import '../../shared/widgets/workloop_studio_graphics.dart';

/// Net received income after recorded expenses, in up to seven calendar bins.
/// Calendar boundaries avoid missing the last day of a daylight-saving week.
List<WorkloopStudioBarDatum> buildMoneyProfitData({
  required Iterable<Payment> payments,
  required Iterable<Expense> expenses,
  required MoneyPeriodRange range,
  DateTime? now,
}) {
  if (!range.end.isAfter(range.start)) return const [];

  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final start = range.start.toLocal();
  final end = range.end.toLocal();
  final totalDays = math.max(
    1,
    DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays,
  );
  final bucketCount = math.min(7, totalDays);
  final boundaries = List.generate(
    bucketCount + 1,
    (index) => index == 0
        ? range.start
        : index == bucketCount
        ? range.end
        : addBusinessCalendarDays(start, index * totalDays ~/ bucketCount),
  );
  final pennies = List<int>.filled(bucketCount, 0);

  void record(DateTime date, double value) {
    if (!value.isFinite ||
        date.isBefore(range.start) ||
        !date.isBefore(range.end)) {
      return;
    }
    final amount = (value * 100).round();
    for (var index = 0; index < bucketCount; index++) {
      if (date.isBefore(boundaries[index + 1])) {
        pennies[index] += amount;
        break;
      }
    }
  }

  for (final payment in payments) {
    for (final receipt in payment.cashReceipts) {
      if (!startOfDay(
        receipt.receivedAt,
      ).isAfter(startOfDay(now ?? DateTime.now()))) {
        record(receipt.receivedAt, receipt.amount);
      }
    }
  }
  for (final expense in expenses) {
    record(expense.expenseDate, -expense.amount);
  }

  return List.generate(bucketCount, (index) {
    final date = boundaries[index].toLocal();
    final amount = pennies[index] / 100;
    final label = totalDays <= 7
        ? weekdays[date.weekday - 1]
        : totalDays <= 31 &&
              start.month == addBusinessCalendarDays(end, -1).month
        ? '${date.day}'
        : '${date.day}/${date.month}';
    return WorkloopStudioBarDatum(
      label: label,
      value: amount,
      valueLabel: amount < 0
          ? '-${formatPounds(amount.abs())}'
          : formatPounds(amount),
    );
  });
}
