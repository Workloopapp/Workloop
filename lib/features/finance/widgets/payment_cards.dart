import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/providers/finance_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../money_timeline.dart';

enum _PaymentCardAction { delete }

class PaymentCard extends StatelessWidget {
  final Payment payment;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showReceivedEntry;
  final double? receivedEntryAmount;
  final DateTime? receivedEntryDate;

  const PaymentCard({
    super.key,
    required this.payment,
    required this.onTap,
    required this.onDelete,
    this.showReceivedEntry = false,
    this.receivedEntryAmount,
    this.receivedEntryDate,
  });

  @override
  Widget build(BuildContext context) {
    final received = receivedEntryAmount ?? receivedAmountFor(payment);
    final receivedDate = receivedEntryDate ?? payment.receivedDate;
    final isRefund = received < 0;
    final isPartPaid = received > 0 && outstandingAmountFor(payment) > 0;
    final clientName = showReceivedEntry
        ? payment.clientName?.trim().isNotEmpty == true
              ? payment.clientName!.trim()
              : payment.number.trim().isNotEmpty
              ? payment.number
              : isRefund
              ? 'Refund'
              : 'Income'
        : payment.clientName ?? 'Unknown';
    final description = _cleanDemoText(payment.notes ?? '');
    final status = moneyStatusFor(payment);
    final isOverdue = status == MoneyStatus.overdue;
    final isPending = status == MoneyStatus.unpaid;
    final isPaid = status == MoneyStatus.paid;
    final statusColor = showReceivedEntry
        ? isRefund
              ? AppColors.of(context).error
              : isPartPaid
              ? AppColors.of(context).warning
              : AppColors.of(context).success
        : isPaid
        ? AppColors.of(context).success
        : isOverdue
        ? AppColors.of(context).t2
        : AppColors.of(context).t3;
    final statusLabel = showReceivedEntry
        ? isRefund
              ? 'Refund'
              : isPartPaid
              ? 'Part-paid'
              : 'Income'
        : isPaid
        ? 'Paid'
        : isOverdue
        ? 'Overdue'
        : isPending
        ? 'Pending'
        : payment.status;
    final displayedAmount = showReceivedEntry
        ? moneyTimelineAmountLabel(received)
        : formatPounds(isPaid ? received : outstandingAmountFor(payment));
    final date = showReceivedEntry
        ? '${isRefund ? 'Recorded' : 'Received'} ${slateShortDate(receivedDate.toLocal())}'
        : _dateSubtitle(payment);
    final showDate =
        (showReceivedEntry ? receivedDate : payment.issueDate)
            .millisecondsSinceEpoch >
        0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            MediaQuery.textScalerOf(context).scale(15) > 20 ||
            (showReceivedEntry && constraints.maxWidth < 330);
        Widget amountLabel() => Text(
          displayedAmount,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).t1,
          ),
        );
        Widget statusText() => Text(
          statusLabel,
          style: TextStyle(
            fontSize: showReceivedEntry ? 12 : 10,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
        );
        return Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.of(context).border),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  button: onTap != null,
                  label:
                      '$clientName payment, $displayedAmount, $statusLabel${showReceivedEntry && showDate ? ', $date' : ''}',
                  hint: onTap == null ? null : 'Open payment actions',
                  onTap: onTap,
                  child: ExcludeSemantics(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        excludeFromSemantics: true,
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const WorkloopIllustration(
                                kind: WorkloopIllustrationKind.receipt,
                                size: 34,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      clientName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.of(context).t1,
                                      ),
                                      maxLines: stacked ? 2 : 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (description.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        description,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.of(context).t3,
                                        ),
                                        maxLines: stacked ? 2 : 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    if (showDate) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        date,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.of(context).t3,
                                        ),
                                      ),
                                    ],
                                    if (stacked) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Wrap(
                                        spacing: AppSpacing.sm,
                                        runSpacing: AppSpacing.xxs,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [amountLabel(), statusText()],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!stacked) ...[
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    amountLabel(),
                                    const SizedBox(height: 3),
                                    statusText(),
                                  ],
                                ),
                              ],
                              if (onTap != null && !stacked) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  LucideIcons.chevronRight,
                                  color: AppColors.of(context).t3,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (onDelete != null)
                PopupMenuButton<_PaymentCardAction>(
                  tooltip: 'More payment actions',
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(AppSpacing.minTouch),
                  ),
                  icon: Icon(
                    LucideIcons.ellipsisVertical,
                    color: AppColors.of(context).t3,
                    size: 18,
                  ),
                  onSelected: (action) {
                    if (action == _PaymentCardAction.delete) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) onDelete?.call();
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<_PaymentCardAction>(
                      value: _PaymentCardAction.delete,
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: 17,
                            color: AppColors.of(context).error,
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Text('Delete income'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  String _dateSubtitle(Payment payment) {
    if (payment.status == 'paid') {
      return 'Received ${slateShortDate(displayReceivedDate(payment))}';
    }
    final dueDate = payment.dueDate;
    if (dueDate == null || dueDate.millisecondsSinceEpoch == 0) {
      return 'Created ${slateShortDate(payment.issueDate)}';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return 'Due ${slateShortDate(dueDate)} · ${diff.abs()}d late';
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    return 'Due ${slateShortDate(dueDate)} · ${diff}d';
  }

  String _cleanDemoText(String value) {
    return value.replaceAll('[Slate demo]', '').trim();
  }
}
