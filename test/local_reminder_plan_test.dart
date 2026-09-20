import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/notifications/local_reminder_plan.dart';

void main() {
  group('task reminder planning', () {
    test('plans the selected reminder day at 09:00 local time', () {
      final task = SlateTask(
        id: '11000000-0000-4000-8000-000000000001',
        workspaceId: 'workspace-1',
        title: 'Confirm tomorrow’s client',
        dueDate: DateTime(2026, 7, 28),
        reminderTiming: 'day_before',
      );

      final plan = planTaskReminder(task, now: DateTime(2026, 7, 25, 12));

      expect(plan, isNotNull);
      final local = plan!.scheduledAtUtc.toLocal();
      expect(
        (local.year, local.month, local.day, local.hour, local.minute),
        (2026, 7, 27, 9, 0),
      );
      expect(plan.route, '/tasks/11000000-0000-4000-8000-000000000001');
      expect(
        plan.payload,
        'workloop-reminder:/tasks/11000000-0000-4000-8000-000000000001',
      );
      expect(plan.body, 'Open Workloop to review this task.');
    });

    test('task title describes the firing day, not the earlier setup day', () {
      for (final timing in ['today', 'day_before']) {
        final task = SlateTask(
          id: 'task-future',
          workspaceId: 'workspace-1',
          title: 'Future task',
          dueDate: DateTime(2026, 10, 26),
          reminderTiming: timing,
        );
        final plan = planTaskReminder(task, now: DateTime(2026, 10, 23, 8));
        expect(
          plan!.title,
          timing == 'today' ? 'Task due today' : 'Task due tomorrow',
        );
        final local = plan.scheduledAtUtc.toLocal();
        expect(local.hour, 9);
        expect(local.day, timing == 'today' ? 26 : 25);
      }
    });

    test('does not pretend a passed 09:00 slot can still be scheduled', () {
      final task = SlateTask(
        id: 'task-2',
        workspaceId: 'workspace-1',
        title: 'Send receipt',
        dueDate: DateTime(2026, 7, 25),
        reminderTiming: 'today',
        updatedAt: DateTime(2026, 7, 25, 14, 59, 45),
      );

      final plan = planTaskReminder(task, now: DateTime(2026, 7, 25, 15));

      expect(plan, isNull);
    });

    test('does not schedule completed, past, or unselected reminders', () {
      final now = DateTime(2026, 7, 25, 8);
      final base = SlateTask(
        id: 'task-3',
        workspaceId: 'workspace-1',
        title: 'Follow up',
        dueDate: DateTime(2026, 7, 26),
        reminderTiming: 'today',
      );

      expect(
        planTaskReminder(
          SlateTask(
            id: base.id,
            workspaceId: base.workspaceId,
            title: base.title,
            status: 'done',
            dueDate: base.dueDate,
            reminderTiming: base.reminderTiming,
          ),
          now: now,
        ),
        isNull,
      );
      expect(
        planTaskReminder(
          SlateTask(
            id: base.id,
            workspaceId: base.workspaceId,
            title: base.title,
            dueDate: DateTime(2026, 7, 24),
            reminderTiming: base.reminderTiming,
          ),
          now: now,
        ),
        isNull,
      );
      expect(
        planTaskReminder(
          SlateTask(
            id: base.id,
            workspaceId: base.workspaceId,
            title: base.title,
            dueDate: base.dueDate,
          ),
          now: now,
        ),
        isNull,
      );
    });
  });

  group('booking reminder planning', () {
    test('plans a scheduled booking about 15 minutes beforehand', () {
      final booking = Appointment(
        id: '12000000-0000-4000-8000-000000000001',
        workspaceId: 'workspace-1',
        startTime: DateTime(2026, 7, 26, 12),
        serviceName: 'Haircut',
        clientName: 'Sam',
      );

      final plan = planBookingReminder(booking, now: DateTime(2026, 7, 25, 12));

      expect(plan, isNotNull);
      final local = plan!.scheduledAtUtc.toLocal();
      expect((local.hour, local.minute), (11, 45));
      expect(plan.body, 'Open Workloop to review this booking.');
      expect(plan.route, '/bookings/12000000-0000-4000-8000-000000000001');
    });

    test('ignores cancelled and already-starting bookings', () {
      final now = DateTime(2026, 7, 25, 12);

      expect(
        planBookingReminder(
          Appointment(
            id: 'booking-2',
            workspaceId: 'workspace-1',
            startTime: DateTime(2026, 7, 26, 12),
            status: 'cancelled',
          ),
          now: now,
        ),
        isNull,
      );
      expect(
        planBookingReminder(
          Appointment(
            id: 'booking-3',
            workspaceId: 'workspace-1',
            startTime: DateTime(2026, 7, 25, 12, 10),
          ),
          now: now,
        ),
        isNull,
      );
    });
  });

  test('caps pending reminders to the earliest 60', () {
    final now = DateTime(2026, 7, 25, 12);
    final bookings = List.generate(
      65,
      (index) => Appointment(
        id: 'booking-$index',
        workspaceId: 'workspace-1',
        startTime: now.add(Duration(hours: index + 2)),
      ),
    );

    final plans = buildLocalReminderPlans(
      tasks: const [],
      appointments: bookings.reversed.toList(),
      bookingRemindersEnabled: true,
      now: now,
    );

    expect(plans, hasLength(workloopMaximumPendingReminders));
    expect(plans.first.key, 'booking:booking-0');
    expect(plans.last.key, 'booking:booking-59');
  });

  test('stable ids and payload parsing are deterministic', () {
    expect(
      stableLocalReminderId('task:abc'),
      stableLocalReminderId('task:abc'),
    );
    expect(stableLocalReminderId('task:abc'), isNot(0));
    expect(
      routeFromReminderPayload(
        'workloop-reminder:/tasks/11000000-0000-4000-8000-000000000001',
      ),
      '/tasks/11000000-0000-4000-8000-000000000001',
    );
    expect(
      routeFromReminderPayload('workloop-reminder:/tasks/not-an-id'),
      isNull,
    );
    expect(routeFromReminderPayload('unrelated:/tasks'), isNull);
  });
}
