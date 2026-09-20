import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const _items = [
  WorkloopNavItem(label: 'Today', icon: LucideIcons.home, color: Colors.blue),
  WorkloopNavItem(
    label: 'Clients',
    icon: LucideIcons.users,
    color: Colors.blue,
  ),
  WorkloopNavItem(
    label: 'Work',
    icon: LucideIcons.briefcase,
    color: Colors.blue,
  ),
  WorkloopNavItem(
    label: 'Money',
    icon: LucideIcons.receipt,
    color: Colors.blue,
  ),
  WorkloopNavItem(
    label: 'Business',
    icon: LucideIcons.store,
    color: Colors.blue,
  ),
];

/// Sample the actual paint result, including the final row: checking widget
/// heights alone would miss the old dividers stopping above the safe area.
Future<List<int>> _dividerGaps(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Color background,
) async {
  return (await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final backgroundArgb = background.toARGB32();
      final red = (backgroundArgb >> 16) & 0xff;
      final green = (backgroundArgb >> 8) & 0xff;
      final blue = backgroundArgb & 0xff;
      return [
        for (var divider = 1; divider < _items.length; divider++)
          (() {
            var gaps = 0;
            final x = (image.width * divider / _items.length).round();
            for (var y = 6; y < image.height; y++) {
              var hasLine = false;
              // Allow subpixel antialiasing around the one logical-pixel rule.
              for (var sample = x - 3; sample <= x + 3; sample++) {
                final offset = (y * image.width + sample) * 4;
                final distance =
                    (data.getUint8(offset) - red).abs() +
                    (data.getUint8(offset + 1) - green).abs() +
                    (data.getUint8(offset + 2) - blue).abs();
                if (distance > 24) hasLine = true;
              }
              if (!hasLine) gaps++;
            }
            return gaps;
          })(),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final inset in [0.0, 34.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'compact $brightness navigation keeps full dividers with inset $inset and text $scale',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final boundaryKey = GlobalKey();
            final taps = <int>[];
            late double controlHeight;
            late Color background;
            await tester.pumpWidget(
              MaterialApp(
                theme: brightness == Brightness.light
                    ? AppTheme.light
                    : AppTheme.dark,
                home: MediaQuery(
                  data: MediaQueryData(
                    padding: EdgeInsets.only(bottom: inset),
                    viewPadding: EdgeInsets.only(bottom: inset),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Builder(
                    builder: (context) {
                      controlHeight = AppSpacing.bottomNavHeightFor(context);
                      background = SlateTheme.of(context).surface;
                      return Scaffold(
                        extendBody: true,
                        body: const SizedBox.expand(),
                        bottomNavigationBar: RepaintBoundary(
                          key: boundaryKey,
                          child: WorkloopBottomNav(
                            currentIndex: 0,
                            items: _items,
                            onTap: taps.add,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
            await tester.pump();
            final nav = tester.getRect(find.byType(WorkloopBottomNav));
            expect(nav.bottom, 844);
            expect(nav.height, closeTo(controlHeight + inset, 0.01));
            if (scale == 1) expect(controlHeight, 52);

            for (var index = 0; index < _items.length; index++) {
              final tab = tester.getRect(
                find.byKey(ValueKey('workloop-bottom-nav-selection-$index')),
              );
              expect(tab.height, greaterThanOrEqualTo(AppSpacing.minTouch));
              expect(tab.bottom, closeTo(nav.bottom - inset, 0.01));
            }

            expect(
              await _dividerGaps(tester, boundaryKey, background),
              [0, 0, 0, 0],
              reason:
                  'Each divider must continue through the safe area to the bottom edge.',
            );
            // Taps on the painted separator still reach the adjacent tab.
            for (var index = 1; index < _items.length; index++) {
              await tester.tapAt(
                Offset(
                  nav.left + nav.width * index / _items.length + 0.1,
                  nav.top + controlHeight / 2,
                ),
              );
              await tester.pump();
            }
            expect(taps, [1, 2, 3, 4]);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
