import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/add_payment_screen.dart';
import 'package:workloop/features/finance/expense_editor_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  testWidgets(
    'Money uses one create action and offers income or expense flows',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final summary = FinanceSummary.from(
        payments: const [],
        expenses: const [],
        monthlyTarget: 5000,
        now: DateTime(2026, 7, 26),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentCollectionEnabledProvider.overrideWithValue(false),
            invoicesProvider.overrideWith((ref) async => const []),
            expensesProvider.overrideWith((ref) async => const []),
            financeSummaryProvider.overrideWith((ref) async => summary),
            workspaceSettingsProvider.overrideWith(
              (ref) async => const {
                'workspace_id': 'workspace-1',
                'revenue_target': 5000,
              },
            ),
            clientsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const FinanceScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final addMoneyAction = find.byWidgetPredicate(
        (widget) =>
            widget is WorkloopTopAction && widget.semanticLabel == 'Add money',
      );

      expect(addMoneyAction, findsOneWidget);
      expect(find.text('Card & contactless payments'), findsOneWidget);
      expect(find.byIcon(LucideIcons.minus), findsNothing);
      final addRect = tester.getRect(addMoneyAction);
      expect(addRect.height, greaterThanOrEqualTo(AppSpacing.minTouch));
      expect(addRect.width, greaterThan(AppSpacing.minTouch));
      expect(addRect.right, lessThanOrEqualTo(390 - AppSpacing.pageX));
      expect(addRect.right, greaterThan(320));
      expect(addRect.top, greaterThanOrEqualTo(0));

      await tester.tap(addMoneyAction);
      await tester.pumpAndSettle();

      expect(find.text('Add to Money'), findsOneWidget);
      expect(find.text('Record income'), findsOneWidget);
      expect(find.text('Add expense'), findsOneWidget);

      await tester.tap(find.text('Record income'));
      await tester.pumpAndSettle();
      expect(find.byType(AddPaymentScreen), findsOneWidget);

      final backToMoney = find.byWidgetPredicate(
        (widget) =>
            widget is WorkloopIconButton &&
            widget.semanticLabel == 'Back to Money',
      );
      await tester.tap(backToMoney);
      await tester.pumpAndSettle();
      await tester.tap(addMoneyAction);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseEditorScreen), findsOneWidget);
    },
  );
}
