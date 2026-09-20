import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/features/public_profile/booking_request_time.dart';
import 'package:workloop/shared/notifications/local_reminder_plan.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';

const _workspace = '11000000-0000-4000-8000-000000000001';
const _requestId = '11000000-0000-4000-8000-000000000002';
const _request = BookingRequest(
  id: _requestId,
  workspaceId: _workspace,
  name: 'Sample customer',
  phone: '07700 900123',
  email: 'sample@example.test',
);

class _BookingBackend {
  String? requestStatus = 'pending';
  String zone = 'Pacific/Auckland';
  int conflictReads = 0;
  int settingsReads = 0;
  bool loseFirstResponse = false;
  final payloads = <Map<String, dynamic>>[];
  final reads = <Uri>[];
  late final client = SupabaseClient(
    'https://example.supabase.co',
    'fake-anon-key',
    httpClient: MockClient((request) async {
      reads.add(request.url);
      Object? body;
      var status = 200;
      switch (request.url.path) {
        case '/rest/v1/booking_requests':
          expect(request.url.queryParameters['id'], 'eq.$_requestId');
          expect(request.url.queryParameters['workspace_id'], 'eq.$_workspace');
          body = requestStatus == null
              ? []
              : [
                  {'status': requestStatus},
                ];
        case '/rest/v1/workspace_settings':
          settingsReads++;
          expect(request.url.queryParameters['workspace_id'], 'eq.$_workspace');
          body = [
            {
              'timezone': zone,
              'working_hours': {
                'Monday': {
                  'enabled': true,
                  'blocks': [
                    {'start': '09:00', 'end': '17:00'},
                  ],
                },
              },
            },
          ];
        case '/rest/v1/appointments':
          conflictReads++;
          expect(request.url.queryParameters['workspace_id'], 'eq.$_workspace');
          body = requestStatus == 'confirmed'
              ? [
                  {'id': 'already-created-booking'},
                ]
              : [];
        case '/functions/v1/confirm-booking-request':
          payloads.add(
            Map<String, dynamic>.from(
              (jsonDecode(request.body) as Map)['payload'] as Map,
            ),
          );
          requestStatus = 'confirmed';
          if (loseFirstResponse && payloads.length == 1) {
            status = 503;
            body = {'error': 'response lost after commit'};
          } else {
            body = {
              'ok': true,
              'confirmationEmail': {'status': 'pending'},
            };
          }
        default:
          throw StateError('Unexpected test endpoint: ${request.url.path}');
      }
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  ProfileRepository get repository => ProfileRepository(client);
}

void main() {
  test(
    'legacy exact website request reaches workflow with its original civil time',
    () async {
      final backend = _BookingBackend()..zone = 'Europe/London';
      addTearDown(backend.client.dispose);
      final request = BookingRequest.fromMap({
        ..._request.toMap(),
        'preferred_time_text': '2026-09-11 at 07:41',
      });
      final zone = await backend.repository.bookingRequestTimezone(request);
      final time = resolveBookingRequestTime(
        timezone: zone,
        preferredTimeText: request.preferredTimeText,
      );
      await backend.repository.confirmBookingRequest(
        request: request,
        startTime: time.instantUtc!,
        durationMins: 60,
        price: 45,
        enforceWorkingHours: false,
      );
      final occurrence =
          (backend.payloads.single['appointments'] as List).single;
      expect(occurrence['start_time'], '2026-09-11T06:41:00.000Z');
      expect(occurrence['end_time'], '2026-09-11T07:41:00.000Z');
      expect(backend.settingsReads, 2);
    },
  );

  test(
    'saved request zone is authoritative and needs no settings lookup',
    () async {
      final backend = _BookingBackend();
      addTearDown(backend.client.dispose);
      final request = BookingRequest.fromMap({
        ..._request.toMap(),
        'requested_timezone': 'UTC',
      });
      expect(await backend.repository.bookingRequestTimezone(request), 'UTC');
      expect(backend.settingsReads, 0);
    },
  );

  test(
    'missing or malformed business zone fails without defaulting to London',
    () async {
      final backend = _BookingBackend();
      addTearDown(backend.client.dispose);
      backend.zone = '';
      await expectLater(
        backend.repository.bookingRequestTimezone(_request),
        throwsFormatException,
      );
      backend.zone = 'Missing/Zone';
      await expectLater(
        backend.repository.bookingRequestTimezone(_request),
        throwsArgumentError,
      );
      expect(backend.payloads, isEmpty);
    },
  );
  test(
    'request hours use the business day rather than the phone day',
    () async {
      final backend = _BookingBackend();
      addTearDown(backend.client.dispose);
      // Monday 09:00 in Auckland, Sunday evening on the UK phone.
      final review = await backend.repository.reviewBookingRequestSchedule(
        request: _request,
        startTime: DateTime.utc(2026, 7, 12, 21),
        endTime: DateTime.utc(2026, 7, 12, 22),
      );
      expect(review.outsideWorkingHoursCount, 0);
      expect(review.conflictCount, 0);
      expect(backend.conflictReads, 1);

      // Monday daytime in the UK is already Tuesday, a closed day in Auckland.
      final closed = await backend.repository.reviewBookingRequestSchedule(
        request: _request,
        startTime: DateTime.utc(2026, 7, 13, 12),
        endTime: DateTime.utc(2026, 7, 13, 13),
      );
      expect(closed.outsideWorkingHoursCount, 1);
    },
  );

  test(
    'confirmation validates business hours and sends the exact instant',
    () async {
      final backend = _BookingBackend();
      addTearDown(backend.client.dispose);
      final start = DateTime.utc(2026, 7, 12, 21, 30, 12, 345);
      await backend.repository.confirmBookingRequest(
        request: _request,
        startTime: start,
        durationMins: 60,
        price: 45,
      );
      final occurrence =
          (backend.payloads.single['appointments'] as List).single;
      expect(occurrence['start_time'], start.toIso8601String());
      expect(
        occurrence['end_time'],
        start.add(const Duration(hours: 1)).toIso8601String(),
      );
      expect(backend.payloads.single['allow_overlap'], false);
    },
  );

  test(
    'lost confirmation response retries the committed operation without self-conflict',
    () async {
      final backend = _BookingBackend()..loseFirstResponse = true;
      addTearDown(backend.client.dispose);
      final start = DateTime.utc(2026, 7, 12, 21, 30);
      Future<BookingRequestConfirmationOutcome> confirm() =>
          backend.repository.confirmBookingRequest(
            request: _request,
            startTime: start,
            durationMins: 60,
            price: 45,
          );
      await expectLater(confirm(), throwsA(isA<FunctionException>()));
      expect(backend.requestStatus, 'confirmed');
      final retryReview = await backend.repository.reviewBookingRequestSchedule(
        request: _request,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
      );
      expect(retryReview.conflictCount, 0);
      final recovered = await confirm();
      expect(
        recovered.confirmationEmailStatus,
        BookingRequestConfirmationEmailStatus.pending,
      );
      expect(backend.payloads, hasLength(2));
      expect(
        backend.payloads[0]['idempotency_key'],
        backend.payloads[1]['idempotency_key'],
      );
      expect(
        backend.payloads[0]['appointments'],
        backend.payloads[1]['appointments'],
      );
      expect(backend.conflictReads, 1);
      expect(backend.settingsReads, 1);
    },
  );

  for (final status in <String?>['declined', null]) {
    test(
      'request state $status prevents an obsolete review or confirmation',
      () async {
        final backend = _BookingBackend()..requestStatus = status;
        addTearDown(backend.client.dispose);
        await expectLater(
          backend.repository.reviewBookingRequestSchedule(
            request: _request,
            startTime: DateTime.utc(2026, 7, 12, 21),
            endTime: DateTime.utc(2026, 7, 12, 22),
          ),
          throwsA(isA<BookingRequestStateException>()),
        );
        expect(backend.conflictReads, 0);
        expect(backend.payloads, isEmpty);
      },
    );
  }

  test('unknown business zone fails before writing a booking', () async {
    final backend = _BookingBackend()..zone = 'Missing/Location';
    addTearDown(backend.client.dispose);
    await expectLater(
      backend.repository.confirmBookingRequest(
        request: _request,
        startTime: DateTime.utc(2026, 7, 12, 21),
        durationMins: 60,
        price: 45,
      ),
      throwsArgumentError,
    );
    expect(backend.payloads, isEmpty);
  });

  for (final start in [
    DateTime.utc(2026, 3, 29, 1, 5),
    DateTime.utc(2026, 10, 25, 0, 30),
    DateTime.utc(2026, 10, 25, 1, 30),
  ]) {
    test('phone reminder is 15 elapsed minutes before $start', () {
      final appointment = Appointment(
        id: 'booking-dst',
        workspaceId: _workspace,
        startTime: start,
        status: 'scheduled',
      );
      final plan = planBookingReminder(
        appointment,
        now: start.subtract(const Duration(days: 2)),
      );
      expect(plan!.scheduledAtUtc, start.subtract(const Duration(minutes: 15)));
      expect(plan.scheduledAtUtc.isUtc, isTrue);
    });
  }
}
