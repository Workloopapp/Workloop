import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/reports/cashflow_forecast.dart';
import 'package:workloop/features/reports/report_export.dart';
import 'package:workloop/features/reports/report_models.dart';
import 'package:workloop/shared/models/slate_models.dart';

final now = DateTime.utc(2026, 10, 24, 12);
Payment payment(
  String id, {
  double total = 100,
  double paid = 0,
  double deposit = 0,
  DateTime? due,
  DateTime? depositDue,
  String status = 'sent',
  String? booking,
}) => Payment(
  id: id,
  workspaceId: 'w',
  number: id,
  status: status,
  issueDate: DateTime(2026, 10, 1),
  dueDate: due,
  depositDueDate: depositDue,
  total: total,
  amountPaid: paid,
  depositAmount: deposit,
  appointmentId: booking,
);
Appointment booking(
  String id, {
  String status = 'scheduled',
  DateTime? start,
  double price = 100,
}) => Appointment(
  id: id,
  workspaceId: 'w',
  startTime: start ?? DateTime.utc(2026, 10, 26, 10),
  status: status,
  price: price,
);
ReportSource source({
  List<Payment> payments = const [],
  List<Appointment> bookings = const [],
  List<Expense> expenses = const [],
}) => ReportSource(
  workspaceId: 'w',
  businessName: 'Sample business',
  payments: payments,
  bookings: bookings,
  expenses: expenses,
);
CashflowForecast forecast(
  ReportSource source, {
  CashflowAssumptions assumptions = const CashflowAssumptions(),
}) => buildCashflowForecast(source: source, now: now, assumptions: assumptions);
int moneyIn(CashflowForecast f) =>
    f.days.fold(0, (s, d) => s + d.paymentPence + d.bookingPence);

void main() {
  test(
    'horizons count civil days through DST and exclude the end boundary',
    () {
      for (final n in [30, 60, 90]) {
        final start = reportDay(now);
        final f = forecast(
          source(
            payments: [
              payment('start', due: start),
              payment('last', due: start.add(Duration(days: n - 1))),
              payment('end', due: start.add(Duration(days: n))),
            ],
          ),
          assumptions: CashflowAssumptions(days: n),
        );
        expect(f.days.length, n);
        expect(f.range.end.difference(f.range.start).inDays, n);
        expect(moneyIn(f), 20000);
      }
    },
  );
  test(
    'partial deposit and balance count once and replace the linked booking',
    () {
      final f = forecast(
        source(
          payments: [
            payment(
              'p',
              paid: 20,
              deposit: 30,
              depositDue: DateTime(2026, 10, 25),
              due: DateTime(2026, 10, 30),
              booking: 'b',
            ),
          ],
          bookings: [booking('b')],
        ),
      );
      expect(f.days[1].paymentPence, 1000);
      expect(f.days[6].paymentPence, 7000);
      expect(f.days.every((d) => d.bookingPence == 0), isTrue);
      expect(moneyIn(f), 8000);
    },
  );
  test('payments beyond the deposit leave only the final unpaid balance', () {
    final f = forecast(
      source(
        payments: [
          payment(
            'p',
            paid: 40,
            deposit: 30,
            depositDue: DateTime(2026, 10, 25),
            due: DateTime(2026, 10, 30),
          ),
        ],
      ),
    );
    expect(f.days[1].paymentPence, 0);
    expect(f.days[6].paymentPence, 6000);
  });
  test(
    'overdue deposit and undated amounts are excluded until explicitly included',
    () {
      final input = source(
        payments: [
          payment(
            'p',
            deposit: 30,
            depositDue: DateTime(2026, 10, 1),
            due: DateTime(2026, 10, 30),
          ),
          payment('undated'),
        ],
      );
      final excluded = forecast(input);
      expect(moneyIn(excluded), 7000);
      expect(excluded.report.notices.join(' '), contains('£130.00'));
      final included = forecast(
        input,
        assumptions: const CashflowAssumptions(
          includeOverdue: true,
          paymentDelayDays: 7,
        ),
      );
      expect(included.days[7].paymentPence, 13000);
      expect(moneyIn(included), 20000);
    },
  );
  test(
    'later collections can move beyond the horizon without being pulled forward',
    () {
      final f = forecast(
        source(payments: [payment('late', due: DateTime(2026, 11, 20))]),
        assumptions: const CashflowAssumptions(paymentDelayDays: 7),
      );
      expect(moneyIn(f), 0);
    },
  );
  test(
    'closed, draft and negative payments contribute no predicted income',
    () {
      final f = forecast(
        source(
          payments: [
            for (final status in ['paid', 'cancelled', 'declined', 'draft'])
              payment(
                status,
                due: DateTime(2026, 10, 26),
                status: status,
                booking: status,
              ),
            payment('negative', total: -100, due: DateTime(2026, 10, 26)),
          ],
          bookings: [
            for (final status in ['paid', 'cancelled', 'declined', 'draft'])
              booking(status),
          ],
        ),
      );
      expect(moneyIn(f), 0);
    },
  );
  test('only future unlinked scheduled or confirmed bookings count', () {
    final input = source(
      bookings: [
        booking('scheduled'),
        booking('confirmed', status: 'confirmed'),
        booking('done', status: 'completed'),
        booking('cancelled', status: 'cancelled'),
        booking('missed', status: 'no_show'),
        booking('past', start: now.subtract(const Duration(hours: 1))),
      ],
    );
    expect(moneyIn(forecast(input)), 20000);
    expect(
      moneyIn(
        forecast(
          input,
          assumptions: const CashflowAssumptions(includeBookings: false),
        ),
      ),
      0,
    );
  });
  test(
    'future expense entries are counted once and weekly extras preserve pennies',
    () {
      final f = forecast(
        source(
          expenses: [
            Expense(
              id: 'today',
              workspaceId: 'w',
              amount: 50,
              category: 'Tools',
              expenseDate: reportDay(now),
            ),
            Expense(
              id: 'future',
              workspaceId: 'w',
              amount: 50,
              category: 'Tools',
              expenseDate: DateTime(2026, 10, 25),
            ),
            Expense(
              id: 'credit',
              workspaceId: 'w',
              amount: -99,
              category: 'Tools',
              expenseDate: DateTime(2026, 10, 26),
            ),
          ],
        ),
        assumptions: const CashflowAssumptions(days: 7, weeklyCostsPence: 100),
      );
      expect(f.days.fold<int>(0, (s, d) => s + d.extraCostPence), 100);
      expect(f.days.fold<int>(0, (s, d) => s + d.expensePence), 5000);
      expect(f.days.last.cumulativeChangePence, -5100);
    },
  );
  test(
    'blank starting cash never invents an account balance; zero is explicit',
    () {
      final unknown = forecast(source());
      expect(unknown.days.last.closingCashPence, isNull);
      expect(
        unknown.report.metrics.any(
          (m) => m.label == 'Estimated cash at the end',
        ),
        isFalse,
      );
      expect(unknown.report.notices.length, 2);
      final zero = forecast(
        source(),
        assumptions: const CashflowAssumptions(
          startingCashPence: 0,
          weeklyCostsPence: 0,
        ),
      );
      expect(zero.days.last.closingCashPence, 0);
      expect(zero.report.notices, isEmpty);
    },
  );
  test(
    'daily low cash is caught even if week-end receipts restore the balance',
    () {
      final f = forecast(
        source(
          payments: [payment('later', total: 500, due: DateTime(2026, 10, 30))],
        ),
        assumptions: const CashflowAssumptions(
          days: 7,
          startingCashPence: 1000,
          weeklyCostsPence: 7000,
        ),
      );
      expect(f.firstNegativeDate, DateTime.utc(2026, 10, 25));
      expect(f.lowestCashPence, -5000);
      expect(f.days.last.closingCashPence, 44000);
      expect(f.report.notices.join(' '), contains('25 Oct 2026'));
      expect(
        forecast(
          source(),
          assumptions: const CashflowAssumptions(
            startingCashPence: -10,
            weeklyCostsPence: 0,
          ),
        ).firstNegativeDate,
        DateTime.utc(2026, 10, 24),
      );
    },
  );
  test(
    'spreadsheet retains every forecast week, assumptions and caution notes',
    () {
      final s = source();
      final f = forecast(
        s,
        assumptions: const CashflowAssumptions(
          days: 90,
          weeklyCostsPence: 12000,
          startingCashPence: 50000,
        ),
      );
      final csv = buildReportCsv(
        report: f.report,
        source: s,
        range: f.range,
        generatedAt: now,
      );
      expect(f.report.rows.length, 13);
      expect(csv, contains('£120.00 a week'));
      expect(csv, contains('£500.00'));
      expect(csv, contains('Forecast note'));
      expect(csv, contains(f.report.rows.last.first.toString()));
    },
  );
  test(
    'money inputs reject invalid or over-precise values without losing pennies',
    () {
      expect(forecastInputPence(''), isNull);
      expect(forecastInputPence('0'), 0);
      expect(forecastInputPence('100.01'), 10001);
      expect(forecastInputPence('-20.5'), -2050);
      for (final input in ['abc', 'NaN', '1.234', '1e5', '10000000000']) {
        expect(() => forecastInputPence(input), throwsFormatException);
      }
    },
  );
}
