import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

final _request = BookingRequest(
  id: 'fictional-request',
  workspaceId: 'fictional-workspace',
  name: 'Maya Patel',
  phone: '07700 900123',
  email: 'maya@example.test',
  serviceName: 'Mobile full valet',
  serviceDurationMins: 90,
  servicePrice: 65,
  requestedFor: DateTime.utc(2026, 9, 9, 9, 30),
  requestedTimezone: 'Europe/London',
  message: 'Please use the driveway. I’ll leave the keys with reception.',
);

void main() {
  setUpAll(() async {
    for (final entry in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      'packages/lucide_flutter/LucideIcons':
          'packages/lucide_flutter/assets/lucide.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  for (final dark in [false, true]) {
    for (final surface in ['request', 'confirmation', 'picker']) {
      testWidgets('$surface sheet appearance ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        final theme = dark ? AppTheme.dark : AppTheme.light;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => RepaintBoundary(
                key: const ValueKey('sheet-golden'),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 34),
                    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
                  ),
                  child: child!,
                ),
              ),
              home: surface == 'picker'
                  ? Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 48, 18, 18),
                        child: WorkloopPickerField<String>(
                          title: 'Repeat booking',
                          hint: 'Choose frequency',
                          value: 'weekly',
                          options: const [
                            WorkloopPickerOption(value: 'once', label: 'Once'),
                            WorkloopPickerOption(
                              value: 'weekly',
                              label: 'Weekly',
                            ),
                            WorkloopPickerOption(
                              value: 'fortnightly',
                              label: 'Every two weeks',
                            ),
                          ],
                          onChanged: (_) {},
                        ),
                      ),
                    )
                  : BookingRequestDetailScreen(request: _request),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (surface == 'confirmation') {
          await tester.ensureVisible(find.text('Book'));
          await tester.tap(find.text('Book'));
          await tester.pumpAndSettle();
        } else if (surface == 'picker') {
          await tester.tap(find.text('Weekly'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final boundary = find.byKey(const ValueKey('sheet-golden'));
        final filename = 'sheet-$surface-${dark ? 'dark' : 'light'}.png';
        if (const bool.fromEnvironment('WORKLOOP_SHEET_REVIEW')) {
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(boundary)
                .toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('/tmp/workloop-sheet-visual-review');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/$filename',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await expectLater(boundary, matchesGoldenFile('files/$filename'));
      });
    }
  }
}
