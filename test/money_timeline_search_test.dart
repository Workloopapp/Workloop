import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/expense_editor_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/money_timeline.dart';
import 'package:workloop/features/finance/widgets/money_timeline_widgets.dart';
import 'package:workloop/features/finance/widgets/payment_cards.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

final _now = DateTime(2026, 9, 16, 12);

Payment _income(
  String id, {
  DateTime? received,
  double total = 100,
  double? paid,
  String status = 'paid',
  String? name,
  String? notes,
  String? number,
}) => Payment(
  id: id,
  workspaceId: 'workspace-one',
  number: number ?? 'PAY-$id',
  status: status,
  issueDate: DateTime(2026, 8, 1),
  incomeRecordedAt: received ?? _now,
  dueDate: DateTime(2050, 1, 1),
  total: total,
  amountPaid: paid ?? total,
  clientName: name ?? 'Customer $id',
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
  workspaceId: 'workspace-one',
  amount: amount,
  category: category,
  expenseDate: date ?? _now,
  notes: notes ?? 'Expense $id',
);

Future<void> _showMoney(
  WidgetTester tester, {
  List<Payment> payments = const [],
  List<Expense> expenses = const [],
  Future<List<Expense>> Function()? loadExpenses,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceIdProvider.overrideWith((ref) async => 'workspace-one'),
        invoicesProvider.overrideWith((ref) async => payments),
        expensesProvider.overrideWith(
          (ref) => loadExpenses?.call() ?? Future.value(expenses),
        ),
        clientsProvider.overrideWith((ref) async => const []),
        paymentCollectionEnabledProvider.overrideWithValue(false),
        workspaceSettingsProvider.overrideWith(
          (ref) async => {
            'workspace_id': 'workspace-one',
            'revenue_target': 4000,
          },
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FinanceScreen(referenceDate: _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final history = find.byKey(const ValueKey('money-history-toggle'));
  if (history.evaluate().isNotEmpty) {
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    await tester.tap(history);
    await tester.pumpAndSettle();
    tester.widget<ListView>(find.byType(ListView).first).controller!.jumpTo(0);
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  final list = tester.widget<ListView>(find.byType(ListView).first);
  list.controller!.jumpTo(0);
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.descendant(
      of: find.byType(WorkloopNavigationControl<MoneySection>),
      matching: find.text(label),
    ),
  );
}

Future<void> _filter(WidgetTester tester, String label) => _tap(
  tester,
  find.descendant(
    of: find.byType(WorkloopSegmentedControl<MoneyTimelineFilter>),
    matching: find.text(label),
  ),
);

Future<void> _search(
  WidgetTester tester,
  String query, {
  String key = 'payments-search',
}) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, query);
  await tester.pumpAndSettle();
}

Finder _incomeRow(String id) => find.byKey(ValueKey('income-payment:$id'));
Finder _expenseRow(String id) => find.byKey(ValueKey('expense-$id'));

void main() {
  testWidgets('cash totals reveal matching history and clear stale search', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [
        _income('receipt'),
        _income('outside', received: DateTime(2026, 8, 1)),
      ],
      expenses: [_expense('supplies')],
    );
    await _search(tester, 'no match');
    await _tap(tester, find.text('Money received'));
    expect(_incomeRow('receipt'), findsOneWidget);
    expect(_incomeRow('outside'), findsNothing);
    expect(_expenseRow('supplies'), findsNothing);
    expect(
      tester
          .widget<WorkloopSegmentedControl<MoneyTimelineFilter>>(
            find.byType(WorkloopSegmentedControl<MoneyTimelineFilter>),
          )
          .selected,
      MoneyTimelineFilter.income,
    );
    expect(
      find.byKey(const ValueKey('payments-search')).hitTestable(),
      findsOneWidget,
    );
    await _tap(tester, find.text('Money spent'));
    expect(_incomeRow('receipt'), findsNothing);
    expect(_expenseRow('supplies'), findsOneWidget);
    expect(
      tester
          .widget<WorkloopSegmentedControl<MoneyTimelineFilter>>(
            find.byType(WorkloopSegmentedControl<MoneyTimelineFilter>),
          )
          .selected,
      MoneyTimelineFilter.expenses,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Payments mixes income and expenses in received-date order', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [
        _income('older', received: DateTime(2026, 9, 14, 9)),
        _income('newer', received: DateTime(2026, 9, 16, 9)),
      ],
      expenses: [_expense('latest', date: DateTime(2026, 9, 16, 10))],
    );

    expect(find.text('Payments received'), findsNothing);
    expect(find.text('Payments'), findsOneWidget);
    expect(_expenseRow('latest'), findsOneWidget);
    expect(_incomeRow('newer'), findsOneWidget);
    expect(_incomeRow('older'), findsOneWidget);
    expect(
      tester.getTopLeft(_expenseRow('latest')).dy,
      lessThan(tester.getTopLeft(_incomeRow('newer')).dy),
    );
    expect(
      tester.getTopLeft(_incomeRow('newer')).dy,
      lessThan(tester.getTopLeft(_incomeRow('older')).dy),
    );
    expect(
      find.descendant(of: _incomeRow('newer'), matching: find.text('+£100')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _expenseRow('latest'), matching: find.text('-£25')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds older rows beyond the five visible entries', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: List.generate(
        12,
        (index) => _income(
          'p$index',
          received: _now.subtract(Duration(hours: index)),
          notes: index == 11 ? 'Ceramic coating balance' : 'Valeting payment',
        ),
      ),
      expenses: [
        _expense(
          'old-supplies',
          date: _now.subtract(const Duration(days: 1)),
          notes: 'Ceramic applicators',
        ),
      ],
    );
    expect(_incomeRow('p11'), findsNothing);
    expect(_expenseRow('old-supplies'), findsNothing);

    await _search(tester, '  CERAMIC  ');
    expect(_incomeRow('p11'), findsOneWidget);
    expect(_expenseRow('old-supplies'), findsOneWidget);
    expect(find.byType(PaymentCard), findsOneWidget);
    expect(find.textContaining('View all'), findsNothing);

    await _search(tester, 'valeting');
    expect(find.byType(PaymentCard), findsNWidgets(11));
    await _search(tester, '');
    expect(find.byType(PaymentCard), findsNWidgets(5));
    expect(_incomeRow('p11'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Income and Expenses filters compose with search', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [_income('wash', notes: 'Mobile wash')],
      expenses: [_expense('wash', notes: 'Wash shampoo')],
    );

    await _search(tester, 'wash');
    await _filter(tester, 'Income');
    expect(_incomeRow('wash'), findsOneWidget);
    expect(_expenseRow('wash'), findsNothing);
    await _filter(tester, 'Expenses');
    expect(_incomeRow('wash'), findsNothing);
    expect(_expenseRow('wash'), findsOneWidget);
    await _filter(tester, 'All');
    expect(_incomeRow('wash'), findsOneWidget);
    expect(_expenseRow('wash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('broad search previews 25 results without hiding older matches', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: List.generate(
        20,
        (index) => _income(
          'p$index',
          received: _now.subtract(Duration(hours: index)),
          notes: 'Detail payment',
        ),
      ),
      expenses: List.generate(
        10,
        (index) => _expense(
          'e$index',
          date: _now.subtract(Duration(hours: index + 20)),
          notes: index == 9 ? 'Detail ceramic supplies' : 'Detail supplies',
        ),
      ),
    );
    await _search(tester, 'detail');
    expect(find.byType(PaymentCard), findsNWidgets(20));
    expect(find.byType(MoneyExpenseRow), findsNWidgets(5));
    expect(find.text('30 results · This week'), findsOneWidget);
    expect(_expenseRow('e9'), findsNothing);
    await _tap(tester, find.text('View all 30 results'));
    expect(find.byType(PaymentCard), findsNWidgets(20));
    expect(find.byType(MoneyExpenseRow), findsNWidgets(10));
    expect(_expenseRow('e9'), findsOneWidget);
    await _tap(tester, find.text('Show first 25 results'));
    expect(find.byType(PaymentCard), findsNWidgets(20));
    expect(find.byType(MoneyExpenseRow), findsNWidgets(5));
    await _search(tester, 'ceramic');
    expect(find.byType(PaymentCard), findsNothing);
    expect(find.byType(MoneyExpenseRow), findsOneWidget);
    expect(_expenseRow('e9'), findsOneWidget);
    await _search(tester, '');
    expect(find.byType(PaymentCard), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search uses names, references, notes, categories and amounts', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [
        _income(
          'alice',
          name: 'Alice Parker',
          number: 'INV-4827',
          notes: 'Full exterior detail',
          total: 123.45,
        ),
      ],
      expenses: [_expense('fuel', category: 'Travel', notes: 'Diesel fill')],
    );
    for (final query in ['ALICE', '4827', 'exterior', '123.45']) {
      await _search(tester, query);
      expect(_incomeRow('alice'), findsOneWidget, reason: query);
      expect(_expenseRow('fuel'), findsNothing, reason: query);
    }
    for (final query in ['travel', 'diesel']) {
      await _search(tester, query);
      expect(_incomeRow('alice'), findsNothing, reason: query);
      expect(_expenseRow('fuel'), findsOneWidget, reason: query);
    }
    await _search(tester, 'no-such-payment');
    expect(_incomeRow('alice'), findsNothing);
    expect(_expenseRow('fuel'), findsNothing);
    expect(find.byKey(const ValueKey('payments-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('received partials and refunds are shown without unpaid money', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [
        _income('deposit', status: 'sent', total: 100, paid: 40),
        _income('unpaid', status: 'sent', paid: 0),
        _income('refund', total: -20, paid: -20),
      ],
    );
    expect(_incomeRow('deposit'), findsOneWidget);
    expect(_incomeRow('refund'), findsOneWidget);
    expect(_incomeRow('unpaid'), findsNothing);
    expect(
      find.descendant(of: _incomeRow('deposit'), matching: find.text('+£40')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _incomeRow('refund'), matching: find.text('-£20')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _incomeRow('refund'),
        matching: find.textContaining('Recorded'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _incomeRow('deposit'),
        matching: find.textContaining('Received'),
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Customer deposit'));
    expect(find.text('Part-paid income'), findsOneWidget);
    expect(find.text('£40 received · £60 still to collect'), findsOneWidget);
    await _tap(tester, find.text('Close'));
    await _tab(tester, 'Owed');
    final cards = tester.widgetList<PaymentCard>(find.byType(PaymentCard));
    expect(
      cards.map((card) => card.payment.id),
      containsAll(['deposit', 'unpaid']),
    );
    expect(cards.map((card) => card.payment.id), isNot(contains('refund')));
    expect(find.text('£60'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected period applies to both types before searching', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [
        _income('week-start', received: DateTime(2026, 9, 14)),
        _income('next-week', received: DateTime(2026, 9, 21)),
        _income('last-month', received: DateTime(2026, 8, 31, 23, 59)),
      ],
      expenses: [
        _expense('week-end', date: DateTime(2026, 9, 20, 23, 59)),
        _expense('earlier-month', date: DateTime(2026, 9, 1)),
      ],
    );
    expect(_incomeRow('week-start'), findsOneWidget);
    expect(_expenseRow('week-end'), findsOneWidget);
    expect(_incomeRow('next-week'), findsNothing);
    expect(_incomeRow('last-month'), findsNothing);
    expect(_expenseRow('earlier-month'), findsNothing);

    await _tap(tester, find.text('Month'));
    expect(_incomeRow('next-week'), findsOneWidget);
    expect(_expenseRow('earlier-month'), findsOneWidget);
    expect(_incomeRow('last-month'), findsNothing);
    await _search(tester, 'last-month');
    expect(_incomeRow('last-month'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a searched expense opens its own existing editor', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [_income('payment')],
      expenses: [_expense('polish', notes: 'Specialist polish', amount: 42)],
    );
    await _search(tester, 'specialist');
    await _tap(tester, find.text('Specialist polish'));
    final editor = tester.widget<ExpenseEditorScreen>(
      find.byType(ExpenseEditorScreen),
    );
    expect(editor.expense!.id, 'polish');
    expect(editor.expense!.amount, 42);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Spent and Owed have independent full-history search', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [
        _income('maria', status: 'sent', paid: 0, name: 'Maria Jones'),
        _income('ben', status: 'sent', paid: 0, name: 'Ben Adams'),
      ],
      expenses: List.generate(
        9,
        (index) => _expense(
          'e$index',
          date: _now.subtract(Duration(hours: index)),
          notes: index == 8 ? 'Specialist buffer' : 'Standard supplies',
        ),
      ),
    );
    await _tab(tester, 'Spent');
    expect(find.text('Specialist buffer'), findsNothing);
    await _search(tester, 'specialist', key: 'expense-search');
    expect(find.text('Specialist buffer'), findsOneWidget);
    expect(find.text('Standard supplies'), findsNothing);
    await _tab(tester, 'Owed');
    await _search(tester, 'maria', key: 'owed-search');
    expect(find.text('Maria Jones'), findsOneWidget);
    expect(find.text('Ben Adams'), findsNothing);
    expect(find.text('2 payments waiting to be paid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new search controls fit a 320px screen with large text', (
    tester,
  ) async {
    await _showMoney(
      tester,
      payments: [_income('income')],
      expenses: [_expense('expense')],
      size: const Size(320, 568),
      textScale: 2,
    );
    await _search(tester, 'expense');
    final searchRect = tester.getRect(
      find.byKey(const ValueKey('payments-search')),
    );
    expect(searchRect.left, greaterThanOrEqualTo(0));
    expect(searchRect.right, lessThanOrEqualTo(320));
    expect(_expenseRow('expense'), findsOneWidget);
    await _filter(tester, 'Expenses');
    expect(_expenseRow('expense'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable expenses never imply a complete profit or timeline',
    (tester) async {
      var expenseAttempts = 0;
      await _showMoney(
        tester,
        payments: [
          _income('received'),
          _income('owed', status: 'sent', paid: 0),
        ],
        loadExpenses: () async {
          if (++expenseAttempts == 1) throw StateError('offline');
          return [_expense('recovered')];
        },
      );
      expect(find.text('CASH SUMMARY'), findsOneWidget);
      expect(find.text('Money received'), findsOneWidget);
      expect(find.text('£100'), findsOneWidget);
      expect(find.text('Monthly target'), findsOneWidget);
      expect(
        find.text('Spending and net profit are unavailable.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('money-net-profit-total')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('money-net-profit-chart')),
        findsNothing,
      );
      expect(_incomeRow('received'), findsNothing);

      await _filter(tester, 'Income');
      expect(_incomeRow('received'), findsOneWidget);
      await _tab(tester, 'Owed');
      expect(find.text('Customer owed'), findsOneWidget);
      await _tab(tester, 'Overview');
      await _filter(tester, 'All');
      await _tap(tester, find.text('Retry expenses'));
      expect(expenseAttempts, 2);
      await _tap(tester, find.text('Profit trend'));
      expect(
        find.byKey(const ValueKey('money-net-profit-chart')),
        findsOneWidget,
      );
      expect(_incomeRow('received'), findsOneWidget);
      expect(_expenseRow('recovered'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timeline expense menu confirms the exact record before deletion',
    (tester) async {
      await _showMoney(
        tester,
        expenses: [
          _expense('fuel', amount: 68, category: 'Travel'),
          _expense('polish', amount: 42, category: 'Materials'),
        ],
      );
      await _search(tester, 'polish');
      await _tap(
        tester,
        find.byKey(const ValueKey('money-expense-menu-polish')),
      );
      await _tap(tester, find.text('Delete expense'));
      expect(find.text('Delete expense?'), findsOneWidget);
      expect(find.text('Materials · £42'), findsOneWidget);
      expect(find.text('Travel · £68'), findsNothing);
      await _tap(tester, find.text('Cancel'));
      expect(_expenseRow('polish'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
