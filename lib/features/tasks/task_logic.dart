part of 'tasks_screen.dart';

enum _TaskView { now, later, done }

enum _TaskEditorExit { save, discard, keepEditing }

class _TaskSection {
  final String title;
  final List<SlateTask> tasks;

  const _TaskSection({required this.title, required this.tasks});
}

class _TaskCounts {
  final int overdue;
  final int today;
  final int upcoming;
  final int noDate;
  final int done;
  final int open;

  const _TaskCounts({
    required this.overdue,
    required this.today,
    required this.upcoming,
    required this.noDate,
    required this.done,
    required this.open,
  });

  int get now => overdue + today + noDate;
}

class _TaskTemplate {
  final String label;
  final String title;
  final String priority;
  final int? dueInDays;

  const _TaskTemplate({
    required this.label,
    required this.title,
    required this.priority,
    this.dueInDays,
  });
}

const _taskTemplates = [
  _TaskTemplate(
    label: 'Follow up',
    title: 'Follow up with client',
    priority: 'medium',
    dueInDays: 1,
  ),
  _TaskTemplate(
    label: 'Chase payment',
    title: 'Chase outstanding payment',
    priority: 'high',
    dueInDays: 0,
  ),
  _TaskTemplate(
    label: 'Prep booking',
    title: 'Prep for booking',
    priority: 'medium',
    dueInDays: 0,
  ),
  _TaskTemplate(
    label: 'Book again',
    title: 'Ask client to book again',
    priority: 'low',
    dueInDays: 7,
  ),
];

List<_TaskSection> _sectionsForView(List<SlateTask> tasks, _TaskView view) {
  final open = tasks.where((task) => task.status != 'done').toList();
  final done = tasks.where((task) => task.status == 'done').toList();
  final overdue = open.where(_isOverdueTask).toList();
  final today = open.where(_isTodayTask).toList();
  final upcoming = open.where(_isUpcomingTask).toList();
  final noDate = open.where((task) => task.dueDate == null).toList();

  switch (view) {
    case _TaskView.now:
      return [
        _TaskSection(title: 'Overdue', tasks: overdue),
        _TaskSection(title: 'Today', tasks: today),
        _TaskSection(title: 'Anytime', tasks: noDate),
      ];
    case _TaskView.later:
      return [
        _TaskSection(
          title: 'Next 7 days',
          tasks: upcoming.where(_isWithinWeekTask).toList(),
        ),
        _TaskSection(
          title: 'Later',
          tasks: upcoming.where((task) => !_isWithinWeekTask(task)).toList(),
        ),
      ];
    case _TaskView.done:
      return [_TaskSection(title: 'Completed', tasks: done)];
  }
}

_TaskCounts _countsForTasks(List<SlateTask> tasks) {
  final open = tasks.where((task) => task.status != 'done').toList();
  final done = tasks.where((task) => task.status == 'done').length;
  final overdue = open.where(_isOverdueTask).length;
  final today = open.where(_isTodayTask).length;
  final upcoming = open.where(_isUpcomingTask).length;
  final noDate = open.where((task) => task.dueDate == null).length;

  return _TaskCounts(
    overdue: overdue,
    today: today,
    upcoming: upcoming,
    noDate: noDate,
    done: done,
    open: open.length,
  );
}

int _taskSort(SlateTask a, SlateTask b) {
  return compareTasksForDisplay(a, b);
}

Color _priorityColor(BuildContext context, String priority) {
  return switch (priority) {
    'high' => AppColors.of(context).error,
    'medium' => AppColors.of(context).warning,
    _ => AppColors.of(context).t3,
  };
}

String _priorityLabel(String priority) {
  return switch (priority) {
    'high' => 'High',
    'medium' => 'Medium',
    _ => 'Low',
  };
}

String _reminderLabel(String reminderTiming) {
  return switch (reminderTiming) {
    'today' => 'On due day',
    'day_before' => 'Day before',
    'week_before' => 'Week before',
    _ => 'No reminder',
  };
}

String _viewLabel(_TaskView view) {
  return switch (view) {
    _TaskView.now => 'Now',
    _TaskView.later => 'Later',
    _TaskView.done => 'Done',
  };
}

int _viewCount(_TaskView view, _TaskCounts counts) {
  return switch (view) {
    _TaskView.now => counts.now,
    _TaskView.later => counts.upcoming,
    _TaskView.done => counts.done,
  };
}

bool _isOverdueTask(SlateTask task) {
  return taskDateBucketFor(task) == TaskDateBucket.overdue;
}

bool _isTodayTask(SlateTask task) {
  return taskDateBucketFor(task) == TaskDateBucket.today;
}

bool _isUpcomingTask(SlateTask task) {
  return taskDateBucketFor(task) == TaskDateBucket.upcoming;
}

bool _isWithinWeekTask(SlateTask task) {
  return taskIsWithinNextSevenDays(task);
}

bool _isOverdue(DateTime dt) =>
    _dateOnly(dt).isBefore(_dateOnly(DateTime.now()));

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String _formatDue(DateTime dt) {
  final today = _dateOnly(DateTime.now());
  final d = _dateOnly(dt);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  if (diff == -1) return 'Due yesterday';
  if (diff < 0) return 'Overdue ${-diff}d';
  return _formatDate(dt);
}

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
