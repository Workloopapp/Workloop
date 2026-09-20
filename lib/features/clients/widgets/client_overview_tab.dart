import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../appointments/appointment_detail_screen.dart';
import '../providers/client_detail_providers.dart';

class ClientOverviewTab extends ConsumerWidget {
  final String clientId;
  final Map<String, dynamic> client;
  final VoidCallback onEdit;
  final VoidCallback onOpenBookings;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenTasks;
  final VoidCallback? onOpenFiles;
  final ValueChanged<String> onOpenAddress;

  const ClientOverviewTab({
    super.key,
    required this.clientId,
    required this.client,
    required this.onEdit,
    required this.onOpenBookings,
    required this.onOpenPayments,
    required this.onOpenTasks,
    this.onOpenFiles,
    required this.onOpenAddress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(clientAppointmentsProvider(clientId));
    final payments = ref.watch(clientPaymentsProvider(clientId));
    final tasks = ref.watch(clientTasksProvider(clientId));
    final activityUnavailable =
        appointments.hasError || payments.hasError || tasks.hasError;
    final activityLoading =
        (!appointments.hasValue && appointments.isLoading) ||
        (!payments.hasValue && payments.isLoading) ||
        (!tasks.hasValue && tasks.isLoading);
    final appointmentRows = appointments.value ?? const [];
    final paymentRows = payments.value ?? const <Payment>[];
    final taskRows = tasks.value ?? const <SlateTask>[];

    Future<void> retryActivity() async {
      await Future.wait([
        refreshClientAppointments(ref, clientId),
        refreshClientPayments(ref, clientId),
        refreshClientTasks(ref, clientId),
      ]);
    }

    return RefreshIndicator(
      color: AppColors.of(context).accentPrimary,
      onRefresh: retryActivity,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageX,
          AppSpacing.xs,
          AppSpacing.pageX,
          AppSpacing.xxl,
        ),
        children: [
          if (activityUnavailable)
            SlateErrorState(
              message:
                  'Some client activity could not be loaded. Try again before relying on this overview.',
              onRetry: retryActivity,
            )
          else if (activityLoading)
            const SlateLoadingBlock(height: 220)
          else ...[
            _NextBookingSection(
              appointments: appointmentRows,
              onOpenBookings: onOpenBookings,
            ),
            const WorkloopDivider(margin: EdgeInsets.symmetric(vertical: 22)),
            _RelationshipSnapshot(
              appointments: appointmentRows,
              payments: paymentRows,
              tasks: taskRows,
              loading:
                  appointments.isLoading ||
                  payments.isLoading ||
                  tasks.isLoading,
            ),
            _WorthALook(
              payments: paymentRows,
              tasks: taskRows,
              onOpenPayments: onOpenPayments,
              onOpenTasks: onOpenTasks,
            ),
          ],
          const WorkloopDivider(margin: EdgeInsets.symmetric(vertical: 22)),
          _NotesSection(client: client, onEdit: onEdit),
          if (onOpenFiles != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _QuietRow(
              icon: LucideIcons.paperclip,
              title: 'Photos & files',
              subtitle: 'Client photos and documents',
              onTap: onOpenFiles!,
            ),
          ],
          const WorkloopDivider(margin: EdgeInsets.symmetric(vertical: 22)),
          _DetailsSection(
            client: client,
            onEdit: onEdit,
            onOpenAddress: onOpenAddress,
          ),
          if (!activityUnavailable && !activityLoading) ...[
            const WorkloopDivider(margin: EdgeInsets.symmetric(vertical: 22)),
            _RecentActivity(
              appointments: appointmentRows,
              payments: paymentRows,
              tasks: taskRows,
              loading:
                  appointments.isLoading ||
                  payments.isLoading ||
                  tasks.isLoading,
              onOpenPayments: onOpenPayments,
              onOpenTasks: onOpenTasks,
            ),
          ],
        ],
      ),
    );
  }
}

class _NextBookingSection extends StatelessWidget {
  final List<Map<String, dynamic>> appointments;
  final VoidCallback onOpenBookings;

  const _NextBookingSection({
    required this.appointments,
    required this.onOpenBookings,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming =
        appointments.where((row) {
          final date = _appointmentDate(row);
          final status = row['status'] as String? ?? 'scheduled';
          return date != null && date.isAfter(now) && status == 'scheduled';
        }).toList()..sort(
          (a, b) => _appointmentDate(a)!.compareTo(_appointmentDate(b)!),
        );
    final next = upcoming.isEmpty ? null : upcoming.first;
    final laterCount = (upcoming.length - 1).clamp(0, upcoming.length);

    return WorkloopPaperPanel(
      title: 'Next booking',
      padding: EdgeInsets.zero,
      trailing: TextButton(
        onPressed: onOpenBookings,
        child: const Text('View bookings'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (next == null)
            _QuietRow(
              flat: true,
              icon: LucideIcons.calendarPlus,
              title: 'Nothing booked yet',
              subtitle: 'Add a booking when a time is agreed.',
              onTap: onOpenBookings,
            )
          else
            _BookingPanel(
              appointment: next,
              laterCount: laterCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppointmentDetailScreen(appointment: next),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _BookingPanel extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final int laterCount;
  final VoidCallback onTap;

  const _BookingPanel({
    required this.appointment,
    required this.laterCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = _appointmentDate(appointment)!;
    final service = _appointmentTitle(appointment);
    final address = appointment['location'] as String? ?? '';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.of(context).modBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.calendarClock,
                  color: AppColors.of(context).modCalendar,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).t1,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      [
                        _formatLongDate(date),
                        _formatTime(date),
                        if (address.isNotEmpty) address,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).t3,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (laterCount > 0) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '$laterCount more ${laterCount == 1 ? 'booking' : 'bookings'} scheduled',
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: AppColors.of(context).t3,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationshipSnapshot extends StatelessWidget {
  final List<Map<String, dynamic>> appointments;
  final List<Payment> payments;
  final List<SlateTask> tasks;
  final bool loading;

  const _RelationshipSnapshot({
    required this.appointments,
    required this.payments,
    required this.tasks,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final completed = appointments
        .where((row) => row['status'] == 'completed')
        .length;
    final received = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.collectedAmount,
    );
    final openTasks = tasks.where((task) => task.status != 'done').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Relationship'),
        const SizedBox(height: AppSpacing.md),
        if (loading &&
            appointments.isEmpty &&
            payments.isEmpty &&
            tasks.isEmpty)
          const SlateLoadingBlock(height: 54, radius: AppRadius.md)
        else
          Row(
            children: [
              Expanded(
                child: _Metric(
                  value: '$completed',
                  label: 'Bookings completed',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Metric(
                  value: formatPounds(received),
                  label: 'Received',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Metric(value: '$openTasks', label: 'Open tasks'),
              ),
            ],
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _WorthALook extends StatelessWidget {
  final List<Payment> payments;
  final List<SlateTask> tasks;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenTasks;

  const _WorthALook({
    required this.payments,
    required this.tasks,
    required this.onOpenPayments,
    required this.onOpenTasks,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.outstandingAmount,
    );
    final openTasks = tasks.where((task) => task.status != 'done').toList();
    if (remaining <= 0 && openTasks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Worth a look'),
          const SizedBox(height: AppSpacing.xs),
          if (remaining > 0)
            _QuietRow(
              icon: LucideIcons.banknote,
              title: '${formatPounds(remaining)} remaining',
              subtitle: 'Across this client’s recorded payments.',
              onTap: onOpenPayments,
            ),
          if (remaining > 0 && openTasks.isNotEmpty)
            const WorkloopDivider(
              margin: EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            ),
          if (openTasks.isNotEmpty)
            _QuietRow(
              icon: LucideIcons.listChecks,
              title:
                  '${openTasks.length} open ${openTasks.length == 1 ? 'task' : 'tasks'}',
              subtitle: openTasks.first.title,
              onTap: onOpenTasks,
            ),
        ],
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onEdit;

  const _NotesSection({required this.client, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final notes = (client['notes'] as String? ?? '').trim();
    final important = (client['important_notes'] as String? ?? '').trim();
    return WorkloopPaperPanel(
      title: 'Client notes',
      tone: WorkloopPaperTone.warm,
      trailing: TextButton(onPressed: onEdit, child: const Text('Edit')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (important.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.bookmark,
                    color: AppColors.of(context).modClients,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      important,
                      style: TextStyle(
                        color: AppColors.of(context).t1,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            notes.isEmpty && important.isEmpty
                ? 'No client notes added yet.'
                : notes.isEmpty
                ? 'No additional notes.'
                : notes,
            style: TextStyle(
              color: notes.isEmpty
                  ? AppColors.of(context).t3
                  : AppColors.of(context).t2,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onEdit;
  final ValueChanged<String> onOpenAddress;

  const _DetailsSection({
    required this.client,
    required this.onEdit,
    required this.onOpenAddress,
  });

  @override
  Widget build(BuildContext context) {
    final address = (client['address'] as String? ?? '').trim();
    final source = (client['source'] as String? ?? '').trim();
    final preferred = client['preferred_contact_method'] as String? ?? 'phone';
    final birthday = DateTime.tryParse(client['birthday']?.toString() ?? '');
    final tags = ((client['tags'] as List?) ?? const [])
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final rows =
        <({IconData icon, String label, String value, VoidCallback? onTap})>[
          (
            icon: LucideIcons.messageCircle,
            label: 'Preferred contact',
            value: _contactLabel(preferred),
            onTap: null,
          ),
          if (address.isNotEmpty)
            (
              icon: LucideIcons.mapPin,
              label: 'Booking address',
              value: address,
              onTap: () => onOpenAddress(address),
            ),
          if (source.isNotEmpty)
            (
              icon: LucideIcons.radio,
              label: 'Source',
              value: source,
              onTap: null,
            ),
          if (birthday != null)
            (
              icon: LucideIcons.cake,
              label: 'Birthday',
              value: '${birthday.day}/${birthday.month}/${birthday.year}',
              onTap: null,
            ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Details', action: 'Edit', onAction: onEdit),
        const SizedBox(height: AppSpacing.xs),
        ...rows.map(
          (row) => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: row.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(row.icon, color: AppColors.of(context).t3, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.label,
                            style: TextStyle(
                              color: AppColors.of(context).t3,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.value,
                            style: TextStyle(
                              color: AppColors.of(context).t2,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (row.onTap != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Icon(
                          LucideIcons.navigation,
                          color: AppColors.of(context).accentPrimary,
                          size: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).t1.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: AppColors.of(context).t2,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _RecentActivity extends StatelessWidget {
  final List<Map<String, dynamic>> appointments;
  final List<Payment> payments;
  final List<SlateTask> tasks;
  final bool loading;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenTasks;

  const _RecentActivity({
    required this.appointments,
    required this.payments,
    required this.tasks,
    required this.loading,
    required this.onOpenPayments,
    required this.onOpenTasks,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = <_ActivityItem>[
      ...appointments
          .where((row) {
            final date = _appointmentDate(row);
            return date != null &&
                (date.isBefore(now) || row['status'] == 'completed');
          })
          .map(_ActivityItem.fromAppointment),
      ...payments.map(_ActivityItem.fromPayment),
      ...tasks.map(_ActivityItem.fromTask),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final visible = items.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recent activity'),
        const SizedBox(height: AppSpacing.xs),
        if (loading && visible.isEmpty)
          const SlateLoadingBlock(height: 72, radius: AppRadius.md)
        else if (visible.isEmpty)
          Text(
            'Bookings, payments, and tasks will appear here as the relationship builds.',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 13,
              height: 1.4,
            ),
          )
        else
          ...visible.map((item) {
            final onTap = switch (item.type) {
              _ActivityType.appointment => () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AppointmentDetailScreen(appointment: item.appointment!),
                  ),
                );
              },
              _ActivityType.payment => onOpenPayments,
              _ActivityType.task => onOpenTasks,
            };
            return _QuietRow(
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
              onTap: onTap,
            );
          }),
      ],
    );
  }
}

enum _ActivityType { appointment, payment, task }

class _ActivityItem {
  final _ActivityType type;
  final DateTime date;
  final IconData icon;
  final String title;
  final String subtitle;
  final Map<String, dynamic>? appointment;

  const _ActivityItem({
    required this.type,
    required this.date,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.appointment,
  });

  factory _ActivityItem.fromAppointment(Map<String, dynamic> row) {
    final date = _appointmentDate(row)!;
    return _ActivityItem(
      type: _ActivityType.appointment,
      date: date,
      icon: LucideIcons.calendar,
      title: _appointmentTitle(row),
      subtitle:
          '${_formatLongDate(date)} · ${(row['status'] as String? ?? 'scheduled').replaceAll('_', ' ')}',
      appointment: row,
    );
  }

  factory _ActivityItem.fromPayment(Payment payment) {
    return _ActivityItem(
      type: _ActivityType.payment,
      date: payment.issueDate,
      icon: LucideIcons.banknote,
      title: payment.status == 'paid' ? 'Payment received' : 'Payment recorded',
      subtitle:
          '${formatPounds(payment.total)} · ${_formatLongDate(payment.issueDate)}',
    );
  }

  factory _ActivityItem.fromTask(SlateTask task) {
    final date = task.updatedAt ?? task.createdAt ?? task.dueDate;
    return _ActivityItem(
      type: _ActivityType.task,
      date: date ?? DateTime.fromMillisecondsSinceEpoch(0),
      icon: LucideIcons.listChecks,
      title: task.title,
      subtitle: task.status == 'done' ? 'Task completed' : 'Task open',
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const _SectionHeader({this.title = '', this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (action != null)
          WorkloopTextButton(label: action!, onPressed: onAction),
      ],
    );
  }
}

class _QuietRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool flat;

  const _QuietRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopListRow(
      flat: flat,
      showDivider: !flat,
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.of(context).modBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.of(context).t3, size: 17),
      ),
      title: Text(
        title,
        maxLines: flat ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: flat ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: AppColors.of(context).t3,
        size: 16,
      ),
    );
  }
}

DateTime? _appointmentDate(Map<String, dynamic> row) =>
    DateTime.tryParse(row['start_time'] as String? ?? '')?.toLocal();

String _appointmentTitle(Map<String, dynamic> row) {
  return row['services']?['name'] as String? ??
      row['title'] as String? ??
      'Booking';
}

String _formatTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _formatLongDate(DateTime date) {
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

String _contactLabel(String value) {
  return switch (value) {
    'sms' => 'Text message',
    'email' => 'Email',
    'whatsapp' => 'WhatsApp',
    _ => 'Phone',
  };
}
