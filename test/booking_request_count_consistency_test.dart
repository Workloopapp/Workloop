import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';

void main() {
  testWidgets(
    'Today, Business and Active requests agree before and after a decision',
    (tester) async {
      var contactedRequestConfirmed = false;
      var requestReads = 0;
      final container = ProviderContainer(
        overrides: [
          businessNowProvider.overrideWithValue(DateTime(2026, 9, 5, 12)),
          workspaceProvider.overrideWith(
            (ref) async => {'id': 'workspace', 'name': 'Sample business'},
          ),
          settingsBusinessProfileProvider.overrideWith(
            (ref) async => const BusinessProfile(
              id: 'profile',
              workspaceId: 'workspace',
              handle: 'sample-business',
            ),
          ),
          settingsWorkspaceSettingsProvider.overrideWith((ref) async => {}),
          settingsServicesProvider.overrideWith((ref) async => []),
          appointmentsProvider.overrideWith((ref) async => []),
          invoicesProvider.overrideWith((ref) async => []),
          bookingRequestsProvider.overrideWith((ref) async {
            requestReads++;
            final statuses = [
              'pending',
              'pending',
              'pending',
              'pending',
              if (contactedRequestConfirmed) 'confirmed' else 'contacted',
              'contacted',
              'confirmed',
              'declined',
            ];
            return [
              for (var index = 0; index < statuses.length; index++)
                BookingRequest(
                  id: 'request-$index',
                  workspaceId: 'workspace',
                  name: 'Sample customer $index',
                  phone: '',
                  status: statuses[index],
                  // An unanswered past-time request still needs a decision;
                  // changing screens must not silently expire it.
                  requestedFor: DateTime(2026, 9, index.isEven ? 1 : 10),
                ),
            ];
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BusinessScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('6 requests waiting'), findsOneWidget);
      expect(
        (await container.read(
          dashboardFocusProvider.future,
        )).pendingBookingRequests,
        6,
      );
      await tester.tap(find.byKey(const ValueKey('business-booking-requests')));
      await tester.pumpAndSettle();
      expect(find.byType(BookingRequestsScreen), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // New excludes contacted.
      expect(find.text('2'), findsOneWidget); // Closed excludes active.
      expect(requestReads, 1);

      contactedRequestConfirmed = true;
      container.invalidate(bookingRequestsProvider);
      await tester.pumpAndSettle();
      expect(
        (await container.read(
          dashboardFocusProvider.future,
        )).pendingBookingRequests,
        5,
      );
      expect(find.text('5'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(requestReads, 2);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('5 requests waiting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
