import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/dashboard/dashboard_screen.dart';
import 'package:workloop/features/weather/local_weather_provider.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/booking_requests_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/setup_checklist_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const _firstWorkspace = 'sample-workspace-one';
const _secondWorkspace = 'sample-workspace-two';
final _now = DateTime(2026, 9, 6, 12);

class _SelectedWorkspace extends Notifier<String> {
  @override
  String build() => _firstWorkspace;

  void select(String id) => state = id;
}

final _selectedWorkspaceProvider = NotifierProvider<_SelectedWorkspace, String>(
  _SelectedWorkspace.new,
);

class _Auth implements AuthRepository {
  @override
  String? get currentUserId => 'sample-owner';
  @override
  String? get currentFirstName => 'Alex';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BookingRequest _request(String workspaceId, String name) => BookingRequest(
  id: '$workspaceId-request',
  workspaceId: workspaceId,
  name: name,
  phone: '',
  serviceName: 'Window clean',
  createdAt: _now.subtract(const Duration(days: 1)),
);

class _Fixture {
  final requestResponses = <String, Future<List<BookingRequest>>>{};
  final requestReads = <String, int>{};
  Future<bool> checklistResponse = Future.value(true);
  late ProviderContainer container;

  Completer<List<BookingRequest>> delayRequests(String workspaceId) {
    final pending = Completer<List<BookingRequest>>();
    requestResponses[workspaceId] = pending.future;
    return pending;
  }

  Future<void> show(WidgetTester tester) async {
    // Keep the two adjacent sections mounted so their physical order can be
    // compared without scrolling changing the measured positions.
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth()),
          workspaceProvider.overrideWith(
            (ref) async => {
              'id': ref.watch(_selectedWorkspaceProvider),
              'name': 'Sample business',
            },
          ),
          setupChecklistDismissedProvider.overrideWith(
            (ref) => checklistResponse,
          ),
          dashboardClockProvider.overrideWith((ref) => Stream.value(_now)),
          businessNowProvider.overrideWithValue(_now),
          weatherUserIdProvider.overrideWith((ref) => Stream.value(null)),
          appointmentsProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return const <Map<String, dynamic>>[];
          }),
          clientsProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return const <Client>[];
          }),
          invoicesProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return const <Payment>[];
          }),
          expensesProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return const <Expense>[];
          }),
          allTasksProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return const <SlateTask>[];
          }),
          allNotesProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return const <SlateNote>[];
          }),
          bookingRequestsProvider.overrideWith((ref) async {
            final workspaceId = await ref.watch(workspaceIdProvider.future);
            if (workspaceId == null) return const <BookingRequest>[];
            requestReads.update(
              workspaceId,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            return requestResponses[workspaceId] ?? const <BookingRequest>[];
          }),
          financeSummaryProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return FinanceSummary.from(
              payments: const [],
              expenses: const [],
              monthlyTarget: 1000,
              now: _now,
            );
          }),
          unreadNotificationsProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: DashboardScreen(
            onNavigate: (_) {},
            onOpenMoneyFollowUps: () {},
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );
    await _flushFrames(tester);
  }
}

Future<void> _flushFrames(WidgetTester tester) async {
  // Loading indicators may animate indefinitely. Advance a bounded set of
  // frames rather than waiting for an unresolved source to settle.
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Finder get _attentionPanel => find.byWidgetPredicate(
  (widget) => widget is WorkloopPaperPanel && widget.title == 'Needs attention',
);

Finder get _overview => find.text('At a glance');
Finder get _attentionLoading =>
    find.byKey(const ValueKey('dashboard-attention-loading'));

const _attentionError = 'Could not check what needs your attention.';
const _attentionRefreshError =
    'Could not refresh what needs your attention. Showing your last update.';

void main() {
  testWidgets('ready summaries wait for the first delayed attention result', (
    tester,
  ) async {
    final fixture = _Fixture();
    final pending = fixture.delayRequests(_firstWorkspace);
    await fixture.show(tester);

    expect(fixture.container.read(appointmentsProvider).hasValue, isTrue);
    expect(fixture.container.read(financeSummaryProvider).hasValue, isTrue);
    expect(
      fixture.container.read(dashboardAttentionProvider).isLoading,
      isTrue,
    );
    expect(find.text('Your day is clear'), findsOneWidget);
    expect(_attentionLoading, findsOneWidget);
    expect(_overview, findsNothing);
    expect(_attentionPanel, findsNothing);

    pending.complete([_request(_firstWorkspace, 'Jamie')]);
    await tester.pumpAndSettle();

    expect(find.text('Review Jamie’s request'), findsOneWidget);
    expect(_attentionLoading, findsNothing);
    expect(_overview, findsOneWidget);
    expect(
      tester.getRect(_attentionPanel).bottom,
      lessThan(tester.getRect(_overview).top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a resolved empty attention result reveals the overview directly',
    (tester) async {
      final fixture = _Fixture();
      final pending = fixture.delayRequests(_firstWorkspace);
      await fixture.show(tester);
      expect(_overview, findsNothing);

      pending.complete(const []);
      await tester.pumpAndSettle();

      expect(_attentionPanel, findsNothing);
      expect(find.text(_attentionError), findsNothing);
      expect(_overview, findsOneWidget);
      expect(find.text('0 open tasks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a source refresh keeps resolved attention and overview in place',
    (tester) async {
      final fixture = _Fixture();
      fixture.requestResponses[_firstWorkspace] = Future.value([
        _request(_firstWorkspace, 'Jamie'),
      ]);
      await fixture.show(tester);
      await tester.pumpAndSettle();
      final attentionTop = tester.getRect(_attentionPanel).top;
      final overviewTop = tester.getRect(_overview).top;

      final pending = fixture.delayRequests(_firstWorkspace);
      fixture.container.invalidate(bookingRequestsProvider);
      await _flushFrames(tester);

      expect(
        fixture.container.read(dashboardAttentionProvider).isLoading,
        isTrue,
      );
      expect(find.text('Review Jamie’s request'), findsOneWidget);
      expect(_attentionLoading, findsNothing);
      expect(tester.getRect(_attentionPanel).top, attentionTop);
      expect(tester.getRect(_overview).top, overviewTop);

      pending.complete([_request(_firstWorkspace, 'Taylor')]);
      await tester.pumpAndSettle();
      expect(find.text('Review Jamie’s request'), findsNothing);
      expect(find.text('Review Taylor’s request'), findsOneWidget);
      expect(tester.getRect(_overview).top, overviewTop);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh preserves a previously confirmed empty attention result',
    (tester) async {
      final fixture = _Fixture();
      await fixture.show(tester);
      await tester.pumpAndSettle();
      expect(_attentionPanel, findsNothing);
      final overviewTop = tester.getRect(_overview).top;

      final pending = fixture.delayRequests(_firstWorkspace);
      fixture.container.invalidate(bookingRequestsProvider);
      await _flushFrames(tester);

      expect(
        fixture.container.read(dashboardAttentionProvider).isLoading,
        isTrue,
      );
      expect(_attentionPanel, findsNothing);
      expect(tester.getRect(_overview).top, overviewTop);

      pending.complete(const []);
      await tester.pumpAndSettle();
      expect(tester.getRect(_overview).top, overviewTop);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pull to refresh keeps the same workspace layout until it finishes',
    (tester) async {
      final fixture = _Fixture();
      fixture.requestResponses[_firstWorkspace] = Future.value([
        _request(_firstWorkspace, 'Jamie'),
      ]);
      await fixture.show(tester);
      await tester.pumpAndSettle();
      final overviewTop = tester.getRect(_overview).top;
      final pending = fixture.delayRequests(_firstWorkspace);
      var finished = false;
      final completion = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh()
          .then((_) => finished = true);
      await _flushFrames(tester);

      expect(finished, isFalse);
      expect(find.text('Review Jamie’s request'), findsOneWidget);
      expect(tester.getRect(_overview).top, overviewTop);
      expect(_attentionLoading, findsNothing);

      pending.complete([_request(_firstWorkspace, 'Taylor')]);
      await completion;
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(find.text('Review Taylor’s request'), findsOneWidget);
      expect(tester.getRect(_overview).top, overviewTop);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('attention failure is visible above the overview and retries', (
    tester,
  ) async {
    final fixture = _Fixture();
    final pending = fixture.delayRequests(_firstWorkspace);
    await fixture.show(tester);
    pending.completeError(StateError('sample connection failure'));
    await tester.pumpAndSettle();

    final error = find.ancestor(
      of: find.text(_attentionError),
      matching: find.byType(SlateErrorState),
    );
    expect(error, findsOneWidget);
    expect(_attentionPanel, findsNothing);
    expect(_overview, findsOneWidget);
    expect(
      tester.getRect(error).bottom,
      lessThan(tester.getRect(_overview).top),
    );
    final retry = fixture.delayRequests(_firstWorkspace);
    await tester.tap(
      find.descendant(of: error, matching: find.text('Try again')),
    );
    await _flushFrames(tester);
    expect(fixture.requestReads[_firstWorkspace], 2);
    expect(find.text('sample connection failure'), findsNothing);

    retry.complete([_request(_firstWorkspace, 'Jamie')]);
    await tester.pumpAndSettle();
    expect(find.text(_attentionError), findsNothing);
    expect(find.text('Review Jamie’s request'), findsOneWidget);
    expect(_overview, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed refresh keeps the last attention result with a retry', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.requestResponses[_firstWorkspace] = Future.value([
      _request(_firstWorkspace, 'Jamie'),
    ]);
    await fixture.show(tester);
    await tester.pumpAndSettle();

    final pending = fixture.delayRequests(_firstWorkspace);
    fixture.container.invalidate(bookingRequestsProvider);
    await _flushFrames(tester);
    pending.completeError(StateError('sample refresh failure'));
    await tester.pumpAndSettle();

    expect(find.text('Review Jamie’s request'), findsOneWidget);
    expect(find.text(_attentionRefreshError), findsOneWidget);
    expect(_overview, findsOneWidget);
    expect(_attentionLoading, findsNothing);
    final retry = fixture.delayRequests(_firstWorkspace);
    await tester.tap(find.text('Try again'));
    await _flushFrames(tester);
    expect(find.text('Review Jamie’s request'), findsOneWidget);
    expect(_overview, findsOneWidget);

    retry.complete([_request(_firstWorkspace, 'Taylor')]);
    await tester.pumpAndSettle();
    expect(find.text(_attentionRefreshError), findsNothing);
    expect(find.text('Review Jamie’s request'), findsNothing);
    expect(find.text('Review Taylor’s request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dismissed in [false, true]) {
    testWidgets('the overview waits for the initial setup choice $dismissed', (
      tester,
    ) async {
      final fixture = _Fixture();
      final pending = Completer<bool>();
      fixture.checklistResponse = pending.future;
      await fixture.show(tester);
      expect(
        fixture.container.read(dashboardAttentionProvider).hasValue,
        isTrue,
      );
      expect(_overview, findsNothing);
      expect(find.text('Set up your workspace'), findsNothing);

      pending.complete(dismissed);
      await tester.pumpAndSettle();
      expect(_overview, findsOneWidget);
      expect(
        find.text('Set up your workspace'),
        dismissed ? findsNothing : findsOneWidget,
      );
      if (!dismissed) {
        expect(
          tester.getRect(find.text('Set up your workspace')).top,
          lessThan(tester.getRect(_overview).top),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a failed setup preference cannot block the dashboard forever', (
    tester,
  ) async {
    final fixture = _Fixture();
    final pending = Completer<bool>();
    fixture.checklistResponse = pending.future;
    await fixture.show(tester);
    expect(_overview, findsNothing);

    pending.completeError(StateError('sample preference failure'));
    await tester.pumpAndSettle();
    expect(_overview, findsOneWidget);
    expect(find.text('Set up your workspace'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching workspaces cannot reuse the previous attention layout',
    (tester) async {
      final fixture = _Fixture();
      fixture.requestResponses[_firstWorkspace] = Future.value([
        _request(_firstWorkspace, 'Jamie'),
      ]);
      final nextWorkspace = fixture.delayRequests(_secondWorkspace);
      await fixture.show(tester);
      await tester.pumpAndSettle();
      expect(find.text('Review Jamie’s request'), findsOneWidget);

      fixture.container
          .read(_selectedWorkspaceProvider.notifier)
          .select(_secondWorkspace);
      await _flushFrames(tester);

      expect(
        fixture.container.read(workspaceIdProvider).value,
        _secondWorkspace,
      );
      expect(find.text('Review Jamie’s request'), findsNothing);
      expect(_attentionLoading, findsOneWidget);
      expect(_overview, findsNothing);

      nextWorkspace.complete([_request(_secondWorkspace, 'Morgan')]);
      await tester.pumpAndSettle();
      expect(find.text('Review Morgan’s request'), findsOneWidget);
      expect(find.text('Review Jamie’s request'), findsNothing);
      expect(_overview, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
