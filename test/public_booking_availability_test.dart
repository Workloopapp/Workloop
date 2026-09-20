import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/models/public_booking_availability.dart';

void main() {
  test(
    'parses capped UTC suggestions without retaining unknown diary fields',
    () {
      final availability = PublicBookingAvailability.fromMap({
        'timezone': 'Europe/London',
        'durationMinutes': 60,
        'generatedAt': '2026-09-01T12:00:00Z',
        'appointmentIds': ['private'],
        'days': List.generate(7, (day) {
          final date = day + 2;
          return {
            'date': '2026-09-${date.toString().padLeft(2, '0')}',
            'busyIntervals': ['private'],
            'slots': List.generate(
              8,
              (hour) =>
                  '2026-09-${date.toString().padLeft(2, '0')}T${(hour + 8).toString().padLeft(2, '0')}:00:00Z',
            ),
          };
        }),
      });

      expect(availability.days, hasLength(5));
      expect(
        availability.days.every((day) => day.slotsUtc.length == 6),
        isTrue,
      );
      expect(availability.days.first.slotsUtc.first.isUtc, isTrue);
    },
  );

  test('rejects malformed availability metadata', () {
    expect(
      () => PublicBookingAvailability.fromMap({
        'timezone': '',
        'durationMinutes': 0,
        'generatedAt': 'not-a-date',
      }),
      throwsFormatException,
    );
  });
}
