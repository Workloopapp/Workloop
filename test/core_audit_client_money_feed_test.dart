import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/models/business_feed_item.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/business_feed_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';

void main() {
  group('core audit client financial truth', () {
    test(
      'CRM uses collected and outstanding amounts for every payment state',
      () {
        final now = DateTime(2026, 7, 26, 10);
        final records = buildClientCrmRecords(
          now: now,
          clients: const [
            Client(id: 'client-1', workspaceId: 'workspace-1', name: 'Ada'),
          ],
          appointments: [
            Appointment(
              id: 'no-show',
              workspaceId: 'workspace-1',
              contactId: 'client-1',
              startTime: now,
              status: 'no_show',
            ),
            Appointment(
              id: 'next',
              workspaceId: 'workspace-1',
              contactId: 'client-1',
              startTime: now,
              status: 'scheduled',
            ),
            Appointment(
              id: 'completed-future',
              workspaceId: 'workspace-1',
              contactId: 'client-1',
              startTime: now.add(const Duration(hours: 1)),
              status: 'completed',
            ),
          ],
          payments: [
            _payment(
              id: 'legacy-paid',
              contactId: 'client-1',
              status: 'paid',
              total: 100,
            ),
            _payment(
              id: 'partial',
              contactId: 'client-1',
              status: 'sent',
              total: 120,
              amountPaid: 40,
            ),
            _payment(
              id: 'fully-collected',
              contactId: 'client-1',
              status: 'sent',
              total: 50,
              amountPaid: 50,
            ),
          ],
          tasks: [
            SlateTask(
              id: 'overdue',
              workspaceId: 'workspace-1',
              contactId: 'client-1',
              title: 'Follow up',
              dueDate: DateTime(2026, 7, 25),
            ),
            SlateTask(
              id: 'today',
              workspaceId: 'workspace-1',
              contactId: 'client-1',
              title: 'Prepare',
              dueDate: DateTime(2026, 7, 26),
            ),
          ],
        );

        final record = records.single;
        expect(record.lifetimeValue, 190);
        expect(record.outstandingBalance, 80);
        expect(record.nextBooking?.id, 'next');
        expect(record.openTaskCount, 2);
        expect(record.overdueTaskCount, 1);
      },
    );
  });

  group('core audit dashboard and feed money alignment', () {
    test('attention asks only for the remaining balance', () {
      final now = DateTime(2026, 7, 26);
      final payments = [
        _payment(
          id: 'partial',
          status: 'sent',
          total: 100,
          amountPaid: 35,
          dueDate: DateTime(2026, 7, 20),
        ),
        _payment(
          id: 'already-collected',
          status: 'sent',
          total: 80,
          amountPaid: 80,
          dueDate: DateTime(2026, 7, 20),
        ),
      ];
      final items = buildDashboardAttentionItems(
        now: now,
        bookingRequests: const [],
        payments: payments,
        tasks: const [],
        appointments: const [],
        clients: const [],
      );
      final focus = dashboardFocusFrom(
        nextAppointment: null,
        pendingBookingRequests: 0,
        payments: payments,
        now: now,
      );

      expect(items.map((item) => item.title), ['Collect £65']);
      expect(focus.overduePayments, 1);
      expect(focus.overdueTotal, 65);
    });

    test('feed keeps the seven-day payment boundary calendar based', () {
      final now = DateTime(2026, 10, 23, 9);
      final daySeven = _payment(
        id: 'day-seven',
        status: 'sent',
        total: 70,
        dueDate: DateTime(2026, 10, 30),
      );
      final dayEight = _payment(
        id: 'day-eight',
        status: 'sent',
        total: 80,
        dueDate: DateTime(2026, 10, 31),
      );
      final items = buildBusinessFeedItems(
        now: now,
        appointments: const [],
        payments: [daySeven, dayEight],
        expenses: const [],
        tasks: const [],
        notes: const [],
        clients: const [],
        bookingRequests: const [],
        finance: FinanceSummary.from(
          payments: [daySeven, dayEight],
          expenses: const [],
          monthlyTarget: 0,
          now: now,
        ),
      );

      final upcomingIds = items
          .where((item) => item.type == BusinessFeedItemType.invoiceUnpaid)
          .map((item) => item.sourceId);
      expect(upcomingIds, ['day-seven']);
    });

    test('feed uses receipt date and remaining balances consistently', () {
      final now = DateTime(2026, 7, 26, 9);
      final paid = _payment(
        id: 'paid',
        status: 'paid',
        total: 120,
        amountPaid: 120,
        issueDate: DateTime(2026, 6, 1),
        incomeRecordedAt: DateTime(2026, 7, 25, 14),
      );
      final partial = _payment(
        id: 'partial',
        status: 'sent',
        total: 100,
        amountPaid: 30,
        dueDate: DateTime(2026, 7, 20),
      );
      final fullyCollected = _payment(
        id: 'collected',
        status: 'sent',
        total: 50,
        amountPaid: 50,
        dueDate: DateTime(2026, 7, 20),
      );
      final items = buildBusinessFeedItems(
        now: now,
        appointments: const [],
        payments: [paid, partial, fullyCollected],
        expenses: const [],
        tasks: const [],
        notes: const [],
        clients: const [],
        bookingRequests: const [],
        finance: FinanceSummary.from(
          payments: [paid, partial, fullyCollected],
          expenses: const [],
          monthlyTarget: 0,
          now: now,
        ),
      );

      final receipt = items.singleWhere(
        (item) => item.type == BusinessFeedItemType.paymentReceived,
      );
      final overdue = items.singleWhere(
        (item) => item.type == BusinessFeedItemType.invoiceOverdue,
      );
      final daily = items.singleWhere(
        (item) => item.type == BusinessFeedItemType.dailySummary,
      );

      expect(receipt.timestamp, paid.receivedDate);
      expect(receipt.subtitle, contains('£120'));
      expect(receipt.subtitle, contains('Business date yesterday'));
      expect(overdue.subtitle, contains('£70'));
      expect(overdue.sourceId, 'partial');
      expect(daily.title, contains('1 payment overdue'));
    });
  });
}

Payment _payment({
  required String id,
  required String status,
  required double total,
  double amountPaid = 0,
  String? contactId,
  DateTime? issueDate,
  DateTime? dueDate,
  DateTime? incomeRecordedAt,
}) {
  return Payment(
    id: id,
    workspaceId: 'workspace-1',
    contactId: contactId,
    number: id,
    status: status,
    issueDate: issueDate ?? DateTime(2026, 7, 1),
    dueDate: dueDate,
    incomeRecordedAt: incomeRecordedAt,
    total: total,
    amountPaid: amountPaid,
  );
}
