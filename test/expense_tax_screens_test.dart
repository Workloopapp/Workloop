import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/tax_estimate.dart';
import 'package:workloop/features/finance/tax_estimate_screen.dart';
import 'package:workloop/features/finance/mileage_screen.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';

void main() {
  testWidgets('tax drafts reset when the active business changes', (
    tester,
  ) async {
    var activeWorkspace = 'first';
    final container = ProviderContainer(
      overrides: [
        workspaceSettingsProvider.overrideWith((ref) async => null),
        workspaceIdProvider.overrideWith((ref) async => activeWorkspace),
        savedTaxEstimateProvider.overrideWith(
          (ref, workspace) async => TaxEstimateInput(
            turnoverMinor: workspace == 'first' ? 11100 : 22200,
            nonVehicleExpensesMinor: 0,
            eligible: false,
          ),
        ),
        mileageEntriesProvider.overrideWith((ref) async => []),
        invoicesProvider.overrideWith((ref) async => []),
        expensesProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const TaxEstimateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final income = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.key == const ValueKey('tax-amount-Annual business income'),
    );
    await tester.scrollUntilVisible(
      income,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(income, '333.00');
    activeWorkspace = 'second';
    container.invalidate(workspaceIdProvider);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      income,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextField>(income).controller!.text, '222.00');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'tax estimate keeps annual amounts separate and requires review after reload',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceSettingsProvider.overrideWith((ref) async => null),
            workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
            savedTaxEstimateProvider.overrideWith(
              (ref, workspace) async => const TaxEstimateInput(
                turnoverMinor: 5000000,
                nonVehicleExpensesMinor: 1000000,
                eligible: true,
              ),
            ),
            mileageEntriesProvider.overrideWith((ref) async => []),
            invoicesProvider.overrideWith((ref) async => []),
            expensesProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const TaxEstimateScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Plan what to put aside'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Calculate and save estimate'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Calculate and save estimate'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Your annual estimate'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mileage empty state opens a usable journey form on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceSettingsProvider.overrideWith((ref) async => null),
            workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
            mileageEntriesProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const MileageScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log journey'));
      await tester.pumpAndSettle();
      expect(find.text('Business miles'), findsOneWidget);
      expect(find.text('Business purpose and route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
