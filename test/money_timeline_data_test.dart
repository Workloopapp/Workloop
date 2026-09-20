import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/finance/money_timeline.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/finance_provider.dart';

final _start = DateTime(2026, 9, 1);
final _end = DateTime(2026, 10, 1);
final _received = DateTime(2026, 9, 16, 11, 30);
final _range = MoneyPeriodRange(start: _start, end: _end, label: 'September');

Payment _payment(
  String id, {
  DateTime? received,
  DateTime? issued,
  DateTime? due,
  String status = 'paid',
  double total = 100,
  double? collected,
  String? name,
  String? email,
  String? notes,
}) => Payment(
  id: id,
  workspaceId: 'sample-workspace',
  number: 'PAY-$id',
  status: status,
  issueDate: issued ?? DateTime(2026, 8, 1),
  incomeRecordedAt: received ?? _received,
  dueDate: due,
  total: total,
  amountPaid: collected ?? total,
  clientName: name,
  clientEmail: email,
  notes: notes,
);

Expense _expense(
  String id, {
  DateTime? date,
  double amount = 25,
  String category = 'Materials',
  String? notes,
}) => Expense(
  id: id,
  workspaceId: 'sample-workspace',
  amount: amount,
  category: category,
  expenseDate: date ?? _received,
  notes: notes,
);

void main() {
  test(
    'received movement includes partial collections, refunds and paid zero',
    () {
      final partial = _payment('partial', status: 'sent', collected: 40);
      final refund = _payment('refund', total: -20, collected: 0);
      final partialRefund = _payment(
        'partial-refund',
        status: 'sent',
        total: -50,
        collected: -10,
      );
      final zero = _payment('zero', total: 0);
      final unpaid = _payment('unpaid', status: 'sent', collected: 0);
      final unpaidZero = _payment('unpaid-zero', status: 'sent', total: 0);
      final legacyPaid = _payment('legacy-paid', total: 60, collected: 0);
      final entries = buildMoneyTimeline(
        payments: [
          partial,
          refund,
          partialRefund,
          zero,
          unpaid,
          unpaidZero,
          legacyPaid,
        ],
        expenses: [_expense('materials')],
        range: _range,
      );

      expect(
        {for (final item in entries) item.stableKey: item.amount},
        {
          'payment:partial': 40,
          'payment:refund': -20,
          'payment:partial-refund': -10,
          'payment:zero': 0,
          'payment:legacy-paid': 60,
          'expense:materials': -25,
        },
      );
      expect(
        entries.singleWhere((item) => item.payment == partial).date,
        _received,
      );
      expect(partial.outstandingAmount, 60);
    },
  );

  test(
    'period boundaries follow receipt and expense dates, not invoice creation',
    () {
      final entries = buildMoneyTimeline(
        payments: [
          _payment('at-start', received: _start),
          _payment(
            'before',
            received: _start.subtract(const Duration(seconds: 1)),
          ),
          _payment('at-end', received: _end),
          _payment(
            'last-second',
            received: _end.subtract(const Duration(seconds: 1)),
          ),
        ],
        expenses: [
          _expense('cost-start', date: _start),
          _expense('cost-end', date: _end),
        ],
        range: _range,
      );
      expect(entries.map((item) => item.stableKey).toSet(), {
        'payment:at-start',
        'payment:last-second',
        'expense:cost-start',
      });
      expect(entries.first.stableKey, 'payment:last-second');
    },
  );

  test(
    'ties are deterministic and a payment and expense cannot share a key',
    () {
      final payments = [_payment('same'), _payment('other')];
      final expenses = [_expense('same'), _expense('other')];
      final first = buildMoneyTimeline(
        payments: payments,
        expenses: expenses,
        range: _range,
      );
      final reversed = buildMoneyTimeline(
        payments: payments.reversed,
        expenses: expenses.reversed,
        range: _range,
      );
      expect(
        first.map((item) => item.stableKey),
        reversed.map((item) => item.stableKey),
      );
      expect(first.map((item) => item.stableKey).toSet(), hasLength(4));
      expect(
        payments.first.id,
        'same',
        reason: 'Sorting must not mutate caller data.',
      );
    },
  );

  test(
    'filters retain their actual source including negative income records',
    () {
      final payments = [_payment('income'), _payment('refund', total: -20)];
      final expenses = [_expense('cost')];
      final income = buildMoneyTimeline(
        payments: payments,
        expenses: expenses,
        range: _range,
        filter: MoneyTimelineFilter.income,
      );
      final costs = buildMoneyTimeline(
        payments: payments,
        expenses: expenses,
        range: _range,
        filter: MoneyTimelineFilter.expenses,
      );
      expect(income.map((item) => item.payment?.id), ['income', 'refund']);
      expect(income.every((item) => item.expense == null), isTrue);
      expect(costs.single.expense?.id, 'cost');
      expect(costs.single.payment, isNull);
      expect(costs.single.amount, -25);
    },
  );

  test(
    'payment search combines case-insensitive words from one complete record',
    () {
      final payment = _payment(
        '123',
        status: 'sent',
        total: 1000,
        collected: 450,
        name: 'Jamie Parker',
        email: 'jamie@example.test',
        notes: 'Emergency shopfront clean',
        due: DateTime(2026, 10, 3),
      );
      for (final query in [
        '  PARKER   emergency ',
        'jamie@example.test PAY-123',
        '£1,000 shopfront',
        '450.00 550',
        '2026-09-16 September',
        '16/09/2026 Wed',
        '01/08/2026',
        '3 October',
        'part-paid',
      ]) {
        expect(paymentMatchesSearch(payment, query), isTrue, reason: query);
      }
      expect(paymentMatchesSearch(payment, 'Jamie plumber'), isFalse);
      expect(paymentMatchesSearch(payment, '   '), isTrue);
    },
  );

  test(
    'expense search includes category, notes, signed amount and calendar date',
    () {
      final expense = _expense(
        'fuel',
        category: 'Fuel',
        amount: 45.50,
        notes: 'Van top-up',
      );
      for (final query in [
        'FUEL van',
        'expense 45.50',
        '-£45.50',
        '16 September 2026',
      ]) {
        expect(expenseMatchesSearch(expense, query), isTrue, reason: query);
      }
      expect(expenseMatchesSearch(expense, 'Van rent'), isFalse);
      expect(expenseMatchesSearch(expense, ' \n\t '), isTrue);
    },
  );

  test(
    'search scans older records before the caller takes a five-row preview',
    () {
      final payments = List.generate(
        12,
        (index) => _payment(
          '$index',
          received: _received.subtract(Duration(days: index)),
          notes: index == 11 ? 'Annual deep clean' : 'Routine visit',
        ),
      );
      final all = buildMoneyTimeline(
        payments: payments,
        expenses: const [],
        range: _range,
      );
      expect(all, hasLength(12));
      final result = buildMoneyTimeline(
        payments: payments,
        expenses: const [],
        range: _range,
        query: 'annual deep',
      );
      expect(result.single.payment?.id, '11');
      expect(
        buildMoneyTimeline(
          payments: payments,
          expenses: const [],
          range: MoneyPeriodRange(start: _received, end: _end, label: 'Later'),
          query: 'annual',
        ),
        isEmpty,
      );
    },
  );

  test(
    'invalid monetary records cannot enter movement totals or formatted rows',
    () {
      final entries = buildMoneyTimeline(
        payments: [_payment('invalid', total: double.nan, collected: 0)],
        expenses: [_expense('invalid', amount: double.infinity)],
        range: _range,
      );
      expect(entries, isEmpty);
    },
  );

  test(
    'signed display preserves pence and a paid zero does not look like a refund',
    () {
      expect(moneyTimelineAmountLabel(19.99), '+£19.99');
      expect(moneyTimelineAmountLabel(-19.99), '-£19.99');
      expect(moneyTimelineAmountLabel(0), '+£0');
      expect(moneyTimelineAmountLabel(-0.0), '+£0');
      expect(moneyTimelineAmountLabel(19.999), '+£20');
    },
  );
}
