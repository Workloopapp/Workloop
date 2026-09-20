import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/clients/providers/client_detail_providers.dart';
import 'package:workloop/features/clients/widgets/client_overview_tab.dart';
import 'package:workloop/features/clients/widgets/client_payments_tab.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/booking_requests_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/workspace_refresh.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';

Payment payment({double received = 0, String workspaceId = 'workspace-1'}) =>
    Payment(
      id: 'payment-1',
      workspaceId: workspaceId,
      contactId: 'client-1',
      appointmentId: 'booking-1',
      number: 'PAY-1',
      status: received == 100 ? 'paid' : 'sent',
      issueDate: DateTime(2026, 9, 1),
      total: 100,
      amountPaid: received,
    );

Map<String, dynamic> booking(
  String id,
  String start, {
  String status = 'scheduled',
}) => {
  'id': id,
  'workspace_id': 'workspace-1',
  'contact_id': 'client-1',
  'start_time': start,
  'status': status,
};

void main() {
  test(
    'client totals and booking detail share one payment read and mutation refresh',
    () async {
      var paymentReads = 0;
      var received = 0.0;
      final container = ProviderContainer(
        overrides: [
          businessNowProvider.overrideWithValue(DateTime(2026, 9, 5, 12)),
          clientsProvider.overrideWith(
            (ref) async => const [
              Client(id: 'client-1', workspaceId: 'workspace-1', name: 'Alex'),
            ],
          ),
          appointmentsProvider.overrideWith(
            (ref) async => [booking('booking-1', '2026-09-06T10:00:00')],
          ),
          invoicesProvider.overrideWith((ref) async {
            paymentReads++;
            return [payment(received: received)];
          }),
          allTasksProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);
      final clientSub = container.listen(
        clientPaymentsProvider('client-1'),
        (_, _) {},
      );
      final bookingSub = container.listen(
        appointmentPaymentsProvider('booking-1'),
        (_, _) {},
      );
      addTearDown(clientSub.close);
      addTearDown(bookingSub.close);

      await container.read(invoicesProvider.future);
      var records = await container.read(clientCrmRecordsProvider.future);
      expect(records.single.outstandingBalance, 100);
      expect(
        (await container.read(
          clientPaymentsProvider('client-1').future,
        )).single.outstandingAmount,
        100,
      );
      expect(paymentReads, 1);

      received = 100;
      container.invalidate(invoicesProvider);
      records = await container.read(clientCrmRecordsProvider.future);
      expect(records.single.lifetimeValue, 100);
      expect(records.single.outstandingBalance, 0);
      expect(
        (await container.read(
          clientPaymentsProvider('client-1').future,
        )).single.outstandingAmount,
        0,
      );
      expect(
        (await container.read(
          appointmentPaymentsProvider('booking-1').future,
        )).single.outstandingAmount,
        0,
      );
      expect(paymentReads, 2);
    },
  );

  test('settings and operational views have one invalidation boundary', () {
    expect(identical(settingsServicesProvider, servicesProvider), isTrue);
    expect(
      identical(settingsWorkspaceSettingsProvider, workspaceSettingsProvider),
      isTrue,
    );
  });

  test('finance starts payments, expenses and settings together', () async {
    final payments = Completer<List<Payment>>();
    final expenses = Completer<List<Expense>>();
    final settings = Completer<Map<String, dynamic>?>();
    final started = <String>{};
    final container = ProviderContainer(
      overrides: [
        businessTodayProvider.overrideWithValue(DateTime(2026, 9, 5)),
        invoicesProvider.overrideWith((ref) {
          started.add('payments');
          return payments.future;
        }),
        expensesProvider.overrideWith((ref) {
          started.add('expenses');
          return expenses.future;
        }),
        workspaceSettingsProvider.overrideWith((ref) {
          started.add('settings');
          return settings.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    final summary = container.read(financeSummaryProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(started, {'payments', 'expenses', 'settings'});
    payments.complete([]);
    expenses.complete([]);
    settings.complete({'revenue_target': 2500});
    expect((await summary).monthlyTarget, 2500);
  });

  test(
    'midnight recalculates due payments without fetching them again',
    () async {
      final clock = StreamController<DateTime>();
      var paymentReads = 0;
      final container = ProviderContainer(
        overrides: [
          businessClockProvider.overrideWith((ref) => clock.stream),
          invoicesProvider.overrideWith((ref) async {
            paymentReads++;
            return [payment()];
          }),
          expensesProvider.overrideWith((ref) async => []),
          workspaceSettingsProvider.overrideWith((ref) async => {}),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await clock.close();
      });
      final subscription = container.listen(financeSummaryProvider, (_, _) {});
      addTearDown(subscription.close);
      clock.add(DateTime(2026, 9, 1, 23, 59));
      await container.pump();
      expect((await container.read(financeSummaryProvider.future)).unpaid, 100);
      clock.add(DateTime(2026, 9, 2, 0, 1));
      await container.pump();
      final updated = await container.read(financeSummaryProvider.future);
      expect(updated.unpaid, 0);
      expect(updated.overdue, 100);
      expect(paymentReads, 1);
    },
  );

  test(
    'dashboard request count follows the requests screen and skips terminal bookings',
    () async {
      var pending = true;
      final container = ProviderContainer(
        overrides: [
          businessNowProvider.overrideWithValue(DateTime(2026, 9, 5, 12)),
          invoicesProvider.overrideWith((ref) async => []),
          appointmentsProvider.overrideWith(
            (ref) async => [
              booking('cancelled', '2026-09-05T13:00:00', status: 'cancelled'),
              booking('completed', '2026-09-05T14:00:00', status: 'completed'),
              booking('no-show', '2026-09-05T15:00:00', status: 'no_show'),
              booking('upcoming', '2026-09-05T16:00:00'),
            ],
          ),
          bookingRequestsProvider.overrideWith(
            (ref) async => [
              BookingRequest(
                id: 'request-1',
                workspaceId: 'workspace-1',
                name: 'Alex',
                phone: '',
                status: pending ? 'pending' : 'declined',
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      var focus = await container.read(dashboardFocusProvider.future);
      expect(focus.nextAppointment?['id'], 'upcoming');
      expect(focus.pendingBookingRequests, 1);
      pending = false;
      container.invalidate(bookingRequestsProvider);
      focus = await container.read(dashboardFocusProvider.future);
      expect(focus.pendingBookingRequests, 0);
    },
  );

  test('recent completed bookings suppress false stale-client follow ups', () {
    final items = buildDashboardAttentionItems(
      now: DateTime(2026, 9, 5),
      bookingRequests: const [],
      payments: [],
      tasks: [],
      appointments: [
        booking('recent', '2026-09-04T12:00:00', status: 'completed'),
      ],
      clients: [
        Client(
          id: 'client-1',
          workspaceId: 'workspace-1',
          name: 'Alex',
          status: 'active',
          lastActivityAt: DateTime(2026, 5, 1),
        ),
      ],
    );
    expect(
      items.where((item) => item.type == DashboardAttentionType.clientFollowUp),
      isEmpty,
    );
  });

  test(
    'an external update refreshes business data as well as the notification badge',
    () async {
      var arrived = false;
      final container = ProviderContainer(
        overrides: [
          businessNowProvider.overrideWithValue(DateTime(2026, 9, 5, 12)),
          invoicesProvider.overrideWith(
            (ref) async => [payment(received: arrived ? 100 : 0)],
          ),
          appointmentsProvider.overrideWith((ref) async => []),
          bookingRequestsProvider.overrideWith(
            (ref) async => arrived
                ? [
                    const BookingRequest(
                      id: 'external-request',
                      workspaceId: 'workspace-1',
                      name: 'Alex',
                      phone: '',
                    ),
                  ]
                : [],
          ),
          unreadNotificationsProvider.overrideWith(
            (ref) async => arrived ? 1 : 0,
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        (await container.read(
          dashboardFocusProvider.future,
        )).pendingBookingRequests,
        0,
      );
      expect(
        (await container.read(invoicesProvider.future)).single.collectedAmount,
        0,
      );
      expect(await container.read(unreadNotificationsProvider.future), 0);
      arrived = true;
      refreshWorkspaceData(container.invalidate);
      expect(
        (await container.read(
          dashboardFocusProvider.future,
        )).pendingBookingRequests,
        1,
      );
      expect(
        (await container.read(invoicesProvider.future)).single.collectedAmount,
        100,
      );
      expect(await container.read(unreadNotificationsProvider.future), 1);
    },
  );

  test(
    'a slow earlier payment response cannot replace refreshed client data',
    () async {
      final older = Completer<List<Payment>>();
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          invoicesProvider.overrideWith(
            (ref) => ++calls == 1
                ? older.future
                : Future.value([payment(received: 100)]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        clientPaymentsProvider('client-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.pump();
      container.invalidate(invoicesProvider);
      expect(
        (await container.read(
          clientPaymentsProvider('client-1').future,
        )).single.collectedAmount,
        100,
      );
      older.complete([payment()]);
      await container.pump();
      expect(
        (await container.read(
          clientPaymentsProvider('client-1').future,
        )).single.collectedAmount,
        100,
      );
    },
  );

  testWidgets(
    'client payment totals use the same paid legacy amount as Money',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            invoicesProvider.overrideWith(
              (ref) async => [
                Payment(
                  id: 'legacy-paid',
                  workspaceId: 'workspace-1',
                  contactId: 'client-1',
                  number: 'Paid booking',
                  status: 'paid',
                  issueDate: DateTime(2026, 9, 1),
                  total: 100,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: ClientPaymentsTab(clientId: 'client-1', clientName: 'Alex'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('£100 received'), findsOneWidget);
      expect(find.text('1 Sep 2026 · Paid\n£100'), findsOneWidget);
      expect(find.textContaining('Unpaid'), findsNothing);
      expect(find.textContaining('left'), findsNothing);
    },
  );

  testWidgets(
    'client overview does not announce empty bookings while they are loading',
    (tester) async {
      final bookings = Completer<List<Map<String, dynamic>>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentsProvider.overrideWith((ref) => bookings.future),
            invoicesProvider.overrideWith((ref) async => []),
            allTasksProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ClientOverviewTab(
                clientId: 'client-1',
                client: const {'name': 'Alex'},
                onEdit: () {},
                onOpenBookings: () {},
                onOpenPayments: () {},
                onOpenTasks: () {},
                onOpenAddress: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Nothing booked yet'), findsNothing);
      expect(find.text('Jobs completed'), findsNothing);
      bookings.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Nothing booked yet'), findsOneWidget);
    },
  );
}
