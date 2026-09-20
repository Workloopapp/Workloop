import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/dashboard/tomorrow_brief_row.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/client_follow_up_provider.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/utils/client_follow_up.dart';

class _Auth extends Fake implements AuthRepository {
  @override
  String? get currentUserId => 'owner';
}

class _Workspace extends Notifier<String> {
  @override
  String build() => 'workspace';
  void change() => state = 'other';
}

final _workspace = NotifierProvider<_Workspace, String>(_Workspace.new);

final _brief = TomorrowBrief(
  [
    Appointment(
      id: 'booking-1',
      workspaceId: 'workspace',
      clientName: 'Sample customer',
      serviceName: 'Window clean',
      startTime: DateTime.utc(2026, 9, 7, 8),
      endTime: DateTime.utc(2026, 9, 7, 9),
    ),
  ],
  'Europe/London',
  60,
  workspaceId: 'workspace',
);

Future<ProviderContainer> _show(
  WidgetTester tester, {
  required Future<TomorrowBrief> Function() load,
  double scale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      workspaceIdProvider.overrideWith((ref) async => ref.watch(_workspace)),
      tomorrowBriefProvider.overrideWith((_) => load()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(workspaceIdProvider.future);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: TomorrowBriefRow()),
        ),
      ),
      GoRoute(
        path: '/bookings/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
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
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  test('tomorrow times keep zone conversion without a visible zone suffix', () {
    expect(
      tomorrowBookingTime(DateTime.utc(2026, 9, 7, 8), 'Europe/London'),
      '09:00',
    );
    expect(
      tomorrowBookingTime(DateTime.utc(2026, 12, 7, 8), 'Europe/London'),
      '08:00',
    );
    expect(
      tomorrowBookingTime(DateTime.utc(2026, 9, 7, 8, 5), 'Asia/Kolkata'),
      '13:35',
    );
    expect(
      tomorrowBookingTime(DateTime.utc(2026, 9, 7, 23, 30), 'Europe/London'),
      '00:30',
    );
  });

  testWidgets('retry refreshes the failed canonical booking source', (
    tester,
  ) async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        workspaceIdProvider.overrideWith((_) async => 'workspace'),
        workspaceSettingsProvider.overrideWith(
          (_) async => {'timezone': 'Europe/London'},
        ),
        businessNowProvider.overrideWithValue(DateTime.utc(2026, 9, 6, 12)),
        appointmentsProvider.overrideWith((_) async {
          reads++;
          if (reads == 1) throw StateError('offline');
          return [for (final booking in _brief.bookings) booking.toMap()];
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: TomorrowBriefRow()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not check tomorrow. Tap to try again.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tomorrow-brief-row')));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('1 booking · 1h booked · First 09:00'), findsOneWidget);
  });
  testWidgets(
    'retained brief from another workspace never appears as the new schedule',
    (tester) async {
      final container = await _show(tester, load: () async => _brief);
      await tester.pumpAndSettle();
      expect(find.text('1 booking · 1h booked · First 09:00'), findsOneWidget);
      container.read(_workspace.notifier).change();
      await tester.pumpAndSettle();
      expect(find.text('Checking your schedule…'), findsOneWidget);
      expect(find.text('1 booking · 1h booked · First 09:00'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tomorrow-brief-row')));
      await tester.pumpAndSettle();
      expect(find.text('Sample customer'), findsNothing);
    },
  );
  testWidgets(
    'loading never claims tomorrow is empty; failure retries real data',
    (tester) async {
      final first = Completer<TomorrowBrief>();
      var calls = 0;
      await _show(
        tester,
        load: () => ++calls == 1 ? first.future : Future.value(_brief),
      );
      expect(find.text('Checking your schedule…'), findsOneWidget);
      expect(find.text('No bookings scheduled.'), findsNothing);
      first.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tomorrow-brief-row')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('1 booking · 1h booked · First 09:00'), findsOneWidget);
    },
  );
  testWidgets(
    '320px at 2x text keeps real schedule and exact booking action reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(tester, load: () async => _brief, scale: 2);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tomorrow-brief-row')));
      await tester.pumpAndSettle();
      expect(find.text('Sample customer'), findsOneWidget);
      expect(find.text('09:00 · Window clean'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('tomorrow-booking-booking-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Opened booking-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('workspace change hides open sheet customer data and actions', (
    tester,
  ) async {
    final container = await _show(tester, load: () async => _brief);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tomorrow-brief-row')));
    await tester.pumpAndSettle();
    container.read(_workspace.notifier).change();
    await tester.pumpAndSettle();
    expect(find.text('This workspace is no longer open.'), findsOneWidget);
    expect(find.text('Sample customer'), findsNothing);
  });
  testWidgets(
    'open sheet rejects a retained result for a different workspace',
    (tester) async {
      var current = _brief;
      final container = await _show(tester, load: () async => current);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tomorrow-brief-row')));
      await tester.pumpAndSettle();
      current = TomorrowBrief(
        _brief.bookings,
        _brief.timezone,
        _brief.bookedMinutes,
        workspaceId: 'other',
      );
      container.invalidate(tomorrowBriefProvider);
      await tester.pumpAndSettle();
      expect(find.text('Sample customer'), findsNothing);
      expect(
        find.byKey(const ValueKey('tomorrow-booking-booking-1')),
        findsNothing,
      );
      expect(find.text('Checking your schedule…'), findsWidgets);
    },
  );
  testWidgets(
    'unknown duration is omitted rather than shown as zero booked time',
    (tester) async {
      await _show(
        tester,
        load: () async => TomorrowBrief(
          [
            Appointment(
              id: 'no-end',
              workspaceId: 'workspace',
              startTime: DateTime.utc(2026, 9, 7, 8),
            ),
          ],
          'Europe/London',
          0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 booking · First 09:00'), findsOneWidget);
    },
  );
}
