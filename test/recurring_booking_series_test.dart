import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/recurring_booking_fields.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/utils/appointment_recurrence.dart';
import 'package:workloop/shared/utils/booking_time.dart';

void main() {
  test('business-zone series keeps 09:00 across spring and autumn DST', () {
    for (final dates in [
      [DateTime.utc(2027, 3, 21, 9), DateTime.utc(2027, 3, 28, 8)],
      [DateTime.utc(2027, 10, 24, 8), DateTime.utc(2027, 10, 31, 9)],
    ]) {
      final next = appointmentOccurrenceStart(
        dates.first,
        'FREQ=WEEKLY;INTERVAL=1',
        1,
        timezoneName: 'Europe/London',
      );
      expect(next, dates.last);
      expect(bookingTimeInZone(next, 'Europe/London').hour, 9);
    }
  });

  test('business-zone series is independent of the device zone', () {
    final next = appointmentOccurrenceStart(
      DateTime.utc(2027, 3, 7, 14),
      'FREQ=WEEKLY;INTERVAL=2',
      1,
      timezoneName: 'America/New_York',
    );
    expect(next, DateTime.utc(2027, 3, 21, 13));
    expect(bookingTimeInZone(next, 'America/New_York').hour, 9);
  });

  test('rejects spring gaps instead of silently shifting a booking', () {
    expect(
      () => recurringBookingInstant(
        DateTime.utc(2027, 3, 28, 1, 30),
        'Europe/London',
      ),
      throwsA(isA<RecurringBookingTimeException>()),
    );
    expect(
      () => appointmentOccurrenceStart(
        DateTime.utc(2027, 3, 21, 1, 30),
        'FREQ=WEEKLY;INTERVAL=1',
        1,
        timezoneName: 'Europe/London',
      ),
      throwsA(isA<RecurringBookingTimeException>()),
    );
  });

  test('preserves the first chosen instant in the repeated autumn hour', () {
    final second0130 = DateTime.utc(2027, 10, 31, 1, 30);
    expect(
      appointmentOccurrenceStart(
        second0130,
        'FREQ=WEEKLY;INTERVAL=1',
        0,
        timezoneName: 'Europe/London',
      ),
      second0130,
    );
  });

  test(
    'editing a repeated-hour occurrence preserves its instant until moved',
    () {
      final second0130 = DateTime.utc(2027, 10, 31, 1, 30);
      expect(
        editedAppointmentStart(
          originalStart: second0130,
          selectedWallClock: DateTime.utc(2027, 10, 31, 1, 30),
          timezoneName: 'Europe/London',
        ),
        second0130,
      );
      expect(
        editedAppointmentStart(
          originalStart: second0130,
          selectedWallClock: DateTime.utc(2027, 11, 1, 9),
          timezoneName: 'Europe/London',
        ),
        DateTime.utc(2027, 11, 1, 9),
      );
    },
  );

  test('payload uses business civil payment dates and elapsed durations', () {
    final payload = buildBookingWorkflowPayload(
      workspaceId: 'workspace',
      idempotencyKey: 'series-test-key-0001',
      contactId: 'contact',
      startTime: DateTime.utc(2027, 1, 1, 11, 30),
      endTime: DateTime.utc(2027, 1, 1, 12, 30),
      price: 40,
      recurrenceRule: 'FREQ=WEEKLY;INTERVAL=4',
      recurrenceTimezone: 'Pacific/Auckland',
      repeatOccurrences: 3,
      notificationTitle: 'Series',
      notificationBody: 'Created',
    );
    final rows = List<Map<String, dynamic>>.from(
      payload['appointments'] as List,
    );
    expect(rows.first['payment_date'], '2027-01-02');
    expect(rows.last['payment_date'], '2027-02-27');
    for (final row in rows) {
      expect(
        DateTime.parse(
          row['end_time'] as String,
        ).difference(DateTime.parse(row['start_time'] as String)),
        const Duration(hours: 1),
      );
    }
  });

  test(
    'repository routes series through atomic endpoint with stable retries',
    () async {
      final payloads = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          expect(
            request.url.path,
            '/rest/v1/rpc/create_recurring_booking_workflow',
          );
          payloads.add(
            (jsonDecode(request.body) as Map)['p_payload']
                as Map<String, dynamic>,
          );
          return http.Response(
            jsonEncode({
              'appointment_ids': ['first', 'second'],
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = AppointmentsRepository(client);
      for (var retry = 0; retry < 2; retry++) {
        expect(
          await repository.createBookingWorkflow(
            workspaceId: 'workspace',
            idempotencyKey: 'series-retry-key-0001',
            contactId: 'contact',
            startTime: DateTime.utc(2027, 3, 21, 9),
            endTime: DateTime.utc(2027, 3, 21, 10),
            price: 45,
            recurrenceRule: 'FREQ=WEEKLY;INTERVAL=1',
            recurrenceTimezone: 'Europe/London',
            repeatOccurrences: 2,
          ),
          ['first', 'second'],
        );
      }
      expect(payloads.first, payloads.last);
      expect(
        (payloads.first['appointments'] as List)[1]['start_time'],
        '2027-03-28T08:00:00.000Z',
      );
    },
  );

  test(
    'preflight reviews every occurrence in the same business timezone',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final review = await AppointmentsRepository(client).reviewSchedule(
        workspaceId: 'workspace',
        startTime: DateTime.utc(2027, 3, 21, 9),
        endTime: DateTime.utc(2027, 3, 21, 10),
        workingHoursTimezone: 'Europe/London',
        recurrenceRule: 'FREQ=WEEKLY;INTERVAL=1',
        repeatOccurrences: 2,
      );
      expect(review.hasWarnings, false);
      expect(requests.length, 2);
      expect(
        requests.last.queryParameters['end_time'],
        'gt.2027-03-28T08:00:00.000Z',
      );
    },
  );

  test('appointment serialization retains the original series zone', () {
    final appointment = Appointment.fromMap({
      'id': 'booking',
      'workspace_id': 'workspace',
      'start_time': '2027-03-28T08:00:00Z',
      'recurrence_rule': 'FREQ=WEEKLY;INTERVAL=1',
      'recurrence_timezone': 'Europe/London',
    });
    expect(appointment.recurrenceTimezone, 'Europe/London');
    expect(appointment.toMap()['recurrence_timezone'], 'Europe/London');
  });

  testWidgets('repeat selector previews finite series and bounds its count', (
    tester,
  ) async {
    int interval = 0;
    int count = 2;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => RecurringBookingFields(
              intervalWeeks: interval,
              occurrences: count,
              firstWallClock: DateTime.utc(2027, 3, 21, 9),
              timezoneName: 'Europe/London',
              onIntervalChanged: (value) => setState(() => interval = value),
              onOccurrencesChanged: (value) => setState(() => count = value),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Number of bookings'), findsNothing);
    await tester.tap(find.text('Weekly'));
    await tester.pump();
    expect(find.textContaining('last on 28/3/2027'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.remove_rounded),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('More bookings'));
    await tester.pump();
    expect(
      find.textContaining('3 bookings · last on 4/4/2027'),
      findsOneWidget,
    );
    await tester.tap(find.text('Every 4 weeks'));
    await tester.pump();
    expect(find.textContaining('last on 16/5/2027'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
