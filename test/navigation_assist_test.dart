import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/clients/clients_screen.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/features/work/work_workspace_switcher.dart';
import 'package:workloop/main.dart' show MainShell;
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/booking_requests_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  for (final nativeStatusTap in [false, true]) {
    testWidgets(
      'real Clients shell returns to top via ${nativeStatusTap ? 'native status message' : 'reselected Clients tab'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(top: 47, bottom: 34);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        final observer = WorkloopNavigationObserver();
        final records = List<ClientCrmRecord>.generate(
          40,
          (index) => ClientCrmRecord(
            client: Client(
              id: 'client-$index',
              workspaceId: 'workspace-1',
              name: 'Client ${index.toString().padLeft(2, '0')}',
            ),
            bookingCount: 0,
            completedBookingCount: 0,
            nextBooking: null,
            lastBooking: null,
            lifetimeValue: 0,
            outstandingBalance: 0,
            openTaskCount: 0,
            overdueTaskCount: 0,
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clientCrmRecordsProvider.overrideWith((ref) async => records),
            ],
            child: _navigationHarness(
              observer: observer,
              home: const MainShell(initialIndex: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final clientScroll = find.descendant(
          of: find.byType(ClientsScreen),
          matching: find.byType(CustomScrollView),
        );
        final controller = tester
            .widget<CustomScrollView>(clientScroll)
            .controller!;
        await tester.drag(clientScroll, const Offset(0, -760));
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(500));
        if (nativeStatusTap) {
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            SystemChannels.statusBar.name,
            SystemChannels.statusBar.codec.encodeMethodCall(
              const MethodCall('handleScrollToTop'),
            ),
            (_) {},
          );
        } else {
          await tester.tap(
            find.descendant(
              of: find.byType(WorkloopBottomNav),
              matching: find.text('Clients'),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(controller.offset, controller.position.minScrollExtent);
        expect(
          find
              .descendant(
                of: find.byType(ClientsScreen),
                matching: find.text('Clients'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real Work reselection and native top preserve its hidden Notes position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final observer = WorkloopNavigationObserver();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentsProvider.overrideWith((ref) async => []),
            bookingRequestsProvider.overrideWith((ref) async => []),
            allTasksProvider.overrideWith(
              (ref) async => List.generate(
                40,
                (index) => SlateTask(
                  id: 'task-$index',
                  workspaceId: 'workspace',
                  title: 'Sample task $index',
                ),
              ),
            ),
            allNotesProvider.overrideWith(
              (ref) async => List.generate(
                40,
                (index) => SlateNote(
                  id: 'note-$index',
                  workspaceId: 'workspace',
                  title: 'Sample note $index',
                  body: 'Remember the details for this work.',
                ),
              ),
            ),
          ],
          child: _navigationHarness(
            observer: observer,
            home: const MainShell(initialIndex: 4),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ScrollPosition positionWithin(Type type) => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(type, skipOffstage: false),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Scrollable &&
                        axisDirectionToAxis(widget.axisDirection) ==
                            Axis.vertical,
                    skipOffstage: false,
                  ),
                )
                .first,
          )
          .position;
      final taskPosition = positionWithin(TasksScreen);
      final notePosition = positionWithin(NotesScreen);
      taskPosition.jumpTo(520);
      notePosition.jumpTo(680);
      await tester.pump();

      await tester.tap(
        find.descendant(
          of: find.byType(WorkloopBottomNav),
          matching: find.text('Work'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkWorkspaceSwitcher>(find.byType(WorkWorkspaceSwitcher))
            .selected,
        WorkWorkspaceSection.tasks,
      );
      expect(taskPosition.pixels, taskPosition.minScrollExtent);
      expect(notePosition.pixels, 680);

      taskPosition.jumpTo(520);
      await tester.pump();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.statusBar.name,
        SystemChannels.statusBar.codec.encodeMethodCall(
          const MethodCall('handleScrollToTop'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(taskPosition.pixels, taskPosition.minScrollExtent);
      expect(notePosition.pixels, 680);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('top tap preserves hidden positions on a shared controller', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    final shared = ScrollController();
    addTearDown(shared.dispose);
    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: IndexedStack(
            index: 0,
            children: [
              _longList(shared, 'Visible shared'),
              _longList(shared, 'Hidden shared'),
            ],
          ),
        ),
      ),
    );
    final positions = shared.positions.toList();
    expect(positions, hasLength(2));
    positions[0].jumpTo(520);
    positions[1].jumpTo(680);
    await tester.pump();
    await tester.tapAt(const Offset(200, 6));
    await tester.pumpAndSettle();
    expect(positions[0].pixels, positions[0].minScrollExtent);
    expect(positions[1].pixels, 680);
  });

  testWidgets('native status-bar message scrolls the current implicit list', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: ListView.builder(
            primary: false,
            itemCount: 80,
            itemBuilder: (context, index) =>
                SizedBox(height: 48, child: Text('Native row $index')),
          ),
        ),
      ),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(640);
    await tester.pump();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.statusBar.name,
      SystemChannels.statusBar.codec.encodeMethodCall(
        const MethodCall('handleScrollToTop'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(position.pixels, position.minScrollExtent);
  });

  testWidgets('a standalone scoped screen also responds to top taps', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: WorkloopNavigationScope(
          id: 'standalone-route',
          child: Scaffold(body: _longList(controller, 'Standalone')),
        ),
      ),
    );
    controller.jumpTo(600);
    await tester.pump();
    await tester.tapAt(const Offset(200, 6));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.minScrollExtent);
  });

  test('iOS preserves Flutter as the single native status-bar detector', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(source, isNot(contains('WorkloopStatusBarScrollBridge')));
    expect(source, isNot(contains('UIScrollView')));
    expect(source, isNot(contains('com.ismaeel.workloop/navigation')));
    expect(
      source,
      allOf(
        contains('func didInitializeImplicitFlutterEngine('),
        contains('engineBridge.applicationRegistrar.messenger()'),
        contains('WorkloopStripeTerminalBridge(messenger: messenger)'),
      ),
    );
  });

  testWidgets('a top-edge tap returns the visible screen to its beginning', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: ListView.builder(
            itemCount: 80,
            itemBuilder: (context, index) =>
                SizedBox(height: 48, child: Text('Row $index')),
          ),
        ),
      ),
    );
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(640);
    await tester.pump();
    expect(scrollable.position.pixels, 640);

    await tester.tapAt(const Offset(200, 6));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, scrollable.position.minScrollExtent);
  });

  testWidgets(
    'a non-primary implicit scroll view is discovered without screen wiring',
    (tester) async {
      final observer = WorkloopNavigationObserver();

      await tester.pumpWidget(
        _navigationHarness(
          observer: observer,
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 80, child: Text('Fixed header')),
                Expanded(
                  child: ListView.builder(
                    primary: false,
                    itemCount: 80,
                    itemBuilder: (context, index) =>
                        SizedBox(height: 48, child: Text('Implicit $index')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(720);
      await tester.pump();

      await tester.tapAt(const Offset(200, 6));
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, scrollable.position.minScrollExtent);
    },
  );

  testWidgets('one easy top tap resets every visible vertical scroll layer', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: _longList(first, 'Upper')),
              Expanded(child: _longList(second, 'Lower')),
            ],
          ),
        ),
      ),
    );
    first.jumpTo(520);
    second.jumpTo(680);
    await tester.pump();

    // This is deliberately below the tiny status-bar edge used by the first
    // implementation. The whole calm top/header zone should be forgiving.
    await tester.tapAt(const Offset(200, 64));
    await tester.pumpAndSettle();

    expect(first.offset, first.position.minScrollExtent);
    expect(second.offset, second.position.minScrollExtent);
  });

  testWidgets('Clients returns to its header from the broad top zone', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    final records = List<ClientCrmRecord>.generate(
      40,
      (index) => ClientCrmRecord(
        client: Client(
          id: 'client-$index',
          workspaceId: 'workspace-1',
          name: 'Client ${index.toString().padLeft(2, '0')}',
        ),
        bookingCount: 0,
        completedBookingCount: 0,
        nextBooking: null,
        lastBooking: null,
        lifetimeValue: 0,
        outstandingBalance: 0,
        openTaskCount: 0,
        overdueTaskCount: 0,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientCrmRecordsProvider.overrideWith((ref) async => records),
        ],
        child: _navigationHarness(
          observer: observer,
          home: const ClientsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final clientsView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final clientsController = clientsView.controller!;
    clientsController.jumpTo(760);
    await tester.pump();
    expect(clientsController.position.pixels, 760);

    await tester.tapAt(const Offset(160, 64));
    await tester.pumpAndSettle();

    expect(
      clientsController.position.pixels,
      clientsController.position.minScrollExtent,
    );
    expect(find.text('Clients'), findsOneWidget);
  });

  testWidgets('a top action keeps its action without resetting the page', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    final controller = ScrollController();
    var actions = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: Stack(
            children: [
              _longList(controller, 'Content'),
              Positioned(
                top: 16,
                right: 16,
                child: FilledButton(
                  onPressed: () => actions++,
                  child: const Text('Create'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.jumpTo(520);
    await tester.pump();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(actions, 1);
    expect(controller.offset, 520);
  });

  testWidgets('the active retained tab is scrolled without resetting others', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    final first = ScrollController();
    final second = ScrollController();
    final harnessKey = GlobalKey<_RetainedTabsHarnessState>();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: _RetainedTabsHarness(
          key: harnessKey,
          first: first,
          second: second,
        ),
      ),
    );
    first.jumpTo(520);
    second.jumpTo(680);
    await tester.pump();
    harnessKey.currentState!.showFirst();
    await tester.pump();

    await tester.tapAt(const Offset(200, 6));
    await tester.pumpAndSettle();

    expect(first.offset, first.position.minScrollExtent);
    expect(second.offset, 680);
  });

  testWidgets('a top tap leaves an offscreen PageView tab untouched', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    final pageController = PageController();
    final visibleController = ScrollController();
    final hiddenController = ScrollController();
    addTearDown(pageController.dispose);
    addTearDown(visibleController.dispose);
    addTearDown(hiddenController.dispose);

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: PageView(
            controller: pageController,
            children: [
              _KeepAliveList(controller: visibleController, label: 'Visible'),
              _KeepAliveList(controller: hiddenController, label: 'Hidden'),
            ],
          ),
        ),
      ),
    );
    visibleController.jumpTo(520);
    pageController.jumpToPage(1);
    await tester.pumpAndSettle();
    hiddenController.jumpTo(680);
    pageController.jumpToPage(0);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 6));
    await tester.pumpAndSettle();

    expect(
      visibleController.offset,
      visibleController.position.minScrollExtent,
    );
    expect(hiddenController.offset, 680);
  });

  testWidgets('clean pushed routes retain the native back-swipe contract', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    late BuildContext homeContext;

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );
    Navigator.of(homeContext).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('Pushed route'))),
      ),
    );
    await tester.pumpAndSettle();

    final route = observer.topRoute! as PageRoute<dynamic>;
    expect(route.popGestureEnabled, isTrue);
    expect(
      AppTheme.dark.pageTransitionsTheme.builders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
  });

  testWidgets('a full edge swipe returns from a clean pushed route', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    late BuildContext homeContext;

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Swipe home'));
          },
        ),
      ),
    );
    Navigator.of(homeContext).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('Swipe detail'))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.flingFrom(const Offset(4, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Swipe detail'), findsNothing);
    expect(find.text('Swipe home'), findsOneWidget);
  });

  testWidgets('a routed header supplies a swipe back action without a stack', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    var backAttempts = 0;

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: WorkloopRouteHeader(
            title: 'Direct route',
            onBack: () => backAttempts++,
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(4, 300), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(backAttempts, 1);
  });

  testWidgets('a cancelled fallback swipe keeps the current screen', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    var showingWorkspace = true;

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: StatefulBuilder(
          builder: (context, setState) => showingWorkspace
              ? WorkloopBackSwipeScope(
                  onBack: () => setState(() => showingWorkspace = false),
                  child: const Scaffold(body: Text('Money workspace')),
                )
              : const Scaffold(body: Text('More workspace')),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(40, 300));
    await gesture.moveBy(const Offset(80, 4));
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(find.text('Money workspace'), findsOneWidget);
    expect(find.text('More workspace'), findsNothing);
  });

  testWidgets('a cancelled routed-header fallback does not navigate', (
    tester,
  ) async {
    final observer = WorkloopNavigationObserver();
    var backAttempts = 0;

    await tester.pumpWidget(
      _navigationHarness(
        observer: observer,
        home: Scaffold(
          body: WorkloopRouteHeader(
            title: 'Interrupted swipe',
            onBack: () => backAttempts++,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(40, 300));
    await gesture.moveBy(const Offset(80, 4));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(backAttempts, 0);
  });

  testWidgets(
    'a retained workspace reveals its predecessor and can cancel smoothly',
    (tester) async {
      var currentIndex = 1;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: WorkloopInteractiveWorkspaceStack(
                index: currentIndex,
                previousIndex: currentIndex == 1 ? 0 : null,
                onBack: () => setState(() => currentIndex = 0),
                children: const [
                  ColoredBox(
                    color: Colors.black,
                    child: Center(child: Text('Previous workspace')),
                  ),
                  ColoredBox(
                    color: Colors.green,
                    child: Center(child: Text('Current workspace')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(12, 300));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();

      expect(find.text('Previous workspace'), findsOneWidget);
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('workloop-workspace-transform-1')),
            )
            .transform
            .getTranslation()
            .x,
        greaterThan(0),
      );

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(find.text('Current workspace'), findsOneWidget);
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('workloop-workspace-transform-1')),
            )
            .transform
            .getTranslation()
            .x,
        0,
      );
    },
  );

  testWidgets(
    'programmatic shell navigation is immediate and retains both destinations',
    (tester) async {
      var currentIndex = 0;
      late void Function(int index) showDestination;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: StatefulBuilder(
            builder: (context, setState) {
              showDestination = (index) => setState(() => currentIndex = index);
              return Scaffold(
                body: WorkloopInteractiveWorkspaceStack(
                  index: currentIndex,
                  previousIndex: null,
                  onBack: () {},
                  children: const [
                    Center(child: Text('First destination')),
                    Center(child: Text('Second destination')),
                  ],
                ),
              );
            },
          ),
        ),
      );

      showDestination(1);
      await tester.pump();

      expect(find.text('First destination'), findsNothing);
      expect(find.text('Second destination').hitTestable(), findsOneWidget);
      expect(
        find.text('First destination', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('workloop-workspace-transform-1')),
            )
            .transform
            .getTranslation()
            .x,
        0,
        reason: 'A tab change must not wait for a forward-entry animation.',
      );
      showDestination(0);
      await tester.pump();
      expect(find.text('First destination').hitTestable(), findsOneWidget);
      expect(find.text('Second destination'), findsNothing);
    },
  );

  testWidgets('shell transitions never replay a retained create request', (
    tester,
  ) async {
    var currentIndex = 0;
    var createOpenings = 0;
    late void Function(int index) showDestination;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) {
            showDestination = (index) => setState(() => currentIndex = index);
            return Scaffold(
              body: WorkloopInteractiveWorkspaceStack(
                index: currentIndex,
                previousIndex: null,
                onBack: () {},
                children: [
                  _CreateReplayProbe(
                    key: const ValueKey('retained-create-probe'),
                    createRequest: 1,
                    onOpened: () => createOpenings++,
                  ),
                  const Center(child: Text('Other destination')),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(createOpenings, 1);

    showDestination(1);
    await tester.pumpAndSettle();
    showDestination(0);
    await tester.pumpAndSettle();
    showDestination(1);
    await tester.pumpAndSettle();

    expect(
      createOpenings,
      1,
      reason: 'Retained Money/Task/Note intents must not replay on navigation',
    );
  });

  testWidgets('reduced motion switches shell destinations immediately', (
    tester,
  ) async {
    var currentIndex = 0;
    late void Function(int index) showDestination;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              showDestination = (index) => setState(() => currentIndex = index);
              return Scaffold(
                body: WorkloopInteractiveWorkspaceStack(
                  index: currentIndex,
                  previousIndex: null,
                  onBack: () {},
                  children: const [
                    Center(child: Text('Reduced first')),
                    Center(child: Text('Reduced second')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    showDestination(1);
    await tester.pump();

    expect(find.text('Reduced first'), findsNothing);
    expect(find.text('Reduced second'), findsOneWidget);
  });

  testWidgets(
    'entering a retained tool is immediate while keeping back history',
    (tester) async {
      var currentIndex = 1;
      int? previousIndex;
      late VoidCallback openTool;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: StatefulBuilder(
            builder: (context, setState) {
              openTool = () => setState(() {
                previousIndex = currentIndex;
                currentIndex = 0;
              });
              return Scaffold(
                body: WorkloopInteractiveWorkspaceStack(
                  index: currentIndex,
                  previousIndex: previousIndex,
                  onBack: () {},
                  children: const [
                    Center(child: Text('Retained tool')),
                    Center(child: Text('Tools launchpad')),
                  ],
                ),
              );
            },
          ),
        ),
      );

      openTool();
      await tester.pump();

      expect(find.text('Retained tool').hitTestable(), findsOneWidget);
      expect(find.text('Tools launchpad').hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('workloop-workspace-back-edge')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('workloop-workspace-transform-0')),
            )
            .transform
            .getTranslation()
            .x,
        0,
      );
    },
  );

  testWidgets('a completed retained-workspace swipe navigates once', (
    tester,
  ) async {
    var currentIndex = 1;
    var backActions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: WorkloopInteractiveWorkspaceStack(
              index: currentIndex,
              previousIndex: currentIndex == 1 ? 0 : null,
              onBack: () {
                backActions++;
                setState(() => currentIndex = 0);
              },
              children: const [
                Center(child: Text('More workspace')),
                Center(child: Text('Money workspace')),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.flingFrom(const Offset(12, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(backActions, 1);
    expect(find.text('More workspace'), findsOneWidget);
    expect(find.text('Money workspace'), findsNothing);
  });

  testWidgets(
    'an edge swipe invokes rather than bypasses a protected draft guard',
    (tester) async {
      final observer = WorkloopNavigationObserver();
      late BuildContext homeContext;
      var blockedAttempts = 0;

      await tester.pumpWidget(
        _navigationHarness(
          observer: observer,
          home: Builder(
            builder: (context) {
              homeContext = context;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      Navigator.of(homeContext).push<void>(
        MaterialPageRoute(
          builder: (_) => PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) blockedAttempts++;
            },
            child: const Scaffold(
              body: Center(
                child: Text('Protected editor', key: ValueKey('protected')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final route = observer.topRoute! as PageRoute<dynamic>;
      expect(route.popGestureEnabled, isFalse);

      await tester.dragFrom(const Offset(4, 300), const Offset(110, 4));
      await tester.pumpAndSettle();

      expect(blockedAttempts, 1);
      expect(find.byKey(const ValueKey('protected')), findsOneWidget);
    },
  );
}

Widget _navigationHarness({
  required WorkloopNavigationObserver observer,
  required Widget home,
}) {
  return MaterialApp(
    theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
    scrollBehavior: const WorkloopScrollBehavior(),
    navigatorObservers: [observer],
    builder: (context, child) => WorkloopNavigationAssistRegion(
      observer: observer,
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );
}

class _CreateReplayProbe extends StatefulWidget {
  final int createRequest;
  final VoidCallback onOpened;

  const _CreateReplayProbe({
    super.key,
    required this.createRequest,
    required this.onOpened,
  });

  @override
  State<_CreateReplayProbe> createState() => _CreateReplayProbeState();
}

class _CreateReplayProbeState extends State<_CreateReplayProbe> {
  @override
  void initState() {
    super.initState();
    if (widget.createRequest != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onOpened();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Create destination'));
  }
}

class _RetainedTabsHarness extends StatefulWidget {
  final ScrollController first;
  final ScrollController second;

  const _RetainedTabsHarness({
    super.key,
    required this.first,
    required this.second,
  });

  @override
  State<_RetainedTabsHarness> createState() => _RetainedTabsHarnessState();
}

class _RetainedTabsHarnessState extends State<_RetainedTabsHarness> {
  var _active = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WorkloopNavigationAssistRegion.activateScope(
      context,
      'tab-$_active',
      controller: _active == 0 ? widget.first : widget.second,
    );
  }

  void showFirst() {
    setState(() => _active = 0);
    WorkloopNavigationAssistRegion.activateScope(
      context,
      'tab-0',
      controller: widget.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _active,
        children: [
          PrimaryScrollController(
            controller: widget.first,
            child: WorkloopNavigationScope(
              id: 'tab-0',
              child: _longList(widget.first, 'First'),
            ),
          ),
          PrimaryScrollController(
            controller: widget.second,
            child: WorkloopNavigationScope(
              id: 'tab-1',
              child: _longList(widget.second, 'Second'),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _longList(ScrollController controller, String label) {
  return ListView.builder(
    controller: controller,
    itemCount: 80,
    itemBuilder: (context, index) =>
        SizedBox(height: 48, child: Text('$label $index')),
  );
}

class _KeepAliveList extends StatefulWidget {
  final ScrollController controller;
  final String label;

  const _KeepAliveList({required this.controller, required this.label});

  @override
  State<_KeepAliveList> createState() => _KeepAliveListState();
}

class _KeepAliveListState extends State<_KeepAliveList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _longList(widget.controller, widget.label);
  }
}
