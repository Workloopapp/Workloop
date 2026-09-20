import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/money_profit.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/utils/currency_format.dart';

final _weekStart = DateTime(2026, 9, 14);
final _week = MoneyPeriodRange(
  start: _weekStart,
  end: DateTime(2026, 9, 21),
  label: 'This week',
);

Payment _income(
  String id,
  double amount,
  DateTime date, {
  String status = 'paid',
  double? total,
  DateTime? issued,
}) => Payment(
  id: id,
  workspaceId: 'workspace-one',
  number: id,
  status: status,
  total: total ?? amount,
  amountPaid: amount,
  issueDate: issued ?? date,
  incomeRecordedAt: date,
);

Expense _expense(String id, double amount, DateTime date) => Expense(
  id: id,
  workspaceId: 'workspace-one',
  category: 'Materials',
  amount: amount,
  expenseDate: date,
);

Future<void> _showMoney(
  WidgetTester tester, {
  List<Payment> payments = const [],
  List<Expense> expenses = const [],
  bool dark = false,
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
        paymentCollectionEnabledProvider.overrideWithValue(false),
        workspaceSettingsProvider.overrideWith(
          (ref) async => const {
            'workspace_id': 'workspace-one',
            'revenue_target': 1000,
          },
        ),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FinanceScreen(referenceDate: DateTime(2026, 9, 16, 12)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final trend = find.text('Profit trend');
  if (trend.evaluate().isNotEmpty) {
    await tester.ensureVisible(trend);
    await tester.pumpAndSettle();
    await tester.tap(trend);
    await tester.pumpAndSettle();
  }
}

void main() {
  test(
    'net profit includes partial receipts and subtracts same-period expenses',
    () {
      final payments = [
        _income('received', 100, _weekStart),
        _income(
          'part-paid',
          25.50,
          DateTime(2026, 9, 15),
          status: 'pending',
          total: 80,
        ),
        _income(
          'not-paid',
          0,
          DateTime(2026, 9, 15),
          status: 'pending',
          total: 100,
        ),
        _income('refund', -10, DateTime(2026, 9, 16)),
      ];
      final expenses = [
        _expense('materials', 40.25, _weekStart),
        _expense('fuel', 50, DateTime(2026, 9, 15)),
      ];
      final data = buildMoneyProfitData(
        now: DateTime(2027),
        payments: payments,
        expenses: expenses,
        range: _week,
      );
      expect(data.map((item) => item.value), [59.75, -24.50, -10, 0, 0, 0, 0]);
      expect(data[1].valueLabel, '-£24.50');
      final summary = PeriodMoneySummary.from(
        now: DateTime(2027),
        payments: payments,
        expenses: expenses,
        range: _week,
      );
      expect(
        roundToPence(data.fold<double>(0, (sum, item) => sum + item.value)),
        roundToPence(summary.profit),
      );
    },
  );

  test(
    'received date and inclusive-start exclusive-end limits match Money totals',
    () {
      final data = buildMoneyProfitData(
        now: DateTime(2027),
        payments: [
          _income(
            'old-issue-new-receipt',
            20,
            _weekStart,
            issued: DateTime(2026, 8, 1),
          ),
          _income(
            'before',
            100,
            _weekStart.subtract(const Duration(microseconds: 1)),
          ),
          _income(
            'last-moment',
            12,
            _week.end.subtract(const Duration(microseconds: 1)),
          ),
          _income('after', 200, _week.end),
        ],
        expenses: [
          _expense(
            'before',
            90,
            _weekStart.subtract(const Duration(microseconds: 1)),
          ),
          _expense('start', 5, _weekStart),
          _expense('after', 90, _week.end),
        ],
        range: _week,
      );
      expect(data.map((item) => item.value), [15, 0, 0, 0, 0, 0, 12]);
    },
  );

  test('penny precision leaves a genuinely balanced day at zero', () {
    final data = buildMoneyProfitData(
      now: DateTime(2027),
      payments: [
        _income('one', .1, _weekStart),
        _income('two', .2, _weekStart),
      ],
      expenses: [_expense('balanced', .3, _weekStart)],
      range: _week,
    );
    expect(data.every((item) => item.value == 0), isTrue);
    expect(data.first.valueLabel, '£0');
  });

  test(
    '31-day and long custom periods retain every transaction exactly once',
    () {
      for (final days in [1, 2, 6, 7, 8, 28, 29, 30, 31, 90, 400]) {
        final end = addBusinessCalendarDays(_weekStart, days);
        final range = MoneyPeriodRange(
          start: _weekStart,
          end: end,
          label: 'Custom',
        );
        final payments = List.generate(
          days,
          (index) => _income(
            'income-$index',
            (index + 1).toDouble(),
            addBusinessCalendarDays(_weekStart, index),
          ),
        );
        final expenses = List.generate(
          days,
          (index) => _expense(
            'expense-$index',
            .25,
            addBusinessCalendarDays(_weekStart, index),
          ),
        );
        final data = buildMoneyProfitData(
          now: end,
          payments: payments,
          expenses: expenses,
          range: range,
        );
        expect(data.length, days > 7 ? 7 : days, reason: '$days days');
        expect(
          data.fold<double>(0, (sum, item) => sum + item.value),
          days * (days + 1) / 2 - days * .25,
          reason: '$days days',
        );
        expect(
          data.every((item) => item.value != 0),
          isTrue,
          reason: 'No empty overflow bucket for $days days',
        );
      }
    },
  );

  for (final start in [DateTime(2026, 3, 23), DateTime(2026, 10, 19)]) {
    test('calendar bins span the daylight-saving week beginning $start', () {
      final end = addBusinessCalendarDays(start, 7);
      final payments = List.generate(
        7,
        (index) => _income(
          'income-$index',
          (index + 1).toDouble(),
          DateTime(start.year, start.month, start.day + index, 23, 30),
        ),
      );
      final data = buildMoneyProfitData(
        now: end,
        payments: payments,
        expenses: const [],
        range: MoneyPeriodRange(start: start, end: end, label: 'This week'),
      );
      expect(data.map((item) => item.label), [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
      expect(data.map((item) => item.value), [1, 2, 3, 4, 5, 6, 7]);
    });
  }

  test('empty and invalid periods never manufacture a profit', () {
    final empty = buildMoneyProfitData(
      now: DateTime(2027),
      payments: const [],
      expenses: const [],
      range: _week,
    );
    expect(empty, hasLength(7));
    expect(empty.every((item) => item.value == 0), isTrue);
    for (final end in [_weekStart, addBusinessCalendarDays(_weekStart, -1)]) {
      expect(
        buildMoneyProfitData(
          now: DateTime(2027),
          payments: const [],
          expenses: const [],
          range: MoneyPeriodRange(
            start: _weekStart,
            end: end,
            label: 'Invalid',
          ),
        ),
        isEmpty,
      );
    }
  });

  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} chart shows loss below zero and profit above it',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _showMoney(
            tester,
            dark: dark,
            payments: [_income('income', 100, _weekStart)],
            expenses: [_expense('expense', 25, DateTime(2026, 9, 15))],
          );
          expect(find.text('Cash movement'), findsNothing);
          expect(find.text('Net profit'), findsOneWidget);
          expect(find.text('Income minus expenses'), findsOneWidget);
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('money-net-profit-total')),
                )
                .data,
            '£75',
          );
          final zero = tester
              .getTopLeft(
                find.byKey(const ValueKey('money-net-profit-zero-line')),
              )
              .dy;
          final profit = tester.getRect(
            find.byKey(const ValueKey('money-net-profit-bar-0')),
          );
          final loss = tester.getRect(
            find.byKey(const ValueKey('money-net-profit-bar-1')),
          );
          expect(profit.top, lessThan(zero));
          expect(profit.bottom, closeTo(zero, .01));
          expect(loss.top, closeTo(zero, .01));
          expect(loss.bottom, greaterThan(zero));
          final tokens = dark
              ? WorkloopThemeTokens.dark
              : WorkloopThemeTokens.light;
          final lossBar = tester.widget<Container>(
            find.byKey(const ValueKey('money-net-profit-bar-1')),
          );
          expect((lossBar.decoration as BoxDecoration).color, tokens.error);
          expect(
            find.semantics.byLabel(
              RegExp(r'Net profit for This week: £75.*Tue -£25'),
            ),
            findsOne,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'expense-only period has an honest negative total and visible loss',
    (tester) async {
      await _showMoney(
        tester,
        expenses: [_expense('expense', 42.50, _weekStart)],
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('money-net-profit-total')))
            .data,
        '-£42.50',
      );
      final zero = tester
          .getTopLeft(find.byKey(const ValueKey('money-net-profit-zero-line')))
          .dy;
      final loss = tester.getRect(
        find.byKey(const ValueKey('money-net-profit-bar-0')),
      );
      expect(loss.top, closeTo(zero, .01));
      expect(loss.height, greaterThan(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty period retains zero total without drawing a trend', (
    tester,
  ) async {
    await _showMoney(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('money-net-profit-total')))
          .data,
      '£0',
    );
    expect(find.byKey(const ValueKey('money-net-profit-chart')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart remains usable with enlarged text on a narrow screen', (
    tester,
  ) async {
    await _showMoney(
      tester,
      size: const Size(320, 740),
      textScale: 1.8,
      payments: [_income('income', 125000.99, _weekStart)],
      expenses: [_expense('expense', 99000.75, DateTime(2026, 9, 15))],
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('money-net-profit-chart')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('money-net-profit-total')))
          .data,
      '£26000.24',
    );
    expect(tester.takeException(), isNull);
  });
}
