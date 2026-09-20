import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/features/appointments/booking_schedule_warning_sheet.dart';
import 'package:workloop/features/profile/working_hours_editor.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';

void main() {
  for (final draft in [true, false]) {
    testWidgets(
      'shared confirmation stays reachable at large text (draft: $draft)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Object? decision;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    decision = draft
                        ? await showWorkloopDraftConfirmation(
                            context,
                            title: 'Save working hours?',
                            message:
                                'Your latest availability changes have not been saved yet.',
                            saveLabel: 'Save hours',
                          )
                        : await showWorkloopOutsideHoursConfirmation(
                            context,
                            detail: 'Monday is outside your working hours.',
                            repeating: true,
                          );
                  },
                  child: const Text('Review'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(decision, isNull);
        final cancel = find.text(draft ? 'Keep editing' : 'Go back');
        await tester.scrollUntilVisible(cancel, 120);
        await tester.pumpAndSettle();
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(decision, draft ? WorkloopDraftDecision.stay : false);
      },
    );
  }
  testWidgets(
    'split working hours remain usable with large text on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsWorkspaceSettingsProvider.overrideWith(
              (ref) async => const {
                'working_hours': {
                  'Monday': {
                    'enabled': true,
                    'blocks': [
                      {'start': '09:00', 'end': '12:00'},
                      {'start': '13:00', 'end': '17:00'},
                    ],
                  },
                },
              },
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(body: WorkingHoursEditor()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Edit Monday hours'));
      await tester.pumpAndSettle();
      final start = find.bySemanticsLabel('Monday start time, block 1');
      await tester.scrollUntilVisible(
        start,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
    },
  );

  testWidgets('booking schedule warning remains scrollable and deliberate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? decision;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                decision = await showBookingScheduleWarning(
                  context,
                  const AppointmentScheduleReview(
                    outsideWorkingHoursCount: 1,
                    conflictCount: 2,
                  ),
                );
              },
              child: const Text('Review'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(decision, isNull);
    await tester.scrollUntilVisible(find.text('Go back'), 120);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(decision, isFalse);
  });
}
