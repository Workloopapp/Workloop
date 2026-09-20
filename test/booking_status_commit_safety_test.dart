import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/repositories/notifications_repository.dart';
import 'package:workloop/shared/repositories/services_repository.dart';

SupabaseClient _client() => SupabaseClient(
  'https://example.supabase.co',
  'test-anon-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

class _Appointments extends AppointmentsRepository {
  _Appointments() : super(_client());
  int saves = 0;
  Map<String, dynamic>? saved;
  @override
  Future<void> update(String id, Map<String, dynamic> values) async {
    saves++;
    saved = values;
  }
}

class _Services extends ServicesRepository {
  _Services() : super(_client());
  @override
  Future<List<Map<String, dynamic>>> listRows(String workspaceId) async => [];
}

class _UnavailableNotifications extends NotificationsRepository {
  _UnavailableNotifications() : super(_client());
  int requests = 0;
  @override
  Future<void> create({
    required String workspaceId,
    required String type,
    required String title,
    required String body,
    String? deepLink,
  }) async {
    requests++;
    throw StateError('notifications unavailable');
  }
}

void main() {
  Future<void> pumpDetail(
    WidgetTester tester, {
    required List<Override> overrides,
    Map<String, dynamic>? initial,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
          clientsProvider.overrideWith((ref) async => []),
          allTasksProvider.overrideWith((ref) async => []),
          invoicesProvider.overrideWith((ref) async => []),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: AppointmentDetailScreen(
            appointment:
                initial ??
                {
                  'id': 'booking-1',
                  'workspace_id': 'workspace-1',
                  'start_time': '2026-09-06T10:00:00',
                  'end_time': '2026-09-06T11:00:00',
                  'status': 'scheduled',
                  'price': 45,
                  'contacts': {'name': 'Alex'},
                  'services': {'name': 'Window clean'},
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('services load only for editing and a failed load can retry', (
    tester,
  ) async {
    var loads = 0;
    await pumpDetail(
      tester,
      overrides: [
        appointmentsProvider.overrideWith((ref) async => []),
        servicesProvider.overrideWith((ref) async {
          loads++;
          if (loads == 1) throw StateError('services offline');
          return [];
        }),
      ],
    );
    expect(loads, 0);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not load services. Your current booking details are kept.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(
      find.text(
        'Could not load services. Your current booking details are kept.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('open booking adopts a refreshed status while not editing', (
    tester,
  ) async {
    var status = 'scheduled';
    await pumpDetail(
      tester,
      overrides: [
        appointmentsProvider.overrideWith(
          (ref) async => [
            {
              'id': 'booking-1',
              'workspace_id': 'workspace-1',
              'start_time': '2026-09-06T10:00:00',
              'end_time': '2026-09-06T11:00:00',
              'status': status,
              'price': 45,
              'contacts': {'name': 'Alex'},
              'services': {'name': 'Window clean'},
            },
          ],
        ),
      ],
    );
    status = 'cancelled';
    ProviderScope.containerOf(
      tester.element(find.byType(AppointmentDetailScreen)),
    ).invalidate(appointmentsProvider);
    await tester.pumpAndSettle();
    expect(find.text('Booking cancelled'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('refreshing booking data never overwrites an active edit draft', (
    tester,
  ) async {
    var title = 'Window clean';
    await pumpDetail(
      tester,
      overrides: [
        servicesProvider.overrideWith((ref) async => []),
        appointmentsProvider.overrideWith(
          (ref) async => [
            {
              'id': 'booking-1',
              'workspace_id': 'workspace-1',
              'start_time': '2026-09-06T10:00:00',
              'end_time': '2026-09-06T11:00:00',
              'status': 'scheduled',
              'price': 45,
              'contacts': {'name': 'Alex'},
              'services': {'name': title},
            },
          ],
        ),
      ],
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Service name'),
      'Keep my draft',
    );
    title = 'Updated elsewhere';
    ProviderScope.containerOf(
      tester.element(find.byType(AppointmentDetailScreen)),
    ).invalidate(appointmentsProvider);
    await tester.pumpAndSettle();
    expect(find.text('Keep my draft'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved cancellation is successful without an owner-self notification',
    (tester) async {
      final repository = _Appointments();
      final notifications = _UnavailableNotifications();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
            clientsProvider.overrideWith((ref) async => []),
            appointmentsProvider.overrideWith((ref) async => []),
            allTasksProvider.overrideWith((ref) async => []),
            invoicesProvider.overrideWith((ref) async => []),
            servicesProvider.overrideWith((ref) async => []),
            servicesRepositoryProvider.overrideWithValue(_Services()),
            appointmentsRepositoryProvider.overrideWithValue(repository),
            notificationsRepositoryProvider.overrideWithValue(notifications),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: AppointmentDetailScreen(
              appointment: {
                'id': 'booking-1',
                'workspace_id': 'workspace-1',
                'start_time': '2026-09-06T10:00:00',
                'end_time': '2026-09-06T11:00:00',
                'status': 'scheduled',
                'price': 45,
                'contacts': {'name': 'Alex'},
                'services': {'name': 'Window clean'},
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel Booking'));
      await tester.tap(find.text('Cancel Booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Client cancelled'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Cancel Booking'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel Booking'));
      await tester.pumpAndSettle();
      expect(repository.saves, 1);
      expect(repository.saved?['status'], 'cancelled');
      expect(find.text('Booking cancelled'), findsOneWidget);
      expect(find.text('The booking could not be updated.'), findsNothing);
      expect(notifications.requests, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
