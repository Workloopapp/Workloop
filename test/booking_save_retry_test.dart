import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/add_appointment_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';

class _Client extends Fake implements SupabaseClient {}

class _Auth extends Fake implements AuthRepository {
  @override
  String get currentUserId => 'owner';
}

class _Workspace extends Notifier<String> {
  @override
  String build() => 'workspace';
  void change(String id) => state = id;
}

final _workspace = NotifierProvider<_Workspace, String>(_Workspace.new);

class _Appointments extends AppointmentsRepository {
  _Appointments() : super(_Client());
  final submissions = <Map<String, dynamic>>[];
  int reviews = 0;
  bool reject = false;
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
  }) async {
    reviews++;
    return const AppointmentScheduleReview(
      outsideWorkingHoursCount: 0,
      conflictCount: 0,
    );
  }

  @override
  Future<List<String>> createBookingWorkflowFromPayload(
    Map<String, dynamic> payload,
  ) async {
    submissions.add(jsonDecode(jsonEncode(payload)) as Map<String, dynamic>);
    if (reject) {
      reject = false;
      throw const AppointmentScheduleException(
        'This time is now taken.',
        issue: AppointmentScheduleIssue.conflict,
      );
    }
    if (submissions.length == 1) {
      throw StateError('Connection lost after commit');
    }
    return ['booking-1', 'booking-2', 'booking-3', 'booking-4'];
  }
}

Finder _input(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

Future<void> _visible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 20,
  );
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  _Appointments repository,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      appointmentsRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_Auth()),
      workspaceIdProvider.overrideWith((ref) async => ref.watch(_workspace)),
      workspaceSettingsProvider.overrideWith(
        (_) async => {'timezone': 'Europe/London'},
      ),
      appointmentsProvider.overrideWith((_) async => []),
      clientsProvider.overrideWith(
        (_) async => [
          const Client(
            id: 'client',
            workspaceId: 'workspace',
            name: 'Sam Morgan',
          ),
        ],
      ),
      servicesProvider.overrideWith((_) async => []),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddAppointmentScreen(
                    initialClientId: 'client',
                    initialDate: DateTime(2027, 3, 21),
                  ),
                ),
              ),
              child: const Text('Open booking form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open booking form'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select service'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Custom service'));
  await tester.pumpAndSettle();
  await _visible(tester, _input('Service name'));
  await tester.enterText(_input('Service name'), 'Window clean');
  await tester.enterText(_input('Price'), '100');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _visible(tester, find.text('Weekly'));
  await tester.tap(find.text('Weekly'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'lost series response retries the same dates without another schedule check',
    (tester) async {
      final repository = _Appointments();
      await _show(tester, repository);
      await tester.tap(find.text('Add 4'));
      await tester.pumpAndSettle();
      expect(find.text('Retry save'), findsOneWidget);
      expect(
        find.textContaining('Your details are kept unchanged'),
        findsOneWidget,
      );
      final sent = repository.submissions.single;
      expect(
        (sent['appointments'] as List)[1]['start_time'],
        '2027-03-28T08:00:00.000Z',
      );
      await _visible(tester, _input('Price'));
      await tester.tap(_input('Price'), warnIfMissed: false);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.text('Retry save'));
      await tester.pumpAndSettle();
      expect(repository.reviews, 1);
      expect(repository.submissions, [sent, sent]);
      expect(find.text('Open booking form'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'known rollback unlocks edits and rechecks a changed submission',
    (tester) async {
      final repository = _Appointments()..reject = true;
      await _show(tester, repository);
      await tester.tap(find.text('Add 4'));
      await tester.pumpAndSettle();
      expect(find.text('Retry save'), findsNothing);
      await _visible(tester, _input('Price'));
      await tester.enterText(_input('Price'), '125');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 4'));
      await tester.pumpAndSettle();
      expect(repository.reviews, 2);
      expect(repository.submissions.last['price'], 125);
    },
  );

  testWidgets('unknown save cannot retry into another workspace', (
    tester,
  ) async {
    final repository = _Appointments();
    final container = await _show(tester, repository);
    await tester.tap(find.text('Add 4'));
    await tester.pumpAndSettle();
    container.read(_workspace.notifier).change('other');
    await tester.pumpAndSettle();
    expect(
      find.text('Return to the original workspace to confirm this save.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(repository.submissions.length, 1);
    container.read(_workspace.notifier).change('workspace');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(repository.submissions.length, 2);
    expect(repository.reviews, 1);
  });

  test(
    'response uncertainty is retained unless the database confirms rollback',
    () {
      expect(
        bookingWorkflowDefinitelyRejected(StateError('Lost response')),
        isFalse,
      );
      expect(
        bookingWorkflowDefinitelyRejected(const FormatException('No ids')),
        isFalse,
      );
      expect(
        bookingWorkflowDefinitelyRejected(
          const PostgrestException(message: 'in progress', code: '40001'),
        ),
        isFalse,
      );
      expect(
        bookingWorkflowDefinitelyRejected(
          const PostgrestException(message: 'bad input', code: '22023'),
        ),
        isTrue,
      );
      expect(
        bookingWorkflowDefinitelyRejected(
          const PostgrestException(message: 'policy', code: '42501'),
        ),
        isTrue,
      );
    },
  );
}
