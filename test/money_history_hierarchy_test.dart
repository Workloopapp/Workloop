import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/add_payment_screen.dart';
import 'package:workloop/features/finance/expense_editor_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/widgets/payment_cards.dart';
import 'package:workloop/features/finance/widgets/money_summary_widgets.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/business_documents_provider.dart';
import 'package:workloop/shared/providers/business_document_defaults_provider.dart';
import 'package:workloop/shared/models/business_document_defaults.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

final _now = DateTime(2026, 9, 16, 12);

Payment _income(int index, {DateTime? received}) => Payment(
  id: 'income-$index',
  workspaceId: 'workspace-one',
  number: 'PAY-$index',
  status: 'paid',
  issueDate: DateTime(2026, 8, 1),
  incomeRecordedAt: received ?? _now.subtract(Duration(hours: index)),
  total: 100,
  amountPaid: 100,
  clientName: 'Customer $index',
  notes: 'Payment details $index',
);

List<Payment> _incomes(int count) => List.generate(count, _income);

List<Expense> _expenses(int count) => List.generate(
  count,
  (index) => Expense(
    id: 'expense-$index',
    workspaceId: 'workspace-one',
    amount: 10,
    category: 'Materials',
    notes: 'Expense details $index',
    expenseDate: _now.subtract(Duration(hours: index)),
  ),
);

Future<void> _showMoney(
  WidgetTester tester, {
  List<Payment> payments = const [],
  List<Expense> expenses = const [],
  bool collectionEnabled = true,
  Future<Map<String, dynamic>?> Function()? settings,
  String? initialPaymentId,
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
        expensesProvider.overrideWith((ref) async => expenses),
        clientsProvider.overrideWith((ref) async => const []),
        businessDocumentsProvider.overrideWith((ref) async => const []),
        businessDocumentDefaultsProvider.overrideWith(
          (ref) async => const BusinessDocumentDefaults(
            business: {'name': 'Test business'},
          ),
        ),
        paymentCollectionEnabledProvider.overrideWithValue(collectionEnabled),
        workspaceSettingsProvider.overrideWith(
          (ref) =>
              settings?.call() ??
              Future.value(const {
                'workspace_id': 'workspace-one',
                'revenue_target': 4345,
              }),
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
        home: FinanceScreen(
          referenceDate: _now,
          initialPaymentId: initialPaymentId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final history = find.byKey(const ValueKey('money-history-toggle'));
  if (history.evaluate().isNotEmpty && initialPaymentId == null) {
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    await tester.tap(history);
    await tester.pumpAndSettle();
    tester.widget<ListView>(find.byType(ListView).first).controller!.jumpTo(0);
    await tester.pumpAndSettle();
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<String> _visiblePaymentIds(WidgetTester tester) => tester
    .widgetList<PaymentCard>(find.byType(PaymentCard))
    .map((card) => card.payment.id)
    .toList();

void main() {
  testWidgets(
    'Money gives invoices a main section and keeps records in context',
    (tester) async {
      await _showMoney(tester, collectionEnabled: false);
      expect(find.text('Business money tools'), findsNothing);
      expect(find.text('Tax planning'), findsNothing);
      expect(find.text('Business mileage'), findsNothing);
      final nav = find.byType(WorkloopNavigationControl<MoneySection>);
      await tester.tap(
        find.descendant(of: nav, matching: find.text('Invoices')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quotes'), findsOneWidget);
      expect(find.text('Tax planning'), findsNothing);
      await tester.tap(find.descendant(of: nav, matching: find.text('Spent')));
      await tester.pumpAndSettle();
      expect(find.text('Business mileage'), findsOneWidget);
      expect(find.text('Expenses & receipts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Money navigation remains readable at 320px and doubled text', (
    tester,
  ) async {
    await _showMoney(
      tester,
      collectionEnabled: false,
      size: const Size(320, 700),
      textScale: 2,
    );
    final nav = find.byType(WorkloopNavigationControl<MoneySection>);
    expect(tester.getSize(nav).width, greaterThan(320 - AppSpacing.pageX * 2));
    await tester.ensureVisible(
      find.descendant(of: nav, matching: find.text('Owed')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: nav, matching: find.text('Owed')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WorkloopNavigationControl<MoneySection>>(nav).selected,
      MoneySection.owed,
    );
    expect(find.text('0 payments waiting to be paid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overview puts cash and recent activity before planning and setup',
    (tester) async {
      await _showMoney(tester, payments: _incomes(30));

      expect(_visiblePaymentIds(tester), [
        'income-0',
        'income-1',
        'income-2',
        'income-3',
        'income-4',
      ]);
      expect(find.text('30 payments this week'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('money-net-profit-total')))
            .data,
        '£3000',
      );
      final chartY = tester.getTopLeft(find.text('Net profit')).dy;
      final targetY = tester.getTopLeft(find.text('Monthly target')).dy;
      final setupY = tester
          .getTopLeft(find.text('Card & contactless payments'))
          .dy;
      final historyY = tester.getTopLeft(find.text('Payments')).dy;
      expect(chartY, lessThan(historyY));
      expect(historyY, lessThan(targetY));
      expect(setupY, greaterThan(targetY));
      expect(historyY, lessThan(tester.getTopLeft(find.text('Customer 0')).dy));
      expect(find.text('View all 30 payments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanding and collapsing history preserve the control position',
    (tester) async {
      await _showMoney(tester, payments: _incomes(30));
      final expand = find.widgetWithText(
        WorkloopTextButton,
        'View all 30 payments',
      );
      await tester.ensureVisible(expand);
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      final offset = list.controller!.offset;
      final position = tester.getTopLeft(expand);
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsNWidgets(30));
      final collapse = find.widgetWithText(
        WorkloopTextButton,
        'Show recent payments',
      );
      expect(tester.getTopLeft(collapse), position);
      expect(list.controller!.offset, offset);
      await tester.tap(collapse);
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsNWidgets(5));
      expect(list.controller!.offset, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('older income retains its exact details and edit action', (
    tester,
  ) async {
    await _showMoney(tester, payments: _incomes(30));
    await _tapVisible(tester, find.text('View all 30 payments'));
    await _tapVisible(tester, find.text('Customer 29'));
    expect(find.text('Income received'), findsOneWidget);
    expect(find.text('Payment details 29').last, findsOneWidget);
    await _tapVisible(tester, find.text('Edit income'));
    final editor = tester.widget<AddPaymentScreen>(
      find.byType(AddPaymentScreen),
    );
    expect(editor.payment!.id, 'income-29');
    expect(editor.payment!.total, 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history uses received dates and resets to recent for a new period',
    (tester) async {
      await _showMoney(
        tester,
        payments: [
          ..._incomes(30),
          _income(90, received: DateTime(2026, 9, 2)),
          _income(91, received: DateTime(2026, 8, 25)),
        ],
      );
      await _tapVisible(tester, find.text('View all 30 payments'));
      expect(_visiblePaymentIds(tester), hasLength(30));
      expect(_visiblePaymentIds(tester), isNot(contains('income-90')));
      await _tapVisible(tester, find.text('Month'));
      expect(_visiblePaymentIds(tester), hasLength(5));
      expect(find.text('31 payments this month'), findsOneWidget);
      await _tapVisible(tester, find.text('View all 31 payments'));
      expect(_visiblePaymentIds(tester), contains('income-90'));
      expect(_visiblePaymentIds(tester), isNot(contains('income-91')));
      await _tapVisible(tester, find.text('Week'));
      expect(_visiblePaymentIds(tester), hasLength(5));
      expect(find.text('View all 30 payments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom dates retain payment setup and expand only the chosen range',
    (tester) async {
      await _showMoney(
        tester,
        payments: [
          ..._incomes(30),
          _income(90, received: DateTime(2026, 8, 25)),
          _income(91, received: DateTime(2026, 7, 25)),
        ],
      );
      await _tapVisible(tester, find.text('View all 30 payments'));
      await _tapVisible(tester, find.text('Custom'));
      await _tapVisible(tester, find.text('Apply Period'));
      expect(find.text('Weekly target'), findsNothing);
      expect(find.text('Monthly target'), findsOneWidget);
      expect(find.text('Card & contactless payments'), findsOneWidget);
      expect(_visiblePaymentIds(tester), hasLength(5));
      await _tapVisible(tester, find.text('View all 31 payments'));
      expect(_visiblePaymentIds(tester), contains('income-90'));
      expect(_visiblePaymentIds(tester), isNot(contains('income-91')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings failure does not hide history and retries only setup', (
    tester,
  ) async {
    var attempts = 0;
    await _showMoney(
      tester,
      payments: _incomes(30),
      settings: () async {
        if (++attempts == 1) throw StateError('offline');
        return {'workspace_id': 'workspace-one', 'revenue_target': 4345};
      },
    );
    expect(find.text('Could not load your Money target'), findsOneWidget);
    expect(find.text('Card & contactless payments'), findsNothing);
    await _tapVisible(tester, find.text('View all 30 payments'));
    expect(find.byType(PaymentCard), findsNWidgets(30));
    await _tapVisible(tester, find.text('Try again'));
    expect(attempts, 2);
    expect(find.text('Card & contactless payments'), findsOneWidget);
    expect(find.byType(PaymentCard), findsNWidgets(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small and empty histories do not display an unnecessary disclosure',
    (tester) async {
      await _showMoney(tester, payments: _incomes(5), collectionEnabled: false);
      expect(find.byType(PaymentCard), findsNWidgets(5));
      expect(find.textContaining('View all'), findsNothing);
      expect(find.text('Card & contactless payments'), findsOneWidget);
      await _tapVisible(tester, find.text('Spent'));
      expect(find.text('Nothing spent in this period'), findsOneWidget);
      expect(find.textContaining('View all'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long expense history follows category totals and still opens editing',
    (tester) async {
      await _showMoney(tester, expenses: _expenses(20));
      await _tapVisible(tester, find.text('Spent'));
      expect(find.text('20 expenses · This week'), findsOneWidget);
      expect(find.text('Expense details 4'), findsOneWidget);
      expect(find.text('Expense details 5'), findsNothing);
      expect(find.byType(ExpenseCategorySummary), findsNothing);
      await _tapVisible(tester, find.text('Spending by category'));
      expect(find.byType(ExpenseCategorySummary), findsOneWidget);
      await _tapVisible(tester, find.text('Spending by category'));
      expect(find.byType(ExpenseCategorySummary), findsNothing);
      expect(
        tester.getTopLeft(find.text('Spending by category')).dy,
        lessThan(tester.getTopLeft(find.text('Expenses & receipts')).dy),
      );
      await _tapVisible(tester, find.text('View all 20 expenses'));
      await _tapVisible(tester, find.text('Expense details 19'));
      final editor = tester.widget<ExpenseEditorScreen>(
        find.byType(ExpenseEditorScreen),
      );
      expect(editor.expense!.id, 'expense-19');
      expect(editor.expense!.amount, 10);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('owed payments remain complete with overdue entries first', (
    tester,
  ) async {
    final payments = List.generate(
      12,
      (index) => Payment(
        id: 'owed-$index',
        workspaceId: 'workspace-one',
        number: 'PAY-$index',
        status: 'sent',
        issueDate: _now,
        dueDate: index == 11 ? DateTime(2020) : DateTime(2050, 1, index + 1),
        total: 100,
        clientName: 'Owed customer $index',
      ),
    );
    await _showMoney(tester, payments: payments);
    await _tapVisible(tester, find.text('Owed'));
    expect(_visiblePaymentIds(tester), hasLength(12));
    expect(_visiblePaymentIds(tester).first, 'owed-11');
    expect(find.textContaining('View all'), findsNothing);
    await _tapVisible(tester, find.text('Owed customer 10'));
    expect(find.text('Mark as Received'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a payment deep link opens even when outside the recent list and period',
    (tester) async {
      await _showMoney(
        tester,
        payments: [
          ..._incomes(30),
          _income(99, received: DateTime(2026, 8, 1)),
        ],
        initialPaymentId: 'income-99',
      );
      expect(find.text('Customer 99'), findsOneWidget);
      expect(find.text('Income received'), findsOneWidget);
      expect(find.text('Edit income'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history disclosure remains readable and usable at 320px and 2x text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _showMoney(
        tester,
        payments: _incomes(30),
        size: const Size(320, 568),
        textScale: 2,
      );
      final expand = find.widgetWithText(
        WorkloopTextButton,
        'View all 30 payments',
      );
      await tester.ensureVisible(expand);
      await tester.pumpAndSettle();
      expect(tester.getSize(expand).height, greaterThanOrEqualTo(44));
      final rect = tester.getRect(expand);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      tester.semantics.tap(find.semantics.byLabel('View all 30 payments'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsNWidgets(30));
      expect(find.text('Show recent payments'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
