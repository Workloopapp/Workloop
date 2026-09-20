import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/booking_requests_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';

void main() {
  group('dashboard attention composer', () {
    test('builds and sorts attention items from existing app data', () {
      final now = DateTime(2026, 7, 6, 9);
      final items = buildDashboardAttentionItems(
        now: now,
        bookingRequests: const [
          BookingRequest(
            id: 'request-1',
            workspaceId: 'workspace-1',
            name: 'Alex',
            phone: '',
          ),
          BookingRequest(
            id: 'request-2',
            workspaceId: 'workspace-1',
            name: 'Jamie',
            phone: '',
          ),
        ],
        payments: [
          Payment.fromMap({
            'id': 'payment-overdue',
            'workspace_id': 'workspace-1',
            'invoice_number': 'PAY-001',
            'status': 'sent',
            'issue_date': '2026-06-28',
            'due_date': '2026-07-01',
            'total': 160,
            'contacts': {'name': 'Ahmed'},
          }),
          Payment.fromMap({
            'id': 'payment-recent',
            'workspace_id': 'workspace-1',
            'invoice_number': 'PAY-002',
            'status': 'sent',
            'issue_date': '2026-07-04',
            'due_date': '2026-07-04',
            'total': 80,
          }),
        ],
        tasks: [
          SlateTask.fromMap({
            'id': 'task-overdue',
            'workspace_id': 'workspace-1',
            'title': 'Send follow-up',
            'status': 'open',
            'due_date': '2026-07-05',
          }),
        ],
        appointments: [
          for (final date in ['2026-05-01', '2026-04-03', '2026-03-06'])
            {
              'id': 'regular-$date',
              'workspace_id': 'workspace-1',
              'contact_id': 'client-dormant',
              'start_time': '${date}T09:00:00',
              'status': 'completed',
            },
          {
            'id': 'appointment-upcoming',
            'workspace_id': 'workspace-1',
            'contact_id': 'client-booked',
            'start_time': '2026-07-06T18:00:00',
            'end_time': '2026-07-06T19:00:00',
            'status': 'scheduled',
            'contacts': {'name': 'Sarah'},
            'services': {'name': 'Consultation'},
          },
        ],
        clients: [
          Client.fromMap({
            'id': 'lead-stale',
            'workspace_id': 'workspace-1',
            'name': 'Maya',
            'status': 'lead',
            'created_at': '2026-06-20T09:00:00',
          }),
          Client.fromMap({
            'id': 'client-dormant',
            'workspace_id': 'workspace-1',
            'name': 'Omar',
            'status': 'active',
            'last_activity_at': '2026-05-01T09:00:00',
          }),
          Client.fromMap({
            'id': 'client-booked',
            'workspace_id': 'workspace-1',
            'name': 'Sarah',
            'status': 'active',
            'last_activity_at': '2026-05-01T09:00:00',
          }),
        ],
      );

      expect(
        items.map((item) => item.type),
        containsAll([
          DashboardAttentionType.unpaid,
          DashboardAttentionType.overdueTask,
          DashboardAttentionType.bookingRequest,
          DashboardAttentionType.clientFollowUp,
        ]),
      );
      expect(
        items.where(
          (item) => item.type == DashboardAttentionType.clientFollowUp,
        ),
        hasLength(2),
      );
      expect(
        items.map((item) => item.title),
        isNot(contains('Reconnect with Sarah')),
      );
      expect(items.map((item) => item.title), isNot(contains('Collect £80')));
      expect(items.map((item) => item.type), [
        DashboardAttentionType.bookingRequest,
        DashboardAttentionType.bookingRequest,
        DashboardAttentionType.overdueTask,
        DashboardAttentionType.unpaid,
        DashboardAttentionType.clientFollowUp,
        DashboardAttentionType.clientFollowUp,
      ]);
    });

    test('provider surfaces a source failure instead of hiding attention', () {
      final sourceError = StateError('tasks unavailable');
      final container = ProviderContainer(
        overrides: [
          invoicesProvider.overrideWith((ref) async => const <Payment>[]),
          allTasksProvider.overrideWith((ref) async => throw sourceError),
          appointmentsProvider.overrideWith(
            (ref) async => const <Map<String, dynamic>>[],
          ),
          clientsProvider.overrideWith((ref) async => const <Client>[]),
          bookingRequestsProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(dashboardAttentionProvider.future),
        throwsA(same(sourceError)),
      );
    });

    test(
      'each active request keeps its identity and oldest requests come first',
      () {
        final now = DateTime(2026, 9, 6);
        final requests = [
          BookingRequest(
            id: 'new',
            workspaceId: 'workspace-1',
            name: 'Alex',
            phone: '',
            serviceName: 'Window clean',
            createdAt: now.subtract(const Duration(hours: 1)),
          ),
          BookingRequest(
            id: 'contacted',
            workspaceId: 'workspace-1',
            name: 'Jamie',
            phone: '',
            status: 'contacted',
            createdAt: now.subtract(const Duration(days: 2)),
          ),
          const BookingRequest(
            id: 'confirmed',
            workspaceId: 'workspace-1',
            name: 'Confirmed',
            phone: '',
            status: 'confirmed',
          ),
          const BookingRequest(
            id: 'declined',
            workspaceId: 'workspace-1',
            name: 'Declined',
            phone: '',
            status: 'declined',
          ),
          const BookingRequest(
            id: '',
            workspaceId: 'workspace-1',
            name: 'Missing identifier',
            phone: '',
          ),
        ];
        final items = buildDashboardAttentionItems(
          bookingRequests: requests,
          payments: const [],
          tasks: const [],
          appointments: const [],
          clients: const [],
          now: now,
        );
        expect(items, hasLength(2));
        expect(items.map((item) => (item.source as BookingRequest).id), [
          'contacted',
          'new',
        ]);
        expect(items.map((item) => item.entityRoute), [
          '/booking-requests/contacted',
          '/booking-requests/new',
        ]);
        expect(items.first.title, 'Review Jamie’s request');
        expect(items.last.detail, 'Window clean · Awaiting decision');
      },
    );

    test(
      'request resolution updates attention from the canonical collection',
      () async {
        var status = 'pending';
        var requestReads = 0;
        final container = ProviderContainer(
          overrides: [
            businessNowProvider.overrideWithValue(DateTime(2026, 9, 6)),
            invoicesProvider.overrideWith((ref) async => const []),
            allTasksProvider.overrideWith((ref) async => const []),
            appointmentsProvider.overrideWith((ref) async => const []),
            clientsProvider.overrideWith((ref) async => const []),
            bookingRequestsProvider.overrideWith((ref) async {
              requestReads++;
              return [
                BookingRequest(
                  id: 'request-1',
                  workspaceId: 'workspace-1',
                  name: 'Alex',
                  phone: '',
                  status: status,
                ),
              ];
            }),
          ],
        );
        addTearDown(container.dispose);
        final first = await container.read(dashboardAttentionProvider.future);
        expect(first.single.entityRoute, '/booking-requests/request-1');
        status = 'contacted';
        container.invalidate(bookingRequestsProvider);
        expect(
          await container.read(dashboardAttentionProvider.future),
          hasLength(1),
        );
        status = 'confirmed';
        container.invalidate(bookingRequestsProvider);
        expect(
          await container.read(dashboardAttentionProvider.future),
          isEmpty,
        );
        expect(requestReads, 3);
      },
    );

    test(
      'request load failures are visible instead of an empty attention list',
      () {
        final failure = StateError('requests unavailable');
        final container = ProviderContainer(
          overrides: [
            invoicesProvider.overrideWith((ref) async => const []),
            allTasksProvider.overrideWith((ref) async => const []),
            appointmentsProvider.overrideWith((ref) async => const []),
            clientsProvider.overrideWith((ref) async => const []),
            bookingRequestsProvider.overrideWith((ref) async => throw failure),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(dashboardAttentionProvider.future),
          throwsA(same(failure)),
        );
      },
    );

    test(
      'entity destinations preserve a single exact ID and reject mismatched sources',
      () {
        final now = DateTime(2026, 9, 6);
        final payment = Payment(
          id: 'payment/one?detail=1#anchor',
          workspaceId: 'workspace-1',
          number: 'PAY',
          status: 'sent',
          issueDate: now,
          total: 10,
        );
        final paymentItem = DashboardAttentionItem(
          type: DashboardAttentionType.unpaid,
          title: 'Collect',
          detail: '',
          source: payment,
          sortTime: now,
        );
        final uri = Uri.parse(paymentItem.entityRoute!);
        expect(uri.pathSegments, ['payments', payment.id]);
        expect(uri.hasQuery, isFalse);
        expect(uri.hasFragment, isFalse);
        final taskItem = DashboardAttentionItem(
          type: DashboardAttentionType.overdueTask,
          title: 'Task',
          detail: '',
          source: const SlateTask(
            id: 'task-one',
            workspaceId: 'workspace-1',
            title: 'Call client',
          ),
          sortTime: now,
        );
        expect(taskItem.entityRoute, '/tasks/task-one');
        final mismatched = DashboardAttentionItem(
          type: DashboardAttentionType.unpaid,
          title: 'Collect',
          detail: '',
          source: taskItem.source,
          sortTime: now,
        );
        expect(mismatched.entityRoute, isNull);
        final aggregate = DashboardAttentionItem(
          type: DashboardAttentionType.bookingRequest,
          title: 'Requests',
          detail: '',
          source: 2,
          sortTime: now,
        );
        expect(aggregate.entityRoute, isNull);
      },
    );
  });
}
