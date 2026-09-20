import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/features/clients/client_detail_screen.dart';
import 'package:workloop/features/clients/client_record_link_screen.dart';
import 'package:workloop/features/clients/widgets/client_overview_tab.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_refresh.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/widgets/record_link_unavailable.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const _clientId = '12000000-0000-4000-8000-000000000001';
const _taskId = '12000000-0000-4000-8000-000000000002';
const _bookingId = '12000000-0000-4000-8000-000000000003';
const _workspaceId = 'workspace-one';
const _client = Client(
  id: _clientId,
  workspaceId: _workspaceId,
  name: 'Client with a long recognisable name',
);

class _SelectedWorkspace extends Notifier<String> {
  @override
  String build() => _workspaceId;
  void change() => state = 'workspace-two';
}

final _selection = NotifierProvider<_SelectedWorkspace, String>(
  _SelectedWorkspace.new,
);

Future<({ProviderContainer container, GoRouter router})> _show(
  WidgetTester tester, {
  bool directClient = false,
  bool linkedTask = true,
  double textScale = 1,
  Future<List<Client>> Function()? loadClients,
  Future<String?> Function()? loadWorkspace,
  Future<List<SlateTask>> Function()? loadTasks,
}) async {
  final container = ProviderContainer(
    overrides: [
      workspaceIdProvider.overrideWith((ref) async {
        final selected = ref.watch(_selection);
        return loadWorkspace == null ? selected : loadWorkspace();
      }),
      clientsProvider.overrideWith(
        (_) async => loadClients == null ? [_client] : loadClients(),
      ),
      allTasksProvider.overrideWith(
        (_) async => loadTasks != null
            ? loadTasks()
            : [
                SlateTask(
                  id: _taskId,
                  workspaceId: _workspaceId,
                  title: 'Prepare for client visit',
                  contactId: linkedTask ? _clientId : null,
                  appointmentId: linkedTask ? _bookingId : null,
                  clientName: linkedTask ? _client.name : null,
                ),
              ],
      ),
      taskChecklistProvider.overrideWith((_, _) async => []),
      appointmentsProvider.overrideWith(
        (_) async => [
          {
            'id': _bookingId,
            'workspace_id': _workspaceId,
            'contact_id': _clientId,
            'title': 'Linked window cleaning',
            'start_time': '2026-09-15T10:00:00Z',
            'end_time': '2026-09-15T11:00:00Z',
            'status': 'scheduled',
            'price': 45,
            'contacts': {'name': _client.name},
          },
        ],
      ),
      invoicesProvider.overrideWith((_) async => []),
      expensesProvider.overrideWith((_) async => []),
      servicesProvider.overrideWith((_) async => []),
      workspaceSettingsProvider.overrideWith(
        (_) async => {'workspace_id': _workspaceId},
      ),
      paymentCollectionEnabledProvider.overrideWithValue(false),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: directClient ? '/clients/$_clientId' : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const TasksScreen(initialTaskId: _taskId),
      ),
      GoRoute(
        path: '/clients',
        builder: (_, _) => const Scaffold(body: Text('Client workspace')),
      ),
      GoRoute(
        path: '/clients/:id',
        builder: (_, state) =>
            ClientRecordLinkScreen(clientId: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

Future<void> _back(WidgetTester tester) async {
  tester
      .widget<WorkloopRouteHeader>(find.byType(WorkloopRouteHeader))
      .onBack!();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'direct client Back returns to Clients without popping the last page',
    (tester) async {
      final harness = await _show(tester, directClient: true);
      expect(find.byType(ClientDetailScreen), findsOneWidget);
      expect(harness.router.canPop(), isFalse);
      await _back(tester);
      expect(find.text('Client workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'direct client discard returns to Clients after the draft decision',
    (tester) async {
      await _show(tester, directClient: true);
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller?.text == _client.name,
        ),
        'Unsaved change',
      );
      await _back(tester);
      expect(find.text('Save client changes?'), findsOneWidget);
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Client workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('client link removes old workspace data when business changes', (
    tester,
  ) async {
    final harness = await _show(tester, directClient: true);
    expect(find.byType(ClientDetailScreen), findsOneWidget);
    harness.container.read(_selection.notifier).change();
    await tester.pumpAndSettle();
    expect(find.byType(ClientDetailScreen), findsNothing);
    expect(find.text(_client.name), findsNothing);
    expect(find.byType(WorkloopRecordLinkUnavailable), findsOneWidget);
  });

  testWidgets(
    'a same-workspace collection refresh preserves an open client draft',
    (tester) async {
      final pending = Completer<List<Client>>();
      var reads = 0;
      final harness = await _show(
        tester,
        directClient: true,
        loadClients: () =>
            ++reads == 1 ? Future.value([_client]) : pending.future,
      );
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller?.text == _client.name,
        ),
        'Keep my unsaved client',
      );
      harness.container.invalidate(clientsProvider);
      await tester.pump();
      expect(find.text('Keep my unsaved client'), findsOneWidget);
      pending.complete([
        const Client(
          id: _clientId,
          workspaceId: _workspaceId,
          name: 'Updated elsewhere',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Keep my unsaved client'), findsOneWidget);
      expect(find.text('Updated elsewhere'), findsNothing);
    },
  );

  testWidgets('task client and booking links return to the originating task', (
    tester,
  ) async {
    await _show(tester);
    await tester.tap(find.text(_client.name));
    await tester.pumpAndSettle();
    expect(find.byType(ClientDetailScreen), findsOneWidget);
    await _back(tester);
    expect(find.text('Prepare for client visit'), findsOneWidget);
    await tester.tap(find.text('View linked booking'));
    await tester.pumpAndSettle();
    expect(find.byType(AppointmentDetailScreen), findsOneWidget);
    expect(find.text('Linked window cleaning'), findsOneWidget);
    await _back(tester);
    expect(find.text('Prepare for client visit'), findsOneWidget);
    expect(find.byType(AppointmentDetailScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'returning from a linked client shows its refreshed name in the same task',
    (tester) async {
      var clientName = _client.name;
      final harness = await _show(
        tester,
        loadTasks: () async => [
          SlateTask(
            id: _taskId,
            workspaceId: _workspaceId,
            title: 'Prepare for client visit',
            contactId: _clientId,
            clientName: clientName,
          ),
        ],
      );
      await tester.tap(find.text(_client.name));
      await tester.pumpAndSettle();
      expect(find.byType(ClientDetailScreen), findsOneWidget);
      clientName = 'Updated client name';
      // This is the same invalidation used after ClientDetailScreen saves.
      refreshClientRelatedData(harness.container.invalidate);
      await tester.pumpAndSettle();
      await _back(tester);
      expect(find.text('Prepare for client visit'), findsOneWidget);
      expect(find.text('Updated client name'), findsOneWidget);
      expect(find.text(_client.name), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an open task hides the previous business record after workspace change',
    (tester) async {
      final harness = await _show(tester);
      expect(find.text('Prepare for client visit'), findsOneWidget);
      harness.container.read(_selection.notifier).change();
      await tester.pumpAndSettle();
      expect(find.text('Prepare for client visit'), findsNothing);
      expect(find.text(_client.name), findsNothing);
      expect(find.byType(WorkloopRecordLinkUnavailable), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed task refresh disables stale actions and offers a working retry',
    (tester) async {
      var reads = 0;
      final harness = await _show(
        tester,
        loadTasks: () async {
          if (++reads == 2) throw StateError('Offline');
          return const [
            SlateTask(
              id: _taskId,
              workspaceId: _workspaceId,
              title: 'Prepare for client visit',
            ),
          ];
        },
      );
      harness.container.invalidate(allTasksProvider);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not refresh this task. Try again before making changes.',
        ),
        findsOneWidget,
      );
      expect(find.text('Mark Complete'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Prepare for client visit'), findsOneWidget);
      expect(find.text('Mark Complete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workspace revalidation hides but preserves a client editing draft',
    (tester) async {
      final pending = Completer<String?>();
      var reads = 0;
      final harness = await _show(
        tester,
        directClient: true,
        loadWorkspace: () =>
            ++reads == 1 ? Future.value(_workspaceId) : pending.future,
      );
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller?.text == _client.name,
        ),
        'Keep this during validation',
      );
      harness.container.invalidate(workspaceIdProvider);
      await tester.pump();
      expect(find.text('Keep this during validation'), findsNothing);
      pending.complete(_workspaceId);
      await tester.pumpAndSettle();
      expect(find.text('Keep this during validation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an unlinked task has no misleading linked-booking action', (
    tester,
  ) async {
    await _show(tester, linkedTask: false);
    expect(find.text('Not linked'), findsOneWidget);
    expect(find.text('View linked booking'), findsNothing);
  });

  testWidgets(
    'task context remains readable and reachable at double text on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(tester, textScale: 2);
      await tester.ensureVisible(find.text(_client.name));
      expect(find.text(_client.name), findsOneWidget);
      await tester.ensureVisible(find.text('View linked booking'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'client overview uses the same received and owed amounts as Money',
    (tester) async {
      var openedFiles = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientAppointmentsProvider.overrideWith((_, _) async => []),
            clientTasksProvider.overrideWith((_, _) async => []),
            clientPaymentsProvider.overrideWith(
              (_, _) async => [
                Payment(
                  id: 'paid',
                  workspaceId: _workspaceId,
                  number: 'P1',
                  status: 'paid',
                  issueDate: DateTime(2026, 9, 1),
                  total: 100,
                ),
                Payment(
                  id: 'cancelled',
                  workspaceId: _workspaceId,
                  number: 'P2',
                  status: 'cancelled',
                  issueDate: DateTime(2026, 9, 1),
                  total: 500,
                ),
                Payment(
                  id: 'part-paid',
                  workspaceId: _workspaceId,
                  number: 'P3',
                  status: 'unpaid',
                  issueDate: DateTime(2026, 9, 1),
                  total: 100,
                  amountPaid: 25,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ClientOverviewTab(
                clientId: _clientId,
                client: _client.toMap(),
                onEdit: () {},
                onOpenBookings: () {},
                onOpenPayments: () {},
                onOpenTasks: () {},
                onOpenAddress: (_) {},
                onOpenFiles: () => openedFiles++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('£125'), findsOneWidget);
      expect(find.text('£75 remaining'), findsOneWidget);
      expect(find.text('£675 remaining'), findsNothing);
      await tester.ensureVisible(find.text('Photos & files'));
      await tester.tap(find.text('Photos & files'));
      expect(openedFiles, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
