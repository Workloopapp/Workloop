import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

List<WorkloopNavItem> _items(AppColors colors) => [
  WorkloopNavItem(
    label: 'Today',
    icon: Icons.calendar_today,
    color: colors.modHome,
  ),
  WorkloopNavItem(
    label: 'Clients',
    icon: Icons.people,
    color: colors.modClients,
  ),
  WorkloopNavItem(label: 'Work', icon: Icons.build, color: colors.modTasks),
  WorkloopNavItem(
    label: 'Money',
    icon: Icons.receipt,
    color: colors.modFinance,
  ),
  WorkloopNavItem(label: 'Business', icon: Icons.store, color: colors.modNotes),
];

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
}

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('QUIET_WARM_SCREENSHOTS')) {
      await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
      await _loadFont('Ahem', 'assets/fonts/Manrope-Variable.ttf');
      await _loadFont('WorkloopMono', 'assets/fonts/WorkloopMono-Regular.ttf');
    }
  });
  for (final tokens in [WorkloopThemeTokens.light, WorkloopThemeTokens.dark]) {
    test('paper text and action contrast ${tokens.background}', () {
      for (final surface in [
        tokens.background,
        tokens.surface,
        tokens.paperBlue,
        tokens.paperYellow,
      ]) {
        expect(
          _contrast(tokens.textPrimary, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(tokens.textSecondary, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        _contrast(tokens.onPrimaryAction, tokens.primaryAction),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(tokens.accentInk, tokens.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(_contrast(tokens.frame, tokens.surface), greaterThanOrEqualTo(3));
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'full-width navigation preserves drag and safe area $direction',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 568),
                padding: EdgeInsets.only(bottom: 34),
                textScaler: TextScaler.linear(2),
              ),
              child: Directionality(
                textDirection: direction,
                child: StatefulBuilder(
                  builder: (context, setState) => Scaffold(
                    bottomNavigationBar: WorkloopBottomNav(
                      currentIndex: selected,
                      items: _items(AppColors.light),
                      onTap: (value) => setState(() => selected = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final bar = tester.getRect(find.byType(WorkloopBottomNav));
        expect(bar.left, 0);
        expect(bar.right, 320);
        final business = tester.getRect(find.bySemanticsLabel('Business'));
        expect(business.width, greaterThanOrEqualTo(48));
        expect(business.height, greaterThanOrEqualTo(48));
        expect(business.bottom, lessThanOrEqualTo(568 - 34));
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Business'))
              .didExceedMaxLines,
          isFalse,
        );
        await tester.tap(find.bySemanticsLabel('Business'));
        await tester.pumpAndSettle();
        expect(selected, 4);
        final today = tester.getCenter(find.bySemanticsLabel('Today'));
        await tester.dragFrom(
          tester.getCenter(find.bySemanticsLabel('Business')),
          today - tester.getCenter(find.bySemanticsLabel('Business')),
        );
        await tester.pumpAndSettle();
        expect(selected, 0);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'paper controls remain readable ${dark ? 'dark' : 'light'} ${scale}x',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var actions = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 844),
                  textScaler: TextScaler.linear(scale),
                ),
                child: RepaintBoundary(
                  key: const ValueKey('paper-preview'),
                  child: WorkloopAppCanvas(
                    child: Scaffold(
                      body: ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          const WorkloopWordmark(),
                          const SizedBox(height: 20),
                          const WorkloopCaption('A quieter working day'),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              for (final kind
                                  in WorkloopIllustrationKind.values)
                                WorkloopIllustration(kind: kind),
                            ],
                          ),
                          const SizedBox(height: 20),
                          WorkloopNavigationControl<int>(
                            segments: const [
                              WorkloopSegment(value: 0, label: 'Overview'),
                              WorkloopSegment(value: 1, label: 'Bookings'),
                            ],
                            selected: 0,
                            onChanged: (_) {},
                          ),
                          const SizedBox(height: 16),
                          WorkloopPaperPanel(
                            title: 'Up next',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Everything you need for your next visit.',
                                ),
                                const SizedBox(height: 12),
                                WorkloopPrimaryButton(
                                  label: 'View booking',
                                  onPressed: () => actions++,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const WorkloopPaperPanel(
                            title: 'Needs attention',
                            tone: WorkloopPaperTone.warm,
                            child: Text(
                              'Your important updates stay easy to find.',
                            ),
                          ),
                        ],
                      ),
                      bottomNavigationBar: WorkloopBottomNav(
                        currentIndex: 0,
                        items: _items(dark ? AppColors.dark : AppColors.light),
                        onTap: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('View booking'));
          await tester.tap(find.text('View booking'));
          expect(actions, 1);
          expect(
            tester
                .renderObject<RenderParagraph>(find.text('View booking'))
                .didExceedMaxLines,
            isFalse,
          );
          if (const bool.fromEnvironment('QUIET_WARM_SCREENSHOTS')) {
            await tester.pumpAndSettle();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('paper-preview')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '/tmp/workloop-quiet-warm-components-${dark ? 'dark' : 'light'}-${scale}x.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}

Future<void> _loadFont(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}
