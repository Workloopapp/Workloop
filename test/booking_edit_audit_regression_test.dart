import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Appointments extends AppointmentsRepository {
  _Appointments({Map<String, dynamic>? appointment})
    : initial = appointment ?? original,
      super(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final Map<String, dynamic> initial;
  Map<String, dynamic>? saved;
  bool? replaceItems;
  @override
  Future<Map<String, dynamic>> editBookingWorkflow({
    required String appointmentId,
    required Map<String, dynamic> values,
    required bool replaceServiceItems,
  }) async {
    saved = values;
    replaceItems = replaceServiceItems;
    return {
      ...initial,
      ...values,
      'appointment_items': replaceServiceItems
          ? [
              {
                ...((initial['appointment_items'] as List).first as Map),
                'name': values['title'],
                'source_service_id': values['service_id'],
                'price': values['price'],
              },
            ]
          : initial['appointment_items'],
    };
  }

  @override
  Future<void> update(String id, Map<String, dynamic> values) async {
    saved = values;
  }

  @override
  Future<AppointmentScheduleReview> reviewSchedule({
    required String workspaceId,
    required DateTime startTime,
    required DateTime endTime,
    Map<String, dynamic>? workingHours,
    String? workingHoursTimezone,
    String? excludeAppointmentId,
    String? recurrenceRule,
    int repeatOccurrences = 1,
  }) async => const AppointmentScheduleReview(
    outsideWorkingHoursCount: 0,
    conflictCount: 0,
  );
}

final original = <String, dynamic>{
  'id': 'booking-1',
  'workspace_id': 'workspace-1',
  'service_id': 'service-1',
  'title': 'Window clean',
  'start_time': '2026-09-15T10:00:00Z',
  'end_time': '2026-09-15T11:00:00Z',
  'status': 'scheduled',
  'price': 45,
  'notes': 'Gate code 1234. Use side entrance.',
  'contacts': {'name': 'Alex'},
  'services': {'name': 'Window clean'},
  'appointment_items': [
    {
      'id': 'item-1',
      'workspace_id': 'workspace-1',
      'item_kind': 'base',
      'source_service_id': 'service-1',
      'name': 'Window clean',
      'duration_mins': 60,
      'price': 45,
      'position': 0,
    },
  ],
};
Future<void> _pump(WidgetTester tester, _Appointments repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
        workspaceSettingsProvider.overrideWith(
          (ref) async => {'timezone': 'Europe/London'},
        ),
        businessClockProvider.overrideWith(
          (ref) => Stream.value(DateTime.utc(2026, 9, 12, 10)),
        ),
        clientsProvider.overrideWith((ref) async => []),
        appointmentsProvider.overrideWith((ref) async => []),
        allTasksProvider.overrideWith((ref) async => []),
        invoicesProvider.overrideWith((ref) async => []),
        servicesProvider.overrideWith(
          (ref) async => [
            {
              'id': 'service-1',
              'name': 'Window clean',
              'duration_mins': 60,
              'price': 45,
            },
            {
              'id': 'service-2',
              'name': 'Gutter clean',
              'duration_mins': 60,
              'price': 45,
            },
          ],
        ),
        appointmentsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: AppointmentDetailScreen(appointment: Map.from(repo.initial)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('editing notes preserves an existing multi-service breakdown', (
    tester,
  ) async {
    final repo = _Appointments(
      appointment: {
        ...original,
        'title': 'Window clean + Gutter clean',
        'price': 60,
        'appointment_items': [
          ...(original['appointment_items'] as List),
          {
            'id': 'item-2',
            'workspace_id': 'workspace-1',
            'item_kind': 'service',
            'source_service_id': 'service-2',
            'name': 'Gutter clean',
            'duration_mins': 30,
            'price': 15,
            'position': 1,
          },
        ],
      },
    );
    await _pump(tester, repo);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final notes = find.widgetWithText(TextField, 'Notes');
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Keep the side gate closed');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.replaceItems, isFalse);
    expect(repo.saved?['title'], 'Window clean + Gutter clean');
    expect(repo.saved?['notes'], 'Keep the side gate closed');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'cancellation preserves booking notes and records separate metadata',
    (tester) async {
      final repo = _Appointments();
      await _pump(tester, repo);
      await tester.ensureVisible(find.text('Cancel Booking'));
      await tester.tap(find.text('Cancel Booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Client cancelled'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(ElevatedButton, 'Cancel Booking');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.saved?['status'], 'cancelled');
      expect(repo.saved!.containsKey('notes'), isFalse);
      expect(repo.saved?['cancellation_reason'], 'Client cancelled');
      expect(
        DateTime.tryParse(repo.saved?['cancelled_at'] as String),
        isNotNull,
      );
      expect(find.text('Gate code 1234. Use side entrance.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('saving a same-price service uses atomic snapshot replacement', (
    tester,
  ) async {
    final repo = _Appointments();
    await _pump(tester, repo);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final picker = find.byWidgetPredicate(
      (w) => w is WorkloopPickerField<String> && w.title == 'Choose a service',
    );
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gutter clean'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved?['service_id'], 'service-2');
    expect(repo.saved?['title'], 'Gutter clean');
    expect(repo.saved!.containsKey('appointment_items'), isFalse);
    expect(repo.replaceItems, isTrue);
    expect(find.text('Gutter clean'), findsWidgets);
    expect(find.text('Window clean'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
