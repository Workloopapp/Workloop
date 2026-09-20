import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/appointments/appointments_screen.dart';
import 'package:workloop/features/clients/clients_screen.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/features/profile/profile_screen.dart';
import 'package:workloop/features/notifications/notifications_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/shared/email/email_preferences_repository.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/notifications/local_reminder_service.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/notifications_repository.dart';

class _Notifications implements NotificationsRepository {
  final pending = Completer<void>();
  int marks = 0;
  @override
  Future<void> markRead(String id) {
    marks++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Permission implements LocalReminderService {
  final first = Completer<LocalReminderPermission>();
  int checks = 0;
  @override
  Stream<void> get permissionChanges => const Stream<void>.empty();

  @override
  Future<LocalReminderPermission> permissionStatus() {
    checks++;
    return checks == 1
        ? first.future
        : Future.value(LocalReminderPermission.granted);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _show(
  WidgetTester tester,
  Widget screen,
  List<Override> overrides,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('working hours summary supports current and legacy stored weekdays', () {
    expect(
      profileWorkingHoursSummary({
        'Monday': {'enabled': true},
        'Tue': {'enabled': true},
        'wednesday': {'enabled': true},
        'Thursday': {'enabled': true, 'blocks': []},
        'Friday': {'enabled': false},
      }),
      '3 working days',
    );
  });

  for (final feature in ['clients', 'notes', 'tasks', 'requests', 'bookings']) {
    testWidgets('$feature refresh remains pending until fresh data arrives', (
      tester,
    ) async {
      var calls = 0;
      final pending = Completer<void>();
      Future<List<T>> load<T>() async {
        calls++;
        if (calls > 1) await pending.future;
        return <T>[];
      }

      final (screen, override) = switch (feature) {
        'clients' => (
          const ClientsScreen(),
          clientCrmRecordsProvider.overrideWith((ref) => load()),
        ),
        'notes' => (
          const NotesScreen(showBackButton: false),
          allNotesProvider.overrideWith((ref) => load()),
        ),
        'tasks' => (
          const TasksScreen(),
          allTasksProvider.overrideWith((ref) => load()),
        ),
        'requests' => (
          const BookingRequestsScreen(),
          bookingRequestsProvider.overrideWith((ref) => load()),
        ),
        _ => (
          const AppointmentsScreen(),
          appointmentsProvider.overrideWith((ref) => load()),
        ),
      };
      await _show(tester, screen, [
        if (feature == 'bookings')
          bookingRequestsProvider.overrideWith((ref) async => []),
        override,
      ]);
      var finished = false;
      final completion = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
          .onRefresh()
          .then((_) => finished = true);
      await tester.pump();
      expect(calls, 2);
      expect(finished, isFalse);
      pending.complete();
      await completion;
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty notifications refresh waits for the replacement data', (
    tester,
  ) async {
    final refresh = Completer<List<SlateNotification>>();
    var calls = 0;
    await _show(tester, const NotificationsScreen(), [
      notificationsProvider.overrideWith((ref) {
        calls++;
        return calls == 1 ? Future.value([]) : refresh.future;
      }),
    ]);
    expect(find.text('No notifications'), findsOneWidget);
    expect(
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );
    var finished = false;
    final completion = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh()
        .then((_) => finished = true);
    await tester.pump();
    expect(calls, 2);
    expect(finished, isFalse);
    refresh.complete([]);
    await completion;
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'older unread notifications can be cleared beyond the first page',
    (tester) async {
      await _show(tester, const NotificationsScreen(), [
        unreadNotificationsProvider.overrideWith((ref) async => 1),
        notificationsProvider.overrideWith(
          (ref) async => List.generate(
            50,
            (index) => SlateNotification(
              id: 'read-$index',
              workspaceId: 'workspace',
              type: 'booking',
              title: 'Read update $index',
              body: 'An earlier booking.',
              read: true,
            ),
          ),
        ),
      ]);
      expect(find.text('Mark all read'), findsOneWidget);
    },
  );

  testWidgets('notification refresh failure remains visible and retryable', (
    tester,
  ) async {
    var calls = 0;
    await _show(tester, const NotificationsScreen(), [
      notificationsProvider.overrideWith((ref) async {
        calls++;
        if (calls == 2) throw StateError('offline');
        return const [];
      }),
    ]);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Could not load notifications'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No notifications'), findsOneWidget);
    expect(calls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid notification link has no false navigation affordance', (
    tester,
  ) async {
    await _show(tester, const NotificationsScreen(), [
      notificationsProvider.overrideWith(
        (ref) async => const [
          SlateNotification(
            id: 'bad-link',
            workspaceId: 'workspace',
            type: 'booking',
            title: 'Old update',
            body: 'A historic notification.',
            read: true,
            deepLink: 'https://untrusted.example',
          ),
        ],
      ),
    ]);
    expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    expect(
      tester
          .getSemantics(
            find.bySemanticsLabel('Old update. A historic notification.'),
          )
          .flagsCollection
          .isButton,
      isFalse,
    );
  });

  testWidgets('repeated notification taps open one destination', (
    tester,
  ) async {
    final repository = _Notifications();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const NotificationsScreen()),
        GoRoute(
          path: '/bookings/12000000-0000-4000-8000-000000000001',
          builder: (_, _) => const Scaffold(body: Text('Related work')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
          notificationsProvider.overrideWith(
            (ref) async => const [
              SlateNotification(
                id: 'notification',
                workspaceId: 'workspace',
                type: 'booking',
                title: 'Open booking',
                body: 'A new booking.',
                deepLink: '/bookings/12000000-0000-4000-8000-000000000001',
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open booking'));
    await tester.tap(find.text('Open booking'));
    expect(repository.marks, 1);
    repository.pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Related work'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('business load failures do not masquerade as unfinished setup', (
    tester,
  ) async {
    await _show(tester, const BusinessScreen(), [
      workspaceProvider.overrideWith(
        (ref) async => throw StateError('offline'),
      ),
      settingsBusinessProfileProvider.overrideWith((ref) async => null),
      settingsWorkspaceSettingsProvider.overrideWith(
        (ref) async => throw StateError('offline'),
      ),
      settingsServicesProvider.overrideWith(
        (ref) async => throw StateError('offline'),
      ),
      bookingRequestsProvider.overrideWith((ref) async => const []),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsNothing);
    expect(find.text('Add what customers can book'), findsNothing);
    expect(find.text('Set when you usually work'), findsNothing);
    expect(find.text('Could not load services'), findsOneWidget);
    expect(
      find.textContaining('Could not check your booking page'),
      findsOneWidget,
    );
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'permission check is honest while pending and updates on resume',
    (tester) async {
      final permission = _Permission();
      await _show(tester, const Scaffold(body: NotificationSettingsView()), [
        localReminderServiceProvider.overrideWithValue(permission),
        notificationPreferencesProvider.overrideWith(
          (ref) async => defaultNotificationPrefs,
        ),
        settingsWorkspaceSettingsProvider.overrideWith((ref) async => null),
        accountEmailPreferenceProvider.overrideWith(
          (ref) async => {'enabled': true},
        ),
      ]);
      expect(find.text('Checking phone permission'), findsOneWidget);
      expect(find.text('Phone alerts are off'), findsNothing);
      expect(find.text('Phone alerts allowed'), findsNothing);
      permission.first.complete(LocalReminderPermission.denied);
      await tester.pumpAndSettle();
      expect(find.text('Phone alerts are off'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(permission.checks, 2);
      expect(find.text('Phone alerts allowed'), findsOneWidget);
      expect(find.text('Phone alerts are off'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
