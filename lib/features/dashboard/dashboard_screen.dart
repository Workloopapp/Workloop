import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/dashboard_provider.dart';
import '../../shared/providers/business_clock_provider.dart';
import '../../shared/providers/booking_requests_provider.dart';
import '../weather/local_weather_greeting.dart';
import 'tomorrow_brief_row.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/client_follow_up_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/notes_provider.dart';
import '../../shared/providers/notifications_provider.dart';
import '../../shared/providers/setup_checklist_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/currency_format.dart';
import '../../shared/utils/date_format.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/income_target_indicator.dart';
import '../appointments/appointment_detail_screen.dart';

// One clock drives all time-sensitive business summaries and the visible date.
final dashboardClockProvider = businessClockProvider;

String dashboardGreetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String dashboardDateLabel(DateTime date) => _dashboardDate(date);

List<Map<String, dynamic>> selectDashboardTodayBookings(
  List<Map<String, dynamic>> rows, {
  required DateTime now,
}) => _todayJobs(rows, now: now);

List<Map<String, dynamic>> selectDashboardComingUpBookings(
  List<Map<String, dynamic>> rows, {
  required DateTime now,
}) => _upcomingJobs(
  rows,
  now: now,
).where((job) => !_isSameDay(_startTime(job), now)).take(3).toList();

int dashboardSetupCompletedCount({
  required bool hasClient,
  required bool hasBooking,
  required bool hasPayment,
}) => [hasClient, hasBooking, hasPayment].where((value) => value).length;

class DashboardScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  final VoidCallback onOpenMoneyFollowUps;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
    required this.onOpenMoneyFollowUps,
  });

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _acceptedAttentionWorkspaceId;
  bool _snoozingFollowUp = false;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final appointments = ref.watch(appointmentsProvider);
    final clients = ref.watch(clientsProvider);
    final payments = ref.watch(invoicesProvider);
    final finance = ref.watch(financeSummaryProvider);
    final attention = ref.watch(dashboardAttentionProvider);
    final tasks = ref.watch(allTasksProvider);
    final notes = ref.watch(allNotesProvider);
    final unreadNotifications = ref.watch(unreadNotificationsProvider);
    final displayName = ref.watch(authRepositoryProvider).currentFirstName;
    final now = ref
        .watch(dashboardClockProvider)
        .maybeWhen(data: (value) => value, orElse: DateTime.now);
    final greeting = dashboardGreetingForHour(now.hour);
    final checklist = ref.watch(setupChecklistDismissedProvider);
    final checklistDismissed = checklist.value;
    final workspaceId = workspace.value?['id'] as String?;
    if (_acceptedAttentionWorkspaceId != workspaceId) {
      _acceptedAttentionWorkspaceId = null;
    }
    // Riverpod keeps previous values during dependency reloads. Only reuse an
    // attention result already settled for this mounted dashboard's workspace;
    // a newly opened workspace must never inherit another workspace's rows.
    if (!workspace.isLoading &&
        !workspace.hasError &&
        !attention.isLoading &&
        !attention.hasError &&
        attention.hasValue) {
      _acceptedAttentionWorkspaceId = workspaceId;
    }
    final retainAttention =
        workspaceId != null && _acceptedAttentionWorkspaceId == workspaceId;
    final attentionPending = attention.isLoading && !retainAttention;
    final checklistPending =
        checklist.isLoading && !checklist.hasValue && !checklist.hasError;
    final setupDataReady =
        clients.hasValue && appointments.hasValue && payments.hasValue;
    final overviewHasFailure =
        workspace.hasError || clients.hasError || payments.hasError;

    void retryOverview() {
      ref.invalidate(workspaceProvider);
      ref.invalidate(clientsProvider);
      ref.invalidate(appointmentsProvider);
      ref.invalidate(invoicesProvider);
    }

    void retryAttention() {
      ref.invalidate(invoicesProvider);
      ref.invalidate(allTasksProvider);
      ref.invalidate(appointmentsProvider);
      ref.invalidate(clientsProvider);
      ref.invalidate(bookingRequestsProvider);
      ref.invalidate(dashboardFocusProvider);
      ref.invalidate(dashboardAttentionProvider);
    }

    void retryFinance() {
      ref.invalidate(invoicesProvider);
      ref.invalidate(expensesProvider);
      ref.invalidate(financeSummaryProvider);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.of(context).accentPrimary,
              onRefresh: () async {
                SlateHaptics.action();
                ref.invalidate(workspaceProvider);
                ref.invalidate(appointmentsProvider);
                ref.invalidate(todayAppointmentsProvider);
                ref.invalidate(financeSummaryProvider);
                ref.invalidate(invoicesProvider);
                ref.invalidate(expensesProvider);
                ref.invalidate(clientsProvider);
                ref.invalidate(allTasksProvider);
                ref.invalidate(tasksProvider);
                ref.invalidate(allNotesProvider);
                ref.invalidate(dashboardFocusProvider);
                ref.invalidate(dashboardAttentionProvider);
                ref.invalidate(unreadNotificationsProvider);
                ref.invalidate(bookingRequestsProvider);
                try {
                  await Future.wait<Object?>([
                    ref.read(appointmentsProvider.future),
                    ref.read(invoicesProvider.future),
                    ref.read(expensesProvider.future),
                    ref.read(clientsProvider.future),
                    ref.read(allTasksProvider.future),
                    ref.read(allNotesProvider.future),
                    ref.read(bookingRequestsProvider.future),
                  ]);
                } catch (_) {
                  // Each section keeps its own visible error and retry action.
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  AppSpacing.screenTop,
                  AppSpacing.pageX,
                  AppSpacing.shellBottomClearance(context),
                ),
                children: [
                  _DashboardGreeting(
                    greeting: displayName == null
                        ? greeting
                        : '$greeting $displayName',
                    subtitle: dashboardDateLabel(now),
                    unreadNotifications: unreadNotifications.maybeWhen(
                      data: (value) => value,
                      orElse: () => 0,
                    ),
                    onOpenNotifications: () async {
                      await context.push('/notifications');
                      ref.invalidate(unreadNotificationsProvider);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _TodaySection(
                    appointments: appointments,
                    now: now,
                    onOpenJob: (appointment) =>
                        _openAppointment(context, ref, appointment),
                    onViewBookings: () => widget.onNavigate(2),
                  ),
                  if (overviewHasFailure) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SlateErrorState(
                      message:
                          'Some workspace details could not be refreshed. Please try again.',
                      onRetry: retryOverview,
                    ),
                  ],
                  attention.when(
                    skipLoadingOnRefresh: retainAttention,
                    skipLoadingOnReload: retainAttention,
                    skipError: retainAttention,
                    data: (items) => items.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.section,
                            ),
                            child: _WorthALookSection(
                              items: selectDashboardAttentionPreview(items),
                              onOpen: (item) =>
                                  _openAttentionItem(context, ref, item),
                              onSnooze:
                                  ref
                                              .read(authRepositoryProvider)
                                              .currentUserId ==
                                          null ||
                                      _snoozingFollowUp
                                  ? null
                                  : _snoozeFollowUp,
                            ),
                          ),
                    loading: () => Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.section),
                      child: Semantics(
                        label: 'Checking what needs your attention',
                        liveRegion: true,
                        child: const SlateLoadingBlock(
                          key: ValueKey('dashboard-attention-loading'),
                          height: 120,
                          radius: AppRadius.sm,
                        ),
                      ),
                    ),
                    error: (_, _) => Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.section),
                      child: SlateErrorState(
                        message: 'Could not check what needs your attention.',
                        onRetry: retryAttention,
                      ),
                    ),
                  ),
                  if (attention.hasError &&
                      attention.hasValue &&
                      retainAttention)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: SlateErrorState(
                        message:
                            'Could not refresh what needs your attention. Showing your last update.',
                        onRetry: retryAttention,
                      ),
                    ),
                  if (!attentionPending && !checklistPending) ...[
                    if (checklistDismissed == false && setupDataReady)
                      _SetupChecklist(
                        hasClient: clients.value?.isNotEmpty ?? false,
                        hasBooking: appointments.value?.isNotEmpty ?? false,
                        hasPayment: payments.value?.isNotEmpty ?? false,
                        onAddClient: () => context.push('/clients/new'),
                        onAddBooking: () => context.push('/bookings/new'),
                        onAddPayment: () => widget.onNavigate(3),
                        onImport: () => context.push('/import-data'),
                        onDismiss: () => dismissSetupChecklist(ref),
                      ),
                    const SizedBox(height: AppSpacing.section),
                    _DashboardSection(
                      title: 'At a glance',
                      child: WorkloopSurface(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs,
                        ),
                        borderColor: Colors.transparent,
                        child: Column(
                          children: [
                            _MoneyPulse(
                              finance: finance,
                              onOpen: () => widget.onNavigate(3),
                              onRetry: retryFinance,
                            ),
                            const TomorrowBriefRow(),
                            _QuickAccessRow(
                              taskSummary: tasks.maybeWhen(
                                data: (items) {
                                  final open = items
                                      .where((item) => item.status != 'done')
                                      .length;
                                  return open == 1
                                      ? '1 open task'
                                      : '$open open tasks';
                                },
                                orElse: () => 'Plan and follow up',
                              ),
                              noteSummary: notes.maybeWhen(
                                data: (items) => items.length == 1
                                    ? '1 saved note'
                                    : '${items.length} saved notes',
                                orElse: () => 'Capture useful context',
                              ),
                              onOpenTasks: () => widget.onNavigate(4),
                              onOpenNotes: () => widget.onNavigate(5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _snoozeFollowUp(Client client) async {
    if (_snoozingFollowUp) return;
    final userId = ref.read(authRepositoryProvider).currentUserId;
    final workspaceId = ref.read(workspaceIdProvider).value;
    if (userId == null || workspaceId != client.workspaceId) return;
    final scope = (userId: userId, workspaceId: client.workspaceId);
    setState(() => _snoozingFollowUp = true);
    try {
      await snoozeClientFollowUp(
        store: ref.read(clientFollowUpSnoozeStoreProvider),
        scope: scope,
        clientId: client.id,
        now: ref.read(businessNowProvider),
      );
      if (!mounted) return;
      ref.invalidate(clientFollowUpSnoozesProvider(scope));
      if (ref.read(authRepositoryProvider).currentUserId != userId ||
          ref.read(workspaceIdProvider).value != workspaceId) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow-up hidden for 7 days on this device.'),
        ),
      );
    } catch (_) {
      if (!mounted ||
          ref.read(authRepositoryProvider).currentUserId != userId ||
          ref.read(workspaceIdProvider).value != workspaceId) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that reminder. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _snoozingFollowUp = false);
    }
  }

  void _openAppointment(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> appointment,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailScreen(appointment: appointment),
      ),
    ).then((_) {
      ref.invalidate(appointmentsProvider);
      ref.invalidate(todayAppointmentsProvider);
    });
  }

  void _openAttentionItem(
    BuildContext context,
    WidgetRef ref,
    DashboardAttentionItem item,
  ) {
    final entityRoute = item.entityRoute;
    if (entityRoute != null) {
      switch (item.type) {
        case DashboardAttentionType.unpaid:
          ref.invalidate(invoicesProvider);
        case DashboardAttentionType.bookingRequest:
          ref.invalidate(bookingRequestsProvider);
        case DashboardAttentionType.overdueTask:
          ref.invalidate(allTasksProvider);
        case DashboardAttentionType.clientFollowUp:
          ref.invalidate(clientsProvider);
      }
      context.push(entityRoute);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This item is no longer available. Refresh Today to check again.',
        ),
      ),
    );
  }
}

class _SetupChecklist extends StatelessWidget {
  final bool hasClient;
  final bool hasBooking;
  final bool hasPayment;
  final VoidCallback onAddClient;
  final VoidCallback onAddBooking;
  final VoidCallback onAddPayment;
  final VoidCallback onImport;
  final VoidCallback onDismiss;

  const _SetupChecklist({
    required this.hasClient,
    required this.hasBooking,
    required this.hasPayment,
    required this.onAddClient,
    required this.onAddBooking,
    required this.onAddPayment,
    required this.onImport,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final completed = dashboardSetupCompletedCount(
      hasClient: hasClient,
      hasBooking: hasBooking,
      hasPayment: hasPayment,
    );
    if (completed == 3) return const SizedBox.shrink();
    final tokens = SlateTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: WorkloopSurface(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set up your workspace',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$completed of 3 essentials complete',
                        style: TextStyle(
                          color: tokens.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                WorkloopIconButton(
                  icon: LucideIcons.x,
                  semanticLabel: 'Dismiss setup checklist',
                  onTap: onDismiss,
                  size: 36,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _SetupStep(
              complete: hasClient,
              label: 'Add your first client',
              onTap: onAddClient,
            ),
            _SetupStep(
              complete: hasBooking,
              label: 'Create your first booking',
              onTap: onAddBooking,
            ),
            _SetupStep(
              complete: hasPayment,
              label: 'Record your first payment',
              onTap: onAddPayment,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: WorkloopTextButton(
                label: 'Import existing data',
                onPressed: onImport,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  final bool complete;
  final String label;
  final VoidCallback onTap;

  const _SetupStep({
    required this.complete,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      onTap: complete ? null : onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      leading: Icon(
        complete ? LucideIcons.checkCircle2 : LucideIcons.circle,
        size: 19,
        color: complete ? tokens.accentInk : tokens.textTertiary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: complete ? tokens.textTertiary : tokens.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          decoration: complete ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: complete
          ? null
          : Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: tokens.textTertiary,
            ),
      showDivider: false,
    );
  }
}

class _DashboardGreeting extends StatelessWidget {
  final String greeting;
  final String subtitle;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  const _DashboardGreeting({
    required this.greeting,
    required this.subtitle,
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: WorkloopWordmark()),
            WorkloopIconButton(
              icon: unreadNotifications > 0
                  ? LucideIcons.bellRing
                  : LucideIcons.bell,
              semanticLabel: unreadNotifications == 0
                  ? 'Open notifications'
                  : 'Open notifications, $unreadNotifications unread',
              onTap: onOpenNotifications,
              badge: unreadNotifications == 0
                  ? null
                  : Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.paperYellow,
                          border: Border.all(color: tokens.frame),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          unreadNotifications > 99
                              ? '99+'
                              : '$unreadNotifications',
                          style: TextStyle(
                            color: tokens.onPaperStrip,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('Today', style: Theme.of(context).textTheme.displayLarge),
        const SizedBox(height: AppSpacing.xs),
        WorkloopCaption(subtitle),
        const WorkloopDivider(
          margin: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        ),
        WorkloopWeatherGreeting(greeting: greeting),
      ],
    );
  }
}

class _QuickAccessRow extends StatelessWidget {
  final String taskSummary;
  final String noteSummary;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenNotes;

  const _QuickAccessRow({
    required this.taskSummary,
    required this.noteSummary,
    required this.onOpenTasks,
    required this.onOpenNotes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WorkloopModuleRow(
          icon: LucideIcons.listChecks,
          title: 'Tasks',
          subtitle: taskSummary,
          color: AppColors.of(context).accentPrimary,
          onTap: onOpenTasks,
        ),
        WorkloopModuleRow(
          icon: LucideIcons.stickyNote,
          title: 'Notes',
          subtitle: noteSummary,
          color: AppColors.of(context).accentPrimary,
          showDivider: false,
          onTap: onOpenNotes,
        ),
      ],
    );
  }
}

class _TodaySection extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> appointments;
  final DateTime now;
  final ValueChanged<Map<String, dynamic>> onOpenJob;
  final VoidCallback onViewBookings;

  const _TodaySection({
    required this.appointments,
    required this.now,
    required this.onOpenJob,
    required this.onViewBookings,
  });

  @override
  Widget build(BuildContext context) {
    return appointments.when(
      loading: () => const SlateLoadingBlock(height: 220, radius: AppRadius.lg),
      error: (_, _) => SlateErrorState(
        message: 'Your schedule could not be loaded. Open Bookings to retry.',
        onRetry: onViewBookings,
      ),
      data: (rows) {
        final todayJobs = selectDashboardTodayBookings(rows, now: now);
        final jobs = todayJobs.isNotEmpty
            ? todayJobs
            : _upcomingJobs(rows, now: now).take(1).toList();
        if (jobs.isEmpty) {
          return _DailyFocusHero(
            label: 'YOUR DAY',
            title: 'Your day is clear',
            detail: 'No more bookings are scheduled today.',
            actionLabel: 'Open Bookings',
            onAction: onViewBookings,
            dayProgress: _dayProgress(now),
          );
        }

        final bookingPositions = jobs
            .map(_startTime)
            .whereType<DateTime>()
            .map(_dayProgress)
            .toList(growable: false);
        return _TodayBookingCarousel(
          jobs: jobs,
          now: now,
          bookingPositions: bookingPositions,
          onOpenJob: onOpenJob,
        );
      },
    );
  }
}

class _TodayBookingCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> jobs;
  final DateTime now;
  final List<double> bookingPositions;
  final ValueChanged<Map<String, dynamic>> onOpenJob;

  const _TodayBookingCarousel({
    required this.jobs,
    required this.now,
    required this.bookingPositions,
    required this.onOpenJob,
  });

  @override
  State<_TodayBookingCarousel> createState() => _TodayBookingCarouselState();
}

class _TodayBookingCarouselState extends State<_TodayBookingCarousel> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      viewportFraction: widget.jobs.length > 1 ? 0.97 : 1,
    );
  }

  @override
  void didUpdateWidget(covariant _TodayBookingCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousId = oldWidget.jobs.isEmpty
        ? null
        : oldWidget.jobs[_index.clamp(0, oldWidget.jobs.length - 1)]['id'];
    final preserved = widget.jobs.indexWhere((row) => row['id'] == previousId);
    final nextIndex = preserved >= 0 ? preserved : 0;
    if (nextIndex == _index && _index < widget.jobs.length) return;
    _index = nextIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(_index);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    const baseHeight = 260;
    final carouselHeight = (baseHeight + ((textScale - 1) * 214).clamp(0, 428))
        .toDouble();

    Widget bookingCard(int index) {
      final job = widget.jobs[index];
      final start = _startTime(job);
      final end = _endTime(job);
      final happeningNow =
          start != null &&
          end != null &&
          !widget.now.isBefore(start) &&
          widget.now.isBefore(end);
      final time = start == null ? null : slateTime(start);
      final later = widget.jobs.length - index - 1;
      final isToday = _isSameDay(start, widget.now);

      return Padding(
        padding: EdgeInsets.only(
          right: widget.jobs.length > 1 ? AppSpacing.xs : 0,
        ),
        child: Semantics(
          label:
              'Booking ${index + 1} of ${widget.jobs.length}, ${_clientName(job)}',
          child: _DailyFocusHero(
            label: !isToday && start != null
                ? 'NEXT BOOKING · ${_friendlyDate(start, now: widget.now)}'
                : happeningNow
                ? 'HAPPENING NOW · ${index + 1} OF ${widget.jobs.length}'
                : 'UP NEXT · ${index + 1} OF ${widget.jobs.length}',
            value: time,
            bookingTime: start == null ? null : TimeOfDay.fromDateTime(start),
            title: _clientName(job),
            detail: [
              _serviceName(job),
              if (start != null && end != null)
                '${end.difference(start).inMinutes} min',
              if (job['price'] is num)
                formatPounds((job['price'] as num).toDouble()),
              if (later == 1) '1 later today',
              if (later > 1) '$later later today',
            ].join(' · '),
            actionLabel: 'Open booking',
            onAction: () => widget.onOpenJob(job),
            dayProgress: _dayProgress(widget.now),
            bookingPositions: widget.bookingPositions,
            activeBookingIndex: _index,
            showDayPath: isToday,
          ),
        ),
      );
    }

    if (widget.jobs.length == 1) return bookingCard(0);

    return Semantics(
      container: true,
      label:
          '${widget.jobs.length} remaining booking${widget.jobs.length == 1 ? '' : 's'} today. Swipe horizontally to browse.',
      child: Column(
        children: [
          SizedBox(
            height: carouselHeight,
            child: PageView.builder(
              key: const ValueKey('today-booking-carousel'),
              controller: _controller,
              padEnds: false,
              physics: widget.jobs.length > 1
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: widget.jobs.length,
              onPageChanged: (index) {
                if (index == _index) return;
                SlateHaptics.tap();
                setState(() => _index = index);
              },
              itemBuilder: (context, index) => bookingCard(index),
            ),
          ),
          if (widget.jobs.length > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < widget.jobs.length; index++)
                  AnimatedContainer(
                    duration: AppMotion.responsive(context, AppMotion.standard),
                    curve: AppMotion.curve,
                    width: index == _index ? 18 : 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: index == _index
                          ? tokens.accentInk
                          : tokens.divider,
                      borderRadius: BorderRadius.circular(AppRadius.capsule),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DailyFocusHero extends StatelessWidget {
  final String label;
  final String? value;
  final TimeOfDay? bookingTime;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;
  final double dayProgress;
  final List<double> bookingPositions;
  final int? activeBookingIndex;
  final bool showDayPath;

  const _DailyFocusHero({
    required this.label,
    this.value,
    this.bookingTime,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
    required this.dayProgress,
    this.bookingPositions = const [],
    this.activeBookingIndex,
    this.showDayPath = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopPaperPanel(
      title: label,
      tone: WorkloopPaperTone.blue,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bookingTime != null &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.5) ...[
                WorkloopIllustration(
                  kind: WorkloopIllustrationKind.clock,
                  clockTime: bookingTime,
                  size: 66,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (value != null) ...[
                      Text(
                        value!,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineLarge?.copyWith(fontSize: 27),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                    ],
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (showDayPath)
            Semantics(
              label: bookingPositions.isEmpty
                  ? 'Today is ${(dayProgress * 100).round()} percent complete'
                  : '${bookingPositions.length} bookings remain today',
              child: ExcludeSemantics(
                child: SizedBox(
                  key: ValueKey(
                    'active-job-marker-${activeBookingIndex ?? 'none'}',
                  ),
                  height: 16,
                  width: double.infinity,
                  child: _AnimatedDayPath(
                    progress: dayProgress,
                    bookingPositions: bookingPositions,
                    activeBookingIndex: activeBookingIndex,
                    track: tokens.divider,
                    accent: tokens.accent,
                    ink: tokens.textPrimary,
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: SlateButton(label: actionLabel, onPressed: onAction),
          ),
        ],
      ),
    );
  }
}

double _dayProgress(DateTime value) {
  final minutes = value.hour * 60 + value.minute;
  return (minutes / (24 * 60)).clamp(0.0, 1.0);
}

class _DayPathPainter extends CustomPainter {
  final double progress;
  final List<double> bookingPositions;
  final int? activeBookingIndex;
  final double? activeBookingPosition;
  final double activeMarkerScale;
  final Color track;
  final Color accent;
  final Color ink;

  const _DayPathPainter({
    required this.progress,
    required this.bookingPositions,
    required this.activeBookingIndex,
    required this.activeBookingPosition,
    required this.activeMarkerScale,
    required this.track,
    required this.accent,
    required this.ink,
  });

  double _y(double x, Size size) {
    return size.height * 0.52 + math.sin(x * math.pi * 2.1) * 4;
  }

  Path _path(Size size, double end) {
    final path = Path();
    const steps = 48;
    for (var index = 0; index <= steps; index++) {
      final fraction = (index / steps) * end;
      final point = Offset(fraction * size.width, _y(fraction, size));
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 4.0;
    final contentSize = Size(size.width - inset * 2, size.height);
    canvas.save();
    canvas.translate(inset, 0);

    canvas.drawPath(
      _path(contentSize, 1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..color = track.withValues(alpha: 0.42),
    );
    canvas.drawPath(
      _path(contentSize, progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round
        ..color = ink.withValues(alpha: 0.78),
    );

    final current = Offset(
      progress * contentSize.width,
      _y(progress, contentSize),
    );
    canvas.drawCircle(
      current,
      3.25,
      Paint()
        ..style = PaintingStyle.fill
        ..color = ink.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      current,
      3.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = accent.withValues(alpha: 0.72),
    );

    final visiblePositions = bookingPositions.take(6).toList(growable: false);
    for (var index = 0; index < visiblePositions.length; index++) {
      if (index == activeBookingIndex) continue;
      final position = visiblePositions[index];
      final clamped = position.clamp(0.0, 1.0);
      final point = Offset(
        clamped * contentSize.width,
        _y(clamped, contentSize),
      );
      canvas.drawCircle(
        point,
        3,
        Paint()
          ..style = PaintingStyle.fill
          ..color = clamped <= progress
              ? ink.withValues(alpha: 0.62)
              : accent.withValues(alpha: 0.82),
      );
    }

    if (activeBookingPosition case final position?) {
      final clamped = position.clamp(0.0, 1.0);
      final point = Offset(
        clamped * contentSize.width,
        _y(clamped, contentSize),
      );
      canvas.drawCircle(
        point,
        9 * activeMarkerScale,
        Paint()..color = accent.withValues(alpha: 0.20),
      );
      canvas.drawCircle(point, 6.25 * activeMarkerScale, Paint()..color = ink);
      canvas.drawCircle(
        point,
        6.25 * activeMarkerScale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DayPathPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        bookingPositions != oldDelegate.bookingPositions ||
        activeBookingIndex != oldDelegate.activeBookingIndex ||
        activeBookingPosition != oldDelegate.activeBookingPosition ||
        activeMarkerScale != oldDelegate.activeMarkerScale ||
        track != oldDelegate.track ||
        accent != oldDelegate.accent ||
        ink != oldDelegate.ink;
  }
}

class _AnimatedDayPath extends StatefulWidget {
  final double progress;
  final List<double> bookingPositions;
  final int? activeBookingIndex;
  final Color track;
  final Color accent;
  final Color ink;

  const _AnimatedDayPath({
    required this.progress,
    required this.bookingPositions,
    required this.activeBookingIndex,
    required this.track,
    required this.accent,
    required this.ink,
  });

  @override
  State<_AnimatedDayPath> createState() => _AnimatedDayPathState();
}

class _AnimatedDayPathState extends State<_AnimatedDayPath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double? _fromPosition;
  double? _targetPosition;

  double? _positionFor(_AnimatedDayPath value) {
    final index = value.activeBookingIndex;
    if (index == null || index < 0 || index >= value.bookingPositions.length) {
      return null;
    }
    return value.bookingPositions[index].clamp(0.0, 1.0);
  }

  double? get _currentPosition {
    final from = _fromPosition;
    final target = _targetPosition;
    if (target == null) return null;
    if (from == null) return target;
    final travel = Curves.easeInOutCubic.transform(_controller.value);
    return from + (target - from) * travel;
  }

  @override
  void initState() {
    super.initState();
    _targetPosition = _positionFor(widget);
    _fromPosition = _targetPosition;
    _controller = AnimationController(
      vsync: this,
      duration: Duration.zero,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.responsive(context, AppMotion.deliberate);
    if (_controller.duration == Duration.zero) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedDayPath oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPosition = _positionFor(widget);
    if (nextPosition == _targetPosition &&
        widget.activeBookingIndex == oldWidget.activeBookingIndex) {
      return;
    }
    _fromPosition = _currentPosition ?? nextPosition;
    _targetPosition = nextPosition;
    if (_controller.duration == Duration.zero || nextPosition == null) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final bounce = _controller.isAnimating
            ? Curves.easeOutBack.transform(_controller.value)
            : 1.0;
        final markerScale = 0.78 + 0.22 * bounce;
        return CustomPaint(
          painter: _DayPathPainter(
            progress: widget.progress,
            bookingPositions: widget.bookingPositions,
            activeBookingIndex: widget.activeBookingIndex,
            activeBookingPosition: _currentPosition,
            activeMarkerScale: markerScale,
            track: widget.track,
            accent: widget.accent,
            ink: widget.ink,
          ),
        );
      },
    );
  }
}

class _WorthALookSection extends StatelessWidget {
  final List<DashboardAttentionItem> items;
  final ValueChanged<DashboardAttentionItem> onOpen;
  final ValueChanged<Client>? onSnooze;

  const _WorthALookSection({
    required this.items,
    required this.onOpen,
    this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopPaperPanel(
      title: 'Needs attention',
      tone: WorkloopPaperTone.warm,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++)
            WorkloopListRow(
              flat: true,
              onTap: () => onOpen(items[index]),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              leading: _SoftIcon(icon: _attentionIcon(items[index].type)),
              title: Text(
                _attentionTitle(items[index]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                _attentionDetail(items[index]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.of(context).t2,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (items[index].type ==
                          DashboardAttentionType.clientFollowUp &&
                      items[index].source is Client &&
                      onSnooze != null)
                    PopupMenuButton<int>(
                      tooltip:
                          'Follow-up options for ${(items[index].source as Client).name}',
                      icon: Icon(
                        LucideIcons.ellipsis,
                        size: 18,
                        color: AppColors.of(context).t3,
                      ),
                      onSelected: (_) =>
                          onSnooze!(items[index].source as Client),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 7, child: Text('Hide for 7 days')),
                      ],
                    ),
                  Icon(
                    LucideIcons.chevronRight,
                    color: AppColors.of(context).t3,
                    size: 16,
                  ),
                ],
              ),
              showDivider: index != items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _MoneyPulse extends StatelessWidget {
  final AsyncValue<FinanceSummary> finance;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  const _MoneyPulse({
    required this.finance,
    required this.onOpen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return finance.when(
      loading: () => const SlateLoadingBlock(height: 68, radius: AppRadius.md),
      error: (_, _) => SlateErrorState(
        message: 'Could not load your Money summary.',
        onRetry: onRetry,
      ),
      data: (summary) => _MoneyRow(
        onOpen: onOpen,
        amount: summary.thisMonthPaid,
        target: summary.monthlyTarget,
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final VoidCallback onOpen;
  final double? amount;
  final double target;

  const _MoneyRow({required this.onOpen, this.amount, required this.target});

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      onTap: onOpen,
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
        child: Icon(LucideIcons.banknote, color: tokens.accentInk, size: 20),
      ),
      title: Text(
        'Money',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        amount == null
            ? 'See your latest business progress'
            : target > 0
            ? '${formatPounds(amount!)} of ${formatPounds(target)} this month'
            : '${formatPounds(amount!)} received this month',
        style: TextStyle(
          color: AppColors.of(context).t2,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: target > 0 && amount != null
          ? WorkloopIncomeTargetIndicator(
              amount: amount!,
              target: target,
              size: 46,
              fontSize: 10,
            )
          : Icon(
              LucideIcons.chevronRight,
              color: AppColors.of(context).t3,
              size: 16,
            ),
    );
  }
}

class _DashboardSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DashboardSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _SoftIcon extends StatelessWidget {
  final IconData icon;

  const _SoftIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.of(context).t1.withValues(alpha: 0.045),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.of(context).t3, size: 17),
    );
  }
}

String _dashboardDate(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}

List<Map<String, dynamic>> _todayJobs(
  List<Map<String, dynamic>> rows, {
  required DateTime now,
}) {
  return _upcomingJobs(
    rows,
    now: now,
  ).where((row) => _isSameDay(_startTime(row), now)).toList();
}

bool _isSameDay(DateTime? first, DateTime second) {
  return first != null &&
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String _attentionTitle(DashboardAttentionItem item) {
  return item.title;
}

String _attentionDetail(DashboardAttentionItem item) {
  return switch (item.type) {
    DashboardAttentionType.bookingRequest => item.detail,
    DashboardAttentionType.unpaid => item.detail,
    DashboardAttentionType.overdueTask =>
      item.detail == 'Overdue task' ? 'A task ready when you are' : item.detail,
    DashboardAttentionType.clientFollowUp => item.detail,
  };
}

IconData _attentionIcon(DashboardAttentionType type) {
  return switch (type) {
    DashboardAttentionType.bookingRequest => LucideIcons.inbox,
    DashboardAttentionType.unpaid => LucideIcons.banknote,
    DashboardAttentionType.overdueTask => LucideIcons.listChecks,
    DashboardAttentionType.clientFollowUp => LucideIcons.userRoundCheck,
  };
}

List<Map<String, dynamic>> _upcomingJobs(
  List<Map<String, dynamic>> rows, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final jobs = rows.where((row) {
    final status = row['status']?.toString().toLowerCase() ?? 'scheduled';
    final start = _startTime(row);
    if (start == null) return false;
    if (status == 'completed' || status == 'cancelled' || status == 'no_show') {
      return false;
    }
    final end = _endTime(row);
    final happeningNow =
        end != null && !current.isBefore(start) && current.isBefore(end);
    return start.isAfter(current) || happeningNow;
  }).toList();

  jobs.sort((a, b) {
    final aStart = _startTime(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bStart = _startTime(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aStart.compareTo(bStart);
  });
  return jobs;
}

DateTime? _startTime(Map<String, dynamic> appointment) =>
    DateTime.tryParse(appointment['start_time']?.toString() ?? '')?.toLocal();

DateTime? _endTime(Map<String, dynamic> appointment) =>
    DateTime.tryParse(appointment['end_time']?.toString() ?? '')?.toLocal();

String _clientName(Map<String, dynamic> appointment) =>
    appointment['contacts']?['name']?.toString() ?? 'Client';

String _serviceName(Map<String, dynamic> appointment) =>
    appointment['services']?['name']?.toString() ??
    appointment['title']?.toString() ??
    'Booking';

String _friendlyDate(DateTime value, {DateTime? now}) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  if (day == today) return 'Today';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
  return '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
}
