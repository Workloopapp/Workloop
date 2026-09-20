import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/notes_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/utils/currency_format.dart';
import '../../shared/widgets/slate_ui.dart';

class MoreScreen extends ConsumerWidget {
  final VoidCallback onOpenMoney;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenNotes;
  final VoidCallback? onOpenBookingPage;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onCreateMoney;
  final VoidCallback? onCreateTask;
  final VoidCallback? onCreateNote;

  const MoreScreen({
    super.key,
    required this.onOpenMoney,
    required this.onOpenTasks,
    required this.onOpenNotes,
    this.onOpenBookingPage,
    this.onOpenProfile,
    this.onOpenSettings,
    this.onCreateMoney,
    this.onCreateTask,
    this.onCreateNote,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SlateTheme.of(context);
    final payments = ref.watch(invoicesProvider);
    final tasks = ref.watch(allTasksProvider);
    final notes = ref.watch(allNotesProvider);

    final moneyStatus = payments.when(
      data: (items) {
        final owed = items.fold<double>(
          0,
          (total, payment) => total + outstandingAmountFor(payment),
        );
        return owed > 0 ? '${formatPounds(owed)} to collect' : 'Nothing owed';
      },
      loading: () => 'Checking your ledger',
      error: (_, _) => 'Open Money to retry',
    );
    final taskStatus = tasks.when(
      data: (items) {
        final open = items.where((task) => task.status != 'done').length;
        return open == 0
            ? 'No open tasks'
            : '$open open ${open == 1 ? 'task' : 'tasks'}';
      },
      loading: () => 'Checking your next actions',
      error: (_, _) => 'Open Tasks to retry',
    );
    final noteStatus = notes.when(
      data: (items) => items.isEmpty
          ? 'Ready for your first note'
          : '${items.length} saved ${items.length == 1 ? 'note' : 'notes'}',
      loading: () => 'Checking your notes',
      error: (_, _) => 'Open Notes to retry',
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                AppSpacing.screenTop,
                AppSpacing.pageX,
                AppSpacing.shellBottomClearance(context),
              ),
              children: [
                WorkloopPageHeader(
                  title: 'Tools',
                  subtitle:
                      'Capture the admin around your work, then get back to your day.',
                  color: tokens.accentInk,
                ),
                const SizedBox(height: AppSpacing.lg),
                _WorkspaceSection(
                  moneyStatus: moneyStatus,
                  taskStatus: taskStatus,
                  noteStatus: noteStatus,
                  onOpenMoney: onOpenMoney,
                  onOpenTasks: onOpenTasks,
                  onOpenNotes: onOpenNotes,
                ),
                const SizedBox(height: AppSpacing.xl),
                _QuickCaptureSection(
                  onCreateMoney: onCreateMoney ?? onOpenMoney,
                  onCreateTask: onCreateTask ?? onOpenTasks,
                  onCreateNote: onCreateNote ?? onOpenNotes,
                ),
                const SizedBox(height: AppSpacing.xl),
                _BusinessSetupSection(
                  onOpenBookingPage: onOpenBookingPage ?? _doNothing,
                  onOpenProfile: onOpenProfile ?? _doNothing,
                ),
                const SizedBox(height: AppSpacing.xl),
                _AccountSection(onOpenSettings: onOpenSettings ?? _doNothing),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _doNothing() {}

class _BusinessSetupSection extends StatelessWidget {
  final VoidCallback onOpenBookingPage;
  final VoidCallback onOpenProfile;

  const _BusinessSetupSection({
    required this.onOpenBookingPage,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkloopSectionHeader(label: 'Business setup'),
        const SizedBox(height: AppSpacing.xs),
        WorkloopSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          borderColor: Colors.transparent,
          child: Column(
            children: [
              WorkloopModuleRow(
                key: const ValueKey('tools-booking-page'),
                icon: LucideIcons.calendarCheck2,
                title: 'Booking page',
                color: AppColors.of(context).accentPrimary,
                subtitle: 'Preview, manage and share your public link',
                semanticLabel: 'Open Booking page',
                onTap: onOpenBookingPage,
              ),
              WorkloopModuleRow(
                key: const ValueKey('tools-business-profile'),
                icon: LucideIcons.store,
                title: 'Business profile',
                color: AppColors.of(context).accentPrimary,
                subtitle: 'Business details, services and working hours',
                semanticLabel: 'Open Business profile',
                showDivider: false,
                onTap: onOpenProfile,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountSection extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _AccountSection({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkloopSectionHeader(label: 'Account & app'),
        const SizedBox(height: AppSpacing.xs),
        WorkloopSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          borderColor: Colors.transparent,
          child: WorkloopModuleRow(
            key: const ValueKey('tools-settings'),
            icon: LucideIcons.settings,
            title: 'Settings',
            color: AppColors.of(context).accentPrimary,
            subtitle: 'Account, appearance, notifications and privacy',
            semanticLabel: 'Open Settings',
            showDivider: false,
            onTap: onOpenSettings,
          ),
        ),
      ],
    );
  }
}

class _QuickCaptureSection extends StatelessWidget {
  final VoidCallback onCreateMoney;
  final VoidCallback onCreateTask;
  final VoidCallback onCreateNote;

  const _QuickCaptureSection({
    required this.onCreateMoney,
    required this.onCreateTask,
    required this.onCreateNote,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickActionData(
        key: const ValueKey('tools-quick-money'),
        icon: LucideIcons.circlePoundSterling,
        label: 'Record money',
        color: AppColors.of(context).accentPrimary,
        onTap: onCreateMoney,
      ),
      _QuickActionData(
        key: const ValueKey('tools-quick-task'),
        icon: LucideIcons.listPlus,
        label: 'New task',
        color: AppColors.of(context).accentPrimary,
        onTap: onCreateTask,
      ),
      _QuickActionData(
        key: const ValueKey('tools-quick-note'),
        icon: LucideIcons.filePlus,
        label: 'New note',
        color: AppColors.of(context).accentPrimary,
        onTap: onCreateNote,
      ),
    ];

    final tokens = SlateTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkloopSectionHeader(label: 'Quick capture'),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Record it without breaking your flow.',
          style: TextStyle(color: tokens.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackActions =
                constraints.maxWidth < 306 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.35;
            if (stackActions) {
              return Column(
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    _QuickAction(data: actions[index], compact: true),
                    if (index != actions.length - 1)
                      const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  Expanded(child: _QuickAction(data: actions[index])),
                  if (index != actions.length - 1)
                    const SizedBox(width: AppSpacing.xs),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickActionData {
  final Key key;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _QuickAction extends StatelessWidget {
  final _QuickActionData data;
  final bool compact;

  const _QuickAction({required this.data, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);

    void handleTap() {
      SlateHaptics.action();
      data.onTap();
    }

    return Semantics(
      button: true,
      label: data.label,
      onTap: handleTap,
      child: ExcludeSemantics(
        child: Material(
          key: data.key,
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: tokens.divider),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: handleTap,
            child: SizedBox(
              height: compact ? 52 : 80,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? AppSpacing.md : AppSpacing.xs,
                  vertical: compact ? AppSpacing.xs : AppSpacing.xxs,
                ),
                child: compact
                    ? Row(
                        children: [
                          _QuickActionIcon(icon: data.icon, color: data.color),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: _QuickActionLabel(label: data.label)),
                          Icon(
                            LucideIcons.arrowUpRight,
                            color: tokens.textTertiary,
                            size: 16,
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _QuickActionIcon(icon: data.icon, color: data.color),
                          const SizedBox(height: AppSpacing.xs),
                          _QuickActionLabel(label: data.label),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _QuickActionIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }
}

class _QuickActionLabel extends StatelessWidget {
  final String label;
  const _QuickActionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: SlateTheme.of(context).textPrimary,
        fontSize: 12,
        height: 1.15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _WorkspaceSection extends StatelessWidget {
  final String moneyStatus;
  final String taskStatus;
  final String noteStatus;
  final VoidCallback onOpenMoney;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenNotes;

  const _WorkspaceSection({
    required this.moneyStatus,
    required this.taskStatus,
    required this.noteStatus,
    required this.onOpenMoney,
    required this.onOpenTasks,
    required this.onOpenNotes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkloopSectionHeader(label: 'Business tools'),
        const SizedBox(height: AppSpacing.xs),
        WorkloopSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          borderColor: Colors.transparent,
          child: Column(
            children: [
              WorkloopModuleRow(
                key: const ValueKey('more-workspace-money'),
                icon: LucideIcons.banknote,
                title: 'Money',
                color: AppColors.of(context).accentPrimary,
                subtitle: moneyStatus,
                semanticLabel: 'Open Money workspace',
                onTap: onOpenMoney,
              ),
              WorkloopModuleRow(
                key: const ValueKey('more-workspace-tasks'),
                icon: LucideIcons.listChecks,
                title: 'Tasks',
                color: AppColors.of(context).accentPrimary,
                subtitle: taskStatus,
                semanticLabel: 'Open Tasks workspace',
                onTap: onOpenTasks,
              ),
              WorkloopModuleRow(
                key: const ValueKey('more-workspace-notes'),
                icon: LucideIcons.stickyNote,
                title: 'Notes',
                color: AppColors.of(context).accentPrimary,
                subtitle: noteStatus,
                semanticLabel: 'Open Notes workspace',
                showDivider: false,
                onTap: onOpenNotes,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
