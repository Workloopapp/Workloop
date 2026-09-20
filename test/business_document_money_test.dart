import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/features/finance/money_profit.dart';
import 'package:workloop/features/finance/money_timeline.dart';
import 'package:workloop/features/finance/widgets/payment_cards.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/business_feed_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';

Payment _managed() => Payment(
  id: 'invoice-1',
  workspaceId: 'business-1',
  number: 'INV-0001',
  status: 'sent',
  sourceDocumentId: 'document-1',
  issueDate: DateTime(2026, 7, 1),
  incomeRecordedAt: DateTime(2026, 8, 31, 12),
  dueDate: DateTime(2026, 9, 15),
  total: 100,
  amountPaid: 75,
  receipts: [
    PaymentReceipt(
      id: 'first',
      amount: 30,
      receivedAt: DateTime(2026, 8, 31, 12),
    ),
    PaymentReceipt(
      id: 'second',
      amount: 70,
      receivedAt: DateTime(2026, 9, 1, 12),
    ),
    PaymentReceipt(
      id: 'refund',
      amount: -25,
      receivedAt: DateTime(2026, 9, 2, 12),
    ),
  ],
);

void main() {
  test(
    'inclusive VAT preserves gross totals and reconciles penny rounding',
    () {
      const visit = BusinessDocumentItem(
        description: 'Visit',
        quantityHundredths: 100,
        unitPricePence: 6000,
      );
      expect(documentTotals([visit], 20, true), (
        subtotal: 5000,
        tax: 1000,
        total: 6000,
      ));
      expect(documentTotals([visit], 20, false), (
        subtotal: 6000,
        tax: 1200,
        total: 7200,
      ));
      const penny = BusinessDocumentItem(
        description: 'Penny',
        quantityHundredths: 100,
        unitPricePence: 3,
      );
      expect(documentTotals([penny], 20, true), (
        subtotal: 2,
        tax: 1,
        total: 3,
      ));
      expect(penny.netUnitPrice(20, true), '£0.0250');
      const lines = [
        BusinessDocumentItem(
          description: 'One',
          quantityHundredths: 300,
          unitPricePence: 7,
        ),
        BusinessDocumentItem(
          description: 'Two',
          quantityHundredths: 100,
          unitPricePence: 5,
        ),
      ];
      expect(documentTotals(lines, 5, true), (subtotal: 25, tax: 1, total: 26));
    },
  );
  test('deposit request, payment and refund share one invoice balance', () {
    Payment payment(double paid, {String status = 'sent'}) => Payment(
      id: 'one-invoice',
      workspaceId: 'business',
      number: 'INV-1',
      status: status,
      issueDate: DateTime(2026, 9, 8),
      total: 100,
      amountPaid: paid,
      sourceDocumentId: 'doc',
      depositAmount: 30,
      depositDueDate: DateTime(2026, 9, 8),
    );
    expect(payment(0).collectionAmount, 30);
    expect(payment(0).outstandingAmount, 100);
    expect(payment(0).cashReceipts, isEmpty);
    expect(payment(10).depositOutstandingAmount, 20);
    expect(payment(30).depositReceived, isTrue);
    expect(payment(30).collectionAmount, 70);
    expect(
      payment(20).depositOutstandingAmount,
      10,
      reason: 'refunding10 reopens deposit requirement',
    );
    expect(payment(20, status: 'cancelled').depositOutstandingAmount, 0);
    expect(payment(20, status: 'cancelled').depositReceived, isFalse);
    expect(Payment.fromMap(payment(30).toMap()).depositAmount, 30);
    expect(documentDepositPence(4846, 'percentage', 5000), 2423);
    expect(documentDepositPence(101, 'percentage', 5000), 51);
    expect(documentMoneyInput(-25), '-0.25');
  });

  test('document balances come from joined ledger and user-facing status', () {
    BusinessDocument doc(int? paid) => BusinessDocument.fromMap({
      'id': 'doc',
      'workspace_id': 'business',
      'type': 'invoice',
      'status': 'sent',
      'issued_at': '2026-09-08T12:00:00Z',
      'issue_date': '2026-09-08',
      'due_date': '2026-09-30',
      'total': 100,
      'deposit_type': 'percentage',
      'deposit_value': 30,
      'deposit_amount': 30,
      if (paid != null) 'payment_state': {'amount_paid': paid},
    });
    expect(doc(0).statusLabel(now: DateTime(2026, 9, 8)), 'Deposit due');
    expect(doc(30).statusLabel(now: DateTime(2026, 9, 8)), 'Part paid');
    expect(doc(30).statusLabel(now: DateTime(2026, 10, 1)), 'Overdue');
    expect(doc(100).statusLabel(now: DateTime(2026, 10, 1)), 'Paid');
    expect(doc(null).statusLabel(now: DateTime(2026, 9, 8)), 'Issued');
    expect(
      doc(null).outstandingPence,
      isNull,
      reason: 'missing ledger is not a zero receipt',
    );
  });
  test(
    'receipt search combines invoice identity with its own amount and date',
    () {
      final range = MoneyPeriodRange(
        start: DateTime(2026, 9),
        end: DateTime(2026, 10),
        label: 'September',
      );
      for (final query in [
        'refund',
        '-25.00',
        '2 September',
        'INV-0001 refund',
        'INV-0001 2 September',
      ]) {
        final entries = buildMoneyTimeline(
          payments: [_managed()],
          expenses: [],
          range: range,
          query: query,
        );
        expect(entries.map((entry) => entry.stableKey), [
          'receipt:refund',
        ], reason: query);
      }
      for (final query in ['75.00', '100.00', '31 August', '15 September']) {
        expect(
          buildMoneyTimeline(
            payments: [_managed()],
            expenses: [],
            range: range,
            query: query,
          ),
          isEmpty,
          reason: 'Invoice totals and dates are not receipt terms: $query',
        );
      }
    },
  );

  testWidgets(
    'received card shows the receipt amount and date rather than lifetime balance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PaymentCard(
              payment: _managed(),
              showReceivedEntry: true,
              receivedEntryAmount: -25,
              receivedEntryDate: DateTime(2026, 9, 2, 12),
              onTap: () {},
              onDelete: null,
            ),
          ),
        ),
      );
      expect(find.text('-£25'), findsOneWidget);
      expect(find.textContaining('Recorded Wed 2 Sep'), findsOneWidget);
      expect(find.text('+£75'), findsNothing);
      expect(find.textContaining('31 Aug'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'business feed reports recent receipt and refund events from an older invoice',
    () {
      final payment = _managed();
      final now = DateTime(2026, 9, 8, 12);
      final items = buildBusinessFeedItems(
        appointments: [],
        payments: [payment],
        expenses: [],
        tasks: [],
        notes: [],
        clients: [],
        bookingRequests: [],
        finance: FinanceSummary.from(
          payments: [payment],
          expenses: [],
          monthlyTarget: 0,
          now: now,
        ),
        now: now,
      );
      final received = items
          .where((item) => item.id == 'payment-receipt-second')
          .single;
      final refunded = items
          .where((item) => item.id == 'payment-receipt-refund')
          .single;
      expect(received.subtitle, contains('£70'));
      expect(received.timestamp, DateTime(2026, 9, 1, 12));
      expect(refunded.title, 'Refund recorded');
      expect(refunded.subtitle, contains('£25'));
      expect(refunded.timestamp, DateTime(2026, 9, 2, 12));
      expect(refunded.sourceId, payment.id);
      expect(items.any((item) => item.id == 'payment-receipt-first'), isFalse);
    },
  );

  test(
    'document money parsing and line rounding agree with SQL decimal arithmetic',
    () {
      expect(parseDocumentMoney('20.25'), 2025);
      expect(parseDocumentMoney('0.01'), 1);
      for (final invalid in [
        'NaN',
        'Infinity',
        '-1',
        '1.005',
        '1e2',
        '',
        '£10',
      ]) {
        expect(parseDocumentMoney(invalid), isNull, reason: invalid);
      }
      const line = BusinessDocumentItem(
        description: 'Work',
        quantityHundredths: 150,
        unitPricePence: 2025,
      );
      expect(line.totalPence, 3038);
      expect(line.quantity, '1.5');
      expect(documentMoneyInput(line.totalPence), '30.38');
      expect(
        const BusinessDocumentItem(
          description: 'Half penny',
          quantityHundredths: 50,
          unitPricePence: 1,
        ).totalPence,
        1,
      );
    },
  );

  test(
    'partial receipts and later refunds remain in their own calendar month',
    () {
      final payment = _managed();
      expect(receivedIncomeForMonth([payment], DateTime(2026, 7, 15)), 0);
      expect(receivedIncomeForMonth([payment], DateTime(2026, 8, 15)), 30);
      expect(receivedIncomeForMonth([payment], DateTime(2026, 9, 15)), 45);
      expect(
        payment.receivedAmountBetween(DateTime(2026, 1), DateTime(2027, 1)),
        payment.collectedAmount,
      );
      expect(payment.outstandingAmount, 25);
    },
  );

  test(
    'period summary, target and profit chart use the same receipt deltas',
    () {
      final payment = _managed();
      final range = MoneyPeriodRange(
        start: DateTime(2026, 9),
        end: DateTime(2026, 10),
        label: 'September',
      );
      final expenses = [
        Expense(
          id: 'expense-1',
          workspaceId: 'business-1',
          amount: 5,
          category: 'Materials',
          expenseDate: DateTime(2026, 9, 2),
        ),
      ];
      final summary = PeriodMoneySummary.from(
        payments: [payment],
        expenses: expenses,
        range: range,
        now: DateTime(2026, 9, 8),
      );
      final bars = buildMoneyProfitData(
        now: DateTime(2027),
        payments: [payment],
        expenses: expenses,
        range: range,
      );
      expect(summary.paid, 45);
      expect(summary.unpaid, 25);
      expect(summary.profit, 40);
      expect(bars.fold<double>(0, (sum, bar) => sum + bar.value), 40);
      expect(
        receivedIncomeForMonth([payment], DateTime(2026, 9, 8)),
        summary.paid,
      );
    },
  );

  test(
    'document history shows individual receipt and refund without cumulative duplicate',
    () {
      final entries = buildMoneyTimeline(
        payments: [_managed()],
        expenses: [],
        range: MoneyPeriodRange(
          start: DateTime(2026, 9),
          end: DateTime(2026, 10),
          label: 'September',
        ),
      );
      expect(entries.map((entry) => entry.stableKey), [
        'receipt:refund',
        'receipt:second',
      ]);
      expect(entries.map((entry) => entry.amount), [-25, 70]);
      expect(entries.first.date, DateTime(2026, 9, 2, 12));
      expect(
        entries.every((entry) => entry.payment?.id == 'invoice-1'),
        isTrue,
      );
    },
  );

  test('receipt interval includes its start and excludes its end', () {
    final payment = _managed();
    expect(
      payment.receivedAmountBetween(
        DateTime(2026, 9, 1, 12),
        DateTime(2026, 9, 2, 12),
      ),
      70,
    );
    expect(
      payment.receivedAmountBetween(
        DateTime(2026, 9, 2, 12),
        DateTime(2026, 9, 3, 12),
      ),
      -25,
    );
  });

  test('legacy payments retain their recorded date and paid fallback', () {
    final legacy = Payment(
      id: 'legacy',
      workspaceId: 'business-1',
      number: 'PAY-001',
      status: 'paid',
      issueDate: DateTime(2026, 7),
      incomeRecordedAt: DateTime(2026, 9, 8),
      total: 60,
    );
    expect(legacy.cashReceipts.single.amount, 60);
    expect(receivedIncomeForMonth([legacy], DateTime(2026, 7)), 0);
    expect(receivedIncomeForMonth([legacy], DateTime(2026, 9)), 60);
    final roundTrip = Payment.fromMap(_managed().toMap());
    expect(roundTrip.sourceDocumentId, 'document-1');
    expect(roundTrip.receipts, hasLength(3));
    expect(
      roundTrip.receivedAmountBetween(DateTime(2026, 9), DateTime(2026, 10)),
      45,
    );
  });
}
