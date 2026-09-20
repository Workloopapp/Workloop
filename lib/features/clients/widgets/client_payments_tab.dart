import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/providers/clients_provider.dart';
import '../../../shared/providers/dashboard_provider.dart';
import '../../../shared/providers/finance_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../finance/add_payment_screen.dart';
import '../../finance/documents/business_documents_screen.dart';
import '../../finance/documents/business_document_detail_screen.dart';
import '../providers/client_detail_providers.dart';

class ClientPaymentsTab extends ConsumerWidget {
  final String clientId;
  final String clientName;

  const ClientPaymentsTab({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(clientPaymentsProvider(clientId));
    return payments.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: AppColors.of(context).green),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SlateErrorState(
          message: 'Money activity could not be loaded.',
          onRetry: () => refreshClientPayments(ref, clientId),
        ),
      ),
      data: (items) {
        Future<void> recordPayment() async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddPaymentScreen(initialClientId: clientId),
            ),
          );
          if (!context.mounted) return;
          ref.invalidate(clientPaymentsProvider(clientId));
          ref.invalidate(invoicesProvider);
          ref.invalidate(dashboardRevenueProvider);
          ref.invalidate(clientCrmRecordsProvider);
        }

        if (items.isEmpty) {
          return Column(
            children: [
              _documentsEntry(context),
              Expanded(child: _EmptyPayments(onAction: recordPayment)),
            ],
          );
        }
        final received = items.fold<double>(
          0,
          (sum, payment) => sum + payment.collectedAmount,
        );
        final remaining = items.fold<double>(
          0,
          (sum, payment) => sum + payment.outstandingAmount,
        );
        return Column(
          children: [
            _documentsEntry(context),
            _PaymentsToolbar(
              received: received,
              remaining: remaining,
              onRecord: recordPayment,
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.of(context).green,
                onRefresh: () => refreshClientPayments(ref, clientId),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    0,
                    AppSpacing.pageX,
                    40,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox.shrink(),
                  itemBuilder: (context, index) {
                    final payment = items[index];
                    return _PaymentRow(
                      payment: payment,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => payment.sourceDocumentId == null
                                ? AddPaymentScreen(payment: payment)
                                : BusinessDocumentDetailScreen(
                                    documentId: payment.sourceDocumentId!,
                                  ),
                          ),
                        );
                        if (!context.mounted) return;
                        ref.invalidate(clientPaymentsProvider(clientId));
                        ref.invalidate(invoicesProvider);
                        ref.invalidate(dashboardRevenueProvider);
                        ref.invalidate(clientCrmRecordsProvider);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _documentsEntry(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
    child: WorkloopModuleRow(
      icon: LucideIcons.fileText,
      title: 'Quotes & invoices',
      subtitle: 'Agree work and request payment for $clientName',
      color: AppColors.of(context).modFinance,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDocumentsScreen(initialClientId: clientId),
        ),
      ),
    ),
  );
}

class _PaymentRow extends StatelessWidget {
  final Payment payment;
  final VoidCallback onTap;
  const _PaymentRow({required this.payment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final amount = payment.total;
    final remaining = payment.outstandingAmount;
    final cancelled = payment.status == 'cancelled' || payment.status == 'void';
    final paid = remaining <= 0;
    final partPaid = !paid && payment.collectedAmount > 0;
    final color = paid && !cancelled
        ? AppColors.of(context).success
        : AppColors.of(context).t3;
    final label = cancelled
        ? 'Cancelled'
        : paid
        ? 'Paid'
        : partPaid
        ? 'Part paid'
        : 'Unpaid';
    return WorkloopListRow(
      onTap: onTap,
      leading: Icon(LucideIcons.banknote, color: color, size: 18),
      title: Text(
        payment.notes ?? payment.number.ifEmpty('Payment'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${_formatDate(payment.issueDate)} · $label\n${formatPounds(amount)}${partPaid ? ' · ${formatPounds(remaining)} left' : ''}',
        style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: AppColors.of(context).t3,
        size: 16,
      ),
    );
  }
}

class _PaymentsToolbar extends StatelessWidget {
  final double received;
  final double remaining;
  final VoidCallback onRecord;

  const _PaymentsToolbar({
    required this.received,
    required this.remaining,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        AppSpacing.xs,
        AppSpacing.pageX,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: [
                Text(
                  '${formatPounds(received)} received',
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (remaining > 0)
                  Text(
                    '${formatPounds(remaining)} left',
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          WorkloopTextButton(label: 'Record', onPressed: onRecord),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _EmptyPayments extends StatelessWidget {
  final VoidCallback onAction;
  const _EmptyPayments({required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const WorkloopEmptyState(
            icon: LucideIcons.banknote,
            title: 'No payments yet.',
            subtitle:
                'Income and outstanding payments for this client will appear here.',
          ),
          const SizedBox(height: 16),
          WorkloopPrimaryButton(label: 'Record payment', onPressed: onAction),
        ],
      ),
    );
  }
}
