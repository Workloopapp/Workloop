import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/onboarding/onboarding_screen.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';

class _HoursDraft extends OnboardingNotifier {
  @override
  OnboardingState build() => OnboardingState(currentStep: 4, workingHours: {
    for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
      day: {'enabled': true, 'open': '09:00', 'close': '17:00'},
  });
  @override
  Future<void> restore() async {}
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  setUpAll(() async {
    for (final entry in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      '.SF Pro Text': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/lucide_flutter/LucideIcons': 'packages/lucide_flutter/assets/lucide.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
    }
  });
  testWidgets('audit render auth double text keyboard and legal reachability', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pump(tester, const AuthScreen(), AppTheme.light);
      await _capture(tester, 'auth-light-2x-top');
      final email = find.widgetWithText(TextField, 'Email address');
      await tester.ensureVisible(email);
      await tester.enterText(email, 'fictional@example.com');
      tester.view.viewInsets = const FakeViewPadding(bottom: 216);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final password = find.widgetWithText(TextField, 'Password');
      await tester.ensureVisible(password);
      await tester.enterText(password, 'Fictional audit only');
      await tester.pumpAndSettle();
      expect(tester.getRect(password).bottom, lessThanOrEqualTo(568 - 216));
      await _capture(tester, 'auth-light-2x-keyboard');
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final privacy = find.byKey(const ValueKey('auth-privacy-link'));
      await tester.ensureVisible(privacy);
      await tester.pumpAndSettle();
      expect(privacy.hitTestable(), findsOneWidget);
      await _capture(tester, 'auth-light-2x-footer');
      expect(tester.takeException(), isNull);
    } finally { debugDefaultTargetPlatformOverride = null; }
  });
  testWidgets('audit render hours double text pinned footer and final day', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, const OnboardingScreen(), AppTheme.dark, hours: true);
      await _capture(tester, 'hours-dark-2x-top');
      final sunday = find.bySemanticsLabel('Sunday closing time');
      await tester.ensureVisible(sunday);
      await tester.pumpAndSettle();
      expect(sunday.hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-hours-continue')).hitTestable(), findsOneWidget);
      await _capture(tester, 'hours-dark-2x-sunday');
      expect(tester.takeException(), isNull);
    } finally { semantics.dispose(); }
  });
}

Future<void> _pump(WidgetTester tester, Widget home, ThemeData theme, {bool hours = false}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(key: const ValueKey('audit-capture'), child: ProviderScope(
    overrides: [if (hours) onboardingProvider.overrideWith(_HoursDraft.new)],
    child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 20), viewPadding: const EdgeInsets.only(top: 20),
        textScaler: const TextScaler.linear(2), disableAnimations: true,
      ), child: child!), home: home),
  )));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('audit-capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/private/tmp/workloop-audit-$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
