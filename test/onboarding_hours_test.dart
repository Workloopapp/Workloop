import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only in-memory backend for SharedPreferencesAsync.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/onboarding/onboarding_screen.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const _days = {
  'Mon': 'Monday',
  'Tue': 'Tuesday',
  'Wed': 'Wednesday',
  'Thu': 'Thursday',
  'Fri': 'Friday',
  'Sat': 'Saturday',
  'Sun': 'Sunday',
};

Map<String, dynamic> _allDaysOpen() => {
  for (final day in _days.keys)
    day: {
      'enabled': true,
      'open': day == 'Sun' ? '08:15' : '09:00',
      'close': day == 'Sun' ? '16:45' : '17:00',
    },
};

class _HoursDraft extends OnboardingNotifier {
  int saves = 0;
  final steps = <int>[];

  @override
  OnboardingState build() =>
      OnboardingState(currentStep: 4, workingHours: _allDaysOpen());

  @override
  Future<void> restore() async {}

  @override
  void setWorkingHours(Map<String, dynamic> hours) {
    saves++;
    super.setWorkingHours(hours);
  }

  @override
  void setStep(int step) {
    steps.add(step);
    super.setStep(step);
  }
}

class _SignedOutAuth implements GoTrueClient {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOutClient implements SupabaseClient {
  @override
  GoTrueClient get auth => _SignedOutAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  setUpAll(() async {
    // Layout assertions should measure the shipped typeface, not Ahem boxes.
    for (final family in ['Manrope', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final (size, safeArea) in [
    (const Size(390, 844), const EdgeInsets.only(top: 47, bottom: 34)),
    (const Size(430, 932), const EdgeInsets.only(top: 59, bottom: 34)),
    (const Size(320, 568), const EdgeInsets.only(top: 20)),
  ]) {
    testWidgets('whole working week fits with onboarding header at $size', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpHours(tester, size: size, safeArea: safeArea);
        expect(find.text('Working hours · 4 of 7'), findsOneWidget);
        expect(_hoursPosition(tester).maxScrollExtent, 0);
        final footer = tester.getRect(_continueButton);
        expect(footer.bottom, lessThanOrEqualTo(size.height - safeArea.bottom));
        expect(_continueButton.hitTestable(), findsOneWidget);
        expect(footer.height, greaterThanOrEqualTo(44));

        for (final day in _days.values) {
          for (final label in [
            '$day working day',
            '$day opening time',
            '$day closing time',
          ]) {
            final control = find.bySemanticsLabel(label);
            expect(control.hitTestable(), findsOneWidget, reason: label);
            final rect = tester.getRect(control);
            expect(rect.height, greaterThanOrEqualTo(44), reason: label);
            expect(rect.width, greaterThanOrEqualTo(44), reason: label);
            expect(rect.top, greaterThanOrEqualTo(safeArea.top));
            expect(rect.bottom, lessThanOrEqualTo(footer.top));
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('double text scrolls the week while Continue stays available', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpHours(
        tester,
        size: const Size(320, 568),
        safeArea: const EdgeInsets.only(top: 20),
        textScale: 2,
      );
      final footerBefore = tester.getRect(_continueButton);
      expect(_continueButton.hitTestable(), findsOneWidget);
      expect(footerBefore.height, greaterThanOrEqualTo(44));
      expect(_hoursPosition(tester).maxScrollExtent, greaterThan(0));
      for (final entry in _days.entries) {
        final toggle = find.bySemanticsLabel('${entry.value} working day');
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        expect(toggle.hitTestable(), findsOneWidget);
        expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
        for (final (field, label) in [
          ('open', 'opening'),
          ('close', 'closing'),
        ]) {
          final control = find.bySemanticsLabel('${entry.value} $label time');
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(control.hitTestable(), findsOneWidget);
          expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
          expect(
            MediaQuery.textScalerOf(tester.element(control)).scale(14),
            28,
          );
          expect(
            tester.getSemantics(control).getSemanticsData().value,
            (_allDaysOpen()[entry.key] as Map)[field],
          );
          final text = find.descendant(
            of: control,
            matching: find.byType(RichText),
          );
          expect(text, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
            isFalse,
          );
          expect(tester.getRect(_continueButton), footerBefore);
          expect(_continueButton.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'day toggles retain times and Continue saves the exact week once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final container = await _pumpHours(tester);
        final sunday = find.bySemanticsLabel('Sunday working day');
        await tester.tap(sunday);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(sunday).getSemanticsData().value, 'Closed');
        expect(find.bySemanticsLabel('Sunday opening time'), findsNothing);
        await tester.tap(sunday);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(sunday).getSemanticsData().value, 'Open');
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Sunday opening time'))
              .getSemanticsData()
              .value,
          '08:15',
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Sunday closing time'))
              .getSemanticsData()
              .value,
          '16:45',
        );
        await tester.tap(find.bySemanticsLabel('Tuesday working day'));
        await tester.pumpAndSettle();
        expect(container.read(onboardingProvider).workingHours, _allDaysOpen());
        final notifier =
            container.read(onboardingProvider.notifier) as _HoursDraft;
        expect(notifier.saves, 0);
        await tester.tap(_continueButton);
        await tester.pumpAndSettle();
        final expected = _allDaysOpen();
        (expected['Tue'] as Map)['enabled'] = false;
        final state = container.read(onboardingProvider);
        expect(state.workingHours, expected);
        expect(OnboardingState.fromJson(state.toJson()).workingHours, expected);
        expect(notifier.saves, 1);
        expect(notifier.steps, [5]);
        expect(find.text('Preferences · 5 of 7'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'time picker cancel and confirm preserve the requested day and field',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final container = await _pumpHours(tester, use24HourFormat: true);
        for (final (label, title, initial, chosen, confirm) in [
          (
            'opening',
            'Choose opening time',
            const TimeOfDay(hour: 9, minute: 0),
            const TimeOfDay(hour: 8, minute: 45),
            false,
          ),
          (
            'opening',
            'Choose opening time',
            const TimeOfDay(hour: 9, minute: 0),
            const TimeOfDay(hour: 7, minute: 5),
            true,
          ),
          (
            'closing',
            'Choose closing time',
            const TimeOfDay(hour: 17, minute: 0),
            const TimeOfDay(hour: 18, minute: 30),
            true,
          ),
        ]) {
          final control = find.bySemanticsLabel('Monday $label time');
          await tester.tap(control);
          await tester.pumpAndSettle();
          expect(find.text(title), findsOneWidget);
          final picker = tester.widget<CupertinoDatePicker>(
            find.byType(CupertinoDatePicker),
          );
          expect(picker.initialDateTime.hour, initial.hour);
          expect(picker.initialDateTime.minute, initial.minute);
          expect(picker.use24hFormat, isTrue);
          picker.onDateTimeChanged(
            DateTime(2000, 1, 1, chosen.hour, chosen.minute),
          );
          await tester.pumpAndSettle();
          final action = find.widgetWithText(
            WorkloopPrimaryButton,
            confirm ? 'Use time' : 'Cancel',
          );
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          await tester.tap(action);
          await tester.pumpAndSettle();
          final expected = confirm ? chosen : initial;
          expect(
            tester.getSemantics(control).getSemanticsData().value,
            '${expected.hour.toString().padLeft(2, '0')}:${expected.minute.toString().padLeft(2, '0')}',
          );
        }
        expect(container.read(onboardingProvider).workingHours, _allDaysOpen());
        await tester.tap(_continueButton);
        await tester.pumpAndSettle();
        final expected = _allDaysOpen();
        (expected['Mon'] as Map)['open'] = '07:05';
        (expected['Mon'] as Map)['close'] = '18:30';
        expect(container.read(onboardingProvider).workingHours, expected);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}

Finder get _continueButton =>
    find.byKey(const ValueKey('onboarding-hours-continue'));

ScrollPosition _hoursPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('onboarding-hours-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<ProviderContainer> _pumpHours(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  EdgeInsets safeArea = const EdgeInsets.only(top: 47, bottom: 34),
  double textScale = 1,
  bool use24HourFormat = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(_SignedOutClient()),
      onboardingProvider.overrideWith(_HoursDraft.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: safeArea,
            viewPadding: safeArea,
            textScaler: TextScaler.linear(textScale),
            alwaysUse24HourFormat: use24HourFormat,
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const OnboardingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return container;
}
