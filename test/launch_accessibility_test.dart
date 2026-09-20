import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/calendar_sync/calendar_sync_screen.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  testWidgets('bottom navigation exposes invokable semantic tap actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selectedIndex = 0;
    var navigationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: WorkloopBottomNav(
              currentIndex: selectedIndex,
              items: [
                WorkloopNavItem(
                  label: 'Home',
                  icon: Icons.home_outlined,
                  color: AppColors.dark.accentPrimary,
                ),
                WorkloopNavItem(
                  label: 'Clients',
                  icon: Icons.people_outline,
                  color: AppColors.dark.accentPrimary,
                ),
              ],
              onTap: (index) {
                navigationCount++;
                setState(() => selectedIndex = index);
              },
            ),
          ),
        ),
      ),
    );

    final clientsSemantics = find.semantics.byLabel('Clients');
    expect(clientsSemantics, findsOne);
    expect(
      clientsSemantics.evaluate().single.getSemanticsData().hasAction(
        SemanticsAction.tap,
      ),
      isTrue,
    );

    tester.semantics.tap(clientsSemantics);
    await tester.pump();

    expect(selectedIndex, 1);
    expect(navigationCount, 1);
    expect(
      clientsSemantics
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('retryable error state exposes a full-size action', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SlateErrorState(
            message: 'Could not load clients',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    final retry = find.widgetWithText(TextButton, 'Try again');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));

    await tester.tap(retry);
    expect(retries, 1);
  });

  testWidgets('segments expose labels and retain 44 point targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                WorkloopSegmentedControl<bool>(
                  segments: const [
                    WorkloopSegment(value: false, label: 'All'),
                    WorkloopSegment(value: true, label: 'Unread', badge: '2'),
                  ],
                  selected: selected,
                  onChanged: (value) => setState(() => selected = value),
                ),
                SlateFilterChip(label: 'Active', selected: true, onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('All'), findsOneWidget);
    expect(find.bySemanticsLabel('Unread'), findsOneWidget);
    expect(
      tester.getSize(find.byType(SlateFilterChip)).height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(find.bySemanticsLabel('Unread'));
    await tester.pump();
    expect(selected, isTrue);
    semantics.dispose();
  });

  testWidgets('loading skeleton disables animation when motion is reduced', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SlateLoadingBlock()),
        ),
      ),
    );

    final animation = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(animation.duration, Duration.zero);
  });

  testWidgets('route header stacks its action safely at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: WorkloopRouteHeader(
                title: 'Notification preferences',
                onBack: () {},
                trailing: WorkloopTextButton(
                  label: 'Save changes',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.bySemanticsLabel('Back')).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.text('Save changes')).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('calendar status rows adapt without overflow at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const CalendarSyncScreen(),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Conflict detection'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Active in booking form'), findsOneWidget);
  });
}
