import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/reports/report_models.dart';
import 'package:workloop/features/reports/cashflow_widgets.dart';
import 'package:workloop/features/reports/reports_provider.dart';
import 'package:workloop/features/reports/reports_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/booking_requests_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Auth extends Fake implements AuthRepository {
  String? userId = 'owner';
  final events = StreamController<AuthState>.broadcast(sync: true);
  @override
  String? get currentUserId => userId;
  @override
  Stream<AuthState> get authChanges => events.stream;
}

final _now = DateTime.utc(2026, 9, 12, 12);
final _source = ReportSource(
  workspaceId: 'business',
  businessName: 'Example business',
  payments: [
    Payment(
      id: 'p',
      workspaceId: 'business',
      number: 'INV-001',
      status: 'paid',
      issueDate: DateTime(2026, 9, 3),
      total: 1250,
    ),
  ],
  expenses: [
    Expense(
      id: 'e',
      workspaceId: 'business',
      amount: 120,
      category: 'Materials',
      expenseDate: DateTime(2026, 9, 4),
    ),
  ],
  bookings: [
    Appointment(
      id: 'b',
      workspaceId: 'business',
      startTime: DateTime.utc(2026, 9, 3),
      status: 'completed',
      price: 1250,
    ),
  ],
);

Future<({ProviderContainer container, _Auth auth})> _mount(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
  double width = 390,
  Future<ReportSource> Function()? load,
  String Function()? workspace,
  Widget? home,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = _Auth();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      workspaceIdProvider.overrideWith(
        (ref) async => workspace?.call() ?? 'business',
      ),
      reportsSourceProvider.overrideWith(
        (ref) async => load == null ? _source : await load(),
      ),
      businessNowProvider.overrideWithValue(_now),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  addTearDown(auth.events.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture-reports'),
          child: home ?? const ReportsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, auth: auth);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      ('Manrope', 'assets/fonts/Manrope-Variable.ttf'),
      ('WorkloopMono', 'assets/fonts/WorkloopMono-Regular.ttf'),
      ('Ahem', 'assets/fonts/Manrope-Variable.ttf'),
      (
        'packages/lucide_flutter/LucideIcons',
        'packages/lucide_flutter/assets/lucide.ttf',
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  testWidgets('Business opens Reports and back returns to Business', (
    tester,
  ) async {
    await _mount(
      tester,
      home: const BusinessScreen(),
      overrides: [
        workspaceProvider.overrideWith(
          (ref) async => {'id': 'business', 'name': 'Example business'},
        ),
        settingsBusinessProfileProvider.overrideWith((ref) async => null),
        settingsWorkspaceSettingsProvider.overrideWith((ref) async => {}),
        settingsServicesProvider.overrideWith((ref) async => []),
        bookingRequestsProvider.overrideWith((ref) async => []),
      ],
    );
    await tester.ensureVisible(find.byKey(const ValueKey('business-reports')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('business-reports')));
    await tester.pumpAndSettle();
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(find.text('Export spreadsheet'), findsOneWidget);
    Navigator.of(tester.element(find.byType(ReportsScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReportsScreen), findsNothing);
    expect(find.byType(BusinessScreen), findsOneWidget);
  });
  testWidgets(
    'all nine report choices render with export actions and current-balance date state',
    (tester) async {
      await _mount(tester);
      expect(find.text('£1,250.00'), findsOneWidget);
      expect(find.text('PDF summary'), findsOneWidget);
      expect(find.text('Export spreadsheet'), findsOneWidget);
      for (final kind in ReportKind.values.skip(1)) {
        await tester.tap(find.byKey(const ValueKey('report-kind')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(WorkloopSearchField),
            matching: find.byType(TextField),
          ),
          kind.label,
        );
        await tester.pumpAndSettle();
        final option = find.text(kind.label).last;
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<WorkloopPickerField<ReportKind>>(
                find.byKey(const ValueKey('report-kind')),
              )
              .value,
          kind,
        );
        expect(tester.takeException(), isNull);
        if (kind == ReportKind.outstanding) {
          expect(find.byKey(const ValueKey('report-period')), findsNothing);
          expect(
            find.text('What you’re owed today · 12 Sep 2026'),
            findsOneWidget,
          );
        }
      }
    },
  );

  testWidgets(
    'period picker and custom date cancellation preserve current report',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.byKey(const ValueKey('report-period')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last month').last);
      await tester.pumpAndSettle();
      expect(find.text('1 Aug 2026 – 31 Aug 2026'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report-period')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose dates').last);
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('1 Aug 2026 – 31 Aug 2026'), findsOneWidget);
    },
  );

  testWidgets(
    'loading and error do not show plausible zeros or exports; retry recovers',
    (tester) async {
      var fail = true;
      final state = await _mount(
        tester,
        load: () async {
          if (fail) throw StateError('Records unavailable');
          return _source;
        },
      );
      expect(find.text('Export spreadsheet'), findsNothing);
      expect(find.textContaining('couldn’t load all'), findsOneWidget);
      fail = false;
      state.container.invalidate(reportsSourceProvider);
      await tester.pumpAndSettle();
      expect(find.text('Export spreadsheet'), findsOneWidget);
    },
  );

  testWidgets(
    'sign-out clears retained report and disables a captured export callback',
    (tester) async {
      final state = await _mount(tester);
      final export = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Export spreadsheet'),
          )
          .onPressed!;
      state.auth.userId = null;
      state.auth.events.add(AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();
      expect(find.text('£1,250.00'), findsNothing);
      expect(find.text('Export spreadsheet'), findsNothing);
      export();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forecast applies reviewed inputs, rejects bad costs and changes horizon',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.byKey(const ValueKey('report-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cashflow forecast').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('report-period')), findsNothing);
      await tester.ensureVisible(find.text('Adjust your forecast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adjust your forecast'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('forecast-starting-cash')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forecast-starting-cash')),
        '100',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('forecast-weekly-costs')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forecast-weekly-costs')),
        '-70',
      );
      await tester.ensureVisible(find.text('Update forecast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update forecast'));
      await tester.pumpAndSettle();
      expect(find.text('Weekly costs must be £0 or more.'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('forecast-weekly-costs')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forecast-weekly-costs')),
        '70',
      );
      await tester.ensureVisible(find.text('Update forecast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update forecast'));
      await tester.pumpAndSettle();
      final chart = tester.widget<CashflowChart>(find.byType(CashflowChart));
      expect(chart.assumptions.startingCashPence, 10000);
      expect(chart.forecast.days.last.closingCashPence, -20000);
      if (const bool.fromEnvironment('WRITE_REPORT_SCREENSHOTS')) {
        await tester.ensureVisible(find.byType(CashflowChart));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture-reports')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/workloop-forecast-reviewed.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('forecast-horizon')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('forecast-horizon')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next 60 days').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CashflowControls>(find.byType(CashflowControls))
            .assumptions
            .days,
        60,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace change revokes a retained report', (tester) async {
    var workspace = 'business';
    final state = await _mount(tester, workspace: () => workspace);
    workspace = 'other-business';
    state.container.invalidate(workspaceIdProvider);
    await tester.pumpAndSettle();
    expect(find.text('Export spreadsheet'), findsNothing);
    expect(find.textContaining('business has changed'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'reports render ${dark ? 'dark' : 'light'} at text scale $scale on narrow phones',
        (tester) async {
          await _mount(
            tester,
            dark: dark,
            scale: scale,
            width: scale == 1 ? 390 : 320,
          );
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('WRITE_REPORT_SCREENSHOTS')) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture-reports')),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '/tmp/workloop-reports-${dark ? 'dark' : 'light'}-$scale.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.ensureVisible(find.byKey(const ValueKey('report-kind')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('report-kind')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.descendant(
              of: find.byType(WorkloopSearchField),
              matching: find.byType(TextField),
            ),
            'Cashflow forecast',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cashflow forecast').last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('WRITE_REPORT_SCREENSHOTS')) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture-reports')),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '/tmp/workloop-forecast-${dark ? 'dark' : 'light'}-$scale.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.drag(
            find.byType(ListView).first,
            const Offset(0, -1400),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test(
    'report source excludes foreign workspace rows across every input',
    () async {
      final container = ProviderContainer(
        overrides: [
          workspaceProvider.overrideWith(
            (ref) async => {'id': 'business', 'name': 'Example'},
          ),
          workspaceSettingsProvider.overrideWith(
            (ref) async => {'timezone': 'Europe/London'},
          ),
          invoicesProvider.overrideWith(
            (ref) async => [
              ..._source.payments,
              Payment(
                id: 'foreign',
                workspaceId: 'other',
                number: 'PRIVATE',
                status: 'paid',
                issueDate: _now,
                total: 999,
              ),
            ],
          ),
          expensesProvider.overrideWith((ref) async => _source.expenses),
          appointmentsProvider.overrideWith(
            (ref) async => [for (final b in _source.bookings) b.toMap()],
          ),
          clientsProvider.overrideWith((ref) async => []),
          allTasksProvider.overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      final result = await container.read(reportsSourceProvider.future);
      expect(result.payments.length, 1);
      expect(result.payments.single.number, 'INV-001');
    },
  );

  test('failure of one input prevents building a partial report', () async {
    final container = ProviderContainer(
      overrides: [
        workspaceProvider.overrideWith((ref) async => {'id': 'business'}),
        workspaceSettingsProvider.overrideWith((ref) async => {}),
        invoicesProvider.overrideWith((ref) async => []),
        expensesProvider.overrideWith(
          (ref) async => throw StateError('Expense load failed'),
        ),
        appointmentsProvider.overrideWith((ref) async => []),
        clientsProvider.overrideWith((ref) async => []),
        allTasksProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(reportsSourceProvider.future),
      throwsA(anything),
    );
  });
}
