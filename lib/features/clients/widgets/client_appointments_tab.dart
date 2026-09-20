import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../appointments/appointment_detail_screen.dart';
import '../../appointments/add_appointment_screen.dart';
import '../providers/client_detail_providers.dart';

class ClientAppointmentsTab extends ConsumerWidget {
  final String clientId;
  const ClientAppointmentsTab({super.key, required this.clientId});

  String _formatDate(DateTime dt) {
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(clientAppointmentsProvider(clientId));

    return appointments.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: AppColors.of(context).green),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SlateErrorState(
          message: 'Bookings could not be loaded.',
          onRetry: () => refreshClientAppointments(ref, clientId),
        ),
      ),
      data: (appts) => appts.isEmpty
          ? _EmptyStateWithAction(
              icon: LucideIcons.calendar,
              title: 'No bookings yet.',
              message: 'Bookings for this client will appear here.',
              actionLabel: 'Add booking',
              onAction: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AddAppointmentScreen(initialClientId: clientId),
                  ),
                );
                if (!context.mounted) return;
                ref.invalidate(clientAppointmentsProvider(clientId));
              },
            )
          : Column(
              children: [
                _AppointmentsToolbar(
                  count: appts.length,
                  onAdd: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddAppointmentScreen(initialClientId: clientId),
                      ),
                    );
                    if (!context.mounted) return;
                    ref.invalidate(clientAppointmentsProvider(clientId));
                  },
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => refreshClientAppointments(ref, clientId),
                    color: AppColors.of(context).green,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageX,
                        0,
                        AppSpacing.pageX,
                        40,
                      ),
                      itemCount: appts.length,
                      separatorBuilder: (_, _) => const SizedBox.shrink(),
                      itemBuilder: (context, i) {
                        final appt = appts[i];
                        final dt = DateTime.tryParse(
                          appt['start_time'] as String? ?? '',
                        )?.toLocal();
                        final endDt = DateTime.tryParse(
                          appt['end_time'] as String? ?? '',
                        )?.toLocal();
                        final status = appt['status'] as String? ?? 'scheduled';
                        final statusColor = status == 'completed'
                            ? AppColors.of(context).success
                            : AppColors.of(context).t3;

                        return WorkloopListRow(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AppointmentDetailScreen(appointment: appt),
                              ),
                            );
                            if (!context.mounted) return;
                            ref.invalidate(
                              clientAppointmentsProvider(clientId),
                            );
                          },
                          leading: Icon(
                            LucideIcons.calendar,
                            color: statusColor,
                            size: 18,
                          ),
                          title: Text(
                            appt['services']?['name'] as String? ?? 'Booking',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.of(context).t1,
                            ),
                          ),
                          subtitle: Text(
                            dt != null
                                ? endDt != null
                                      ? '${_formatDate(dt)} · ${_fmtTime(dt)} - ${_fmtTime(endDt)}'
                                      : '${_formatDate(dt)} · ${_fmtTime(dt)}'
                                : 'No date set',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.of(context).t3,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (appt['price'] != null)
                                Text(
                                  formatPounds(appt['price'] as num),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.of(context).t2,
                                  ),
                                ),
                              const SizedBox(width: 10),
                              Text(
                                status.replaceAll('_', ' '),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                LucideIcons.chevronRight,
                                color: AppColors.of(context).t3,
                                size: 14,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AppointmentsToolbar extends StatelessWidget {
  final int count;
  final VoidCallback onAdd;

  const _AppointmentsToolbar({required this.count, required this.onAdd});

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
          Text(
            '$count ${count == 1 ? 'booking' : 'bookings'}',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          WorkloopTextButton(label: 'New booking', onPressed: onAdd),
        ],
      ),
    );
  }
}

// ── Empty state with action button ────────────────────────────────────────────
class _EmptyStateWithAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyStateWithAction({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkloopEmptyState(icon: icon, title: title, subtitle: message),
          const SizedBox(height: 16),
          WorkloopPrimaryButton(label: actionLabel, onPressed: onAction),
        ],
      ),
    );
  }
}
