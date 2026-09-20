import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only in-memory backend for SharedPreferencesAsync.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/onboarding/screens/ob_first_booking.dart';
import 'package:workloop/features/onboarding/screens/ob_hours.dart';
import 'package:workloop/features/onboarding/screens/ob_revenue_target.dart';
import 'package:workloop/features/onboarding/screens/ob_services.dart';
import 'package:workloop/features/onboarding/screens/ob_welcome.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

Future<void> _pumpOnboardingScreen(
  WidgetTester tester,
  Widget screen, {
  EdgeInsets? safeArea,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            padding: safeArea,
            viewPadding: safeArea,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: safeArea == null ? screen : SafeArea(child: screen),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'welcome stays readable and starts setup on a compact large-text phone',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var nextCalls = 0;
        await _pumpOnboardingScreen(
          tester,
          ObWelcome(onNext: () => nextCalls++),
          safeArea: const EdgeInsets.only(top: 20, bottom: 34),
        );

        for (final text in [
          'Your business,\nin good order.',
          'Bookings, clients and money, connected in one place. Built for people who work for themselves.',
          'A CLEARER WORKING DAY',
          'Know what’s next',
          'Your bookings and tasks, together.',
          'Every client, remembered',
          'Their details and history, ready.',
          'Money in view',
          'Quotes, invoices and payments.',
        ]) {
          final copy = find.text(text);
          expect(copy, findsOneWidget);
          await tester.ensureVisible(copy);
          await tester.pumpAndSettle();
          expect(MediaQuery.textScalerOf(tester.element(copy)).scale(16), 32);
          expect(find.semantics.byLabel(RegExp(RegExp.escape(text))), findsOne);
          expect(tester.takeException(), isNull);
        }

        final start = find.byKey(const ValueKey('onboarding-get-started'));
        await tester.ensureVisible(start);
        await tester.pumpAndSettle();
        expect(start.hitTestable(), findsOneWidget);
        expect(tester.getSize(start).height, greaterThanOrEqualTo(44));
        expect(tester.getRect(start).bottom, lessThanOrEqualTo(568 - 34));
        expect(nextCalls, 0);
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(nextCalls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('working hours remain usable on a small phone at large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpOnboardingScreen(tester, ObHours(onNext: () {}, onBack: () {}));

    expect(tester.takeException(), isNull);
    final openingTime = find.bySemanticsLabel('Monday opening time');
    final closingTime = find.bySemanticsLabel('Monday closing time');
    expect(openingTime, findsOneWidget);
    expect(closingTime, findsOneWidget);
    expect(tester.getSize(openingTime).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(closingTime).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Sunday working day'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('service removal and skip controls expose full-size targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpOnboardingScreen(
      tester,
      ObServices(onNext: () {}, onBack: () {}),
    );

    expect(tester.takeException(), isNull);
    final remove = find.bySemanticsLabel('Remove Consultation');
    expect(remove, findsOneWidget);
    expect(tester.getSize(remove).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));

    await tester.scrollUntilVisible(
      find.text('Skip — add services later'),
      120,
    );
    final skip = find.widgetWithText(TextButton, 'Skip — add services later');
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(44));

    semantics.dispose();
  });

  testWidgets('service editor scrolls and stacks fields on a compact phone', (
    tester,
  ) async {
    await _pumpOnboardingScreen(
      tester,
      ObServices(onNext: () {}, onBack: () {}),
    );

    final add = find.widgetWithText(OutlinedButton, 'Add a service');
    await tester.scrollUntilVisible(add, 140);
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(find.text('Add your service'), findsOneWidget);
    final description = find.byKey(
      const ValueKey('onboarding-service-description'),
    );
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Windows and frames.\nInside and out.');
    expect(find.text('Description'), findsOneWidget);
    expect(
      find.text('Shown to customers on your booking page.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(description).minLines, 2);
    expect(tester.widget<TextField>(description).maxLines, 4);
    expect(MediaQuery.textScalerOf(tester.element(description)).scale(16), 32);
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(description);
    await tester.pumpAndSettle();
    expect(description.hitTestable(), findsOneWidget);
    final hours = _serviceField('Hours');
    final minutes = _serviceField('Minutes');
    expect(hours, findsOneWidget);
    expect(minutes, findsOneWidget);
    expect(
      tester.getTopLeft(hours).dx,
      closeTo(tester.getTopLeft(minutes).dx, 1),
    );
    await tester.ensureVisible(_serviceField('Price'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(SlateButton, 'Add service');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(568 - 180));
    expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
    // Actual add/update persistence is covered by onboarding_improvements_test.
    await tester.binding.handlePopRoute();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-booking date and time fields are labelled and resilient', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpOnboardingScreen(
      tester,
      ObFirstBooking(onNext: () {}, onBack: () {}),
    );

    expect(tester.takeException(), isNull);
    final date = find.bySemanticsLabel('Booking date');
    final time = find.bySemanticsLabel('Booking time');
    expect(date, findsOneWidget);
    expect(time, findsOneWidget);
    expect(tester.getSize(date).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(time).height, greaterThanOrEqualTo(44));
    expect(find.text('Add your first booking to get started.'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('revenue shortcuts remain full-size at large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpOnboardingScreen(
      tester,
      ObRevenueTarget(onNext: () {}, onBack: () {}),
    );

    expect(tester.takeException(), isNull);
    final target = find.bySemanticsLabel('£1000');
    expect(target, findsOneWidget);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));

    semantics.dispose();
  });
}

Finder _serviceField(String label) => find.descendant(
  of: find.widgetWithText(WorkloopFormField, label),
  matching: find.byType(TextField),
);
