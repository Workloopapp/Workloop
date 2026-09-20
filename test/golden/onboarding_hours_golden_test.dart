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
import 'package:workloop/features/onboarding/onboarding_screen.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';

class _HoursDraft extends OnboardingNotifier {
  @override
  OnboardingState build() => OnboardingState(
    currentStep: 4,
    workingHours: {
      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
        day: {
          'enabled': true,
          'open': day == 'Sun' ? '08:15' : '09:00',
          'close': day == 'Sun' ? '16:45' : '17:00',
        },
    },
  );

  @override
  Future<void> restore() async {}
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  setUpAll(() async {
    for (final entry in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
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
    testWidgets('onboarding whole working week $appearance surface', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('hours-golden'),
          child: ProviderScope(
            overrides: [onboardingProvider.overrideWith(_HoursDraft.new)],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 47, bottom: 34),
                  viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const OnboardingScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Working hours · 4 of 7'), findsOneWidget);
      final continueButton = find.byKey(
        const ValueKey('onboarding-hours-continue'),
      );
      expect(continueButton.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(continueButton).bottom,
        lessThanOrEqualTo(844 - 34),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('hours-golden')),
        matchesGoldenFile('files/onboarding-hours-$appearance.png'),
      );
    });
  }
}
