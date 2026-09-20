import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

Payment _income(
  String id,
  String client,
  double amount,
  String notes,
  DateTime date, {
  double? total,
}) => Payment(
  id: id,
  workspaceId: 'fictional-workspace',
  number: 'PAY-$id',
  status: total == null ? 'paid' : 'pending',
  total: total ?? amount,
  amountPaid: amount,
  issueDate: DateTime(2026, 9, 1),
  incomeRecordedAt: date,
  dueDate: DateTime(2026, 9, 30),
  clientName: client,
  notes: notes,
);

final _payments = [
  _income(
    '01',
    'Maya Patel',
    85,
    'Exterior window clean',
    DateTime(2026, 9, 16, 14),
  ),
  _income(
    '02',
    'Sam Reed',
    45,
    'Deposit for deep clean',
    DateTime(2026, 9, 15, 16),
    total: 120,
  ),
  _income(
    '03',
    'Jordan Ellis',
    -15,
    'Agreed service refund',
    DateTime(2026, 9, 15, 10),
  ),
  _income(
    '04',
    'Alex Morgan',
    65,
    'Regular window clean',
    DateTime(2026, 9, 14, 15),
  ),
];

final _expenses = [
  Expense(
    id: '01',
    workspaceId: 'fictional-workspace',
    amount: 24.50,
    category: 'Materials',
    notes: 'Window-cleaning supplies',
    expenseDate: DateTime(2026, 9, 16, 10),
  ),
  Expense(
    id: '02',
    workspaceId: 'fictional-workspace',
    amount: 32.80,
    category: 'Travel',
    notes: 'Fuel for this week’s visits',
    expenseDate: DateTime(2026, 9, 15, 9),
  ),
  Expense(
    id: '03',
    workspaceId: 'fictional-workspace',
    amount: 8.50,
    category: 'Equipment',
    notes: 'Replacement cleaning cloths',
    expenseDate: DateTime(2026, 9, 14, 10),
  ),
];

void main() {
  setUpAll(_loadFonts);
  for (final scenario in [
    (name: 'light', dark: false, search: false),
    (name: 'dark', dark: true, search: false),
    (name: 'search-light', dark: false, search: true),
  ]) {
    testWidgets('Payments timeline ${scenario.name}', (tester) async {
      final theme = scenario.dark ? AppTheme.dark : AppTheme.light;
      final colors = scenario.dark ? AppColors.dark : AppColors.light;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceIdProvider.overrideWith(
              (ref) async => 'fictional-workspace',
            ),
            invoicesProvider.overrideWith((ref) async => _payments),
            expensesProvider.overrideWith((ref) async => _expenses),
            clientsProvider.overrideWith((ref) async => const []),
            paymentCollectionEnabledProvider.overrideWithValue(false),
            workspaceSettingsProvider.overrideWith(
              (ref) async => const {
                'workspace_id': 'fictional-workspace',
                'revenue_target': 1000,
              },
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                devicePixelRatio: 1,
                padding: EdgeInsets.only(top: 47, bottom: 34),
                viewPadding: EdgeInsets.only(top: 47, bottom: 34),
                disableAnimations: true,
              ),
              child: RepaintBoundary(
                key: const ValueKey('money-timeline-golden'),
                child: WorkloopAppCanvas(
                  child: Scaffold(
                    body: FinanceScreen(
                      referenceDate: DateTime(2026, 9, 16, 17),
                    ),
                    bottomNavigationBar: WorkloopBottomNav(
                      currentIndex: 3,
                      items: [
                        WorkloopNavItem(
                          label: 'Today',
                          icon: LucideIcons.home,
                          color: colors.accentPrimary,
                        ),
                        WorkloopNavItem(
                          label: 'Clients',
                          icon: LucideIcons.users,
                          color: colors.accentPrimary,
                        ),
                        WorkloopNavItem(
                          label: 'Work',
                          icon: LucideIcons.briefcase,
                          color: colors.accentPrimary,
                        ),
                        WorkloopNavItem(
                          label: 'Money',
                          icon: LucideIcons.circlePoundSterling,
                          color: colors.accentPrimary,
                        ),
                        WorkloopNavItem(
                          label: 'Business',
                          icon: LucideIcons.store,
                          color: colors.accentPrimary,
                        ),
                      ],
                      onTap: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heading = find.text('Payments');
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      await tester.tap(heading);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(heading), alignment: 0);
      await tester.pumpAndSettle();
      if (scenario.search) {
        final search = find.descendant(
          of: find.byKey(const ValueKey('payments-search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, 'clean');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(heading), alignment: 0);
        await tester.pumpAndSettle();
        expect(find.text('5 results · This week'), findsOneWidget);
      }
      expect(
        find.text('Income and expenses · This week · Newest first'),
        findsOneWidget,
      );
      expect(find.text('Maya Patel'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final boundary = find.byKey(const ValueKey('money-timeline-golden'));
      final filename = 'money-timeline-${scenario.name}.png';
      if (const bool.fromEnvironment('WORKLOOP_MONEY_GOLDEN_REVIEW')) {
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(boundary)
              .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('/tmp/workloop-money-timeline-review');
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

Future<void> _loadFonts() async {
  final manrope = FontLoader('Manrope')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  final mono = FontLoader('WorkloopMono')
    ..addFont(rootBundle.load('assets/fonts/WorkloopMono-Regular.ttf'));
  final fallback = FontLoader('Ahem')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  final lucide = FontLoader('packages/lucide_flutter/LucideIcons')
    ..addFont(rootBundle.load('packages/lucide_flutter/assets/lucide.ttf'));
  final material = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([
    manrope.load(),
    mono.load(),
    fallback.load(),
    lucide.load(),
    material.load(),
  ]);
}
