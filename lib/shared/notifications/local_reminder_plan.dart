import '../models/slate_models.dart';
import 'notification_route.dart';

const workloopReminderPayloadPrefix = 'workloop-reminder:';
const workloopMaximumPendingReminders = 60;

enum LocalReminderKind { task, booking }

class LocalReminderPlan {
  final int id;
  final String key;
  final LocalReminderKind kind;
  final DateTime scheduledAtUtc;
  final String title;
  final String body;
  final String route;

  const LocalReminderPlan({
    required this.id,
    required this.key,
    required this.kind,
    required this.scheduledAtUtc,
    required this.title,
    required this.body,
    required this.route,
  });

  String get payload => '$workloopReminderPayloadPrefix$route';
}

LocalReminderPlan? planTaskReminder(SlateTask task, {required DateTime now}) {
  if (task.status != 'open' ||
      task.dueDate == null ||
      task.reminderTiming == 'none') {
    return null;
  }

  final localNow = now.toLocal();
  final due = task.dueDate!.toLocal();
  final dueDay = DateTime(due.year, due.month, due.day);
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  if (dueDay.isBefore(today)) return null;

  final daysBefore = switch (task.reminderTiming) {
    'today' => 0,
    'day_before' => 1,
    'week_before' => 7,
    _ => null,
  };
  if (daysBefore == null) return null;

  final reminderAt = DateTime(
    dueDay.year,
    dueDay.month,
    dueDay.day - daysBefore,
    9,
  );
  if (!reminderAt.isAfter(localNow)) return null;

  final title = switch (daysBefore) {
    0 => 'Task due today',
    1 => 'Task due tomorrow',
    _ => 'Task reminder',
  };
  final key = 'task:${task.id}';

  return LocalReminderPlan(
    id: stableLocalReminderId(key),
    key: key,
    kind: LocalReminderKind.task,
    scheduledAtUtc: reminderAt.toUtc(),
    title: title,
    body: 'Open Workloop to review this task.',
    route: workloopNotificationEntityRoute(
      WorkloopNotificationEntity.task,
      task.id,
    ),
  );
}

LocalReminderPlan? planBookingReminder(
  Appointment appointment, {
  required DateTime now,
}) {
  if (appointment.status != 'scheduled') return null;

  final reminderAt = appointment.startTime.toLocal().subtract(
    const Duration(minutes: 15),
  );
  if (!reminderAt.isAfter(now.toLocal())) return null;

  final key = 'booking:${appointment.id}';

  return LocalReminderPlan(
    id: stableLocalReminderId(key),
    key: key,
    kind: LocalReminderKind.booking,
    scheduledAtUtc: reminderAt.toUtc(),
    title: 'Booking in about 15 minutes',
    body: 'Open Workloop to review this booking.',
    route: workloopNotificationEntityRoute(
      WorkloopNotificationEntity.booking,
      appointment.id,
    ),
  );
}

List<LocalReminderPlan> buildLocalReminderPlans({
  required List<SlateTask> tasks,
  required List<Appointment> appointments,
  required bool bookingRemindersEnabled,
  required DateTime now,
}) {
  final plans = <LocalReminderPlan>[
    for (final task in tasks) ?planTaskReminder(task, now: now),
    if (bookingRemindersEnabled)
      for (final appointment in appointments)
        ?planBookingReminder(appointment, now: now),
  ]..sort((a, b) => a.scheduledAtUtc.compareTo(b.scheduledAtUtc));

  return plans.take(workloopMaximumPendingReminders).toList(growable: false);
}

int stableLocalReminderId(String key) {
  var hash = 0x811c9dc5;
  for (final codeUnit in key.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

String? routeFromReminderPayload(String? payload) {
  if (payload == null || !payload.startsWith(workloopReminderPayloadPrefix)) {
    return null;
  }
  final route = payload.substring(workloopReminderPayloadPrefix.length);
  return workloopNotificationRoute(route);
}
