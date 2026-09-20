import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/widgets/money_editor_widgets.dart';
import 'package:workloop/features/finance/widgets/money_summary_widgets.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'))).load();
  });

  for (final scenario in [
    (width: 390.0, scale: 1.0),
    (width: 320.0, scale: 1.0),
    (width: 320.0, scale: 2.0),
  ]) {
    testWidgets(
      'Custom dates stay outside period tabs at ${scenario.width}px and ${scenario.scale}x',
      (tester) async {
        tester.view.physicalSize = Size(scenario.width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = FinancePeriod.week;
        var customRequests = 0;
        const dates = '1 May 2026 - 12 Sep 2026';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: RepaintBoundary(
                      key: const ValueKey('custom-period-preview'),
                      child: MoneyPeriodSwitcher(
                        selected: selected,
                        customLabel: dates,
                        onSelected: (value) {
                          if (value == FinancePeriod.custom) customRequests++;
                          setState(() => selected = value);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final tabs = find.byType(WorkloopNavigationControl<FinancePeriod>);
        final originalWidth = tester.getSize(tabs).width;
        final custom = find.descendant(of: tabs, matching: find.text('Custom'));
        await tester.ensureVisible(custom);
        await tester.tap(custom);
        await tester.pumpAndSettle();
        expect(tester.getSize(tabs).width, originalWidth);
        if (scenario.scale == 1) {
          expect(originalWidth, lessThanOrEqualTo(scenario.width - 36));
        }
        expect(
          find.descendant(of: tabs, matching: find.text(dates)),
          findsNothing,
        );
        expect(
          tester.getTopLeft(find.text(dates)).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(tabs).dy),
        );
        expect(
          tester.getRect(find.text(dates)).right,
          lessThanOrEqualTo(scenario.width - 18),
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(dates))
              .didExceedMaxLines,
          isFalse,
        );
        if (const bool.fromEnvironment('CAPTURE_CUSTOM_PERIOD')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('custom-period-preview')),
          );
          await tester.runAsync(() async {
            final shot = await boundary.toImage(pixelRatio: 2);
            final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '/tmp/workloop-custom-period-${scenario.width}-${scenario.scale}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            shot.dispose();
          });
        }
        await tester.tap(find.text('Change'));
        expect(customRequests, 2);
        final week = find.descendant(of: tabs, matching: find.text('Week'));
        await tester.ensureVisible(week);
        await tester.tap(week);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('money-custom-date-range')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Money navigation exposes four clear sections', (tester) async {
    MoneySection selected = MoneySection.made;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: WorkloopNavigationControl<MoneySection>(
              selected: selected,
              segments: const [
                WorkloopSegment(value: MoneySection.made, label: 'Overview'),
                WorkloopSegment(
                  value: MoneySection.documents,
                  label: 'Invoices',
                ),
                WorkloopSegment(value: MoneySection.spent, label: 'Spent'),
                WorkloopSegment(value: MoneySection.owed, label: 'Owed'),
              ],
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Spent'), findsOneWidget);
    expect(find.text('Owed'), findsOneWidget);

    await tester.tap(find.text('Owed'));
    await tester.pumpAndSettle();
    expect(selected, MoneySection.owed);
  });

  testWidgets('Money period selector uses the shared segmented interaction', (
    tester,
  ) async {
    FinancePeriod selected = FinancePeriod.week;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: MoneyPeriodSwitcher(
              selected: selected,
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(selected, FinancePeriod.month);
  });

  testWidgets('Money amount field uses one stable mobile input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MoneyAmountField(controller: controller)),
      ),
    );

    await tester.enterText(find.byType(TextField), '48.50');
    expect(controller.text, '48.50');
    expect(find.text('£ '), findsOneWidget);
  });
}
