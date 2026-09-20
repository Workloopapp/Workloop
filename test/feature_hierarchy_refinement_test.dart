import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointments_screen.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/profile/booking_page_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/features/work/work_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

List<Override> _businessData({
  bool pageUnavailable = false,
  bool emptyHours = false,
}) => [
  workspaceProvider.overrideWith(
    (ref) async => const {'id': 'workspace-one', 'name': 'Sample Studio'},
  ),
  settingsBusinessProfileProvider.overrideWith((ref) async {
    if (pageUnavailable) throw StateError('page temporarily unavailable');
    return const BusinessProfile(
      id: 'profile-one',
      workspaceId: 'workspace-one',
      handle: 'sample-studio',
    );
  }),
  settingsWorkspaceSettingsProvider.overrideWith(
    (ref) async => {
      'working_hours': {
        'Monday': {'enabled': true, if (emptyHours) 'blocks': <Object>[]},
      },
    },
  ),
  settingsServicesProvider.overrideWith(
    (ref) async => const [
      {
        'id': 'service-one',
        'workspace_id': 'workspace-one',
        'name': 'Window clean',
        'duration_minutes': 30,
        'price': 35,
        'active': true,
        'show_on_profile': true,
      },
    ],
  ),
  bookingRequestsProvider.overrideWith(
    (ref) async => const [
      BookingRequest(
        id: 'request-one',
        workspaceId: 'workspace-one',
        name: 'Jamie Sample',
        phone: '07000000000',
      ),
    ],
  ),
];

Future<void> _show(
  WidgetTester tester,
  Widget screen,
  List<Override> overrides, {
  double scale = 1,
  bool shell = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
            textScaler: TextScaler.linear(scale),
          ),
          child: shell
              ? Scaffold(
                  extendBody: true,
                  body: screen,
                  bottomNavigationBar: SizedBox(
                    height: AppSpacing.bottomNavHeight + 34,
                  ),
                )
              : screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final screen in <Widget>[
    const BusinessScreen(),
    const BookingPageScreen(),
  ]) {
    testWidgets(
      '${screen.runtimeType} does not advertise empty hours as ready',
      (tester) async {
        await _show(tester, screen, _businessData(emptyHours: true));
        expect(find.text('Needs attention'), findsOneWidget);
        expect(find.text('Live'), findsNothing);
        expect(find.text('Accepting requests'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Business keeps requests and key management easy to reach', (
    tester,
  ) async {
    await _show(tester, const BusinessScreen(), _businessData(), shell: true);
    expect(find.byType(WorkloopWordmark), findsNothing);
    final requests = tester.getRect(
      find.byKey(const ValueKey('business-booking-requests')),
    );
    final page = tester.getRect(
      find.byKey(const ValueKey('business-booking-page')),
    );
    final services = tester.getRect(
      find.byKey(const ValueKey('business-services')),
    );
    final hours = tester.getRect(find.byKey(const ValueKey('business-hours')));
    final profile = tester.getRect(
      find.byKey(const ValueKey('business-profile')),
    );
    expect(requests.top, lessThan(page.top));
    expect(page.top, lessThan(services.top));
    expect(services.top, lessThan(hours.top));
    expect(hours.top, lessThan(profile.top));
    expect(
      hours.bottom,
      lessThanOrEqualTo(844 - AppSpacing.bottomNavHeight - 34),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('business-profile')));
    await tester.pumpAndSettle();
    expect(find.text('1 request waiting'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking request inbox opens even when booking page data fails', (
    tester,
  ) async {
    await _show(
      tester,
      const BusinessScreen(),
      _businessData(pageUnavailable: true),
    );
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('business-booking-requests')));
    await tester.pumpAndSettle();
    expect(find.byType(BookingRequestsScreen), findsOneWidget);
    expect(find.text('Jamie Sample'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking-page requests precede the setup checklist', (
    tester,
  ) async {
    await _show(tester, const BookingPageScreen(), _businessData());
    final requests = tester.getTopLeft(find.text('Booking requests'));
    final readiness = tester.getTopLeft(find.text('Page readiness'));
    expect(requests.dy, lessThan(readiness.dy));
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final screen in <Widget>[
    const WorkScreen(),
    const AppointmentsScreen(),
    const TasksScreen(),
    const NotesScreen(showBackButton: false),
  ]) {
    testWidgets(
      '${screen.runtimeType} starts after one safe inset without repeated branding',
      (tester) async {
        await _show(tester, screen, [
          appointmentsProvider.overrideWith((ref) async => const []),
          bookingRequestsProvider.overrideWith((ref) async => const []),
          allTasksProvider.overrideWith((ref) async => const []),
          allNotesProvider.overrideWith((ref) async => const []),
        ]);
        expect(find.byType(WorkloopWordmark), findsNothing);
        expect(find.byType(WorkloopPageHeader), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(WorkloopPageHeader)).dy,
          47 + AppSpacing.screenTop,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Money shows category totals before its recent expense history', (
    tester,
  ) async {
    await _show(tester, const FinanceScreen(), [
      invoicesProvider.overrideWith((ref) async => const []),
      expensesProvider.overrideWith(
        (ref) async => [
          Expense(
            id: 'expense-one',
            workspaceId: 'workspace-one',
            amount: 30,
            category: 'Materials',
            notes: 'Supplies for Monday',
            expenseDate: DateTime.now(),
          ),
        ],
      ),
      workspaceSettingsProvider.overrideWith(
        (ref) async => const {'revenue_target': 1000},
      ),
    ]);
    await tester.tap(find.text('Spent'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkloopWordmark), findsNothing);
    expect(
      tester.getTopLeft(find.text('Spending by category')).dy,
      lessThan(tester.getTopLeft(find.text('Supplies for Monday')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
