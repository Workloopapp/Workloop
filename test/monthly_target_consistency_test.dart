import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/dashboard/dashboard_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/widgets/monthly_target_editor.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/setup_checklist_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/workspace_settings_repository.dart';
import 'package:workloop/shared/widgets/income_target_indicator.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_studio_graphics.dart';

final _now = DateTime(2026, 9, 16, 12);

Finder get _targetField => find.descendant(
  of: find.byType(MonthlyTargetEditor),
  matching: find.byType(TextField),
);

Finder _receivedTotal(String amount) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is Column &&
        widget.children.whereType<Text>().any(
          (child) => child.data == 'Money received',
        ),
  ),
  matching: find.text(amount),
);

Payment _payment(
  String id, {
  required double total,
  required DateTime received,
  DateTime? issued,
  String status = 'paid',
  double? collected,
}) => Payment(
  id: id,
  workspaceId: 'workspace-one',
  number: id,
  status: status,
  issueDate: issued ?? received,
  incomeRecordedAt: received,
  total: total,
  amountPaid: collected ?? total,
  clientName: id,
);

// Month receipts are £450; this week is £150. Invoice creation dates and
// outstanding balances must not become either the receipt date or amount.
List<Payment> _calendarReceipts() => [
  _payment(
    'Old invoice, new receipt',
    total: 200,
    issued: DateTime(2026, 8, 1),
    received: DateTime(2026, 9, 2),
  ),
  _payment(
    'Partial collection',
    total: 300,
    collected: 150,
    status: 'sent',
    received: DateTime(2026, 9, 15),
  ),
  _payment('First minute', total: 100, received: DateTime(2026, 9, 1)),
  _payment(
    'Previous month',
    total: 900,
    received: DateTime(2026, 8, 31, 23, 59),
    issued: DateTime(2026, 9, 1),
  ),
  _payment('Next month', total: 800, received: DateTime(2026, 10, 1)),
  _payment(
    'Still outstanding',
    total: 500,
    collected: 0,
    status: 'sent',
    received: _now,
  ),
];

class _Settings implements WorkspaceSettingsRepository {
  double target;
  bool failNextSave = false;
  Completer<void>? pendingSave;
  final writes = <({String workspace, Map<String, dynamic> values})>[];

  _Settings({this.target = 1000});

  @override
  Future<Map<String, dynamic>?> get(String workspaceId) async => {
    'workspace_id': workspaceId,
    'revenue_target': target,
  };

  @override
  Future<void> update(String workspaceId, Map<String, dynamic> values) async {
    writes.add((workspace: workspaceId, values: Map.of(values)));
    await pendingSave?.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Sample network failure');
    }
    target = (values['revenue_target'] as num).toDouble();
  }
}

class _Auth implements AuthRepository {
  @override
  String? get currentFirstName => 'Alex';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container({
  required _Settings settings,
  List<Payment>? payments,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      workspaceIdProvider.overrideWith((ref) async => 'workspace-one'),
      workspaceProvider.overrideWith(
        (ref) async => const {'id': 'workspace-one', 'name': 'Sample business'},
      ),
      workspaceSettingsRepositoryProvider.overrideWithValue(settings),
      invoicesProvider.overrideWith(
        (ref) async => payments ?? _calendarReceipts(),
      ),
      expensesProvider.overrideWith((ref) async => const []),
      paymentCollectionEnabledProvider.overrideWithValue(false),
      dashboardClockProvider.overrideWith((ref) => Stream.value(_now)),
      businessNowProvider.overrideWithValue(_now),
      businessTodayProvider.overrideWithValue(DateTime(2026, 9, 16)),
      appointmentsProvider.overrideWith((ref) async => const []),
      clientsProvider.overrideWith((ref) async => const []),
      allTasksProvider.overrideWith((ref) async => const []),
      allNotesProvider.overrideWith((ref) async => const []),
      dashboardAttentionProvider.overrideWith((ref) async => const []),
      unreadNotificationsProvider.overrideWith((ref) async => 0),
      setupChecklistDismissedProvider.overrideWith((ref) async => true),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _showScreen(
  WidgetTester tester,
  ProviderContainer container, {
  bool dashboard = false,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        key: ValueKey(dashboard),
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: dashboard
            ? DashboardScreen(onNavigate: (_) {}, onOpenMoneyFollowUps: () {})
            : FinanceScreen(referenceDate: _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Let a newly focused text field finish bringing its caret into view before
  // scrolling a different control into view, as a real user's next gesture does.
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _expectTarget(
  WidgetTester tester, {
  required double amount,
  required double target,
}) async {
  final finder = find.byType(WorkloopIncomeTargetIndicator);
  await _reveal(tester, finder);
  final indicator = tester.widget<WorkloopIncomeTargetIndicator>(finder);
  expect(indicator.amount, closeTo(amount, 0.000001));
  expect(indicator.target, target);
  expect(tester.takeException(), isNull);
}

Future<void> _openEditor(WidgetTester tester) async {
  final header = find.widgetWithText(WorkloopSectionHeader, 'Monthly target');
  await _reveal(tester, header);
  await _tap(tester, find.descendant(of: header, matching: find.text('Edit')));
  expect(find.text('Monthly money target'), findsOneWidget);
}

Finder get _save => find.widgetWithText(SlateButton, 'Save Target');

void main() {
  testWidgets('Today and Money use the same actual calendar-month receipts', (
    tester,
  ) async {
    final container = _container(settings: _Settings());
    await _showScreen(tester, container, dashboard: true);
    await _expectTarget(tester, amount: 450, target: 1000);
    expect(find.text('£450 of £1000 this month'), findsOneWidget);

    await _showScreen(tester, container);
    await _expectTarget(tester, amount: 450, target: 1000);
    expect(find.text('Monthly target'), findsOneWidget);
    expect(find.text('Weekly target'), findsNothing);
    expect(find.text('45%'), findsOneWidget);
    final summary = await container.read(financeSummaryProvider.future);
    expect(summary.thisMonthPaid, 450);
    expect(summary.monthlyTarget, 1000);
  });

  testWidgets(
    'Week, Month and Custom alter history but retain the monthly goal',
    (tester) async {
      final container = _container(settings: _Settings());
      await _showScreen(tester, container);
      expect(_receivedTotal('£150'), findsOneWidget);
      await _expectTarget(tester, amount: 450, target: 1000);

      await _tap(tester, find.text('Month'));
      expect(_receivedTotal('£450'), findsOneWidget);
      await _expectTarget(tester, amount: 450, target: 1000);

      await _tap(tester, find.text('Custom'));
      await _tap(tester, find.text('Apply Period'));
      // The default custom range also includes the previous month's £900.
      expect(_receivedTotal('£1350'), findsOneWidget);
      await _expectTarget(tester, amount: 450, target: 1000);
      expect(find.text('Monthly target'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);

      await _tap(tester, find.text('Week'));
      expect(_receivedTotal('£150'), findsOneWidget);
      await _expectTarget(tester, amount: 450, target: 1000);
    },
  );

  testWidgets(
    'monthly-only editor saves the exact amount and refreshes Today',
    (tester) async {
      final settings = _Settings();
      final container = _container(settings: settings);
      await _showScreen(tester, container);
      await _openEditor(tester);
      expect(_targetField, findsOneWidget);
      expect(find.text('Weekly'), findsNothing);
      expect(find.text('Monthly'), findsNothing);
      await tester.enterText(_targetField, '2750.50');
      await _tap(tester, _save);
      expect(settings.writes, hasLength(1));
      expect(settings.writes.single.workspace, 'workspace-one');
      expect(settings.writes.single.values, {'revenue_target': 2750.50});
      expect(find.text('Monthly money target'), findsNothing);
      await _expectTarget(tester, amount: 450, target: 2750.50);

      await _showScreen(tester, container, dashboard: true);
      await _expectTarget(tester, amount: 450, target: 2750.50);
    },
  );

  testWidgets(
    'fractional receipts reach the same penny-exact goal on both screens',
    (tester) async {
      final container = _container(
        settings: _Settings(target: 99.95),
        payments: List.generate(
          5,
          (index) => _payment(
            'Receipt $index',
            total: 19.99,
            received: DateTime(2026, 9, index + 1),
          ),
        ),
      );
      for (final dashboard in [false, true]) {
        await _showScreen(tester, container, dashboard: dashboard);
        await _expectTarget(tester, amount: 99.95, target: 99.95);
        final arc = tester.widget<WorkloopStudioProgressArc>(
          find.descendant(
            of: find.byType(WorkloopIncomeTargetIndicator),
            matching: find.byType(WorkloopStudioProgressArc),
          ),
        );
        expect(arc.progress, 1);
        expect(arc.color, WorkloopThemeTokens.light.success);
        expect(find.text('100%'), findsOneWidget);
        if (!dashboard) expect(find.text('Target reached'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'target save failure preserves input and allows one deliberate retry',
    (tester) async {
      final settings = _Settings()..failNextSave = true;
      final container = _container(settings: settings);
      await _showScreen(tester, container);
      await _openEditor(tester);
      await tester.enterText(_targetField, '2250');
      await _tap(tester, _save);
      expect(find.text('The target could not be updated.'), findsOneWidget);
      expect(find.text('Monthly money target'), findsOneWidget);
      expect(tester.widget<TextField>(_targetField).controller!.text, '2250');
      expect(settings.target, 1000);
      await _tap(tester, _save);
      expect(settings.writes, hasLength(2));
      await _expectTarget(tester, amount: 450, target: 2250);
    },
  );

  testWidgets('target save blocks duplicate taps and editing while waiting', (
    tester,
  ) async {
    final settings = _Settings()..pendingSave = Completer<void>();
    final container = _container(settings: settings);
    await _showScreen(tester, container);
    await _openEditor(tester);
    await tester.enterText(_targetField, '1750');
    await tester.tap(_save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.writes, hasLength(1));
    expect(tester.widget<TextField>(_targetField).enabled, isFalse);
    final busyButton = find.widgetWithText(SlateButton, 'Saving...');
    expect(tester.widget<SlateButton>(busyButton).onPressed, isNull);
    await tester.tap(busyButton);
    await tester.pump();
    expect(settings.writes, hasLength(1));
    settings.pendingSave!.complete();
    await tester.pumpAndSettle();
    await _expectTarget(tester, amount: 450, target: 1750);
  });

  testWidgets('invalid editor input does not save and zero removes the goal', (
    tester,
  ) async {
    final settings = _Settings();
    final container = _container(settings: settings);
    await _showScreen(tester, container);
    await _openEditor(tester);
    for (final value in ['', '-1', 'NaN', 'Infinity']) {
      await tester.enterText(_targetField, value);
      await _tap(tester, _save);
      expect(
        find.text('Enter zero or a positive monthly amount.'),
        findsOneWidget,
      );
      expect(settings.writes, isEmpty);
    }
    await tester.enterText(_targetField, '0');
    await _tap(tester, _save);
    expect(settings.writes.single.values, {'revenue_target': 0.0});
    await _expectTarget(tester, amount: 450, target: 0);
    expect(find.text('Set target'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WorkloopIncomeTargetIndicator),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'monthly target remains editable on a small screen with keyboard and large text',
    (tester) async {
      final settings = _Settings();
      final container = _container(settings: settings);
      await _showScreen(
        tester,
        container,
        size: const Size(320, 568),
        scale: 2,
      );
      await _openEditor(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 230);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(_targetField, '1500');
      await _tap(tester, _save);
      expect(settings.writes.single.values, {'revenue_target': 1500.0});
      expect(find.text('Monthly money target'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    final tokens = dark ? WorkloopThemeTokens.dark : WorkloopThemeTokens.light;
    for (final scenario in [
      (amount: 0.0, percentage: 0, progress: 0.0, colour: tokens.error),
      (amount: 499.0, percentage: 49, progress: 0.499, colour: tokens.error),
      (amount: 500.0, percentage: 50, progress: 0.5, colour: tokens.warning),
      (amount: 999.0, percentage: 99, progress: 0.999, colour: tokens.warning),
      (amount: 1000.0, percentage: 100, progress: 1.0, colour: tokens.success),
      (amount: 1250.0, percentage: 125, progress: 1.0, colour: tokens.success),
    ]) {
      testWidgets(
        '${dark ? 'dark' : 'light'} target at ${scenario.amount} has honest percentage, colour and semantics',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: Scaffold(
                  body: WorkloopIncomeTargetIndicator(
                    amount: scenario.amount,
                    target: 1000,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final arc = tester.widget<WorkloopStudioProgressArc>(
              find.byType(WorkloopStudioProgressArc),
            );
            expect(arc.progress, closeTo(scenario.progress, 0.000001));
            expect(arc.color, scenario.colour);
            expect(find.text('${scenario.percentage}%'), findsOneWidget);
            expect(
              find.bySemanticsLabel(
                '${scenario.percentage} percent of monthly target. '
                '${scenario.amount >= 1000 ? 'Target reached.' : 'Target not yet reached.'}',
              ),
              findsOneWidget,
            );
            // The arc's generic percentage is hidden from screen readers, so
            // the goal is spoken once with its purpose and completion state.
            expect(
              find.bySemanticsLabel(RegExp('percent complete')),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  for (final scenario in [
    (
      name: 'no goal',
      amount: 400.0,
      target: 0.0,
      label: 'Monthly target not set',
    ),
    (
      name: 'negative goal',
      amount: 400.0,
      target: -1.0,
      label: 'Monthly target not set',
    ),
    (
      name: 'nonfinite goal',
      amount: 400.0,
      target: double.infinity,
      label: 'Monthly target not set',
    ),
    (
      name: 'NaN amount',
      amount: double.nan,
      target: 1000.0,
      label: 'Monthly target progress unavailable',
    ),
    (
      name: 'infinite amount',
      amount: double.infinity,
      target: 1000.0,
      label: 'Monthly target progress unavailable',
    ),
    (
      name: 'overflowing ratio',
      amount: 1e308,
      target: 0.01,
      label: 'Monthly target progress unavailable',
    ),
  ]) {
    testWidgets('${scenario.name} renders neutral, bounded progress safely', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: WorkloopIncomeTargetIndicator(
                amount: scenario.amount,
                target: scenario.target,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final arc = tester.widget<WorkloopStudioProgressArc>(
          find.byType(WorkloopStudioProgressArc),
        );
        expect(arc.progress, 0);
        expect(arc.color, WorkloopThemeTokens.light.divider);
        expect(find.text('—'), findsOneWidget);
        expect(find.bySemanticsLabel(scenario.label), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
