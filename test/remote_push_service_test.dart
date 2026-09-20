import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/notifications/remote_push_bootstrap.dart';
import 'package:workloop/shared/notifications/remote_push_service.dart';

void main() {
  test('APNs environment is explicit and never inferred from build mode', () {
    expect(apnsEnvironmentFromDefine('production'), 'production');
    expect(apnsEnvironmentFromDefine('sandbox'), 'sandbox');
    expect(apnsEnvironmentFromDefine(''), isNull);
    expect(apnsEnvironmentFromDefine('release'), isNull);
    expect(apnsEnvironmentFromDefine('profile'), isNull);
    expect(apnsEnvironmentFromDefine('development'), isNull);
  });

  test('remote push routes only open known authenticated surfaces', () {
    const bookingId = '12000000-0000-4000-8000-000000000001';
    expect(
      remotePushRouteFromData(const {'deep_link': '/booking-requests'}),
      '/notifications',
    );
    expect(
      remotePushRouteFromData(const {'deep_link': '/bookings/$bookingId'}),
      '/bookings/$bookingId',
    );
    expect(
      remotePushRouteFromData(const {
        'deep_link': '/tasks/12000000-0000-4000-8000-000000000002',
      }),
      '/tasks/12000000-0000-4000-8000-000000000002',
    );
    expect(
      remotePushRouteFromData(const {'deep_link': '/unknown-private-route'}),
      '/notifications',
    );
    expect(
      remotePushRouteFromData(const {
        'deep_link': '/bookings/not-a-workloop-id',
      }),
      '/notifications',
    );
    expect(
      remotePushRouteFromData(const {
        'deep_link':
            '/bookings/12000000-0000-4000-8000-000000000001?workspace=other',
      }),
      '/notifications',
    );
    expect(
      remotePushRouteFromData(const {'deep_link': 'https://bad.test'}),
      isNull,
    );
    expect(remotePushRouteFromData(const {}), isNull);
  });

  test('push registration context must still match user and workspace', () {
    const contextKey = 'user-1:workspace-1';

    expect(
      pushRegistrationContextMatches(
        contextKey: contextKey,
        userId: 'user-1',
        workspaceId: 'workspace-1',
      ),
      isTrue,
    );
    expect(
      pushRegistrationContextMatches(
        contextKey: contextKey,
        userId: 'user-2',
        workspaceId: 'workspace-1',
      ),
      isFalse,
    );
    expect(
      pushRegistrationContextMatches(
        contextKey: contextKey,
        userId: 'user-1',
        workspaceId: 'workspace-2',
      ),
      isFalse,
    );
    expect(
      pushRegistrationContextMatches(
        contextKey: contextKey,
        userId: null,
        workspaceId: 'workspace-1',
      ),
      isFalse,
    );
  });
}
