import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../money_timeline.dart';

enum _ExpenseAction { delete }

/// A flat expense record with a separate, labelled action menu.
class MoneyExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const MoneyExpenseRow({
    super.key,
    required this.expense,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final category = expense.category.trim().isEmpty
        ? 'Expense'
        : expense.category;
    final description =
        expense.notes?.replaceAll('[Slate demo]', '').trim() ?? '';
    final amount = moneyTimelineAmountLabel(-expense.amount);
    final date = slateShortDate(expense.expenseDate.toLocal());
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(15) > 20;
        Widget amountLabel() => Text(
          amount,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        );
        return Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.divider)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: '$category, Expense, $amount, $date',
                  hint: 'Edit expense',
                  onTap: onTap,
                  onLongPress: onDelete,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      onLongPress: onDelete,
                      child: WorkloopListRow(
                        flat: true,
                        showDivider: false,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onTap: onTap,
                        leading: const SizedBox(
                          width: 34,
                          height: 34,
                          child: WorkloopIllustration(
                            kind: WorkloopIllustrationKind.receipt,
                            size: 30,
                          ),
                        ),
                        title: Text(
                          category,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: stacked ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (description.isNotEmpty)
                              Text(
                                description,
                                maxLines: stacked ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tokens.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            Text(
                              'Expense · $date',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            if (stacked) ...[
                              const SizedBox(height: AppSpacing.xs),
                              amountLabel(),
                            ],
                          ],
                        ),
                        trailing: stacked
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  amountLabel(),
                                  const SizedBox(width: AppSpacing.sm),
                                  Icon(
                                    LucideIcons.chevronRight,
                                    color: tokens.textTertiary,
                                    size: 16,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<_ExpenseAction>(
                key: ValueKey('money-expense-menu-${expense.id}'),
                tooltip: 'More expense actions',
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(AppSpacing.minTouch),
                ),
                icon: Icon(
                  LucideIcons.ellipsisVertical,
                  color: tokens.textTertiary,
                  size: 18,
                ),
                onSelected: (action) {
                  if (action == _ExpenseAction.delete) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) onDelete();
                    });
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<_ExpenseAction>(
                    value: _ExpenseAction.delete,
                    child: Text('Delete expense'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
