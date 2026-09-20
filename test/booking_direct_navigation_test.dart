import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/features/appointments/appointments_screen.dart';
import 'package:workloop/features/dashboard/tomorrow_brief_row.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/client_follow_up_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/utils/client_follow_up.dart';
import 'package:workloop/shared/widgets/record_link_unavailable.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const _id = '12000000-0000-4000-8000-000000000001';
const _workspace = 'workspace-one';

Map<String, dynamic> _booking({String title = 'Tomorrow window clean'}) => {
  'id': _id,
  'workspace_id': _workspace,
  'start_time': '2026-09-08T08:00:00Z',
  'end_time': '2026-09-08T09:00:00Z',
  'status': 'scheduled',
  'price': 45,
  'title': title,
  'contacts': {'name': 'Tomorrow customer'},
};

class _Auth extends Fake implements AuthRepository {
  @override
  String? get currentUserId => 'owner';
}

class _RouteObserver extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes.add(route);
  }
}

class _Workspace extends Notifier<String> {
  @override
  String build() => _workspace;
  void change() => state = 'other-workspace';
}

final _workspaceSelection = NotifierProvider<_Workspace, String>(
  _Workspace.new,
);

Future<({ProviderContainer container, _RouteObserver observer})> _show(
  WidgetTester tester, {
  required Future<List<Map<String, dynamic>>> Function() load,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      workspaceIdProvider.overrideWith(
        (ref) async => ref.watch(_workspaceSelection),
      ),
      appointmentsProvider.overrideWith((ref) async {
        await ref.watch(workspaceIdProvider.future);
        return load();
      }),
      tomorrowBriefProvider.overrideWith(
        (_) async => TomorrowBrief(
          [Appointment.fromMap(_booking())],
          'Europe/London',
          60,
          workspaceId: _workspace,
        ),
      ),
      invoicesProvider.overrideWith((_) async => []),
      allTasksProvider.overrideWith((_) async => []),
      clientsProvider.overrideWith((_) async => []),
      servicesProvider.overrideWith((_) async => []),
      workspaceSettingsProvider.overrideWith(
        (_) async => {'workspace_id': _workspace},
      ),
      paymentCollectionEnabledProvider.overrideWithValue(false),
    ],
  );
  addTearDown(container.dispose);
  await container.read(workspaceIdProvider.future);
  final observer = _RouteObserver();
  final router = GoRouter(
    observers: [observer],
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: TomorrowBriefRow()),
        ),
      ),
      // This is the same destination widget as the production booking route.
      GoRoute(
        path: '/bookings/:bookingId',
        builder: (_, state) => AppointmentsScreen(
          initialAppointmentId: state.pathParameters['bookingId'],
          showBackButton: true,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('tomorrow-brief-row')));
  await tester.pumpAndSettle();
  observer.pushes.clear();
  return (container: container, observer: observer);
}

Future<void> _tapBooking(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tomorrow-booking-$_id')));
}

void _expectNoSchedule() {
  expect(find.text('Today'), findsNothing);
  expect(find.text('Upcoming'), findsNothing);
  expect(find.text('Nothing scheduled today'), findsNothing);
  expect(find.byType(TabBarView), findsNothing);
}

Future<void> _checkTransition(WidgetTester tester) async {
  // Do not hide a transient wrong screen behind pumpAndSettle: inspect the
  // first routed frame and each following 16ms transition frame individually.
  await tester.pump();
  _expectNoSchedule();
  for (var frame = 0; frame < 24; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    _expectNoSchedule();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets(
    'tomorrow opens one direct booking route without a Today frame or extra Back',
    (tester) async {
      var reads = 0;
      final harness = await _show(
        tester,
        load: () async {
          reads++;
          return [_booking()];
        },
      );
      await harness.container.read(appointmentsProvider.future);
      await _tapBooking(tester);
      await _checkTransition(tester);
      expect(find.byType(AppointmentDetailScreen), findsOneWidget);
      expect(find.text('Tomorrow customer'), findsOneWidget);
      expect(harness.observer.pushes, hasLength(1));
      expect(
        reads,
        1,
        reason: 'Opening a loaded booking must not refetch all bookings.',
      );

      tester
          .widget<WorkloopRouteHeader>(find.byType(WorkloopRouteHeader))
          .onBack!();
      await tester.pumpAndSettle();
      expect(find.byType(AppointmentDetailScreen), findsNothing);
      expect(find.byKey(const ValueKey('tomorrow-brief-row')), findsOneWidget);
      _expectNoSchedule();
    },
  );

  testWidgets('a refreshing exact link never reveals Today or stale detail', (
    tester,
  ) async {
    final fresh = Completer<List<Map<String, dynamic>>>();
    var reads = 0;
    final harness = await _show(
      tester,
      load: () => ++reads == 1
          ? Future.value([_booking(title: 'Stale booking title')])
          : fresh.future,
    );
    await harness.container.read(appointmentsProvider.future);
    harness.container.invalidate(appointmentsProvider);
    final reload = harness.container.read(appointmentsProvider.future);
    await _tapBooking(tester);
    await _checkTransition(tester);
    expect(find.byType(AppointmentDetailScreen), findsNothing);
    expect(find.text('Stale booking title'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    fresh.complete([_booking(title: 'Fresh booking title')]);
    await reload;
    await _checkTransition(tester);
    expect(find.byType(AppointmentDetailScreen), findsOneWidget);
    expect(find.text('Fresh booking title'), findsWidgets);
    expect(harness.observer.pushes, hasLength(1));
  });

  testWidgets('a workspace change removes the open exact booking immediately', (
    tester,
  ) async {
    final harness = await _show(tester, load: () async => [_booking()]);
    await _tapBooking(tester);
    await _checkTransition(tester);
    expect(find.text('Tomorrow customer'), findsOneWidget);
    harness.container.read(_workspaceSelection.notifier).change();
    await tester.pump();
    expect(find.byType(AppointmentDetailScreen), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow customer'), findsNothing);
    expect(find.byType(WorkloopRecordLinkUnavailable), findsOneWidget);
    _expectNoSchedule();
  });

  testWidgets('an exact detail draft survives background booking refresh', (
    tester,
  ) async {
    final refreshed = Completer<List<Map<String, dynamic>>>();
    var reads = 0;
    final harness = await _show(
      tester,
      load: () => ++reads == 1 ? Future.value([_booking()]) : refreshed.future,
    );
    await _tapBooking(tester);
    await _checkTransition(tester);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    final title = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller?.text == 'Tomorrow window clean',
    );
    await tester.enterText(title, 'Keep this unsaved draft');
    harness.container.invalidate(appointmentsProvider);
    await tester.pump();
    expect(find.text('Keep this unsaved draft'), findsOneWidget);
    refreshed.complete([_booking(title: 'Server update')]);
    await tester.pumpAndSettle();
    expect(find.text('Keep this unsaved draft'), findsOneWidget);
    expect(find.text('Server update'), findsNothing);
    expect(harness.observer.pushes, hasLength(1));
    _expectNoSchedule();
  });
}
