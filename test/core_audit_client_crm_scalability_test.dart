import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/repositories/clients_repository.dart';
import 'package:workloop/shared/repositories/payments_repository.dart';
import 'package:workloop/shared/repositories/tasks_repository.dart';

void main() {
  group('client CRM aggregation', () {
    test(
      'pre-grouped aggregation is equivalent to the prior scan semantics',
      () {
        final now = DateTime(2026, 7, 26, 12);
        final clients = const [
          Client(
            id: 'client-empty',
            workspaceId: 'workspace-1',
            name: 'No relations',
          ),
          Client(id: 'client-a', workspaceId: 'workspace-1', name: 'Ada'),
          Client(id: 'client-b', workspaceId: 'workspace-1', name: 'Ben'),
        ];
        final appointments = [
          _appointment(
            'a-completed',
            'client-a',
            DateTime(2026, 7, 20),
            'completed',
          ),
          _appointment(
            'a-last-no-show',
            'client-a',
            DateTime(2026, 7, 25),
            'no_show',
          ),
          _appointment('a-next', 'client-a', now, 'scheduled'),
          _appointment(
            'a-future-completed',
            'client-a',
            DateTime(2026, 7, 27),
            'completed',
          ),
          _appointment(
            'a-later',
            'client-a',
            DateTime(2026, 7, 28),
            'scheduled',
          ),
          _appointment(
            'b-past',
            'client-b',
            DateTime(2026, 7, 24),
            'scheduled',
          ),
          _appointment(
            'orphan-appointment',
            'unknown-client',
            DateTime(2026, 7, 27),
            'scheduled',
          ),
          Appointment(
            id: 'unlinked-appointment',
            workspaceId: 'workspace-1',
            startTime: DateTime(2026, 7, 27),
            status: 'scheduled',
          ),
        ];
        final payments = [
          _payment('a-paid', 'client-a', 'paid', 100),
          _payment('a-partial', 'client-a', 'sent', 120, amountPaid: 40),
          _payment('a-collected', 'client-a', 'sent', 50, amountPaid: 50),
          _payment('b-refund', 'client-b', 'paid', -20),
          _payment('orphan-payment', 'unknown-client', 'sent', 80),
          _payment('unlinked-payment', null, 'sent', 70),
        ];
        final tasks = [
          _task('a-overdue', 'client-a', 'open', DateTime(2026, 7, 25)),
          _task('a-today', 'client-a', 'open', DateTime(2026, 7, 26)),
          _task('a-done', 'client-a', 'done', DateTime(2026, 7, 20)),
          _task('b-anytime', 'client-b', 'open', null),
          _task('orphan-task', 'unknown-client', 'open', DateTime(2026, 7, 20)),
          _task('unlinked-task', null, 'open', DateTime(2026, 7, 20)),
        ];

        final expected = _referenceBuildClientCrmRecords(
          clients: clients,
          appointments: appointments,
          payments: payments,
          tasks: tasks,
          now: now,
        ).map(_snapshot).toList();
        final actual = buildClientCrmRecords(
          clients: clients,
          appointments: appointments,
          payments: payments,
          tasks: tasks,
          now: now,
        ).map(_snapshot).toList();

        expect(actual, expected);
        expect(
          actual.map((record) => record.clientId),
          ['client-empty', 'client-a', 'client-b'],
          reason: 'Input client order must remain unchanged.',
        );
      },
    );

    test('provider starts all four independent reads concurrently', () async {
      final release = Completer<void>();
      final clientsStarted = Completer<void>();
      final appointmentsStarted = Completer<void>();
      final paymentsStarted = Completer<void>();
      final tasksStarted = Completer<void>();
      final client = _testSupabaseClient();
      final container = ProviderContainer(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
          clientsRepositoryProvider.overrideWithValue(
            _BlockingClientsRepository(client, clientsStarted, release),
          ),
          appointmentsRepositoryProvider.overrideWithValue(
            _BlockingAppointmentsRepository(
              client,
              appointmentsStarted,
              release,
            ),
          ),
          paymentsRepositoryProvider.overrideWithValue(
            _BlockingPaymentsRepository(client, paymentsStarted, release),
          ),
          tasksRepositoryProvider.overrideWithValue(
            _BlockingTasksRepository(client, tasksStarted, release),
          ),
        ],
      );
      addTearDown(() {
        if (!release.isCompleted) release.complete();
        container.dispose();
      });

      final recordsFuture = container.read(clientCrmRecordsProvider.future);
      await Future.wait([
        clientsStarted.future,
        appointmentsStarted.future,
        paymentsStarted.future,
        tasksStarted.future,
      ]).timeout(const Duration(seconds: 2));
      release.complete();

      expect(await recordsFuture, isEmpty);
    });

    test('10,000 clients with one related row each stays linear', () {
      const count = 10000;
      final now = DateTime(2026, 7, 26, 12);
      final clients = List.generate(
        count,
        (index) => Client(
          id: 'client-$index',
          workspaceId: 'workspace-1',
          name: 'Client $index',
        ),
        growable: false,
      );
      final appointments = List.generate(
        count,
        (index) => _appointment(
          'appointment-$index',
          'client-$index',
          DateTime(2026, 7, 27, 9),
          'scheduled',
        ),
        growable: false,
      );
      final payments = List.generate(count, (index) {
        final amount = (index % 100 + 1).toDouble();
        return _payment(
          'payment-$index',
          'client-$index',
          'paid',
          amount,
          amountPaid: amount,
        );
      }, growable: false);
      final tasks = List.generate(
        count,
        (index) => _task(
          'task-$index',
          'client-$index',
          'open',
          DateTime(2026, 7, 25),
        ),
        growable: false,
      );

      final stopwatch = Stopwatch()..start();
      final records = buildClientCrmRecords(
        clients: clients,
        appointments: appointments,
        payments: payments,
        tasks: tasks,
        now: now,
      );
      stopwatch.stop();
      final elapsed = stopwatch.elapsed;

      expect(records, hasLength(count));
      expect(
        records.indexed.every((entry) {
          final index = entry.$1;
          final record = entry.$2;
          return record.client.id == 'client-$index' &&
              record.bookingCount == 1 &&
              record.completedBookingCount == 0 &&
              record.nextBooking?.id == 'appointment-$index' &&
              record.lastBooking == null &&
              record.lifetimeValue == (index % 100 + 1).toDouble() &&
              record.outstandingBalance == 0 &&
              record.openTaskCount == 1 &&
              record.overdueTaskCount == 1;
        }),
        isTrue,
      );
      expect(
        elapsed,
        lessThan(const Duration(seconds: 5)),
        reason:
            '10,000-client aggregation took ${elapsed.inMilliseconds} ms; '
            'this guard is intentionally generous.',
      );
    });
  });
}

SupabaseClient _testSupabaseClient() {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

class _BlockingClientsRepository extends ClientsRepository {
  final Completer<void> started;
  final Completer<void> release;

  _BlockingClientsRepository(super.client, this.started, this.release);

  @override
  Future<List<Client>> list(String workspaceId) async {
    started.complete();
    await release.future;
    return const [];
  }
}

class _BlockingAppointmentsRepository extends AppointmentsRepository {
  final Completer<void> started;
  final Completer<void> release;

  _BlockingAppointmentsRepository(super.client, this.started, this.release);

  @override
  Future<List<Map<String, dynamic>>> listRows(String workspaceId) async {
    started.complete();
    await release.future;
    return const [];
  }
}

class _BlockingPaymentsRepository extends PaymentsRepository {
  final Completer<void> started;
  final Completer<void> release;

  _BlockingPaymentsRepository(super.client, this.started, this.release);

  @override
  Future<List<Payment>> list(String workspaceId) async {
    started.complete();
    await release.future;
    return const [];
  }
}

class _BlockingTasksRepository extends TasksRepository {
  final Completer<void> started;
  final Completer<void> release;

  _BlockingTasksRepository(super.client, this.started, this.release);

  @override
  Future<List<SlateTask>> list(String workspaceId) async {
    started.complete();
    await release.future;
    return const [];
  }
}

typedef _CrmSnapshot = ({
  String clientId,
  int bookingCount,
  int completedBookingCount,
  String? nextBookingId,
  String? lastBookingId,
  double lifetimeValue,
  double outstandingBalance,
  int openTaskCount,
  int overdueTaskCount,
});

_CrmSnapshot _snapshot(ClientCrmRecord record) {
  return (
    clientId: record.client.id,
    bookingCount: record.bookingCount,
    completedBookingCount: record.completedBookingCount,
    nextBookingId: record.nextBooking?.id,
    lastBookingId: record.lastBooking?.id,
    lifetimeValue: record.lifetimeValue,
    outstandingBalance: record.outstandingBalance,
    openTaskCount: record.openTaskCount,
    overdueTaskCount: record.overdueTaskCount,
  );
}

List<ClientCrmRecord> _referenceBuildClientCrmRecords({
  required Iterable<Client> clients,
  required Iterable<Appointment> appointments,
  required Iterable<Payment> payments,
  required Iterable<SlateTask> tasks,
  required DateTime now,
}) {
  return clients.map((client) {
    final clientAppointments = appointments
        .where((item) => item.contactId == client.id)
        .toList();
    final clientPayments = payments
        .where((item) => item.contactId == client.id)
        .toList();
    final clientTasks = tasks
        .where((item) => item.contactId == client.id)
        .toList();
    final futureAppointments =
        clientAppointments
            .where(
              (item) =>
                  !item.startTime.isBefore(now) &&
                  !const {
                    'cancelled',
                    'no_show',
                    'completed',
                  }.contains(item.status.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final pastAppointments =
        clientAppointments
            .where((item) => item.startTime.isBefore(now))
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

    return ClientCrmRecord(
      client: client,
      bookingCount: clientAppointments.length,
      completedBookingCount: clientAppointments
          .where((item) => item.status == 'completed')
          .length,
      nextBooking: futureAppointments.isEmpty ? null : futureAppointments.first,
      lastBooking: pastAppointments.isEmpty ? null : pastAppointments.first,
      lifetimeValue: clientPayments.fold<double>(
        0,
        (sum, item) => sum + item.collectedAmount,
      ),
      outstandingBalance: clientPayments.fold<double>(
        0,
        (sum, item) => sum + item.outstandingAmount,
      ),
      openTaskCount: clientTasks.where((item) => item.status != 'done').length,
      overdueTaskCount: clientTasks
          .where(
            (item) =>
                item.status != 'done' && _referenceIsOverdue(item.dueDate, now),
          )
          .length,
    );
  }).toList();
}

bool _referenceIsOverdue(DateTime? date, DateTime now) {
  if (date == null) return false;
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(date.year, date.month, date.day);
  return dueDay.isBefore(today);
}

Appointment _appointment(
  String id,
  String? contactId,
  DateTime startTime,
  String status,
) {
  return Appointment(
    id: id,
    workspaceId: 'workspace-1',
    contactId: contactId,
    startTime: startTime,
    status: status,
  );
}

Payment _payment(
  String id,
  String? contactId,
  String status,
  double total, {
  double amountPaid = 0,
}) {
  return Payment(
    id: id,
    workspaceId: 'workspace-1',
    contactId: contactId,
    number: id,
    status: status,
    issueDate: DateTime(2026, 7, 1),
    total: total,
    amountPaid: amountPaid,
  );
}

SlateTask _task(
  String id,
  String? contactId,
  String status,
  DateTime? dueDate,
) {
  return SlateTask(
    id: id,
    workspaceId: 'workspace-1',
    contactId: contactId,
    title: id,
    status: status,
    dueDate: dueDate,
  );
}
