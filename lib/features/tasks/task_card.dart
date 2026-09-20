part of 'tasks_screen.dart';

class _TaskCard extends StatelessWidget {
  final SlateTask task;
  final VoidCallback onOpen;
  final VoidCallback onCompleteRequest;
  final VoidCallback onReopen;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onOpen,
    required this.onCompleteRequest,
    required this.onReopen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';
    final priorityColor = _priorityColor(context, task.priority);
    final dueLabel = task.dueDate == null ? null : _formatDue(task.dueDate!);
    final dueColor =
        !isDone && task.dueDate != null && _isOverdue(task.dueDate!)
        ? AppColors.of(context).error
        : AppColors.of(context).t3;

    return Dismissible(
      key: ValueKey(task.id),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (isDone) {
            onReopen();
          } else {
            onCompleteRequest();
          }
        } else {
          onDelete();
        }
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        icon: isDone ? LucideIcons.rotateCcw : LucideIcons.checkCircle,
        label: isDone ? 'Reopen' : 'Complete',
        color: AppColors.of(context).success,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        icon: LucideIcons.trash2,
        label: 'Delete',
        color: AppColors.of(context).error,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.of(context).t1.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                button: true,
                checked: isDone,
                label: isDone
                    ? 'Reopen ${task.title}'
                    : 'Complete ${task.title}',
                onTap: isDone ? onReopen : onCompleteRequest,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isDone ? onReopen : onCompleteRequest,
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
                          width: 24,
                          height: 24,
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
                                  size: 14,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDone
                                  ? AppColors.of(context).t3
                                  : AppColors.of(context).t1,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _PriorityDot(
                          color: isDone
                              ? AppColors.of(context).t3
                              : priorityColor,
                        ),
                      ],
                    ),
                    if (dueLabel != null || task.clientName != null) ...[
                      const SizedBox(height: 5),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (dueLabel != null)
                              TextSpan(
                                text: dueLabel,
                                style: TextStyle(color: dueColor),
                              ),
                            if (dueLabel != null && task.clientName != null)
                              const TextSpan(text: '  ·  '),
                            if (task.clientName != null)
                              TextSpan(text: task.clientName!),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.of(context).t3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.of(context).t3,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color color;

  const _SwipeBackground({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: color.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: alignment == Alignment.centerLeft
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  final Color color;
  const _PriorityDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
