import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/appointments/appointments_screen.dart';
import 'package:workloop/features/clients/providers/client_detail_providers.dart';
import 'package:workloop/features/clients/widgets/client_overview_tab.dart';
import 'package:workloop/features/profile/working_hours_editor.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/public_profile/public_profile_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/settings/widgets/settings_business_tab.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';
import 'package:workloop/shared/sms/booking_sms_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  testWidgets('business settings load failures expose an accessible retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
          settingsBusinessProfileProvider.overrideWith((ref) async => null),
          settingsWorkspaceSettingsProvider.overrideWith((ref) async => null),
          settingsServicesProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SettingsBusinessTab(showOnlySelected: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load workspace'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.bySemanticsLabel('Try again'), findsOneWidget);
    expect(find.bySemanticsLabel('Could not load workspace'), findsOneWidget);
  });

  testWidgets(
    'client overview reports provider failure instead of trustworthy-looking zeroes',
    (tester) async {
      final sourceError = StateError('offline');
      var failing = true;
      var appointmentReads = 0;
      var paymentReads = 0;
      var taskReads = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientAppointmentsProvider.overrideWith((ref, clientId) async {
              appointmentReads++;
              if (failing) throw sourceError;
              return [];
            }),
            clientPaymentsProvider.overrideWith((ref, clientId) async {
              paymentReads++;
              if (failing) throw sourceError;
              return [];
            }),
            clientTasksProvider.overrideWith((ref, clientId) async {
              taskReads++;
              if (failing) throw sourceError;
              return [];
            }),
            bookingSmsCapabilitiesProvider.overrideWith(
              (ref) async => const BookingSmsCapabilities(
                availability: BookingSmsAvailability.notReady,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ClientOverviewTab(
                clientId: 'client-1',
                client: const {'name': 'Launch Client'},
                onEdit: () {},
                onOpenBookings: () {},
                onOpenPayments: () {},
                onOpenTasks: () {},
                onOpenAddress: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Some client activity could not be loaded. Try again before relying on this overview.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nothing booked yet'), findsNothing);
      expect(find.text('Bookings completed'), findsNothing);
      expect(find.text('Recent activity'), findsNothing);
      final activityError = find.ancestor(
        of: find.text(
          'Some client activity could not be loaded. Try again before relying on this overview.',
        ),
        matching: find.byType(SlateErrorState),
      );
      final retry = find.descendant(
        of: activityError,
        matching: find.widgetWithText(TextButton, 'Try again'),
      );
      expect(retry, findsOneWidget);
      final readsBefore = (appointmentReads, paymentReads, taskReads);
      failing = false;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(appointmentReads, greaterThan(readsBefore.$1));
      expect(paymentReads, greaterThan(readsBefore.$2));
      expect(taskReads, greaterThan(readsBefore.$3));
      expect(activityError, findsNothing);
      expect(find.text('Nothing booked yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar month navigation is labelled and thumb sized', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentsProvider.overrideWith((ref) async => const []),
          bookingRequestsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: AppointmentsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Calendar'));
    await tester.pumpAndSettle();

    final previous = find.byTooltip('Previous month');
    final next = find.byTooltip('Next month');
    expect(previous, findsOneWidget);
    expect(next, findsOneWidget);
    expect(find.bySemanticsLabel('Previous month'), findsOneWidget);
    expect(find.bySemanticsLabel('Next month'), findsOneWidget);
    expect(tester.getSize(previous).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(previous).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(next).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(next).height, greaterThanOrEqualTo(44));
  });

  testWidgets('checklist removal is labelled and thumb sized', (tester) async {
    const task = SlateTask(
      id: 'task-1',
      workspaceId: 'workspace-1',
      title: 'Launch checklist',
    );
    const item = TaskChecklistItem(
      id: 'item-1',
      workspaceId: 'workspace-1',
      taskId: 'task-1',
      title: 'Test iOS',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTasksProvider.overrideWith((ref) async => const [task]),
          workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
          clientsProvider.overrideWith((ref) async => const []),
          taskChecklistProvider.overrideWith(
            (ref, taskId) async => const [item],
          ),
        ],
        child: const MaterialApp(home: TasksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Launch checklist'));
    await tester.pumpAndSettle();

    final remove = find.byTooltip('Remove Test iOS from checklist');
    expect(remove, findsOneWidget);
    expect(
      find.bySemanticsLabel('Remove Test iOS from checklist'),
      findsOneWidget,
    );
    expect(tester.getSize(remove).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
  });

  testWidgets('working-hours block removal is labelled and thumb sized', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsWorkspaceSettingsProvider.overrideWith(
            (ref) async => const {
              'working_hours': {
                'Monday': {
                  'enabled': true,
                  'blocks': [
                    {'start': '09:00', 'end': '12:00'},
                    {'start': '13:00', 'end': '17:00'},
                  ],
                },
              },
            },
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: WorkingHoursEditor())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Edit Monday hours'));
    await tester.pumpAndSettle();
    final remove = find.byTooltip('Remove Monday time block 1');
    expect(remove, findsOneWidget);
    expect(find.bySemanticsLabel('Remove Monday time block 1'), findsOneWidget);
    expect(tester.getSize(remove).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
  });

  testWidgets('legacy pay-now flag is never advertised publicly', (
    tester,
  ) async {
    const preview = PublicProfile(
      profile: BusinessProfile(
        id: 'profile-1',
        workspaceId: 'workspace-1',
        handle: 'launch-studio',
        payNowEnabled: true,
      ),
      businessName: 'Launch Studio',
      workingHours: {},
      services: [],
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PublicProfileScreen(
            handle: 'launch-studio',
            previewProfile: preview,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch Studio'), findsOneWidget);
    expect(find.text('Pay now available'), findsNothing);
  });

  test('legacy pay-now value round-trips without enabling the feature', () {
    const profile = BusinessProfile(
      id: 'profile-1',
      workspaceId: 'workspace-1',
      handle: 'launch-studio',
      payNowEnabled: true,
    );

    expect(profile.payNowEnabled, isFalse);
    expect(profile.toMap()['pay_now_enabled'], isTrue);
  });
}
