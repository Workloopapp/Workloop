import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/notifications/notification_route.dart';
import '../../../shared/providers/clients_provider.dart';
import '../../../shared/providers/notifications_provider.dart';
import '../../../shared/providers/tasks_provider.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/repositories/slate_repositories.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import '../providers/client_detail_providers.dart';

class ClientTasksTab extends ConsumerStatefulWidget {
  final String clientId;
  final String clientName;

  const ClientTasksTab({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  ConsumerState<ClientTasksTab> createState() => _ClientTasksTabState();
}

class _ClientTasksTabState extends ConsumerState<ClientTasksTab> {
  void _showAddTaskSheet() {
    final titleController = TextEditingController();
    String priority = 'medium';
    DateTime? dueDate;
    var saving = false;
    String? error;

    showWorkloopBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => PopScope(
          canPop: !saving,
          child: AnimatedPadding(
            duration: AppMotion.responsive(context, AppMotion.fast),
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SlateSheetFrame(
              scrollable: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New Task',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.of(ctx).t1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.user,
                        size: 12,
                        color: AppColors.of(ctx).green,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Linked to ${widget.clientName}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.of(ctx).green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: TextStyle(color: AppColors.of(ctx).t1),
                    decoration: InputDecoration(
                      label: const WorkloopFieldLabel(
                        'Task title',
                        isRequired: true,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      hintText: 'Task title',
                      hintStyle: TextStyle(color: AppColors.of(ctx).t3),
                      filled: true,
                      fillColor: AppColors.of(ctx).bgInteract,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const WorkloopFieldLabel('Priority', isRequired: false),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      _PriorityChip(
                        value: 'high',
                        label: 'High',
                        color: AppColors.of(ctx).error,
                        selected: priority,
                        onTap: (v) => setModal(() => priority = v),
                      ),
                      const SizedBox(width: 8),
                      _PriorityChip(
                        value: 'medium',
                        label: 'Medium',
                        color: AppColors.of(ctx).warning,
                        selected: priority,
                        onTap: (v) => setModal(() => priority = v),
                      ),
                      const SizedBox(width: 8),
                      _PriorityChip(
                        value: 'low',
                        label: 'Low',
                        color: AppColors.of(ctx).t3,
                        selected: priority,
                        onTap: (v) => setModal(() => priority = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const WorkloopFieldLabel('Due date', isRequired: false),
                  const SizedBox(height: AppSpacing.xs),
                  Semantics(
                    button: true,
                    label: 'Task due date',
                    value: dueDate == null ? 'Not set' : _formatDate(dueDate!),
                    onTap: () async {
                      final picked = await showWorkloopDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setModal(() => dueDate = picked);
                    },
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          final picked = await showWorkloopDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) setModal(() => dueDate = picked);
                        },
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: AppSpacing.minTouch,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppColors.of(ctx).bgInteract,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.calendar,
                                color: dueDate != null
                                    ? AppColors.of(ctx).green
                                    : AppColors.of(ctx).t3,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  dueDate == null
                                      ? 'Set due date (optional)'
                                      : _formatDate(dueDate!),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: dueDate != null
                                        ? AppColors.of(ctx).t1
                                        : AppColors.of(ctx).t3,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: AppColors.of(ctx).error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final title = titleController.text.trim();
                              if (title.isEmpty) {
                                setModal(
                                  () => error = 'Add a task title to continue.',
                                );
                                return;
                              }
                              setModal(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                final workspaceId = await ref.read(
                                  workspaceIdProvider.future,
                                );
                                if (workspaceId == null) {
                                  if (ctx.mounted) {
                                    setModal(() {
                                      saving = false;
                                      error =
                                          'Your workspace is not ready yet. Please try again.';
                                    });
                                  }
                                  return;
                                }

                                final taskId = await ref
                                    .read(tasksRepositoryProvider)
                                    .create(
                                      workspaceId: workspaceId,
                                      title: title,
                                      priority: priority,
                                      contactId: widget.clientId,
                                      dueDate: dueDate,
                                    );

                                var notificationFailed = false;
                                if (dueDate != null &&
                                    _isDueWithinTwoDays(dueDate!)) {
                                  try {
                                    await ref
                                        .read(notificationsRepositoryProvider)
                                        .create(
                                          workspaceId: workspaceId,
                                          type: 'task_due',
                                          title: 'Client task due soon',
                                          body: '${widget.clientName}: $title',
                                          deepLink:
                                              workloopNotificationEntityRoute(
                                                WorkloopNotificationEntity.task,
                                                taskId,
                                              ),
                                        );
                                  } catch (_) {
                                    notificationFailed = true;
                                  }
                                }

                                ref.invalidate(
                                  clientTasksProvider(widget.clientId),
                                );
                                ref.invalidate(allTasksProvider);
                                ref.invalidate(tasksProvider);
                                ref.invalidate(clientCrmRecordsProvider);
                                ref.invalidate(notificationsProvider);
                                ref.invalidate(unreadNotificationsProvider);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (notificationFailed && mounted) {
                                  _snack(
                                    'Task added, but its in-app notification could not be created.',
                                    AppColors.of(context).warning,
                                  );
                                }
                              } catch (_) {
                                if (!ctx.mounted) {
                                  if (mounted) {
                                    _snack(
                                      'Couldn’t add this task. Nothing was saved. Please try again.',
                                      AppColors.of(context).error,
                                    );
                                  }
                                  return;
                                }
                                setModal(() {
                                  saving = false;
                                  error =
                                      'Couldn’t add this task. Nothing was saved. Please try again.';
                                });
                              }
                            },
                      child: saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: AppColors.of(ctx).onBrandAccent,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Add Task',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTask(SlateTask task) async {
    var deleting = false;
    String? deleteError;

    await showWorkloopBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => PopScope(
          canPop: !deleting,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete task?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.title,
                  style: TextStyle(fontSize: 14, color: AppColors.of(ctx).t3),
                  textAlign: TextAlign.center,
                ),
                if (deleteError != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      deleteError!,
                      style: TextStyle(
                        color: AppColors.of(ctx).error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _actionBtn(
                  ctx,
                  label: 'Delete Task',
                  color: AppColors.of(ctx).error,
                  loading: deleting,
                  onTap: () async {
                    if (deleting) return;
                    setModal(() {
                      deleting = true;
                      deleteError = null;
                    });
                    try {
                      await ref.read(tasksRepositoryProvider).delete(task.id);
                    } catch (_) {
                      if (!ctx.mounted) return;
                      setModal(() {
                        deleting = false;
                        deleteError =
                            'Couldn’t delete this task. Nothing was removed. Please try again.';
                      });
                      return;
                    }
                    ref.invalidate(clientTasksProvider(widget.clientId));
                    ref.invalidate(allTasksProvider);
                    ref.invalidate(tasksProvider);
                    ref.invalidate(clientCrmRecordsProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: TextButton(
                    onPressed: deleting ? null : () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.of(ctx).t3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTaskActions(SlateTask task) {
    final isDone = task.status == 'done';
    var mutating = false;
    String? actionError;
    showWorkloopBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => PopScope(
          canPop: !mutating,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDone ? AppColors.of(ctx).t3 : AppColors.of(ctx).t1,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.dueDate == null
                      ? 'No due date'
                      : _formatDue(task.dueDate!),
                  style: TextStyle(fontSize: 13, color: AppColors.of(ctx).t3),
                ),
                if (actionError != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      actionError!,
                      style: TextStyle(
                        color: AppColors.of(ctx).error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SlateButton(
                  label: mutating
                      ? (isDone ? 'Reopening…' : 'Completing…')
                      : (isDone ? 'Reopen Task' : 'Mark Complete'),
                  icon: isDone
                      ? LucideIcons.rotateCcw
                      : LucideIcons.checkCircle,
                  onPressed: mutating
                      ? null
                      : () async {
                          setModal(() {
                            mutating = true;
                            actionError = null;
                          });
                          try {
                            await ref
                                .read(tasksRepositoryProvider)
                                .updateStatus(
                                  task.id,
                                  isDone ? 'open' : 'done',
                                );
                            ref.invalidate(
                              clientTasksProvider(widget.clientId),
                            );
                            ref.invalidate(allTasksProvider);
                            ref.invalidate(tasksProvider);
                            ref.invalidate(clientCrmRecordsProvider);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (_) {
                            if (!ctx.mounted) return;
                            setModal(() {
                              mutating = false;
                              actionError = isDone
                                  ? 'Couldn’t reopen this task. Please try again.'
                                  : 'Couldn’t complete this task. Please try again.';
                            });
                          }
                        },
                ),
                const SizedBox(height: 10),
                SlateButton(
                  label: 'Delete Task',
                  destructive: true,
                  onPressed: mutating
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _confirmDeleteTask(task);
                          });
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(clientTasksProvider(widget.clientId));

    return tasks.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: AppColors.of(context).green),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SlateErrorState(
          message: 'Tasks could not be loaded.',
          onRetry: () => refreshClientTasks(ref, widget.clientId),
        ),
      ),
      data: (tks) => Column(
        children: [
          _TasksToolbar(
            openCount: tks.where((task) => task.status != 'done').length,
            onAdd: _showAddTaskSheet,
            onOpenTasks: () => context.push('/tasks'),
          ),
          if (tks.isEmpty)
            const Expanded(child: _EmptyState())
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => refreshClientTasks(ref, widget.clientId),
                color: AppColors.of(context).green,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    0,
                    AppSpacing.pageX,
                    40,
                  ),
                  itemCount: tks.length,
                  separatorBuilder: (_, _) => const SizedBox.shrink(),
                  itemBuilder: (context, i) {
                    final task = tks[i];
                    final isDone = task.status == 'done';
                    final dueDate = task.dueDate;

                    return WorkloopListRow(
                      onTap: () => _showTaskActions(task),
                      leading: AnimatedContainer(
                        key: ValueKey(Theme.of(context).brightness),
                        duration: AppMotion.responsive(
                          context,
                          AppMotion.standard,
                        ),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? AppColors.of(context).success
                              : Colors.transparent,
                          border: Border.all(
                            color: isDone
                                ? AppColors.of(context).success
                                : AppColors.of(context).border,
                            width: 2,
                          ),
                        ),
                        child: isDone
                            ? Icon(
                                Icons.check_rounded,
                                color: AppColors.of(context).bg,
                                size: 13,
                              )
                            : null,
                      ),
                      title: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDone
                              ? AppColors.of(context).t3
                              : AppColors.of(context).t1,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: dueDate == null
                          ? Text(
                              'No due date',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.of(context).t3,
                              ),
                            )
                          : Text(
                              _formatDue(dueDate),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.of(context).t3,
                              ),
                            ),
                      trailing: Text(
                        isDone ? 'Done' : 'Open',
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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

  // ── Date helpers ─────────────────────────────────────────────────────────────
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
    return '${dt.day} ${months[dt.month - 1]}';
  }

  String _formatDue(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    if (diff == -1) return 'Due yesterday';
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
    return '${dt.day} ${months[dt.month - 1]}';
  }

  bool _isDueWithinTwoDays(DateTime dueDate) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return !dueDateOnly.isAfter(todayDate.add(const Duration(days: 1)));
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TasksToolbar extends StatelessWidget {
  final int openCount;
  final VoidCallback onAdd;
  final VoidCallback onOpenTasks;

  const _TasksToolbar({
    required this.openCount,
    required this.onAdd,
    required this.onOpenTasks,
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
          Text(
            '$openCount open',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          WorkloopTextButton(label: 'Open Tasks', onPressed: onOpenTasks),
          WorkloopTextButton(label: 'New task', onPressed: onAdd),
        ],
      ),
    );
  }
}

// ── Priority chip ─────────────────────────────────────────────────────────────
class _PriorityChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final String selected;
  final Function(String) onTap;

  const _PriorityChip({
    required this.value,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return Semantics(
      button: true,
      selected: active,
      label: '$label priority',
      onTap: () => onTap(value),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(value),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.15)
                  : AppColors.of(context).bgInteract,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: active ? color : Colors.transparent),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? color : AppColors.of(context).t2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkloopEmptyState(
            icon: LucideIcons.checkSquare,
            title: 'No tasks yet.',
            subtitle: 'Client tasks will appear here.',
          ),
        ],
      ),
    );
  }
}

Widget _actionBtn(
  BuildContext context, {
  required String label,
  required VoidCallback? onTap,
  bool loading = false,
  Color? color,
}) {
  final colors = AppColors.of(context);
  final resolvedColor = color ?? colors.brandAccent;
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: resolvedColor,
        foregroundColor: resolvedColor == colors.error
            ? colors.bg
            : colors.onBrandAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        elevation: 0,
      ),
      child: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: colors.bg,
                strokeWidth: 2,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
    ),
  );
}
