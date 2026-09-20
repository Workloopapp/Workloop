import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/tax_estimate.dart';
import 'package:workloop/features/finance/tax_estimate_screen.dart';
import 'package:workloop/features/finance/widgets/money_summary_widgets.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

final _today = DateTime(2026, 9, 16, 12);
Payment _payment(String id, {double paid = 0, String status = 'sent'}) =>
    Payment(
      id: id,
      workspaceId: 'workspace',
      number: 'INV-$id',
      status: status,
      issueDate: DateTime(2026, 9, 10),
      dueDate: DateTime(2026, 9, 15),
      incomeRecordedAt: _today,
      total: 100,
      amountPaid: paid,
      depositAmount: 30,
    );

Future<void> _show(
  WidgetTester tester, {
  List<Payment> payments = const [],
  Future<List<Payment>> Function()? loadPayments,
  Future<List<Expense>> Function()? loadExpenses,
  bool tax = false,
  double scale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = scale > 1
      ? const Size(320, 700)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceIdProvider.overrideWith((_) async => 'workspace'),
        workspaceSettingsProvider.overrideWith(
          (_) async => {
            'workspace_id': 'workspace',
            'timezone': 'Europe/London',
            'revenue_target': 1000,
          },
        ),
        businessClockProvider.overrideWith((_) => Stream.value(_today)),
        invoicesProvider.overrideWith(
          (_) => loadPayments?.call() ?? Future.value(payments),
        ),
        expensesProvider.overrideWith(
          (_) => loadExpenses?.call() ?? Future.value([]),
        ),
        paymentCollectionEnabledProvider.overrideWithValue(false),
        mileageEntriesProvider.overrideWith((_) async => []),
        savedTaxEstimateProvider.overrideWith(
          (_, workspace) async => const TaxEstimateInput(
            turnoverMinor: 5000000,
            nonVehicleExpensesMinor: 1000000,
            eligible: false,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const ValueKey('money-qa'),
            child: WorkloopAppCanvas(child: child!),
          ),
        ),
        home: tax
            ? const TaxEstimateScreen()
            : FinanceScreen(referenceDate: _today),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_MONEY_PRIORITY')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('money-qa')),
  );
  await tester.runAsync(() async {
    final shot = await boundary.toImage();
    final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/tmp/workloop-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    shot.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'packages/lucide_flutter/LucideIcons':
          'packages/lucide_flutter/assets/lucide.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'outstanding money leads to owed before planning at ${scale}x',
      (tester) async {
        await _show(
          tester,
          scale: scale,
          payments: [
            _payment('open', paid: 30),
            _payment('void', status: 'cancelled'),
          ],
        );
        expect(find.text('£70 waiting to be paid'), findsOneWidget);
        expect(find.text('1 payment · 1 overdue · View owed'), findsOneWidget);
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('money-payment-attention')))
              .dy,
          lessThan(tester.getTopLeft(find.text('Money received')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Payments')).dy,
          lessThan(tester.getTopLeft(find.text('Monthly target')).dy),
        );
        await _capture(
          tester,
          'money-priority-${scale == 1 ? 'normal' : 'large'}',
        );
        expect(find.byKey(const ValueKey('payments-search')), findsNothing);
        expect(
          find.byKey(const ValueKey('money-net-profit-chart')),
          findsNothing,
        );
        final trend = find.text('Profit trend');
        await tester.ensureVisible(trend);
        await tester.pumpAndSettle();
        await tester.tap(trend);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('money-net-profit-chart')),
          findsOneWidget,
        );
        await tester.tap(trend);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('money-net-profit-chart')),
          findsNothing,
        );
        final history = find.byKey(const ValueKey('money-history-toggle'));
        await tester.ensureVisible(history);
        await tester.pumpAndSettle();
        await tester.tap(history);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('payments-search')), findsOneWidget);
        await tester.tap(history);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('payments-search')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('money-payment-attention')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('money-payment-attention')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<WorkloopNavigationControl<MoneySection>>(
                find.byType(WorkloopNavigationControl<MoneySection>),
              )
              .selected,
          MoneySection.owed,
        );
        expect(find.text('Payments owed'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tax labels stay outside focused outlines at ${scale}x', (
      tester,
    ) async {
      await _show(tester, tax: true, scale: scale);
      const label = 'Other allowable costs';
      final field = find.byKey(const ValueKey('tax-amount-$label'));
      await tester.scrollUntilVisible(
        field,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      final wrapper = find.ancestor(
        of: field,
        matching: find.byType(WorkloopFormField),
      );
      final heading = find.descendant(of: wrapper, matching: find.text(label));
      expect(
        tester.getBottomLeft(heading).dy,
        lessThan(tester.getTopLeft(field).dy),
      );
      expect(tester.widget<TextField>(field).decoration!.labelText, isNull);
      expect(tester.widget<TextField>(field).controller!.text, '10000.00');
      final selectedMethod = tester.renderObject<RenderParagraph>(
        find.text('Actual allowable costs'),
      );
      expect(selectedMethod.didExceedMaxLines, isFalse);
      await Scrollable.ensureVisible(tester.element(wrapper), alignment: 0.12);
      await tester.pumpAndSettle();
      await _capture(tester, 'tax-label-${scale == 1 ? 'normal' : 'large'}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large-text period choices scroll without clipping labels', (
    tester,
  ) async {
    await _show(tester, scale: 2);
    final periods = find.byType(WorkloopNavigationControl<FinancePeriod>);
    expect(
      tester.getSize(periods).width,
      greaterThan(320 - AppSpacing.pageX * 2),
    );
    final custom = find.descendant(of: periods, matching: find.text('Custom'));
    expect(
      tester.renderObject<RenderParagraph>(custom).didExceedMaxLines,
      isFalse,
    );
    await tester.scrollUntilVisible(
      periods,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.drag(periods, const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.ensureVisible(custom);
    await tester.tap(custom);
    await tester.pumpAndSettle();
    expect(find.text('Apply Period'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fresh Money has zero cash without an invented trend or attention',
    (tester) async {
      await _show(tester);
      expect(find.text('Money received'), findsOneWidget);
      expect(find.text('Money spent'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('money-payment-attention')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('money-net-profit-chart')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('money-history-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('payments-search')), findsNothing);
      await _capture(tester, 'money-priority-empty');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable expenses preserve income and require retry before net totals',
    (tester) async {
      var reads = 0;
      await _show(
        tester,
        payments: [_payment('received', paid: 100, status: 'paid')],
        loadExpenses: () async {
          if (reads++ == 0) throw StateError('Offline');
          return [];
        },
      );
      expect(
        find.text('Spending and net profit are unavailable.'),
        findsOneWidget,
      );
      expect(find.text('Money received'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('money-net-profit-total')),
        findsNothing,
      );
      await tester.tap(find.text('Retry expenses'));
      await tester.pumpAndSettle();
      expect(find.text('Money spent'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('money-net-profit-total')))
            .data,
        '£100',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading and failed income do not present zero cash as fact', (
    tester,
  ) async {
    final pending = Completer<List<Payment>>();
    await _show(tester, loadPayments: () => pending.future, settle: false);
    expect(find.text('Money received'), findsNothing);
    pending.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load income'), findsOneWidget);
    expect(find.text('Money received'), findsNothing);
    expect(
      find.byType(WorkloopNavigationControl<MoneySection>),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
