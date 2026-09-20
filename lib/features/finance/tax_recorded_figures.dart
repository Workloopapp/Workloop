import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/business_clock_provider.dart';
import 'tax_estimate.dart';
import 'widgets/money_editor_widgets.dart';

class TaxRecordedFigures extends ConsumerWidget {
  final ValueChanged<int>? onUseIncome;
  const TaxRecordedFigures({super.key, this.onUseIncome});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(invoicesProvider);
    final expenses = ref.watch(expensesProvider);
    final incomeToday = ref.watch(businessTodayProvider);
    final today = ref.watch(workspaceTodayProvider);
    final receipts = (payments.value ?? [])
        .expand((p) => p.cashReceipts)
        .where(
          (receipt) =>
              receipt.amount != 0 &&
              !receipt.receivedAt.isBefore(SoleTraderTaxRules.cashStart) &&
              receipt.receivedAt.isBefore(SoleTraderTaxRules.cashEnd),
        );
    final collected = receipts
        .where((r) => !startOfDay(r.receivedAt).isAfter(incomeToday))
        .fold<int>(0, (sum, receipt) => sum + (receipt.amount * 100).round());
    bool inYear(DateTime date) =>
        !date.isBefore(SoleTraderTaxRules.start) &&
        date.isBefore(SoleTraderTaxRules.end);
    final yearExpenses = (expenses.value ?? []).where(
      (e) => inYear(e.expenseDate),
    );
    final spent = yearExpenses
        .where((e) => !DateUtils.dateOnly(e.expenseDate).isAfter(today))
        .fold<int>(0, (sum, e) => sum + (e.amount * 100).round());
    final hasFutureRecords =
        receipts.any((r) => startOfDay(r.receivedAt).isAfter(incomeToday)) ||
        yearExpenses.any(
          (e) => DateUtils.dateOnly(e.expenseDate).isAfter(today),
        );
    return MoneyFormSection(
      title: 'Recorded in Workloop · 2026/27',
      subtitle:
          'Reference figures to reconcile with your bank and receipts. These are not automatically treated as annual or taxable totals.',
      child: payments.isLoading || expenses.isLoading
          ? const LinearProgressIndicator()
          : payments.hasError || expenses.hasError
          ? TextButton(
              onPressed: () {
                ref.invalidate(invoicesProvider);
                ref.invalidate(expensesProvider);
              },
              child: const Text('Could not load records · retry'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collected payments so far: £${formatHundredths(collected)}',
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: onUseIncome == null || collected < 0
                      ? null
                      : () => onUseIncome!(collected),
                  child: const Text(
                    'Use collected income as a starting figure',
                  ),
                ),
                const Text(
                  'Then add expected income for the rest of the year and any income recorded elsewhere. Review costs separately; a receipt does not make a cost allowable.',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('Recorded expenses so far: £${formatHundredths(spent)}'),
                const SizedBox(height: AppSpacing.sm),
                if (hasFutureRecords) ...[
                  const Text(
                    'Future-dated payments or expenses are excluded. Check their recorded dates in Money.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const Text(
                  'Payment records use their recorded received date; reconcile partial payments, refunds and money received outside Workloop. Expense records may contain personal or non-allowable costs.',
                ),
              ],
            ),
    );
  }
}
