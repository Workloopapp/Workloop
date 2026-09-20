import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/expense_receipt_section.dart';
import 'package:workloop/features/finance/receipt_capture_service.dart';
import 'package:workloop/features/finance/mileage_screen.dart';
import 'package:workloop/features/finance/tax_estimate.dart';
import 'package:workloop/features/finance/tax_estimate_screen.dart';
import 'package:workloop/features/finance/tax_recorded_figures.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';

late SupabaseClient _stubClient;

class _NoNativeRecovery extends ReceiptCaptureService {
  @override
  Future<bool> discardUnscopedRecovery() async => false;
}

class _Records extends ExpenseRecordsRepository {
  _Records() : super(_stubClient);
  final creations = <String?>[];
  TaxEstimateInput? saved;
  bool failFirstJourney = false;
  @override
  Future<void> saveTaxInput(String workspaceId, TaxEstimateInput input) async {
    saved = input;
  }

  @override
  Future<void> saveJourney({
    required String workspaceId,
    String? id,
    String? creationId,
    required DateTime date,
    required int milesHundredths,
    required String purpose,
    required String vehicle,
    required String vehicleType,
  }) async {
    creations.add(creationId);
    if (failFirstJourney && creations.length == 1) {
      throw StateError('Response lost');
    }
  }
}

final _journey = MileageEntry(
  id: 'journey',
  date: DateTime(2026, 9, 8),
  milesHundredths: 10000,
  purpose: 'Visit client',
  vehicle: 'ab12 cde',
  vehicleType: 'car_van',
);
Finder _field(String label) {
  final keyed = find.byKey(ValueKey('tax-amount-$label'));
  return keyed.evaluate().isNotEmpty
      ? keyed
      : find.widgetWithText(TextField, label);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  Widget screen = const TaxEstimateScreen(),
  String Function()? workspace,
  List<MileageEntry> Function()? entries,
  TaxEstimateInput? saved,
  _Records? repository,
  String? structure,
  List<Payment> payments = const [],
  List<Expense> expenses = const [],
  double scale = 1,
  Future<ReceiptFile?> Function()? picker,
  DateTime? now,
  String timezone = 'Europe/London',
}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      businessNowProvider.overrideWithValue(now ?? DateTime(2026, 9, 8, 12)),
      receiptCaptureServiceProvider.overrideWithValue(_NoNativeRecovery()),
      if (picker != null)
        expenseReceiptPickerProvider.overrideWithValue(picker),
      workspaceIdProvider.overrideWith(
        (ref) async => workspace?.call() ?? 'workspace',
      ),
      workspaceSettingsProvider.overrideWith(
        (ref) async => {'business_structure': structure, 'timezone': timezone},
      ),
      mileageEntriesProvider.overrideWith(
        (ref) async => entries?.call() ?? const [],
      ),
      savedTaxEstimateProvider.overrideWith((ref, id) async => saved),
      invoicesProvider.overrideWith((ref) async => payments),
      expensesProvider.overrideWith((ref) async => expenses),
      if (repository != null)
        expenseRecordsRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() {
    _stubClient = SupabaseClient(
      'https://example.supabase.co',
      'fake',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => _stubClient.dispose());
  testWidgets(
    'annual mileage is saved as a forecast and log changes invalidate its result',
    (tester) async {
      final repo = _Records();
      var rows = [_journey];
      final container = await _mount(
        tester,
        repository: repo,
        entries: () => rows,
        saved: const TaxEstimateInput(
          turnoverMinor: 5000000,
          nonVehicleExpensesMinor: 1000000,
          eligible: false,
          vehicleMethod: VehicleExpenseMethod.mileage,
          annualCarVanMilesHundredths: 1100000,
          annualMotorcycleMilesHundredths: 0,
        ),
      );
      for (final label in [
        'I am a sole trader with no other taxable income',
        'My mileage method and forecast are correct',
        'I reviewed these annual figures',
      ]) {
        await _show(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await _show(tester, find.text('Calculate and save estimate'));
      await tester.tap(find.text('Calculate and save estimate'));
      await tester.pumpAndSettle();
      expect(repo.saved?.annualCarVanMilesHundredths, 1100000);
      await _show(tester, find.text('Your annual estimate'));
      expect(find.text('Your annual estimate'), findsOneWidget);
      rows = [
        ...rows,
        MileageEntry(
          id: 'second',
          date: DateTime(2026, 9, 8),
          milesHundredths: 100,
          purpose: 'Supplies',
          vehicle: 'ab12 cde',
          vehicleType: 'car_van',
        ),
      ];
      container.invalidate(mileageEntriesProvider);
      await tester.pumpAndSettle();
      expect(find.text('Your annual estimate'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recorded income reuse takes UK received timestamps rather than invoice totals',
    (tester) async {
      await _mount(
        tester,
        payments: [
          Payment(
            id: 'payment',
            workspaceId: 'workspace',
            number: 'INV-1',
            status: 'sent',
            issueDate: DateTime(2026, 4, 1),
            total: 1000,
            amountPaid: 125,
            sourceDocumentId: 'document',
            receipts: [
              PaymentReceipt(
                id: 'before',
                amount: 25,
                receivedAt: DateTime.utc(2026, 4, 5, 22, 59),
              ),
              PaymentReceipt(
                id: 'inside',
                amount: 100,
                receivedAt: DateTime.utc(2026, 4, 5, 23, 1),
              ),
            ],
          ),
        ],
      );
      await _show(
        tester,
        find.text('Use collected income as a starting figure'),
      );
      await tester.tap(find.text('Use collected income as a starting figure'));
      await tester.pumpAndSettle();
      await _show(tester, _field('Annual business income'));
      expect(
        tester
            .widget<TextField>(_field('Annual business income'))
            .controller!
            .text,
        '100.00',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tax form remains usable at 320 pixels and doubled text', (
    tester,
  ) async {
    await _mount(
      tester,
      scale: 2,
      saved: const TaxEstimateInput(
        turnoverMinor: 5000000,
        nonVehicleExpensesMinor: 1000000,
        eligible: false,
      ),
    );
    await _show(tester, find.text('Calculate and save estimate'));
    expect(tester.takeException(), isNull);
    await _show(
      tester,
      find.text('Rules checked 8 September 2026. HMRC guidance'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved company setup prevents the sole trader eligibility shortcut',
    (tester) async {
      await _mount(tester, structure: 'limited_company');
      await _show(
        tester,
        find.text('I am a sole trader with no other taxable income'),
      );
      final box = find.ancestor(
        of: find.text('I am a sole trader with no other taxable income'),
        matching: find.byType(CheckboxListTile),
      );
      expect(tester.widget<CheckboxListTile>(box).onChanged, isNull);
    },
  );

  testWidgets(
    'journey reuses vehicle and keeps the same identity after a lost save response',
    (tester) async {
      final repo = _Records()..failFirstJourney = true;
      await _mount(
        tester,
        screen: const MileageScreen(),
        entries: () => [_journey],
        repository: repo,
        scale: 2,
      );
      await _show(tester, find.widgetWithText(FilledButton, 'Log journey'));
      await tester.tap(find.widgetWithText(FilledButton, 'Log journey'));
      await tester.pumpAndSettle();
      await _show(tester, _field('Business miles'));
      await tester.enterText(_field('Business miles'), '12.50');
      await _show(tester, _field('Business purpose and route'));
      await tester.enterText(
        _field('Business purpose and route'),
        'Workshop to client and return',
      );
      await _show(tester, _field('Vehicle'));
      expect(
        tester.widget<TextField>(_field('Vehicle')).controller!.text,
        'ab12 cde',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.creations.length, 2);
      expect(repo.creations.first, isNotNull);
      expect(repo.creations.toSet().length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('journey draft cannot carry across a business switch', (
    tester,
  ) async {
    var workspace = 'first';
    final container = await _mount(
      tester,
      screen: const MileageScreen(),
      workspace: () => workspace,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log journey'));
    await tester.pumpAndSettle();
    await _show(tester, _field('Business miles'));
    await tester.enterText(_field('Business miles'), '20');
    workspace = 'second';
    container.invalidate(workspaceIdProvider);
    await tester.pumpAndSettle();
    expect(
      find.text('Reopen mileage from your current business.'),
      findsOneWidget,
    );
    expect(find.text('Save'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'receipt picker result cannot attach to a different active business',
    (tester) async {
      var workspace = 'first';
      var attachments = 0;
      final picked = Completer<ReceiptFile?>();
      final container = await _mount(
        tester,
        workspace: () => workspace,
        picker: () => picked.future,
        screen: Scaffold(
          body: ExpenseReceiptSection(onChanged: (_) => attachments++),
        ),
      );
      await tester.tap(find.text('Attach receipt photo or PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      workspace = 'second';
      container.invalidate(workspaceIdProvider);
      await tester.pumpAndSettle();
      picked.complete(
        ReceiptFile.checked(
          'receipt.pdf',
          Uint8List.fromList('%PDF-1.4'.codeUnits),
        ),
      );
      await tester.pumpAndSettle();
      expect(attachments, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test('journey repository retries use one upsert identity', () async {
    final rows = <String, Map<String, dynamic>>{};
    var attempts = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'fake',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(
          request.headers['prefer'],
          contains('resolution=merge-duplicates'),
        );
        rows[body['id'] as String] = body;
        if (++attempts == 1) throw http.ClientException('Response lost');
        return http.Response('', 201, request: request);
      }),
    );
    addTearDown(client.dispose);
    final repo = ExpenseRecordsRepository(client);
    Future<void> save() => repo.saveJourney(
      workspaceId: 'workspace',
      creationId: 'stable-id',
      date: DateTime(2026, 4, 6),
      milesHundredths: 1250,
      purpose: 'Client visit',
      vehicle: 'AB12 CDE',
      vehicleType: 'car_van',
    );
    await expectLater(save(), throwsA(isA<http.ClientException>()));
    await save();
    expect(rows.length, 1);
    expect(rows['stable-id']!['vehicle'], 'ab12 cde');
  });

  testWidgets(
    'tax reference excludes future calendar dates and includes today',
    (tester) async {
      var reused = 0;
      await _mount(
        tester,
        screen: Scaffold(
          body: SingleChildScrollView(
            child: TaxRecordedFigures(onUseIncome: (amount) => reused = amount),
          ),
        ),
        expenses: [
          for (final day in [7, 8, 9])
            Expense(
              id: '$day',
              workspaceId: 'workspace',
              amount: 10,
              category: 'Other',
              expenseDate: DateTime(2026, 9, day),
            ),
        ],
        payments: [
          Payment(
            id: 'paid',
            workspaceId: 'workspace',
            number: 'INV-1',
            status: 'sent',
            issueDate: DateTime(2026, 9, 7),
            total: 100,
            sourceDocumentId: 'doc',
            receipts: [
              PaymentReceipt(
                id: 'past',
                amount: 10,
                receivedAt: DateTime(2026, 9, 7, 12),
              ),
              PaymentReceipt(
                id: 'now',
                amount: 20,
                receivedAt: DateTime(2026, 9, 8, 12),
              ),
              PaymentReceipt(
                id: 'future',
                amount: 30,
                receivedAt: DateTime(2026, 9, 9),
              ),
            ],
          ),
        ],
      );
      expect(find.text('Collected payments so far: £30.00'), findsOneWidget);
      expect(find.text('Recorded expenses so far: £20.00'), findsOneWidget);
      expect(
        find.textContaining('Future-dated payments or expenses are excluded.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use collected income as a starting figure'));
      expect(reused, 3000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tax expense reference uses the same workspace day as paid-date entry',
    (tester) async {
      await _mount(
        tester,
        now: DateTime.utc(2026, 9, 8, 12),
        timezone: 'Pacific/Kiritimati',
        screen: const Scaffold(
          body: SingleChildScrollView(child: TaxRecordedFigures()),
        ),
        expenses: [
          Expense(
            id: 'today',
            workspaceId: 'workspace',
            amount: 20,
            category: 'Other',
            expenseDate: DateTime(2026, 9, 9),
          ),
          Expense(
            id: 'tomorrow',
            workspaceId: 'workspace',
            amount: 30,
            category: 'Other',
            expenseDate: DateTime(2026, 9, 10),
          ),
        ],
      );
      expect(find.text('Recorded expenses so far: £20.00'), findsOneWidget);
      expect(
        find.textContaining('Future-dated payments or expenses are excluded.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
