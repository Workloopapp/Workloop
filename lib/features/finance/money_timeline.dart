import '../../shared/models/slate_models.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/utils/currency_format.dart';

enum MoneyTimelineFilter { all, income, expenses }

String moneyTimelineAmountLabel(double amount) {
  final value = roundToPence(amount);
  return '${value < 0 ? '-' : '+'}${formatPounds(value.abs())}';
}

/// One existing money record, expressed as movement into or out of the business.
/// This is a display model, not a second payment or expense ledger.
class MoneyTimelineEntry {
  final Payment? payment;
  final Expense? expense;
  final DateTime date;
  final double amount;
  final String stableKey;

  MoneyTimelineEntry.fromPayment(Payment value)
    : payment = value,
      expense = null,
      date = value.receivedDate.toLocal(),
      amount = roundToPence(receivedAmountFor(value)),
      stableKey = 'payment:${value.id}';

  MoneyTimelineEntry.fromExpense(Expense value)
    : payment = null,
      expense = value,
      date = value.expenseDate.toLocal(),
      amount = roundToPence(-value.amount),
      stableKey = 'expense:${value.id}';

  MoneyTimelineEntry.fromReceipt(Payment value, PaymentReceipt receipt)
    : payment = value,
      expense = null,
      date = receipt.receivedAt.toLocal(),
      amount = roundToPence(receipt.amount),
      stableKey = 'receipt:${receipt.id}';
}

/// Searches the complete selected period before the screen limits its preview.
/// A partially collected payment belongs here even while its balance is owed.
List<MoneyTimelineEntry> buildMoneyTimeline({
  required Iterable<Payment> payments,
  required Iterable<Expense> expenses,
  required MoneyPeriodRange range,
  MoneyTimelineFilter filter = MoneyTimelineFilter.all,
  String query = '',
}) {
  bool inRange(DateTime value) =>
      !value.isBefore(range.start) && value.isBefore(range.end);

  final entries = <MoneyTimelineEntry>[
    if (filter != MoneyTimelineFilter.expenses)
      for (final payment in payments)
        if (payment.sourceDocumentId != null) ...[
          for (final receipt in payment.cashReceipts)
            if (receipt.amount != 0 &&
                receipt.amount.isFinite &&
                inRange(receipt.receivedAt) &&
                _matches(query, [
                  payment.clientName ?? '',
                  payment.clientEmail ?? '',
                  payment.number,
                  payment.notes ?? '',
                  receipt.amount < 0 ? 'refund' : 'income',
                  ..._amountTerms(receipt.amount),
                  ..._dateTerms(receipt.receivedAt),
                ]))
              MoneyTimelineEntry.fromReceipt(payment, receipt),
        ] else if ((receivedAmountFor(payment) != 0 ||
                payment.status == 'paid') &&
            receivedAmountFor(payment).isFinite &&
            inRange(payment.receivedDate) &&
            paymentMatchesSearch(payment, query))
          MoneyTimelineEntry.fromPayment(payment),
    if (filter != MoneyTimelineFilter.income)
      for (final expense in expenses)
        if (expense.amount.isFinite &&
            inRange(expense.expenseDate) &&
            expenseMatchesSearch(expense, query))
          MoneyTimelineEntry.fromExpense(expense),
  ];
  entries.sort((a, b) {
    final dateOrder = b.date.compareTo(a.date);
    return dateOrder != 0 ? dateOrder : a.stableKey.compareTo(b.stableKey);
  });
  return entries;
}

bool paymentMatchesSearch(Payment payment, String query) {
  if (query.trim().isEmpty) return true;
  return _matches(query, [
    payment.clientName ?? '',
    payment.clientEmail ?? '',
    payment.number,
    payment.notes ?? '',
    payment.status,
    receivedAmountFor(payment) < 0 ? 'refund' : 'income',
    if (receivedAmountFor(payment) > 0 && outstandingAmountFor(payment) > 0)
      'part-paid partially paid',
    ..._amountTerms(payment.total),
    ..._amountTerms(receivedAmountFor(payment)),
    ..._amountTerms(outstandingAmountFor(payment)),
    ..._dateTerms(payment.receivedDate),
    ..._dateTerms(payment.issueDate),
    if (payment.dueDate != null) ..._dateTerms(payment.dueDate!),
  ]);
}

bool expenseMatchesSearch(Expense expense, String query) {
  if (query.trim().isEmpty) return true;
  return _matches(query, [
    'expense',
    expense.category,
    expense.notes ?? '',
    ..._amountTerms(expense.amount),
    ..._amountTerms(-expense.amount),
    ..._dateTerms(expense.expenseDate),
  ]);
}

bool _matches(String query, List<String> values) {
  final tokens = _searchText(
    query,
  ).split(RegExp(r'\s+')).where((v) => v.isNotEmpty);
  if (tokens.isEmpty) return true;
  final haystack = _searchText(values.join(' '));
  return tokens.every((token) {
    // A calendar day such as "2 September" must not match the year 2026.
    if (RegExp(r'^\d+$').hasMatch(token)) {
      return RegExp('(^|[^0-9])$token(?=\$|[^0-9])').hasMatch(haystack);
    }
    return haystack.contains(token);
  });
}

String _searchText(String value) =>
    value.toLowerCase().replaceAll('−', '-').replaceAll(',', '').trim();

List<String> _amountTerms(double amount) {
  if (!amount.isFinite) return const [];
  final value = roundToPence(amount);
  return [
    currencyInputValue(value),
    value.toStringAsFixed(2),
    formatPounds(value),
    '${value < 0 ? '-' : '+'}${formatPounds(value.abs())}',
  ];
}

List<String> _dateTerms(DateTime value) {
  final date = value.toLocal();
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return [
    '${date.year}-$month-$day',
    '$day/$month/${date.year}',
    '${date.day}/${date.month}/${date.year}',
    '${date.day} ${months[date.month - 1]} ${date.year}',
    '${date.day} ${months[date.month - 1].substring(0, 3)} ${date.year}',
    weekdays[date.weekday - 1],
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
  ];
}
