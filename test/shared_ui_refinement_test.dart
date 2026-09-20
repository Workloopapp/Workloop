import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  test('feature sheets use the shared Workloop launcher', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              !file.path.endsWith('lib/shared/widgets/slate_ui.dart') &&
              file.readAsStringSync().contains('showModalBottomSheet'),
        )
        .map((file) => file.path)
        .toList();

    expect(offenders, isEmpty);
    final sharedSource = File(
      'lib/shared/widgets/slate_ui.dart',
    ).readAsStringSync();
    expect('showModalBottomSheet'.allMatches(sharedSource), hasLength(1));
  });

  test('direct entity routes opt into pushed-route headers', () {
    final routerSource = File('lib/main.dart').readAsStringSync();

    expect(
      RegExp(
        r'AppointmentsScreen\([\s\S]*?showBackButton: true,[\s\S]*?\)',
      ).hasMatch(routerSource),
      isTrue,
    );
    expect(
      RegExp(
        r'FinanceScreen\([\s\S]*?showBackButton: true,[\s\S]*?\)',
      ).hasMatch(routerSource),
      isTrue,
    );
    expect(
      RegExp(
        r'TasksScreen\([\s\S]*?showBackButton: true,[\s\S]*?\)',
      ).hasMatch(routerSource),
      isTrue,
    );
  });

  testWidgets(
    'folder tabs and root navigation use their approved selection cues',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                WorkloopNavigationControl<int>(
                  segments: const [
                    WorkloopSegment(value: 0, label: 'First'),
                    WorkloopSegment(value: 1, label: 'Second'),
                  ],
                  selected: 0,
                  onChanged: (_) {},
                ),
              ],
            ),
            bottomNavigationBar: WorkloopBottomNav(
              currentIndex: 0,
              items: [
                WorkloopNavItem(
                  label: 'Today',
                  icon: Icons.home_outlined,
                  color: AppColors.light.modHome,
                ),
                WorkloopNavItem(
                  label: 'Clients',
                  icon: Icons.people_outline,
                  color: AppColors.light.modClients,
                ),
              ],
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('workloop-navigation-selection')),
            )
            .height,
        greaterThanOrEqualTo(36),
      );
      final selected = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('workloop-bottom-nav-selection-0')),
      );
      final unselected = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('workloop-bottom-nav-selection-1')),
      );
      final selectedBorder =
          (selected.decoration! as BoxDecoration).border! as BorderDirectional;
      final unselectedBorder =
          (unselected.decoration! as BoxDecoration).border!
              as BorderDirectional;
      expect(selectedBorder.top.color, WorkloopThemeTokens.light.accentInk);
      expect(selectedBorder.top.width, 2);
      expect(unselectedBorder.top.color, Colors.transparent);
      expect((selected.decoration! as BoxDecoration).boxShadow, isNull);
    },
  );

  testWidgets(
    'working page headers omit the wordmark and keep actions beside the heading',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: WorkloopPageHeader(
                title: 'Bookings',
                subtitle: 'Your working schedule',
                color: AppColors.dark.modCalendar,
                trailing: const SizedBox(
                  key: ValueKey('header-action'),
                  width: 44,
                  height: 44,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(WorkloopWordmark), findsNothing);
      expect(
        find.byKey(const ValueKey('workloop-header-accent')),
        findsNothing,
      );
      final titleRect = tester.getRect(find.text('Bookings'));
      final actionRect = tester.getRect(
        find.byKey(const ValueKey('header-action')),
      );
      expect(actionRect.center.dy, greaterThanOrEqualTo(titleRect.top));
      expect(actionRect.top, lessThan(titleRect.bottom));
    },
  );

  testWidgets('Slate sheet frame leaves the drag handle to the theme', (
    tester,
  ) async {
    expect(AppTheme.light.bottomSheetTheme.showDragHandle, isTrue);
    expect(AppTheme.light.bottomSheetTheme.dragHandleSize, const Size(36, 4));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SlateSheetFrame(child: Text('Sheet content')),
        ),
      ),
    );

    final legacyHandles = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints == BoxConstraints.tight(const Size(36, 4)),
    );
    expect(legacyHandles, findsNothing);
    expect(find.text('Sheet content'), findsOneWidget);
  });

  testWidgets('shared picker uses the canonical sheet frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: WorkloopPickerField<int>(
            value: 1,
            title: 'Choose service',
            hint: 'Service',
            options: const [
              WorkloopPickerOption(value: 1, label: 'Consultation'),
              WorkloopPickerOption(value: 2, label: 'Follow-up'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Consultation'));
    await tester.pumpAndSettle();

    expect(find.byType(SlateSheetFrame), findsOneWidget);
    expect(find.text('Choose service'), findsOneWidget);
    final legacyHandles = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints == BoxConstraints.tight(const Size(36, 4)),
    );
    expect(
      legacyHandles,
      findsOneWidget,
      reason: 'The modal theme owns the single visible drag handle.',
    );
  });

  testWidgets('shared sheet launcher owns scrim, handle and typed result', (
    tester,
  ) async {
    int? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorkloopBottomSheet<int>(
                  context: context,
                  builder: (sheetContext) => SlateSheetFrame(
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext, 7),
                      child: const Text('Use result'),
                    ),
                  ),
                );
              },
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.byType(SlateSheetFrame), findsOneWidget);
    final expectedScrim = AppTheme.light
        .extension<WorkloopThemeTokens>()!
        .scrim;
    expect(
      tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .any((barrier) => barrier.color == expectedScrim),
      isTrue,
    );
    final handles = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints == BoxConstraints.tight(const Size(36, 4)),
    );
    expect(handles, findsOneWidget);

    await tester.tap(find.text('Use result'));
    await tester.pumpAndSettle();
    expect(result, 7);
  });
}
