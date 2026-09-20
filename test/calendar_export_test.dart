import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/utils/calendar_export.dart';

void main() {
  test('exports valid, deterministic Workloop calendar data', () {
    final ics = buildWorkloopIcs([
      {
        'id': 'booking-1',
        'title': 'Cut, colour & finish',
        'start_time': '2026-07-25T09:30:00Z',
        'end_time': '2026-07-25T10:45:00Z',
        'notes': 'Bring reference\nphoto',
        'contacts': {'name': 'Alex'},
        'services': {'name': 'Colour'},
      },
    ], generatedAt: DateTime.utc(2026, 7, 25, 8));

    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0'));
    expect(ics, contains('PRODID:-//Workloop//Appointments//EN'));
    expect(ics, contains('DTSTAMP:20260725T080000Z'));
    expect(ics, contains('DTSTART:20260725T093000Z'));
    expect(ics, contains('DTEND:20260725T104500Z'));
    expect(ics, contains(r'SUMMARY:Cut\, colour & finish'));
    expect(
      ics,
      contains(
        r'DESCRIPTION:Client: Alex\nService: Colour\nBring reference\nphoto',
      ),
    );
    expect(ics, endsWith('END:VCALENDAR'));
  });

  test('skips rows without a valid start time', () {
    final ics = buildWorkloopIcs([
      {'id': 'missing-start'},
      {'id': 'invalid-start', 'start_time': 'not-a-date'},
    ], generatedAt: DateTime.utc(2026));

    expect(ics, isNot(contains('BEGIN:VEVENT')));
  });
  test(
    'cancelled snapshot retains UID and carries updated cancellation state',
    () {
      final booking = <String, dynamic>{
        'id': 'booking-cancelled',
        'title': 'Window cleaning',
        'start_time': '2026-09-14T09:00:00Z',
        'status': 'confirmed',
        'updated_at': '2026-09-12T09:00:00Z',
      };
      final active = buildWorkloopIcs([
        booking,
      ], generatedAt: DateTime.utc(2026, 9, 12, 9));
      final cancelled = buildWorkloopIcs([
        {
          ...booking,
          'status': 'cancelled',
          'updated_at': '2026-09-12T10:00:00Z',
        },
      ], generatedAt: DateTime.utc(2026, 9, 12, 10));
      expect(active, contains('UID:booking-cancelled@workloop'));
      expect(cancelled, contains('UID:booking-cancelled@workloop'));
      expect(active, contains('STATUS:CONFIRMED'));
      expect(cancelled, contains('STATUS:CANCELLED'));
      expect(cancelled, contains('TRANSP:TRANSPARENT'));
      expect(cancelled, contains('LAST-MODIFIED:20260912T100000Z'));
      expect(cancelled, isNot(contains('STATUS:CONFIRMED')));
    },
  );
}
