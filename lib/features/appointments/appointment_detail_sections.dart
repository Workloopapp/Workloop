part of 'appointment_detail_screen.dart';

class _PickedAppointmentDetailTime {
  final int hour;
  final int minute;

  const _PickedAppointmentDetailTime({
    required this.hour,
    required this.minute,
  });
}

Future<_PickedAppointmentDetailTime?> _showAppointmentDetailTimePicker({
  required BuildContext context,
  required int initialHour,
  required int initialMinute,
}) {
  int tempHour = initialHour;
  int tempMinute = initialMinute;

  return showWorkloopBottomSheet<_PickedAppointmentDetailTime>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setModal) => SlateSheetFrame(
        child: SizedBox(
          height: 240,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.of(context).t1,
                      ),
                    ),
                    WorkloopTextButton(
                      label: 'Done',
                      onPressed: () => Navigator.pop(
                        context,
                        _PickedAppointmentDetailTime(
                          hour: tempHour,
                          minute: tempMinute,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        itemExtent: 48,
                        perspective: 0.003,
                        diameterRatio: 1.8,
                        physics: const FixedExtentScrollPhysics(),
                        controller: FixedExtentScrollController(
                          initialItem: tempHour,
                        ),
                        onSelectedItemChanged: (i) =>
                            setModal(() => tempHour = i),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 24,
                          builder: (context, i) {
                            final selected = i == tempHour;
                            return Center(
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: selected ? 24 : 18,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected
                                      ? AppColors.of(context).t1
                                      : AppColors.of(context).t3,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Text(
                      ':',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.of(context).t1,
                      ),
                    ),
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        itemExtent: 48,
                        perspective: 0.003,
                        diameterRatio: 1.8,
                        physics: const FixedExtentScrollPhysics(),
                        controller: FixedExtentScrollController(
                          initialItem: tempMinute ~/ 15,
                        ),
                        onSelectedItemChanged: (i) =>
                            setModal(() => tempMinute = i * 15),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 4,
                          builder: (context, i) {
                            final min = i * 15;
                            final selected = min == tempMinute;
                            return Center(
                              child: Text(
                                min.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: selected ? 24 : 18,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected
                                      ? AppColors.of(context).t1
                                      : AppColors.of(context).t3,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _repeatLabel(String rule) {
  if (rule.contains('FREQ=MONTHLY')) return 'Repeats monthly';
  if (rule.contains('INTERVAL=2')) return 'Repeats fortnightly';
  if (rule.contains('INTERVAL=3')) return 'Repeats every 3 weeks';
  if (rule.contains('INTERVAL=4')) return 'Repeats every 4 weeks';
  if (rule.contains('FREQ=WEEKLY')) return 'Repeats weekly';
  return 'Repeating booking';
}

class _BookingTasksCard extends StatelessWidget {
  final AsyncValue<List<SlateTask>> tasks;
  final VoidCallback onAddTask;
  final VoidCallback onRetry;
  final ValueChanged<SlateTask> onToggle;

  const _BookingTasksCard({
    required this.tasks,
    required this.onAddTask,
    required this.onRetry,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.listChecks,
                color: AppColors.of(context).t3,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Booking tasks',
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddTask,
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          tasks.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (_, _) => SlateErrorState(
              message: 'Could not load booking tasks.',
              onRetry: onRetry,
            ),
            data: (items) {
              if (items.isEmpty) {
                return Text(
                  'Add prep, follow-up, or payment tasks for this booking.',
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 13,
                  ),
                );
              }
              return Column(
                children: items.map((task) {
                  final done = task.status == 'done';
                  return Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: () => onToggle(task),
                      leading: Icon(
                        done ? LucideIcons.checkCircle2 : LucideIcons.circle,
                        color: done
                            ? AppColors.of(context).success
                            : AppColors.of(context).t3,
                        size: 19,
                      ),
                      title: Text(
                        task.title,
                        style: TextStyle(
                          color: done
                              ? AppColors.of(context).t3
                              : AppColors.of(context).t1,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BookingPaymentCard extends StatelessWidget {
  final AsyncValue<List<Payment>> payments;
  final double price;
  final VoidCallback onRecordPayment;
  final ValueChanged<Payment> onMarkPaid;
  final ValueChanged<Payment> onOpenInvoice;

  const _BookingPaymentCard({
    required this.payments,
    required this.price,
    required this.onRecordPayment,
    required this.onMarkPaid,
    required this.onOpenInvoice,
  });

  @override
  Widget build(BuildContext context) {
    return payments.when(
      loading: () => const SlateLoadingBlock(height: 96, radius: 16),
      error: (_, _) =>
          const SlateErrorState(message: 'Could not load booking payment'),
      data: (rows) {
        final active = rows
            .where(
              (payment) =>
                  payment.status != 'cancelled' && payment.status != 'declined',
            )
            .toList();

        final unpaid = active
            .where((payment) => payment.outstandingAmount > 0)
            .toList();
        final primary = unpaid.isNotEmpty ? unpaid.first : active.firstOrNull;
        final statusLabel =
            primary != null &&
                primary.collectedAmount > 0 &&
                primary.outstandingAmount > 0
            ? 'Part paid'
            : primary?.status == 'paid'
            ? 'Paid'
            : unpaid.isNotEmpty
            ? 'Unpaid'
            : 'No payment linked';
        final amount = primary?.total ?? price;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.of(context).bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).t1.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.banknote,
                      size: 17,
                      color: AppColors.of(context).t2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.of(context).t3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$statusLabel · ${formatPounds(amount)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: primary?.status == 'paid'
                                ? AppColors.of(context).success
                                : unpaid.isNotEmpty
                                ? AppColors.of(context).warning
                                : AppColors.of(context).t1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (primary?.sourceDocumentId != null) ...[
                const SizedBox(height: AppSpacing.sm),
                if (primary!.hasDeposit)
                  Text(
                    primary.depositReceived
                        ? '${formatPounds(primary.depositAmount)} deposit received'
                        : '${formatPounds(primary.depositOutstandingAmount)} deposit due'
                              '${primary.depositDueDate == null ? '' : ' · ${slateShortDate(primary.depositDueDate!)}'}',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      fontSize: 13,
                    ),
                  ),
                if (primary.outstandingAmount > 0)
                  Text(
                    '${formatPounds(primary.outstandingAmount)} left on invoice',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                SlateButton(
                  label: 'Open invoice',
                  icon: LucideIcons.fileText,
                  secondary: true,
                  onPressed: () => onOpenInvoice(primary),
                ),
              ] else if (unpaid.isNotEmpty) ...[
                const SizedBox(height: 14),
                SlateButton(
                  label: 'Mark Payment Received',
                  icon: LucideIcons.checkCircle,
                  onPressed: () => onMarkPaid(unpaid.first),
                ),
              ] else if (active.isEmpty) ...[
                const SizedBox(height: 14),
                SlateButton(
                  label: 'Record Payment',
                  icon: LucideIcons.plus,
                  secondary: true,
                  onPressed: onRecordPayment,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BookingLocationOption {
  final String value;
  final String label;

  const _BookingLocationOption({required this.value, required this.label});
}
