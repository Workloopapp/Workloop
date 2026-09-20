import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  for (final compact in [false, true]) {
    testWidgets('navigation targets fill the rail (compact: $compact)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: WorkloopNavigationControl<int>(
                  compact: compact,
                  segments: const [
                    WorkloopSegment(value: 0, label: 'All'),
                    WorkloopSegment(value: 1, label: 'Unread', badge: '12'),
                  ],
                  selected: selected,
                  onChanged: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      final target = find.bySemanticsLabel('Unread');
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
      final rail = tester.getRect(find.byType(WorkloopNavigationControl<int>));
      await tester.tapAt(Offset(rail.right - 60, rail.top + 1));
      expect(
        selected,
        1,
        reason: 'The top edge is part of the visible control.',
      );
      semantics.dispose();
    });
  }

  testWidgets('decision labels stay fully readable with enlarged text', (
    tester,
  ) async {
    var confirmations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 284,
                child: SlateButton(
                  label: 'Save booking anyway',
                  icon: Icons.check,
                  onPressed: () => confirmations++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final label = find.text('Save booking anyway');
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
    await tester.tap(label);
    expect(confirmations, 1);
  });

  testWidgets('navigation count badges grow with accessibility text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.5)),
          child: Scaffold(
            body: WorkloopNavigationControl<int>(
              segments: [
                WorkloopSegment(value: 0, label: 'All'),
                WorkloopSegment(value: 1, label: 'Unread', badge: '12'),
              ],
              selected: 0,
              onChanged: _ignoreSelection,
            ),
          ),
        ),
      ),
    );
    final badge = find.text('12');
    final badgeBox = find
        .ancestor(of: badge, matching: find.byType(Container))
        .first;
    expect(tester.getSize(badgeBox).height, greaterThanOrEqualTo(25));
    expect(tester.takeException(), isNull);
  });
}

void _ignoreSelection(int value) {}
