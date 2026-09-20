import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/notifications/notification_route.dart';

void main() {
  const id = '12000000-0000-4000-8000-000000000001';

  test('allows exact entity destinations used by notifications', () {
    for (final route in const [
      '/bookings/$id',
      '/booking-requests/$id',
      '/payments/$id',
      '/tasks/$id',
      '/notes/$id',
    ]) {
      expect(workloopNotificationRoute(route), route);
    }
  });

  test('rejects malformed, external and parameter-bearing destinations', () {
    expect(
      workloopNotificationRoute('https://example.test/bookings/$id'),
      isNull,
    );
    expect(workloopNotificationRoute('/bookings/not-a-uuid'), isNull);
    expect(
      workloopNotificationRoute('/bookings/$id?workspace=another'),
      isNull,
    );
    expect(workloopNotificationRoute('/bookings/$id#private'), isNull);
  });

  test(
    'legacy record collections open inbox while genuine summaries keep Today',
    () {
      for (final route in [
        '/payments',
        '/booking-requests',
        '/work',
        '/tasks',
        '/notes',
      ]) {
        expect(workloopNotificationDestination(route), '/notifications');
      }
      expect(workloopNotificationDestination('/bookings/$id'), '/bookings/$id');
      expect(workloopNotificationDestination('/home'), '/home');
      expect(
        workloopNotificationHasMissingRecordLink('morning_digest', '/home'),
        isFalse,
      );
      expect(
        workloopNotificationHasMissingRecordLink('booking', '/work'),
        isTrue,
      );
      expect(
        workloopNotificationHasMissingRecordLink(
          'payment_received',
          '/payments/$id',
        ),
        isFalse,
      );
    },
  );

  test('constructs stable entity paths', () {
    expect(
      workloopNotificationEntityRoute(WorkloopNotificationEntity.booking, id),
      '/bookings/$id',
    );
    expect(
      workloopNotificationEntityRoute(
        WorkloopNotificationEntity.bookingRequest,
        id,
      ),
      '/booking-requests/$id',
    );
  });
}
