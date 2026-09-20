import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/client_follow_up_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_settings_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/booking_time.dart';
import '../../shared/utils/client_follow_up.dart';
import '../../shared/widgets/slate_ui.dart';

String tomorrowBookingTime(DateTime instant, String zone) {
  final local = bookingTimeInZone(instant, zone);
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

void _retryTomorrow(WidgetRef ref) {
  ref.invalidate(appointmentsProvider);
  ref.invalidate(workspaceSettingsProvider);
  ref.invalidate(tomorrowBriefProvider);
}

class TomorrowBriefRow extends ConsumerWidget {
  const TomorrowBriefRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brief = ref.watch(tomorrowBriefProvider);
    final workspaceId = ref.watch(workspaceIdProvider).value;
    final matchesWorkspace =
        brief.value?.workspaceId == null ||
        brief.value?.workspaceId == workspaceId;
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      key: const ValueKey('tomorrow-brief-row'),
      flat: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tokens.divider),
        ),
        child: Icon(LucideIcons.sunrise, size: 20, color: tokens.accentInk),
      ),
      title: Text(
        'Tomorrow',
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        !matchesWorkspace
            ? 'Checking your schedule…'
            : brief.when(
                skipLoadingOnReload: true,
                data: _summary,
                loading: () => 'Checking your schedule…',
                error: (_, _) => 'Could not check tomorrow. Tap to try again.',
              ),
        style: TextStyle(
          color: AppColors.of(context).t2,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: AppColors.of(context).t3,
      ),
      onTap: () {
        if (brief.hasError) {
          _retryTomorrow(ref);
          return;
        }
        if (!brief.hasValue || !matchesWorkspace) return;
        final userId = ref.read(authRepositoryProvider).currentUserId;
        final workspaceId = ref.read(workspaceIdProvider).value;
        if (userId == null || workspaceId == null) return;
        showWorkloopBottomSheet<void>(
          context: context,
          builder: (_) =>
              _TomorrowBookings(userId: userId, workspaceId: workspaceId),
        );
      },
    );
  }

  String _summary(TomorrowBrief brief) {
    if (brief.bookings.isEmpty) return 'No bookings scheduled.';
    final count = brief.bookings.length;
    final hours = brief.bookedMinutes ~/ 60;
    final minutes = brief.bookedMinutes % 60;
    final duration = hours > 0
        ? (minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m')
        : '${minutes}m';
    final allDurationsKnown = brief.bookings.every(
      (booking) =>
          booking.endTime != null &&
          booking.endTime!.isAfter(booking.startTime),
    );
    final booked = allDurationsKnown ? ' · $duration booked' : '';
    return '$count ${count == 1 ? 'booking' : 'bookings'}$booked · '
        'First ${tomorrowBookingTime(brief.bookings.first.startTime, brief.timezone)}';
  }
}

class _TomorrowBookings extends ConsumerWidget {
  final String userId;
  final String workspaceId;
  const _TomorrowBookings({required this.userId, required this.workspaceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sameWorkspace = ref.watch(workspaceIdProvider).value == workspaceId;
    final sameUser = ref.watch(authRepositoryProvider).currentUserId == userId;
    final brief = ref.watch(tomorrowBriefProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: SlateSheetFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WorkloopSheetHeader(title: 'Tomorrow'),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: !sameWorkspace || !sameUser
                  ? const Text('This workspace is no longer open.')
                  : brief.when(
                      skipLoadingOnReload: true,
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => Column(
                        children: [
                          const Text('Could not check tomorrow’s bookings.'),
                          TextButton(
                            onPressed: () => _retryTomorrow(ref),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                      data: (data) =>
                          data.workspaceId != null &&
                              data.workspaceId != workspaceId
                          ? const Text('Checking your schedule…')
                          : data.bookings.isEmpty
                          ? const Text('No bookings scheduled for tomorrow.')
                          : ListView.builder(
                              itemCount: data.bookings.length,
                              itemBuilder: (context, index) {
                                final booking = data.bookings[index];
                                return WorkloopListRow(
                                  key: ValueKey(
                                    'tomorrow-booking-${booking.id}',
                                  ),
                                  flat: true,
                                  leading: Icon(
                                    LucideIcons.clock,
                                    size: 20,
                                    color: AppColors.of(context).t2,
                                  ),
                                  title: Text(
                                    booking.clientName ?? 'Walk-in booking',
                                  ),
                                  subtitle: Text(
                                    '${tomorrowBookingTime(booking.startTime, data.timezone)}'
                                    ' · ${booking.serviceName ?? booking.title ?? 'Booking'}',
                                  ),
                                  trailing: const Icon(
                                    LucideIcons.chevronRight,
                                    size: 18,
                                  ),
                                  onTap: () {
                                    if (ref
                                                .read(authRepositoryProvider)
                                                .currentUserId !=
                                            userId ||
                                        ref.read(workspaceIdProvider).value !=
                                            workspaceId) {
                                      return;
                                    }
                                    final router = GoRouter.of(context);
                                    Navigator.of(context).pop();
                                    router.push(
                                      Uri(
                                        pathSegments: [
                                          '',
                                          'bookings',
                                          booking.id,
                                        ],
                                      ).toString(),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
