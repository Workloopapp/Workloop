import '../../shared/models/slate_models.dart';
import '../../shared/utils/booking_time.dart';

/// Civil dates, independent of the phone's timezone and daylight-saving hours.
DateTime reportDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

class ReportRange {
  final DateTime start;
  final DateTime end;

  ReportRange(DateTime start, DateTime end)
    : start = reportDay(start),
      end = reportDay(end) {
    if (!this.end.isAfter(this.start)) {
      throw ArgumentError('A report must include at least one day.');
    }
  }

  bool contains(DateTime civilDate) {
    final day = reportDay(civilDate);
    return !day.isBefore(start) && day.isBefore(end);
  }

  ReportRange get previous => ReportRange(
    start.subtract(Duration(days: end.difference(start).inDays)),
    start,
  );

  String get label =>
      '${reportFriendlyDate(start)} – '
      '${reportFriendlyDate(end.subtract(const Duration(days: 1)))}';
}

enum ReportPeriod {
  month('This month so far'),
  week('This week so far'),
  lastMonth('Last month'),
  quarter('This quarter so far'),
  year('This year so far'),
  all('All time'),
  custom('Choose dates');

  final String label;
  const ReportPeriod(this.label);

  ReportRange range(DateTime today, {DateTime? earliest}) {
    final day = reportDay(today);
    final tomorrow = day.add(const Duration(days: 1));
    return switch (this) {
      week => ReportRange(
        day.subtract(Duration(days: day.weekday - 1)),
        tomorrow,
      ),
      lastMonth => ReportRange(
        DateTime.utc(day.year, day.month - 1),
        DateTime.utc(day.year, day.month),
      ),
      quarter => ReportRange(
        DateTime.utc(day.year, ((day.month - 1) ~/ 3) * 3 + 1),
        tomorrow,
      ),
      year => ReportRange(DateTime.utc(day.year), tomorrow),
      all => ReportRange(
        earliest == null || earliest.isAfter(day) ? day : earliest,
        tomorrow,
      ),
      _ => ReportRange(DateTime.utc(day.year, day.month), tomorrow),
    };
  }
}

class ReportSource {
  final String workspaceId;
  final String businessName;
  final String timezone;
  final List<Payment> payments;
  final List<Expense> expenses;
  final List<Appointment> bookings;
  final List<Client> clients;
  final List<SlateTask> tasks;

  const ReportSource({
    required this.workspaceId,
    required this.businessName,
    this.timezone = 'Europe/London',
    this.payments = const [],
    this.expenses = const [],
    this.bookings = const [],
    this.clients = const [],
    this.tasks = const [],
  });

  DateTime civil(DateTime instant) => bookingWallClockInZone(instant, timezone);

  /// Money's legacy fallback uses an issue date, while recorded receipts are instants.
  DateTime receiptDay(Payment payment, PaymentReceipt receipt) =>
      payment.sourceDocumentId == null && payment.incomeRecordedAt == null
      ? reportDay(payment.issueDate)
      : reportDay(civil(receipt.receivedAt));

  DateTime earliestDay(DateTime now) {
    final dates = [
      reportDay(civil(now)),
      for (final p in payments) ...[
        reportDay(p.issueDate),
        for (final r in p.cashReceipts) receiptDay(p, r),
      ],
      for (final e in expenses) reportDay(e.expenseDate),
      for (final b in bookings) reportDay(civil(b.startTime)),
      for (final c in clients)
        if (c.createdAt != null) reportDay(civil(c.createdAt!)),
      for (final t in tasks)
        if (t.dueDate != null) reportDay(t.dueDate!),
    ]..sort();
    return dates.first;
  }
}

enum ReportKind {
  overview('Business overview', 'Money in, money out and the work behind it.'),
  forecast(
    'Cashflow forecast',
    'See how expected payments and costs could change your cash over the coming weeks.',
  ),
  cash(
    'Money received',
    'See what customers have paid, including part-payments and refunds.',
  ),
  expenses('Spending', 'See where your money goes and review each expense.'),
  bookings(
    'Bookings',
    'See how much work you completed, plus cancellations and missed appointments.',
  ),
  services(
    'Service performance',
    'See which services you completed and the value of that work.',
  ),
  clients(
    'Client activity',
    'See who you served, who came back and what they paid.',
  ),
  outstanding(
    'Money owed to you',
    'See what is still unpaid and which payments need chasing.',
  ),
  tasks(
    'Work & follow-ups',
    'Review tasks due in these dates and see what still needs doing.',
  );

  final String label;
  final String description;
  const ReportKind(this.label, this.description);
}

class ReportMetric {
  final String label;
  final String value;
  final String? comparison;
  const ReportMetric(this.label, this.value, [this.comparison]);
}

class BusinessReport {
  final ReportKind kind;
  final String basis;
  final List<ReportMetric> metrics;
  final List<String> columns;
  final List<List<Object>> rows;
  final String emptyMessage;
  final List<String> notices;

  const BusinessReport({
    required this.kind,
    required this.basis,
    required this.metrics,
    required this.columns,
    required this.rows,
    this.notices = const [],
    this.emptyMessage =
        'There is nothing to show for these dates yet. Try a wider date range.',
  });
}

int reportPence(num amount) => (amount * 100).round();
String reportMoney(int pence) {
  final parts = (pence.abs() / 100).toStringAsFixed(2).split('.');
  final pounds = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${pence < 0 ? '−' : ''}£$pounds.${parts.last}';
}

String reportDate(DateTime civil) =>
    '${civil.year.toString().padLeft(4, '0')}-${civil.month.toString().padLeft(2, '0')}-${civil.day.toString().padLeft(2, '0')}';
String reportCell(Object value) =>
    value is double ? value.toStringAsFixed(2) : value.toString();

const _reportMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String reportFriendlyDate(DateTime date) =>
    '${date.day} ${_reportMonths[date.month - 1]} ${date.year}';

String reportDisplayCell(Object value, String column) {
  if (column.endsWith(' GBP') && value is num) {
    return reportMoney(reportPence(value));
  }
  final text = reportCell(value);
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    final date = DateTime.tryParse(text);
    if (date != null) return reportFriendlyDate(date);
  }
  if (column == 'Month' && RegExp(r'^\d{4}-\d{2}$').hasMatch(text)) {
    final date = DateTime.tryParse('$text-01');
    if (date != null) return '${_reportMonths[date.month - 1]} ${date.year}';
  }
  return text;
}
