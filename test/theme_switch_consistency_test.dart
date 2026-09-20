import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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
import 'package:workloop/features/onboarding/screens/ob_hours.dart';
import 'package:workloop/features/onboarding/screens/ob_services.dart';
import 'package:workloop/features/onboarding/screens/onboarding_service_editor.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/providers/theme_mode_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const _captureKey = ValueKey('theme-transition-capture');

class _AppearanceStore implements ThemeModeStore {
  String value = 'dark';

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async => this.value = value;
}

class _ServicesDraft extends OnboardingNotifier {
  @override
  OnboardingState build() => OnboardingState(
    currentStep: 3,
    servicesReviewed: true,
    services: [
      {
        'name': 'Consultation',
        'duration': 45,
        'price': 55.0,
        'description': 'A practical first meeting.\nIncludes a written plan.',
      },
    ],
  );
}

Map<String, dynamic> _workingWeek() => {
  for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
    day: {'enabled': true, 'open': '08:15', 'close': '16:45'},
};

class _HoursDraft extends OnboardingNotifier {
  int saves = 0;

  @override
  OnboardingState build() =>
      OnboardingState(currentStep: 4, workingHours: _workingWeek());

  @override
  Future<void> restore() async {}

  @override
  void setWorkingHours(Map<String, dynamic> hours) {
    saves++;
    state = state.copyWith(workingHours: hours);
  }

  @override
  void setStep(int step) => state = state.copyWith(currentStep: step);
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  setUpAll(() async {
    for (final family in ['Manrope', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('mounted service card repaints across appearance changes', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        themeModeStoreProvider.overrideWithValue(_AppearanceStore()),
        onboardingProvider.overrideWith(_ServicesDraft.new),
      ],
    );
    addTearDown(container.dispose);
    await _pumpAppearance(
      tester,
      container,
      Scaffold(
        body: SafeArea(
          child: ObServices(onNext: () {}, onBack: () {}),
        ),
      ),
    );
    final originalState = tester.state(find.byType(ObServices));
    final originalDraft = container.read(onboardingProvider).toJson();
    final card = find
        .ancestor(
          of: find.text('Consultation'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        )
        .first;

    for (final (appearance, tokens) in [
      (WorkloopAppearance.dark, WorkloopThemeTokens.dark),
      (WorkloopAppearance.light, WorkloopThemeTokens.light),
      (WorkloopAppearance.dark, WorkloopThemeTokens.dark),
    ]) {
      await container
          .read(workloopAppearanceProvider.notifier)
          .setAppearance(appearance);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ObServices)), same(originalState));
      expect(container.read(onboardingProvider).toJson(), originalDraft);
      final pixels = await _pixelsAt(tester, {
        'service card': tester.getTopLeft(card) + const Offset(8, 30),
      });
      expect(
        pixels['service card'],
        tokens.surface.toARGB32(),
        reason:
            '${appearance.name}: the painted fill must match the active theme',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'mounted working hours follow manual and system themes without losing edits',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final container = ProviderContainer(
          overrides: [
            themeModeStoreProvider.overrideWithValue(_AppearanceStore()),
            onboardingProvider.overrideWith(_HoursDraft.new),
          ],
        );
        addTearDown(container.dispose);
        await _pumpAppearance(tester, container, const OnboardingScreen());
        final originalOnboarding = tester.state(find.byType(OnboardingScreen));
        final originalHours = tester.state(find.byType(ObHours));
        final sunday = find.bySemanticsLabel('Sunday working day');
        await tester.tap(sunday);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(sunday).getSemanticsData().value, 'Closed');
        final panel = find.byType(WorkloopPaperPanel);
        final mondayTime = find.bySemanticsLabel('Monday opening time');

        Future<void> expectHoursAppearance(
          Brightness expected,
          String reason,
        ) async {
          final tokens = expected == Brightness.light
              ? WorkloopThemeTokens.light
              : WorkloopThemeTokens.dark;
          final pixels = await _pixelsAt(tester, {
            'canvas': const Offset(2, 840),
            'hours paper': tester.getTopLeft(panel) + const Offset(4, 55),
            'hours header': tester.getTopLeft(panel) + const Offset(5, 16),
            'time field':
                tester.getRect(mondayTime).centerLeft + const Offset(5, 0),
          });
          expect(pixels, {
            'canvas': tokens.background.toARGB32(),
            'hours paper': tokens.surface.toARGB32(),
            'hours header': tokens.paperBlue.toARGB32(),
            'time field': tokens.surfaceSubtle.toARGB32(),
          }, reason: reason);
          expect(
            tester.widget<Text>(find.text('When do you work?')).style?.color,
            tokens.textPrimary,
          );
          expect(
            tester.state(find.byType(OnboardingScreen)),
            same(originalOnboarding),
          );
          expect(tester.state(find.byType(ObHours)), same(originalHours));
          expect(
            tester.getSemantics(sunday).getSemanticsData().value,
            'Closed',
          );
          expect(
            tester.getSemantics(mondayTime).getSemanticsData().value,
            '08:15',
          );
          expect(
            container.read(onboardingProvider).workingHours,
            _workingWeek(),
          );
          expect(container.read(onboardingProvider).currentStep, 4);
          expect(tester.takeException(), isNull);
        }

        for (final (appearance, platform, expected) in [
          (WorkloopAppearance.light, Brightness.dark, Brightness.light),
          (WorkloopAppearance.light, Brightness.light, Brightness.light),
          (WorkloopAppearance.dark, Brightness.light, Brightness.dark),
        ]) {
          tester.platformDispatcher.platformBrightnessTestValue = platform;
          await container
              .read(workloopAppearanceProvider.notifier)
              .setAppearance(appearance);
          await tester.pumpAndSettle();
          await expectHoursAppearance(
            expected,
            '${appearance.name} with ${platform.name} phone appearance',
          );
        }

        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await container
            .read(workloopAppearanceProvider.notifier)
            .setAppearance(WorkloopAppearance.system);
        await tester.pumpAndSettle();
        // These transitions only change the phone setting. The harness does
        // not observe brightness or write the appearance provider again.
        for (final platform in [
          Brightness.light,
          Brightness.dark,
          Brightness.light,
        ]) {
          tester.platformDispatcher.platformBrightnessTestValue = platform;
          await tester.pumpAndSettle();
          expect(
            container.read(workloopAppearanceProvider).value,
            WorkloopAppearance.system,
          );
          await expectHoursAppearance(
            platform,
            'System follows ${platform.name} phone appearance',
          );
        }
        final continueButton = find.byKey(
          const ValueKey('onboarding-hours-continue'),
        );
        expect(continueButton.hitTestable(), findsOneWidget);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        final expectedWeek = _workingWeek();
        (expectedWeek['Sun'] as Map)['enabled'] = false;
        expect(container.read(onboardingProvider).workingHours, expectedWeek);
        expect(
          (container.read(onboardingProvider.notifier) as _HoursDraft).saves,
          1,
        );
        expect(container.read(onboardingProvider).currentStep, 5);
        expect(find.text('Preferences · 5 of 7'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('SlateSurface repaints without replacing nested editor state', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(_AppearanceStore())],
    );
    addTearDown(container.dispose);
    await _pumpAppearance(
      tester,
      container,
      const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: SlateSurface(
              key: ValueKey('retained-surface'),
              child: _RetainedEditor(),
            ),
          ),
        ),
      ),
    );
    final editor = tester.state<_RetainedEditorState>(
      find.byType(_RetainedEditor),
    );
    final controller = editor.controller;
    final focus = editor.focus;
    await tester.enterText(find.byType(TextField), 'Keep this unsaved draft');
    await tester.tap(find.text('Count 0'));
    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
    focus.requestFocus();
    await tester.pumpAndSettle();

    for (final appearance in [
      WorkloopAppearance.light,
      WorkloopAppearance.dark,
      WorkloopAppearance.light,
    ]) {
      await container
          .read(workloopAppearanceProvider.notifier)
          .setAppearance(appearance);
      await tester.pumpAndSettle();
      final current = tester.state<_RetainedEditorState>(
        find.byType(_RetainedEditor),
      );
      expect(current, same(editor));
      expect(current.controller, same(controller));
      expect(current.controller.text, 'Keep this unsaved draft');
      expect(
        current.controller.selection,
        const TextSelection(baseOffset: 5, extentOffset: 9),
      );
      expect(current.focus, same(focus));
      expect(current.focus.hasFocus, isTrue);
      expect(find.text('Count 1'), findsOneWidget);
      final surface = tester.getRect(
        find.byKey(const ValueKey('retained-surface')),
      );
      final pixels = await _pixelsAt(tester, {
        'surface': surface.bottomLeft + const Offset(8, -8),
      });
      final tokens = appearance == WorkloopAppearance.light
          ? WorkloopThemeTokens.light
          : WorkloopThemeTokens.dark;
      expect(pixels['surface'], tokens.surface.toARGB32());
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('open service editor follows the theme and preserves its draft', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        themeModeStoreProvider.overrideWithValue(_AppearanceStore()),
        onboardingProvider.overrideWith(_ServicesDraft.new),
      ],
    );
    addTearDown(container.dispose);
    await _pumpAppearance(
      tester,
      container,
      Scaffold(
        body: SafeArea(
          child: ObServices(onNext: () {}, onBack: () {}),
        ),
      ),
    );
    final savedDraft = container.read(onboardingProvider).toJson();
    await tester.tap(find.text('Consultation'));
    await tester.pumpAndSettle();
    final editor = find.byType(OnboardingServiceEditor);
    final originalState = tester.state(editor);
    final description = find.byKey(
      const ValueKey('onboarding-service-description'),
    );
    await tester.enterText(
      description,
      'Keep this revised description.\nStill being edited.',
    );
    final controller = tester.widget<TextField>(description).controller!;
    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pumpAndSettle();

    for (final appearance in [
      WorkloopAppearance.light,
      WorkloopAppearance.dark,
      WorkloopAppearance.light,
    ]) {
      await container
          .read(workloopAppearanceProvider.notifier)
          .setAppearance(appearance);
      await tester.pumpAndSettle();
      final tokens = appearance == WorkloopAppearance.light
          ? WorkloopThemeTokens.light
          : WorkloopThemeTokens.dark;
      final sheet = tester.getRect(find.byType(BottomSheet));
      final pixels = await _pixelsAt(tester, {
        'sheet': sheet.centerLeft + const Offset(8, 0),
      });
      expect(pixels['sheet'], tokens.surface.toARGB32());
      expect(
        tester.widget<Text>(find.text('Edit service')).style?.color,
        tokens.textPrimary,
      );
      expect(tester.state(editor), same(originalState));
      expect(
        tester.widget<TextField>(description).controller,
        same(controller),
      );
      expect(
        controller.text,
        'Keep this revised description.\nStill being edited.',
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 8));
      expect(container.read(onboardingProvider).toJson(), savedDraft);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'open date picker follows manual and system themes and keeps the chosen date',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          themeModeStoreProvider.overrideWithValue(_AppearanceStore()),
        ],
      );
      addTearDown(container.dispose);
      DateTime? result;
      var completions = 0;
      await _pumpAppearance(
        tester,
        container,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showWorkloopDatePicker(
                    context: context,
                    initialDate: DateTime(2026, 9, 9),
                    firstDate: DateTime(2026, 9, 1),
                    lastDate: DateTime(2026, 9, 30),
                  );
                  completions++;
                },
                child: const Text('Choose booking date'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose booking date'));
      await tester.pumpAndSettle();
      final calendar = find.byType(CalendarDatePicker);
      final originalState = tester.state(calendar);
      final chosen = DateTime(2026, 9, 17);
      await tester.tap(find.text('17'));
      await tester.pumpAndSettle();

      for (final (appearance, platform, expected) in [
        (WorkloopAppearance.light, Brightness.dark, Brightness.light),
        (WorkloopAppearance.dark, Brightness.light, Brightness.dark),
        (WorkloopAppearance.system, Brightness.light, Brightness.light),
        (WorkloopAppearance.system, Brightness.dark, Brightness.dark),
      ]) {
        tester.platformDispatcher.platformBrightnessTestValue = platform;
        await container
            .read(workloopAppearanceProvider.notifier)
            .setAppearance(appearance);
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(calendar));
        expect(theme.brightness, expected);
        expect(theme.colorScheme.brightness, expected);
        expect(tester.state(calendar), same(originalState));
        expect(tester.widget<CalendarDatePicker>(calendar).initialDate, chosen);
        expect(completions, 0);
        expect(tester.takeException(), isNull);
      }
      final useDate = find.widgetWithText(WorkloopPrimaryButton, 'Use date');
      expect(useDate.hitTestable(), findsOneWidget);
      await tester.tap(useDate);
      await tester.pumpAndSettle();
      expect(result, chosen);
      expect(completions, 1);
      expect(calendar, findsNothing);
    },
  );
}

class _RetainedEditor extends StatefulWidget {
  const _RetainedEditor();

  @override
  State<_RetainedEditor> createState() => _RetainedEditorState();
}

class _RetainedEditorState extends State<_RetainedEditor> {
  final controller = TextEditingController();
  final focus = FocusNode();
  int count = 0;

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextField(controller: controller, focusNode: focus),
      TextButton(
        onPressed: () => setState(() => count++),
        child: Text('Count $count'),
      ),
    ],
  );
}

Future<void> _pumpAppearance(
  WidgetTester tester,
  ProviderContainer container,
  Widget home,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _AppearanceHarness(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

class _AppearanceHarness extends ConsumerWidget {
  const _AppearanceHarness({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode =
        ref.watch(workloopAppearanceProvider).value?.themeMode ??
        ThemeMode.system;
    return RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: home,
      ),
    );
  }
}

// Widget color properties can resolve to the new palette while an existing
// decoration painter still holds the outgoing color. Sample actual pixels.
Future<Map<String, int>> _pixelsAt(
  WidgetTester tester,
  Map<String, Offset> points,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final origin = tester.getTopLeft(find.byKey(_captureKey));
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return points.map((label, global) {
        final point = global - origin;
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final argb =
            (bytes.getUint8(offset + 3) << 24) |
            (bytes.getUint8(offset) << 16) |
            (bytes.getUint8(offset + 1) << 8) |
            bytes.getUint8(offset + 2);
        return MapEntry(label, argb);
      });
    } finally {
      image.dispose();
    }
  });
  return result!;
}
