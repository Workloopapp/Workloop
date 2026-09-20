import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/profile/profile_editor_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/settings/widgets/settings_business_tab.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('seven days and Save fit without scrolling at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsWorkspaceSettingsProvider.overrideWith(
              (ref) async => {'working_hours': {}},
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: EdgeInsets.only(
                  top: size.width == 320 ? 20 : 47,
                  bottom: size.width == 320 ? 0 : 34,
                ),
              ),
              child: child!,
            ),
            home: const ProfileEditorScreen(
              section: SettingsBusinessSection.workingHours,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final day in [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        final toggle = find.bySemanticsLabel('$day working day');
        final edit = find.bySemanticsLabel('Edit $day hours');
        expect(toggle.hitTestable(), findsOneWidget);
        expect(edit.hitTestable(), findsOneWidget);
        expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(edit).height, greaterThanOrEqualTo(44));
      }
      expect(find.text('Save hours').hitTestable(), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('working-hours-week')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, 0);
      await tester.tap(find.bySemanticsLabel('Sunday working day'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Edit Sunday hours'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Sunday start time, block 1'),
        findsOneWidget,
      );
      await tester.tap(find.text('Add working block'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Sunday start time, block 2'),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('+1 block', findRichText: true), findsNothing);
      expect(find.text('09:00–17:00\n+1 block'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
