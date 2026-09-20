import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/public_profile/booking_request_time.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';
import 'package:workloop/shared/utils/duration_format.dart';
import 'package:workloop/shared/utils/working_hours.dart';

void main() {
  group('legacy requested time resolution', () {
    test('exact website text resolves in the business zone', () {
      final result = resolveBookingRequestTime(
        timezone: 'Europe/London',
        preferredTimeText: '2026-09-11 at 07:41',
      );
      expect(result.date, DateTime.utc(2026, 9, 11));
      expect((result.hour, result.minute), (7, 41));
      expect(result.instantUtc, DateTime.utc(2026, 9, 11, 6, 41));
      expect(result.issue, isNull);
      final overseas = resolveBookingRequestTime(
        timezone: 'Pacific/Auckland',
        preferredTimeText: '2026-09-11 at 07:41',
      );
      expect(overseas.instantUtc, DateTime.utc(2026, 9, 10, 19, 41));
    });
    test('structured instant overrides conflicting generated text', () {
      final original = DateTime.utc(2026, 10, 25, 1, 30, 12, 345);
      final result = resolveBookingRequestTime(
        timezone: 'Europe/London',
        requestedFor: original,
        preferredTimeText: '2026-09-11 at 07:41',
      );
      expect(result.instantUtc, original);
      expect(result.date, DateTime.utc(2026, 10, 25));
      expect((result.hour, result.minute), (1, 30));
    });
    for (final text in [
      '2026-02-30 at 10:00',
      '2026-09-11 at 24:00',
      '2026-09-11 at 07:60',
      '2026-03-29 at 01:30',
    ]) {
      test('does not normalize invalid preference $text', () {
        final result = resolveBookingRequestTime(
          timezone: 'Europe/London',
          preferredTimeText: text,
        );
        expect(result.instantUtc, isNull);
        expect(result.hour, isNull);
        expect(result.issue, BookingRequestTimeIssue.invalid);
      });
    }
    for (final text in [
      null,
      '',
      'Friday morning',
      '09/11/2026 at 07:41',
      '2026-09-11 at 07:41 or 10:00',
    ]) {
      test('does not guess freeform preference $text', () {
        final result = resolveBookingRequestTime(
          timezone: 'Europe/London',
          preferredTimeText: text,
        );
        expect(result.instantUtc, isNull);
        expect(result.date, isNull);
        expect(result.hour, isNull);
        expect(result.issue, BookingRequestTimeIssue.unspecified);
      });
    }
    test('date-only request keeps its day but invents no time', () {
      final result = resolveBookingRequestTime(
        timezone: 'Europe/London',
        preferredTimeText: '2026-09-11',
      );
      expect(result.date, DateTime.utc(2026, 9, 11));
      expect(result.hour, isNull);
      expect(result.instantUtc, isNull);
    });
    test(
      'autumn repeated hour exposes both instants without selecting one',
      () {
        final result = resolveBookingRequestTime(
          timezone: 'Europe/London',
          preferredTimeText: '2026-10-25 at 01:30',
        );
        expect(result.instantUtc, isNull);
        expect(result.issue, BookingRequestTimeIssue.repeatedHour);
        final choices = bookingRequestPossibleInstants(
          date: result.date!,
          hour: result.hour!,
          minute: result.minute!,
          timezone: 'Europe/London',
        );
        expect(choices, [
          DateTime.utc(2026, 10, 25, 0, 30),
          DateTime.utc(2026, 10, 25, 1, 30),
        ]);
        expect(
          bookingRequestOccurrenceLabel(choices.first, 'Europe/London'),
          'BST (UTC+01:00)',
        );
        expect(
          bookingRequestOccurrenceLabel(choices.last, 'Europe/London'),
          'GMT (UTC+00:00)',
        );
      },
    );
  });
  test('Europe London requested wall clock survives summer DST conversion', () {
    final requestedUtc = bookingRequestUtcFromWallClock(
      date: DateTime(2026, 7, 15),
      hour: 10,
      minute: 30,
      timezone: 'Europe/London',
    );

    expect(requestedUtc, DateTime.utc(2026, 7, 15, 9, 30));
    final restored = bookingRequestWallClock(
      requestedForUtc: requestedUtc,
      timezone: 'Europe/London',
    );
    expect(restored, DateTime.utc(2026, 7, 15, 10, 30));
  });

  test('UTC workspaces preserve the selected wall clock exactly', () {
    final requestedUtc = bookingRequestUtcFromWallClock(
      date: DateTime(2026, 7, 15),
      hour: 10,
      minute: 30,
      timezone: 'UTC',
    );

    expect(requestedUtc, DateTime.utc(2026, 7, 15, 10, 30));
  });

  test(
    'Europe London winter request remains on UTC without shifting display',
    () {
      final requestedUtc = bookingRequestUtcFromWallClock(
        date: DateTime(2026, 12, 15),
        hour: 10,
        minute: 30,
        timezone: 'Europe/London',
      );

      expect(requestedUtc, DateTime.utc(2026, 12, 15, 10, 30));
      expect(
        bookingRequestWallClock(
          requestedForUtc: requestedUtc,
          timezone: 'Europe/London',
        ),
        DateTime.utc(2026, 12, 15, 10, 30),
      );
    },
  );

  test('non-existent spring clock-change time is rejected, not shifted', () {
    expect(
      () => bookingRequestUtcFromWallClock(
        date: DateTime(2026, 3, 29),
        hour: 1,
        minute: 30,
        timezone: 'Europe/London',
      ),
      throwsArgumentError,
    );
  });

  for (final hour in [0, 1]) {
    test('unchanged autumn 01:30 preserves original UTC hour $hour', () {
      final instant = DateTime.utc(2026, 10, 25, hour, 30, 12, 345);
      final wall = bookingRequestWallClock(
        requestedForUtc: instant,
        timezone: 'Europe/London',
      );
      expect((wall.day, wall.hour, wall.minute), (25, 1, 30));
      expect(
        bookingRequestUtcFromWallClock(
          date: wall,
          hour: wall.hour,
          minute: wall.minute,
          timezone: 'Europe/London',
          preferredInstantUtc: instant,
        ),
        instant,
      );
    });
  }

  test('changing the chosen time does not reuse the old requested instant', () {
    expect(
      bookingRequestUtcFromWallClock(
        date: DateTime.utc(2026, 10, 25),
        hour: 3,
        minute: 45,
        timezone: 'Europe/London',
        preferredInstantUtc: DateTime.utc(2026, 10, 25, 0, 30),
      ),
      DateTime.utc(2026, 10, 25, 3, 45),
    );
  });

  test('unknown time zones fail clearly without choosing another location', () {
    expect(
      () => bookingRequestUtcFromWallClock(
        date: DateTime(2026, 10, 25),
        hour: 9,
        minute: 0,
        timezone: 'Missing/Location',
      ),
      throwsArgumentError,
    );
    expect(
      () => bookingRequestWallClock(
        requestedForUtc: DateTime.utc(2026, 10, 25, 9),
        timezone: 'Missing/Location',
      ),
      throwsArgumentError,
    );
  });

  test('hours guidance measures actual duration through both DST changes', () {
    const hours = {
      'Sunday': {
        'enabled': true,
        'blocks': [
          {'start': '00:00', 'end': '03:00'},
        ],
      },
    };
    // 00:30 GMT + 2 hours ends at 03:30 BST, outside the closing time.
    expect(
      bookingRequestHoursFit(
        requestedForUtc: DateTime.utc(2026, 3, 29, 0, 30),
        timezone: 'Europe/London',
        workingHours: hours,
        durationMinutes: 120,
      ),
      BookingRequestHoursFit.outsidePublishedHours,
    );
    // 01:45 BST + 30 minutes ends at the second 01:15 GMT; still within hours.
    expect(
      bookingRequestHoursFit(
        requestedForUtc: DateTime.utc(2026, 10, 25, 0, 45),
        timezone: 'Europe/London',
        workingHours: hours,
        durationMinutes: 30,
      ),
      BookingRequestHoursFit.withinPublishedHours,
    );
  });

  test('public request payload carries exact UTC and workspace timezone', () {
    final payload = buildPublicBookingRequestPayload(
      handle: 'bright-studio',
      name: 'Ada',
      phone: '07123456789',
      email: 'ada@example.com',
      requestToken: 'ad5f5592-9f8f-4b35-9604-8fc09270982d',
      requestedFor: DateTime.utc(2026, 7, 15, 9, 30),
      requestedTimezone: 'Europe/London',
      preferredTimeText: '15 Jul 2026 at 10:30',
    );

    expect(payload['requestedFor'], '2026-07-15T09:30:00.000Z');
    expect(payload['requestedTimezone'], 'Europe/London');
  });

  test(
    'booking request model reads the structured requested time contract',
    () {
      final request = BookingRequest.fromMap({
        'id': 'request-1',
        'workspace_id': 'workspace-1',
        'name': 'Ada',
        'phone': '07123456789',
        'requested_for': '2026-07-15T09:30:00Z',
        'requested_timezone': 'Europe/London',
      });

      expect(request.requestedFor, DateTime.utc(2026, 7, 15, 9, 30));
      expect(request.requestedTimezone, 'Europe/London');
    },
  );

  test(
    'customer-facing durations and working hours avoid raw minute clocks',
    () {
      expect(formatFriendlyDuration(60), '1 hour');
      expect(formatFriendlyDuration(150), '2 hours 30 min');
      expect(
        formatFriendlyWorkingHourValue({
          'enabled': true,
          'blocks': [
            {'start': '09:00', 'end': '17:30'},
          ],
        }),
        '9am - 5:30pm',
      );
    },
  );

  test('availability guidance uses the workspace wall clock across DST', () {
    const hours = {
      'Monday': {
        'enabled': true,
        'blocks': [
          {'start': '09:00', 'end': '17:00'},
        ],
      },
    };

    expect(
      bookingRequestHoursFit(
        requestedForUtc: DateTime.utc(2026, 7, 13, 8, 30),
        timezone: 'Europe/London',
        workingHours: hours,
        durationMinutes: 60,
      ),
      BookingRequestHoursFit.withinPublishedHours,
    );
    expect(
      bookingRequestHoursFit(
        requestedForUtc: DateTime.utc(2026, 7, 13, 15, 30),
        timezone: 'Europe/London',
        workingHours: hours,
        durationMinutes: 60,
      ),
      BookingRequestHoursFit.outsidePublishedHours,
    );
    expect(
      bookingRequestHoursFit(
        requestedForUtc: DateTime.utc(2026, 7, 14, 9),
        timezone: 'Europe/London',
        workingHours: hours,
      ),
      BookingRequestHoursFit.noPublishedHours,
    );
  });
}
