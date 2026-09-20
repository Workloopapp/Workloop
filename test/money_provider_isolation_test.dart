import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';

void main() {
  testWidgets('Money only blocks the section whose provider failed', (
    tester,
  ) async {
    var expenseLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoicesProvider.overrideWith((ref) async => const []),
          expensesProvider.overrideWith((ref) async {
            expenseLoads += 1;
            throw StateError('expenses offline');
          }),
          workspaceSettingsProvider.overrideWith(
            (ref) async => const {'revenue_target': 1200},
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const FinanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CASH SUMMARY'), findsOneWidget);
    expect(find.text('Money received'), findsOneWidget);
    expect(find.text('£0'), findsOneWidget);
    expect(
      find.text('Spending and net profit are unavailable.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('money-net-profit-total')), findsNothing);
    expect(find.text('No payments in this period'), findsNothing);
    expect(find.text('Could not load expenses'), findsNothing);

    await tester.tap(find.text('Spent'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load expenses'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(expenseLoads, 2);

    await tester.tap(find.text('Owed'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing waiting to be collected.'), findsOneWidget);
    expect(find.text('Could not load expenses'), findsNothing);
  });
}
