import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/profile/booking_page_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';

void main() {
  testWidgets('booking page hub explains readiness, sharing and requests', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(
            (ref) async => const {
              'id': 'workspace-1',
              'name': 'Quality Studio',
              'industry': 'Business consulting',
            },
          ),
          settingsBusinessProfileProvider.overrideWith(
            (ref) async => const BusinessProfile(
              id: 'profile-1',
              workspaceId: 'workspace-1',
              handle: 'quality-studio',
              bookingMode: 'manual',
            ),
          ),
          settingsWorkspaceSettingsProvider.overrideWith(
            (ref) async => const {
              'working_hours': {
                'monday': {'enabled': true, 'open': '09:00', 'close': '17:00'},
              },
            },
          ),
          settingsServicesProvider.overrideWith(
            (ref) async => const [
              {
                'id': 'service-1',
                'workspace_id': 'workspace-1',
                'name': 'Signature consultation',
                'duration_mins': 60,
                'price': 85.0,
                'active': true,
                'show_on_profile': true,
              },
            ],
          ),
          bookingRequestsProvider.overrideWith(
            (ref) async => const [
              BookingRequest(
                id: 'request-1',
                workspaceId: 'workspace-1',
                name: 'Aisha Morgan',
                phone: '+44 7700 900123',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: BookingPageScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Booking page'), findsOneWidget);
    expect(find.text('Accepting requests'), findsOneWidget);
    expect(find.text('workloop.uk/quality-studio'), findsWidgets);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Page readiness'), findsOneWidget);
    expect(find.text('1 service shown'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Booking requests')).dy,
      lessThan(tester.getTopLeft(find.text('Page readiness')).dy),
    );

    await tester.scrollUntilVisible(find.text('Booking requests'), 220);
    expect(find.text('1 request waiting for a response'), findsOneWidget);
    await tester.tap(find.text('Booking requests'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingRequestsScreen), findsOneWidget);
    expect(find.text('Aisha Morgan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
