import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/dashboard/dashboard_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/booking_requests_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/client_follow_up_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/setup_checklist_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

final _now = DateTime(2026, 9, 6, 12);

BookingRequest _request(String id, String name, int daysOld) => BookingRequest(
  id: id,
  workspaceId: 'workspace-one',
  name: name,
  phone: '',
  serviceName: 'Window clean',
  createdAt: _now.subtract(Duration(days: daysOld)),
);

final _payment = Payment(
  id: 'payment-exact',
  workspaceId: 'workspace-one',
  number: 'PAY-100',
  status: 'sent',
  issueDate: _now.subtract(const Duration(days: 10)),
  dueDate: _now.subtract(const Duration(days: 8)),
  total: 125,
  amountPaid: 25,
  clientName: 'Sam',
);

final _task = SlateTask(
  id: 'task-exact',
  workspaceId: 'workspace-one',
  title: 'Confirm access with Jamie',
  dueDate: _now.subtract(const Duration(days: 1)),
);

final _client = Client(
  id: 'client-exact',
  workspaceId: 'workspace-one',
  name: 'Taylor',
  status: 'lead',
  createdAt: _now.subtract(const Duration(days: 9)),
);

class _SignedInAuth extends AuthRepository {
  _SignedInAuth(super.client);
  @override
  String? get currentUserId => 'owner-one';
}

class _Snoozes implements ClientFollowUpSnoozeStore {
  final values = <String, DateTime>{};
  bool fail = false;
  int writes = 0;
  @override
  Future<Map<String, DateTime>> read(ClientFollowUpScope scope) async =>
      Map.of(values);
  @override
  Future<void> write(
    ClientFollowUpScope scope,
    Map<String, DateTime> value,
  ) async {
    expect(scope, (userId: 'owner-one', workspaceId: 'workspace-one'));
    writes++;
    if (fail) throw StateError('local storage unavailable');
    values.clear();
    values.addAll(value);
  }
}

class _DashboardFixture {
  final reads = <String, int>{};
  final selectedRoutes = <String>[];
  final genericDestinations = <int>[];
  var genericMoneyOpens = 0;
  late GoRouter router;

  Future<T> read<T>(String source, T value) async {
    reads.update(source, (count) => count + 1, ifAbsent: () => 1);
    return value;
  }
}

Future<_DashboardFixture> _showDashboard(
  WidgetTester tester, {
  List<BookingRequest> requests = const [],
  List<Payment> payments = const [],
  List<SlateTask> tasks = const [],
  List<Client> clients = const [],
  List<DashboardAttentionItem>? overrideAttention,
  Size size = const Size(390, 844),
  double textScale = 1,
  _Snoozes? snoozes,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = _DashboardFixture();
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final auth = snoozes == null ? AuthRepository(client) : _SignedInAuth(client);
  fixture.router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => DashboardScreen(
          onNavigate: fixture.genericDestinations.add,
          onOpenMoneyFollowUps: () => fixture.genericMoneyOpens++,
        ),
      ),
      for (final type in ['payments', 'tasks', 'booking-requests', 'clients'])
        GoRoute(
          path: '/$type/:id',
          builder: (_, state) {
            fixture.selectedRoutes.add(state.uri.path);
            return Scaffold(
              body: Text('Opened $type ${state.pathParameters['id']}'),
            );
          },
        ),
    ],
  );
  addTearDown(fixture.router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        if (snoozes != null)
          clientFollowUpSnoozeStoreProvider.overrideWithValue(snoozes),
        workspaceProvider.overrideWith(
          (ref) async => const {
            'id': 'workspace-one',
            'name': 'Sample business',
          },
        ),
        setupChecklistDismissedProvider.overrideWith((ref) async => true),
        dashboardClockProvider.overrideWith((ref) => Stream.value(_now)),
        businessNowProvider.overrideWithValue(_now),
        appointmentsProvider.overrideWith((ref) async => const []),
        clientsProvider.overrideWith((ref) => fixture.read('clients', clients)),
        invoicesProvider.overrideWith(
          (ref) => fixture.read('payments', payments),
        ),
        allTasksProvider.overrideWith((ref) => fixture.read('tasks', tasks)),
        bookingRequestsProvider.overrideWith(
          (ref) => fixture.read('booking-requests', requests),
        ),
        allNotesProvider.overrideWith((ref) async => const []),
        unreadNotificationsProvider.overrideWith((ref) async => 0),
        financeSummaryProvider.overrideWith(
          (ref) async => FinanceSummary.from(
            payments: payments,
            expenses: const [],
            monthlyTarget: 1000,
            now: _now,
          ),
        ),
        if (overrideAttention != null)
          dashboardAttentionProvider.overrideWith(
            (ref) async => overrideAttention,
          ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: fixture.router,
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
  return fixture;
}

Future<void> _tapAttention(WidgetTester tester, String title) async {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(WorkloopListRow),
  );
  await tester.scrollUntilVisible(
    row,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  for (final failFirst in [false, true]) {
    testWidgets(
      'client snooze ${failFirst ? 'failure keeps the row and can retry' : 'hides the exact follow-up after saving'}',
      (tester) async {
        final snoozes = _Snoozes()..fail = failFirst;
        await _showDashboard(tester, clients: [_client], snoozes: snoozes);
        Future<void> hide() async {
          final menu = find.byTooltip('Follow-up options for Taylor');
          await tester.scrollUntilVisible(
            menu,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Hide for 7 days'));
          await tester.pumpAndSettle();
        }

        await hide();
        if (failFirst) {
          expect(find.text('Contact Taylor'), findsOneWidget);
          expect(
            find.text('Could not save that reminder. Please try again.'),
            findsOneWidget,
          );
          expect(snoozes.values, isEmpty);
          snoozes.fail = false;
          await hide();
        }
        expect(find.text('Contact Taylor'), findsNothing);
        expect(
          snoozes.values['client-exact'],
          _now.toUtc().add(const Duration(days: 7)),
        );
        expect(snoozes.writes, failFirst ? 2 : 1);
      },
    );
  }
  final cases = [
    (type: 'payments', title: 'Collect £100', id: 'payment-exact'),
    (type: 'tasks', title: 'Confirm access with Jamie', id: 'task-exact'),
    (
      type: 'booking-requests',
      title: 'Review Alex’s request',
      id: 'request-exact',
    ),
    (type: 'clients', title: 'Contact Taylor', id: 'client-exact'),
  ];

  for (final target in cases) {
    testWidgets(
      '${target.type} attention opens its exact route and refreshes only its source',
      (tester) async {
        final fixture = await _showDashboard(
          tester,
          requests: [_request('request-exact', 'Alex', 2)],
          payments: [_payment],
          tasks: [_task],
          clients: [_client],
        );
        expect(fixture.reads.values, everyElement(1));
        await _tapAttention(tester, target.title);
        expect(fixture.selectedRoutes.last, '/${target.type}/${target.id}');
        expect(find.text('Opened ${target.type} ${target.id}'), findsOneWidget);
        expect(fixture.genericDestinations, isEmpty);
        expect(fixture.genericMoneyOpens, 0);
        for (final entry in fixture.reads.entries) {
          expect(
            entry.value,
            entry.key == target.type ? 2 : 1,
            reason: entry.key,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'each request row opens that request instead of a grouped inbox',
    (tester) async {
      final fixture = await _showDashboard(
        tester,
        requests: [
          _request('request-alex', 'Alex', 1),
          _request('request-jamie', 'Jamie', 3),
        ],
      );
      expect(find.text('Review 2 booking requests'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Review Jamie’s request')).dy,
        lessThan(tester.getTopLeft(find.text('Review Alex’s request')).dy),
      );
      await _tapAttention(tester, 'Review Alex’s request');
      expect(fixture.selectedRoutes.last, '/booking-requests/request-alex');
      fixture.router.pop();
      await tester.pumpAndSettle();
      await _tapAttention(tester, 'Review Jamie’s request');
      expect(fixture.selectedRoutes.last, '/booking-requests/request-jamie');
      expect(fixture.genericDestinations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a mixed backlog keeps urgent categories in the four-entry preview',
    (tester) async {
      await _showDashboard(
        tester,
        requests: List.generate(
          6,
          (i) => _request('request-$i', 'Customer $i', 6 - i),
        ),
        payments: [_payment],
        tasks: [_task],
      );
      for (var index = 0; index < 2; index++) {
        expect(find.text('Review Customer $index’s request'), findsOneWidget);
      }
      expect(find.text('Review Customer 2’s request'), findsNothing);
      expect(find.text('Review Customer 4’s request'), findsNothing);
      expect(find.text('Review Customer 5’s request'), findsNothing);
      expect(find.text('Confirm access with Jamie'), findsOneWidget);
      expect(find.text('Collect £100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a malformed legacy attention row never guesses a generic destination',
    (tester) async {
      final fixture = await _showDashboard(
        tester,
        overrideAttention: [
          DashboardAttentionItem(
            type: DashboardAttentionType.bookingRequest,
            title: 'Legacy request alert',
            detail: 'Saved before refresh',
            source: 3,
            sortTime: _now,
          ),
        ],
      );
      await _tapAttention(tester, 'Legacy request alert');
      expect(fixture.router.routeInformationProvider.value.uri.path, '/');
      expect(fixture.selectedRoutes, isEmpty);
      expect(fixture.genericDestinations, isEmpty);
      expect(
        find.text(
          'This item is no longer available. Refresh Today to check again.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'enlarged-text attention still opens the exact request with one tap',
    (tester) async {
      final fixture = await _showDashboard(
        tester,
        requests: [_request('request-accessible', 'Alex', 1)],
        size: const Size(320, 568),
        textScale: 2,
      );
      await _tapAttention(tester, 'Review Alex’s request');
      expect(
        fixture.selectedRoutes.last,
        '/booking-requests/request-accessible',
      );
      expect(fixture.genericDestinations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
