import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/profile/booking_page_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';

void main() {
  testWidgets('Business remains usable on a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(
            (ref) async => const {'id': 'workspace-1'},
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
                'Monday': {
                  'enabled': true,
                  'blocks': [
                    {'start': '09:00', 'end': '17:00'},
                  ],
                },
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
          bookingRequestsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              devicePixelRatio: 1,
              textScaler: TextScaler.linear(1),
              disableAnimations: true,
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: BusinessScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Your booking page'), findsOneWidget);
    for (final key in [
      'business-booking-requests',
      'business-booking-page',
      'business-services',
      'business-hours',
      'business-profile',
      'business-customer-reminders',
    ]) {
      final control = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(control, 140);
      await tester.pumpAndSettle();
      expect(control.hitTestable(), findsOneWidget, reason: key);
      expect(
        tester.getSize(control).height,
        greaterThanOrEqualTo(44),
        reason: key,
      );
    }
    final page = find.byKey(const ValueKey('business-booking-page'));
    await tester.scrollUntilVisible(page, -140);
    await tester.pumpAndSettle();
    expect(page.hitTestable(), findsOneWidget);
    await tester.tap(page);
    await tester.pumpAndSettle();
    expect(find.byType(BookingPageScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
