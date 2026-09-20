part of 'tasks_screen.dart';

class _TaskDetailStatus extends StatelessWidget {
  final bool loading;
  final VoidCallback onRetry;

  const _TaskDetailStatus({required this.loading, required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Stack(
      children: [
        const Positioned.fill(child: WorkloopTexturedBackdrop()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageX,
              AppSpacing.screenTop,
              AppSpacing.pageX,
              AppSpacing.lg,
            ),
            child: Column(
              children: [
                const WorkloopRouteHeader(title: 'Task'),
                Expanded(
                  child: Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : SlateErrorState(
                            message:
                                'Could not refresh this task. Try again before making changes.',
                            onRetry: onRetry,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _TaskContextPanel extends StatelessWidget {
  final SlateTask task;
  final VoidCallback? onOpenClient;
  final VoidCallback? onOpenBooking;

  const _TaskContextPanel({
    required this.task,
    this.onOpenClient,
    this.onOpenBooking,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TaskContextRow(
          icon: LucideIcons.calendarClock,
          label: 'Timing',
          value: task.dueDate == null
              ? 'No due date'
              : _formatDue(task.dueDate!),
        ),
        const SizedBox(height: 12),
        _TaskContextRow(
          icon: LucideIcons.user,
          label: 'Client',
          value:
              task.clientName ??
              (task.contactId == null ? 'Not linked' : 'View client'),
          onTap: onOpenClient,
        ),
        if (onOpenBooking != null) ...[
          const SizedBox(height: 12),
          _TaskContextRow(
            icon: LucideIcons.calendar,
            label: 'Booking',
            value: 'View linked booking',
            onTap: onOpenBooking,
          ),
        ],
        const SizedBox(height: 12),
        _TaskContextRow(
          icon: LucideIcons.bell,
          label: 'Reminder',
          value: _reminderLabel(task.reminderTiming),
        ),
        if (task.updatedAt != null || task.createdAt != null) ...[
          const SizedBox(height: 12),
          _TaskContextRow(
            icon: LucideIcons.history,
            label: task.updatedAt != null ? 'Updated' : 'Created',
            value: _formatDate(task.updatedAt ?? task.createdAt!),
          ),
        ],
      ],
    );
  }
}

class _TaskContextRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _TaskContextRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopListRow(
      flat: true,
      showDivider: false,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      onTap: onTap,
      leading: Icon(icon, size: 18, color: AppColors.of(context).t3),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.of(context).t3,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.of(context).t2,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: onTap == null
          ? null
          : Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: AppColors.of(context).t3,
            ),
    );
  }
}

class _TaskChecklistPanel extends StatelessWidget {
  final AsyncValue<List<TaskChecklistItem>> items;
  final VoidCallback onAdd;
  final VoidCallback onRetry;
  final ValueChanged<TaskChecklistItem> onToggle;
  final ValueChanged<TaskChecklistItem> onEdit;
  final ValueChanged<TaskChecklistItem> onDelete;

  const _TaskChecklistPanel({
    required this.items,
    required this.onAdd,
    required this.onRetry,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.listChecks,
              size: 16,
              color: AppColors.of(context).t3,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Checklist',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.of(context).t1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            WorkloopTextButton(label: 'Add', onPressed: onAdd),
          ],
        ),
        const SizedBox(height: 12),
        items.when(
          loading: () =>
              const SlateLoadingBlock(height: 48, radius: AppRadius.md),
          error: (_, _) => SlateErrorState(
            message: 'Checklist could not load.',
            onRetry: onRetry,
          ),
          data: (data) {
            if (data.isEmpty) {
              return Text(
                'Break this task into smaller steps.',
                style: TextStyle(color: AppColors.of(context).t3, fontSize: 13),
              );
            }
            return Column(
              children: data
                  .map(
                    (item) => _ChecklistRow(
                      item: item,
                      onToggle: () => onToggle(item),
                      onEdit: () => onEdit(item),
                      onDelete: () => onDelete(item),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final TaskChecklistItem item;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ChecklistRow({
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            checked: item.completed,
            label: item.completed
                ? 'Mark ${item.title} incomplete'
                : 'Mark ${item.title} complete',
            onTap: onToggle,
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: SizedBox(
                  width: AppSpacing.minTouch,
                  height: AppSpacing.minTouch,
                  child: Center(
                    child: AnimatedContainer(
                      key: ValueKey(Theme.of(context).brightness),
                      duration: AppMotion.responsive(
                        context,
                        AppMotion.standard,
                      ),
                      curve: AppMotion.curve,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: item.completed
                            ? AppColors.of(context).success
                            : Colors.transparent,
                        border: Border.all(
                          color: item.completed
                              ? AppColors.of(context).success
                              : AppColors.of(context).border,
                          width: 2,
                        ),
                      ),
                      child: item.completed
                          ? Icon(
                              Icons.check_rounded,
                              color: AppColors.of(context).bg,
                              size: 13,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onEdit,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTouch,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.completed
                          ? AppColors.of(context).t3
                          : AppColors.of(context).t1,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Remove ${item.title} from checklist',
            child: WorkloopIconButton(
              icon: LucideIcons.x,
              semanticLabel: 'Remove ${item.title} from checklist',
              size: AppSpacing.minTouch,
              onTap: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}
