import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointments_screen.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/features/work/work_screen.dart';
import 'package:workloop/features/work/work_workspace_switcher.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  testWidgets('Work keeps its command header while retained content changes', (
    tester,
  ) async {
    final section = ValueNotifier(WorkWorkspaceSection.schedule);
    addTearDown(section.dispose);
    await _pump(
      tester,
      WorkScreen(sectionController: section),
      overrides: [
        appointmentsProvider.overrideWith((ref) async => const []),
        bookingRequestsProvider.overrideWith((ref) async => const []),
        allTasksProvider.overrideWith((ref) async => const []),
        allNotesProvider.overrideWith((ref) async => const []),
      ],
    );

    final headerFinder = find.byType(WorkloopPageHeader);
    expect(headerFinder, findsOneWidget);
    final headerRect = tester.getRect(headerFinder);
    expect(find.text('Nothing scheduled today'), findsOneWidget);

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    expect(tester.getRect(headerFinder), headerRect);
    expect(find.text('Nothing to do'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pump();
    expect(tester.getRect(headerFinder), headerRect);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.byType(WorkloopTopAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Work switcher connects Schedule, Tasks and Notes', (
    tester,
  ) async {
    var openedTasks = 0;
    var openedNotes = 0;
    await _pump(
      tester,
      AppointmentsScreen(
        onOpenTasks: () => openedTasks++,
        onOpenNotes: () => openedNotes++,
      ),
      overrides: [
        appointmentsProvider.overrideWith((ref) async => const []),
        bookingRequestsProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await tester.tap(find.text('Tasks'));
    await tester.tap(find.text('Notes'));
    expect(openedTasks, 1);
    expect(openedNotes, 1);

    var openedSchedule = 0;
    openedNotes = 0;
    await _pump(
      tester,
      TasksScreen(
        onOpenSchedule: () => openedSchedule++,
        onOpenNotes: () => openedNotes++,
      ),
      overrides: [allTasksProvider.overrideWith((ref) async => const [])],
    );
    await tester.tap(find.text('Schedule'));
    await tester.tap(find.text('Notes'));
    expect(openedSchedule, 1);
    expect(openedNotes, 1);

    openedSchedule = 0;
    var openedTaskList = 0;
    await _pump(
      tester,
      NotesScreen(
        showBackButton: false,
        onOpenSchedule: () => openedSchedule++,
        onOpenTasks: () => openedTaskList++,
      ),
      overrides: [allNotesProvider.overrideWith((ref) async => const [])],
    );
    await tester.tap(find.text('Schedule'));
    await tester.tap(find.text('Tasks'));
    expect(openedSchedule, 1);
    expect(openedTaskList, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Business leads with booking requests and compact management rows',
    (tester) async {
      const profile = BusinessProfile(
        id: 'profile-1',
        workspaceId: 'workspace-1',
        handle: 'workloop-studio',
      );
      const request = BookingRequest(
        id: 'request-1',
        workspaceId: 'workspace-1',
        name: 'Jamie Taylor',
        phone: '07000000000',
      );
      await _pump(
        tester,
        const BusinessScreen(),
        overrides: [
          workspaceProvider.overrideWith(
            (ref) async => const {
              'id': 'workspace-1',
              'name': 'Workloop Studio',
            },
          ),
          settingsBusinessProfileProvider.overrideWith((ref) async => profile),
          settingsWorkspaceSettingsProvider.overrideWith(
            (ref) async => const {
              'working_hours': {
                'monday': {'enabled': true},
              },
            },
          ),
          settingsServicesProvider.overrideWith(
            (ref) async => const [
              {
                'id': 'service-1',
                'name': 'Window cleaning',
                'active': true,
                'show_on_profile': true,
              },
            ],
          ),
          bookingRequestsProvider.overrideWith((ref) async => const [request]),
        ],
      );

      expect(find.text('Business'), findsOneWidget);
      expect(find.text('Your booking page'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('1 request waiting'), findsOneWidget);
      expect(find.text('Booking requests'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('business-booking-page')),
        findsOneWidget,
      );
      expect(find.text('Run your business'), findsOneWidget);
      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
      expect(find.text('Services'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Working hours'), 120);
      expect(find.text('Working hours'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Business profile'), 120);
      expect(find.text('Business profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
  await tester.pumpAndSettle();
}
