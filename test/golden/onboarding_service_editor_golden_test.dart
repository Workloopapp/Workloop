import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only in-memory backend for SharedPreferencesAsync.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/onboarding/screens/ob_services.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

class _ServicesDraft extends OnboardingNotifier {
  @override
  OnboardingState build() => const OnboardingState(
    servicesReviewed: true,
    services: [
      {'name': 'Consultation', 'duration': 45, 'price': 55.0},
    ],
  );
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  setUpAll(() async {
    // Use the shipped fonts rather than the headless engine's Ahem glyphs.
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

  for (final (appearance, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('onboarding service description editor $appearance surface', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          // Include the navigator overlay, so the modal itself is captured.
          key: const ValueKey('service-editor-golden'),
          child: ProviderScope(
            overrides: [onboardingProvider.overrideWith(_ServicesDraft.new)],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 59, bottom: 34),
                  viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                backgroundColor: theme.scaffoldBackgroundColor,
                body: Stack(
                  children: [
                    const Positioned.fill(child: WorkloopTexturedBackdrop()),
                    SafeArea(
                      child: ObServices(onNext: () {}, onBack: () {}),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consultation'));
      await tester.pumpAndSettle();
      final description = find.byKey(
        const ValueKey('onboarding-service-description'),
      );
      await tester.ensureVisible(description);
      await tester.enterText(
        description,
        'Talk through your plans and priorities.\nLeave with clear next steps.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final labelledField = find.widgetWithText(
        WorkloopFormField,
        'Description',
      );
      await tester.ensureVisible(labelledField);
      await tester.pumpAndSettle();
      expect(labelledField.hitTestable(), findsOneWidget);
      expect(
        find.text('Shown to customers on your booking page.'),
        findsOneWidget,
      );
      expect(find.text('Save service'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('service-editor-golden')),
        matchesGoldenFile('files/onboarding-service-editor-$appearance.png'),
      );
    });
  }
}
