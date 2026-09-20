import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/workloop_quiet_warm.dart';

void main() {
  const cases = [
    (TimeOfDay(hour: 0, minute: 0), Offset(24, 14.5), Offset(24, 11.5)),
    (
      TimeOfDay(hour: 3, minute: 15),
      Offset(33.418727, 25.239999),
      Offset(36.5, 24),
    ),
    (
      TimeOfDay(hour: 18, minute: 30),
      Offset(21.541219, 33.176295),
      Offset(24, 36.5),
    ),
    (
      TimeOfDay(hour: 23, minute: 45),
      Offset(22.760001, 14.581273),
      Offset(11.5, 24),
    ),
  ];
  for (final (time, hourEnd, minuteEnd) in cases) {
    testWidgets('clock paints the booking time $time', (tester) async {
      await tester.pumpWidget(_clock(time));
      final drawing = find.descendant(
        of: find.byType(WorkloopIllustration),
        matching: find.byType(CustomPaint),
      );
      // Match the actual two hands, allowing floating-point rounding. The
      // expected endpoints cover midnight, PM and an hour hand between ticks.
      bool hand(Symbol method, List<dynamic> args, Offset endpoint) =>
          method == #drawLine &&
          args[0] == const Offset(24, 24) &&
          ((args[1] as Offset) - endpoint).distance < 0.001;
      expect(
        drawing,
        paints
          ..something((method, args) => hand(method, args, hourEnd))
          ..something((method, args) => hand(method, args, minuteEnd)),
      );
    });
  }

  testWidgets('changing the booking time invalidates the clock painting', (
    tester,
  ) async {
    final drawing = find.descendant(
      of: find.byType(WorkloopIllustration),
      matching: find.byType(CustomPaint),
    );
    await tester.pumpWidget(_clock(const TimeOfDay(hour: 10, minute: 0)));
    final before = tester.widget<CustomPaint>(drawing).painter!;
    await tester.pumpWidget(_clock(const TimeOfDay(hour: 10, minute: 45)));
    final after = tester.widget<CustomPaint>(drawing).painter!;
    expect(after.shouldRepaint(before), isTrue);
    await tester.pumpWidget(_clock(const TimeOfDay(hour: 10, minute: 45)));
    expect(
      tester.widget<CustomPaint>(drawing).painter!.shouldRepaint(after),
      isFalse,
    );
  });
}

Widget _clock(TimeOfDay time) => MaterialApp(
  theme: AppTheme.light,
  home: Center(
    child: WorkloopIllustration(
      kind: WorkloopIllustrationKind.clock,
      clockTime: time,
      size: 66,
    ),
  ),
);
