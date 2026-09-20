import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/appointments/appointments_screen.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/features/clients/client_detail_screen.dart';
import 'package:workloop/features/clients/client_record_link_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/widgets/record_link_unavailable.dart';

const _id = '12000000-0000-4000-8000-000000000001';
const _otherId = '12000000-0000-4000-8000-000000000002';
const _workspace = 'workspace-one';
Payment _payment(String id) => Payment(
  id: id,
  workspaceId: _workspace,
  number: id,
  status: 'paid',
  issueDate: DateTime(2025, 1, 1),
  total: 73,
  notes: 'Exact payment $id',
  clientName: 'Payment client',
);

List<Override> _defaults() => [
  workspaceIdProvider.overrideWith((_) async => _workspace),
  invoicesProvider.overrideWith((_) async => []),
  expensesProvider.overrideWith((_) async => []),
  allTasksProvider.overrideWith((_) async => []),
  allNotesProvider.overrideWith((_) async => []),
  appointmentsProvider.overrideWith((_) async => []),
  bookingRequestsProvider.overrideWith((_) async => []),
  clientsProvider.overrideWith((_) async => []),
  servicesProvider.overrideWith((_) async => []),
  workspaceSettingsProvider.overrideWith(
    (_) async => {'workspace_id': _workspace},
  ),
  paymentCollectionEnabledProvider.overrideWithValue(false),
  taskChecklistProvider.overrideWith((ref, id) async => []),
];

Future<ProviderContainer> _show(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  ProviderContainer? container,
}) async {
  final scope =
      container ??
      ProviderContainer(
        overrides: [
          // Callers replace exact entries rather than stacking duplicate overrides.
          ..._defaults().where(
            (base) =>
                !overrides.any((override) => override.origin == base.origin),
          ),
          ...overrides,
        ],
      );
  if (container == null) addTearDown(scope.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
  await tester.pumpAndSettle();
  return scope;
}

void main() {
  testWidgets(
    'payment link waits for refresh instead of consuming a retained empty snapshot',
    (tester) async {
      final pending = Completer<List<Payment>>();
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          ..._defaults().where((item) => item.origin != invoicesProvider),
          invoicesProvider.overrideWith(
            (_) async => ++calls == 1 ? [] : pending.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(invoicesProvider.future);
      container.invalidate(invoicesProvider);
      await _show(
        tester,
        const FinanceScreen(initialPaymentId: _id),
        container: container,
      );
      expect(container.read(invoicesProvider).isLoading, isTrue);
      expect(find.byType(WorkloopRecordLinkUnavailable), findsNothing);
      pending.complete([_payment(_id)]);
      await tester.pumpAndSettle();
      expect(find.text('Exact payment $_id'), findsOneWidget);
      expect(find.text('Edit income'), findsOneWidget);
    },
  );

  testWidgets(
    'task link opens the exact completed task without changing filters',
    (tester) async {
      await _show(
        tester,
        const TasksScreen(initialTaskId: _id),
        overrides: [
          allTasksProvider.overrideWith(
            (_) async => const [
              SlateTask(
                id: _otherId,
                workspaceId: _workspace,
                title: 'Other task',
              ),
              SlateTask(
                id: _id,
                workspaceId: _workspace,
                title: 'Exact finished task',
                status: 'done',
              ),
            ],
          ),
        ],
      );
      expect(find.text('Exact finished task'), findsOneWidget);
      expect(find.text('Reopen Task'), findsOneWidget);
      expect(find.text('Other task'), findsNothing);
    },
  );

  testWidgets('note link opens the exact editor instead of notes search', (
    tester,
  ) async {
    await _show(
      tester,
      const NotesScreen(initialNoteId: _id),
      overrides: [
        allNotesProvider.overrideWith(
          (_) async => const [
            SlateNote(
              id: _otherId,
              workspaceId: _workspace,
              title: 'Other note',
              body: 'Other body',
            ),
            SlateNote(
              id: _id,
              workspaceId: _workspace,
              title: 'Exact note',
              body: 'Only this note body',
            ),
          ],
        ),
      ],
    );
    final editedText = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((field) => field.controller.text);
    expect(editedText, contains('Exact note\nOnly this note body'));
    expect(find.text('Other note'), findsNothing);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('booking link opens an exact past booking outside Today', (
    tester,
  ) async {
    await _show(
      tester,
      const AppointmentsScreen(initialAppointmentId: _id),
      overrides: [
        appointmentsProvider.overrideWith(
          (_) async => [
            {
              'id': _id,
              'workspace_id': _workspace,
              'start_time': '2025-01-01T10:00:00Z',
              'end_time': '2025-01-01T11:00:00Z',
              'status': 'completed',
              'price': 73,
              'title': 'Exact historic booking',
              'contacts': {'name': 'Historic client'},
            },
          ],
        ),
      ],
    );
    expect(find.byType(AppointmentDetailScreen), findsOneWidget);
    expect(find.text('Historic client'), findsOneWidget);
  });

  testWidgets(
    'closed request link opens the exact request outside active filter',
    (tester) async {
      await _show(
        tester,
        const BookingRequestsScreen(initialRequestId: _id),
        overrides: [
          bookingRequestsProvider.overrideWith(
            (_) async => const [
              BookingRequest(
                id: _otherId,
                workspaceId: _workspace,
                name: 'Other request',
                phone: '',
              ),
              BookingRequest(
                id: _id,
                workspaceId: _workspace,
                name: 'Exact declined request',
                phone: '',
                status: 'declined',
              ),
            ],
          ),
        ],
      );
      expect(find.byType(BookingRequestDetailScreen), findsOneWidget);
      expect(find.text('Exact declined request'), findsOneWidget);
      expect(find.text('Other request'), findsNothing);
    },
  );

  for (final entry in <String, Widget>{
    'Payment': const FinanceScreen(initialPaymentId: _id),
    'Task': const TasksScreen(initialTaskId: _id),
    'Note': const NotesScreen(initialNoteId: _id),
    'Booking': const AppointmentsScreen(initialAppointmentId: _id),
    'Booking request': const BookingRequestsScreen(initialRequestId: _id),
    'Client': const ClientRecordLinkScreen(clientId: _id),
  }.entries) {
    testWidgets(
      'deleted ${entry.key} shows unavailable instead of a generic hunt',
      (tester) async {
        await _show(tester, entry.value);
        expect(find.byType(WorkloopRecordLinkUnavailable), findsOneWidget);
        expect(
          find.text('This ${entry.key.toLowerCase()} is no longer available'),
          findsOneWidget,
        );
        expect(find.text('Check again'), findsOneWidget);
      },
    );
  }

  testWidgets('new incoming ID on reused task screen opens the new record', (
    tester,
  ) async {
    final selected = ValueNotifier<String>(_id);
    addTearDown(selected.dispose);
    await _show(
      tester,
      ValueListenableBuilder<String>(
        valueListenable: selected,
        builder: (_, id, _) => TasksScreen(initialTaskId: id),
      ),
      overrides: [
        allTasksProvider.overrideWith(
          (_) async => const [
            SlateTask(
              id: _id,
              workspaceId: _workspace,
              title: 'First exact task',
            ),
            SlateTask(
              id: _otherId,
              workspaceId: _workspace,
              title: 'Second exact task',
            ),
          ],
        ),
      ],
    );
    expect(find.text('First exact task'), findsOneWidget);
    final context = tester.element(find.text('First exact task'));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    selected.value = _otherId;
    await tester.pumpAndSettle();
    expect(find.text('Second exact task'), findsOneWidget);
    expect(find.text('First exact task'), findsNothing);
  });

  testWidgets('client link reads the current canonical client', (tester) async {
    await _show(
      tester,
      const ClientRecordLinkScreen(clientId: _id),
      overrides: [
        clientsProvider.overrideWith(
          (_) async => const [
            Client(
              id: _id,
              workspaceId: _workspace,
              name: 'Current client name',
            ),
          ],
        ),
      ],
    );
    expect(find.byType(ClientDetailScreen), findsOneWidget);
    expect(find.text('Current client name'), findsOneWidget);
  });

  testWidgets(
    'unavailable request retry stays reachable on small enlarged UI',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retries = 0;
      await _show(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: WorkloopRecordLinkUnavailable(
            recordName: 'Booking request',
            onRetry: () => retries++,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Check again'));
      await tester.tap(find.text('Check again'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
