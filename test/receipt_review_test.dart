import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/expense_editor_screen.dart';
import 'package:workloop/features/finance/expense_receipt_section.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/receipt_capture_service.dart';
import 'package:workloop/features/finance/receipt_review_sheet.dart';
import 'package:workloop/features/finance/receipt_text_service.dart';
import 'package:workloop/features/finance/widgets/money_editor_widgets.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/documents/workloop_document_viewer.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';

class _Auth implements AuthRepository {
  String? user = 'first-user';
  @override
  String? get currentUserId => user;
  @override
  Stream<AuthState> get authChanges => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Capture extends ReceiptCaptureService {
  @override
  Future<bool> discardUnscopedRecovery() async => false;
}

class _Reader extends ReceiptTextService {
  final Future<ReceiptRecognizedText> Function() action;
  int calls = 0;
  _Reader(this.action);
  @override
  Future<ReceiptRecognizedText> recognize(ReceiptFile file) {
    calls++;
    return action();
  }
}

final _receipt = ReceiptFile.checked(
  'receipt.jpg',
  Uint8List.fromList([255, 216, 255]),
);
const _recognized = ReceiptRecognizedText(
  text: 'ACME Supplies\nReceipt No: A123\nDate: 2026-09-07\nTOTAL £24.00',
);

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required _Reader reader,
  _Auth? auth,
  String Function()? workspace,
  Expense? expense,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth ?? _Auth()),
      workspaceIdProvider.overrideWith(
        (ref) async => workspace?.call() ?? 'workspace',
      ),
      workspaceSettingsProvider.overrideWith(
        (ref) async => {'timezone': 'Europe/London'},
      ),
      businessNowProvider.overrideWithValue(DateTime.utc(2026, 9, 8, 12)),
      receiptCaptureServiceProvider.overrideWithValue(_Capture()),
      expenseReceiptPickerProvider.overrideWithValue(() async => _receipt),
      receiptTextServiceProvider.overrideWithValue(reader),
      expenseReceiptsProvider.overrideWith((ref, id) async => []),
    ],
  );
  addTearDown(container.dispose);
  await container.read(workspaceIdProvider.future);
  await container.read(workspaceSettingsProvider.future);
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
        home: ExpenseEditorScreen(expense: expense),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _attach(WidgetTester tester) async {
  await _tap(tester, 'Attach receipt photo or PDF');
  await tester.pumpAndSettle();
  await _tap(tester, 'Choose file');
  await tester.pump(const Duration(milliseconds: 400));
}

String _amount(WidgetTester tester) => tester
    .widget<MoneyAmountField>(find.byType(MoneyAmountField))
    .controller
    .text;
String _notes(WidgetTester tester) =>
    tester.widget<MoneyTextField>(find.byType(MoneyTextField)).controller.text;

void main() {
  testWidgets(
    'reading suggests details without changing the expense until review is applied',
    (tester) async {
      final reader = _Reader(() async => _recognized);
      await _mount(tester, reader: reader);
      await _attach(tester);
      await tester.pumpAndSettle();
      expect(find.text('Review receipt details'), findsOneWidget);
      expect(_amount(tester), '');
      expect(_notes(tester), '');
      expect(reader.calls, 1);
      await _tap(tester, 'Use selected details');
      await tester.pumpAndSettle();
      expect(_amount(tester), '24.00');
      expect(
        _notes(tester),
        'Supplier: ACME Supplies\nReceipt reference: A123',
      );
      expect(find.text('7 Sep 2026'), findsOneWidget);
      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'manually entered amount and date remain while reviewed notes append',
    (tester) async {
      await _mount(
        tester,
        reader: _Reader(() async => _recognized),
        expense: Expense(
          id: 'saved',
          workspaceId: 'workspace',
          amount: 45,
          category: 'Materials',
          expenseDate: DateTime(2026, 9, 6),
          notes: 'Paint for client job',
        ),
      );
      await _attach(tester);
      await tester.pumpAndSettle();
      final amountCheck = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Use receipt amount'),
      );
      final dateCheck = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Use receipt date as paid date'),
      );
      expect(amountCheck.value, false);
      expect(dateCheck.value, false);
      await _tap(tester, 'Add supplier and reference to note');
      await _tap(tester, 'Use selected details');
      await tester.pumpAndSettle();
      expect(_amount(tester), '45');
      expect(find.text('6 Sep 2026'), findsOneWidget);
      expect(
        _notes(tester),
        'Paint for client job\nSupplier: ACME Supplies\nReceipt reference: A123',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('an existing amount changes only after explicit selection', (
    tester,
  ) async {
    await _mount(
      tester,
      reader: _Reader(() async => _recognized),
      expense: Expense(
        id: 'saved',
        workspaceId: 'workspace',
        amount: 45,
        category: 'Materials',
        expenseDate: DateTime(2026, 9, 6),
        notes: 'Keep my note',
      ),
    );
    await _attach(tester);
    await tester.pumpAndSettle();
    await _tap(tester, 'Use receipt amount');
    await _tap(tester, 'Use selected details');
    await tester.pumpAndSettle();
    expect(_amount(tester), '24.00');
    expect(_notes(tester), 'Keep my note');
    expect(find.text('6 Sep 2026'), findsOneWidget);
  });
  testWidgets(
    'receipt can be opened fully from review without applying suggestions',
    (tester) async {
      await _mount(tester, reader: _Reader(() async => _recognized));
      await _attach(tester);
      await tester.pumpAndSettle();
      await _tap(tester, 'View full receipt');
      await tester.pumpAndSettle();
      final viewer = tester.widget<WorkloopDocumentViewerScreen>(
        find.byType(WorkloopDocumentViewerScreen),
      );
      expect(viewer.workspaceId, 'workspace');
      expect(viewer.mimeType, 'image/jpeg');
      expect(await viewer.loadBytes(), _receipt.bytes);
      Navigator.of(
        tester.element(find.byType(WorkloopDocumentViewerScreen)),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.text('Review receipt details'), findsOneWidget);
      expect(_amount(tester), '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'character truncation explains incomplete text without a false page count',
    (tester) async {
      await _mount(
        tester,
        reader: _Reader(
          () async => const ReceiptRecognizedText(
            text: 'ACME\nTOTAL £24.00',
            textTruncated: true,
          ),
        ),
      );
      await _attach(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('too long to read in full'), findsOneWidget);
      expect(find.textContaining('Only 1 of 1'), findsNothing);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Use receipt amount'),
            )
            .value,
        false,
      );
    },
  );
  testWidgets('foreign currency cannot become a GBP expense amount', (
    tester,
  ) async {
    await _mount(
      tester,
      reader: _Reader(
        () async => const ReceiptRecognizedText(text: 'ACME\nTOTAL EUR 24.00'),
      ),
    );
    await _attach(tester);
    await tester.pumpAndSettle();
    expect(find.text('Use receipt amount'), findsNothing);
    expect(
      find.textContaining('enter its GBP amount yourself'),
      findsOneWidget,
    );
    await _tap(tester, 'Use selected details');
    await tester.pumpAndSettle();
    expect(_amount(tester), '');
  });
  testWidgets(
    'unknown currency needs an explicit GBP confirmation before amount selection',
    (tester) async {
      await _mount(
        tester,
        reader: _Reader(
          () async => const ReceiptRecognizedText(text: 'ACME\nTOTAL 24.00'),
        ),
      );
      await _attach(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Use receipt amount'),
            )
            .onChanged,
        isNull,
      );
      await _tap(tester, 'This receipt amount is in GBP');
      await _tap(tester, 'Use receipt amount');
      await _tap(tester, 'Use selected details');
      await tester.pumpAndSettle();
      expect(_amount(tester), '24.00');
    },
  );
  testWidgets(
    'partial PDF scans disclose limits and do not preselect an amount',
    (tester) async {
      await _mount(
        tester,
        reader: _Reader(
          () async => const ReceiptRecognizedText(
            text: 'ACME\nTOTAL £24.00',
            pageCount: 9,
            processedPages: 5,
          ),
        ),
        scale: 2,
      );
      await _attach(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Only 5 of 9 pages'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Use receipt amount'),
            )
            .value,
        false,
      );
      await _tap(tester, 'Keep details as they are');
      await tester.pumpAndSettle();
      expect(_amount(tester), '');
      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('future receipt date is not applied by default', (tester) async {
    await _mount(
      tester,
      reader: _Reader(
        () async => const ReceiptRecognizedText(
          text: 'ACME\nDate 2026-09-10\nTOTAL £24.00',
        ),
      ),
    );
    await _attach(tester);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(
              CheckboxListTile,
              'Use receipt date as paid date',
            ),
          )
          .value,
      false,
    );
    await _tap(tester, 'Use selected details');
    await tester.pumpAndSettle();
    expect(find.text('8 Sep 2026'), findsOneWidget);
  });
  testWidgets(
    'manual fallback cancels a pending result and keeps the attachment',
    (tester) async {
      final complete = Completer<ReceiptRecognizedText>();
      await _mount(tester, reader: _Reader(() => complete.future));
      await _attach(tester);
      expect(find.text('Reading receipt on your device…'), findsOneWidget);
      await _tap(tester, 'Enter details manually');
      complete.complete(_recognized);
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptReviewSheet), findsNothing);
      expect(_amount(tester), '');
      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unreadable receipts leave manual entry and the original attachment available',
    (tester) async {
      await _mount(
        tester,
        reader: _Reader(
          () => Future.error(
            const ReceiptRecognitionException('Enter details manually.'),
          ),
        ),
      );
      await _attach(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptReviewSheet), findsNothing);
      expect(find.text('Enter details manually.'), findsOneWidget);
      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(_amount(tester), '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('manual editing during reading is kept when suggestions arrive', (
    tester,
  ) async {
    final complete = Completer<ReceiptRecognizedText>();
    await _mount(tester, reader: _Reader(() => complete.future));
    await _attach(tester);
    final amount = tester
        .widget<MoneyAmountField>(find.byType(MoneyAmountField))
        .controller;
    amount.text = '18.50';
    final notes = tester
        .widget<MoneyTextField>(find.byType(MoneyTextField))
        .controller;
    notes.text = 'My purchase note';
    complete.complete(_recognized);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Use receipt amount'),
          )
          .value,
      false,
    );
    await _tap(tester, 'Use selected details');
    await tester.pumpAndSettle();
    expect(_amount(tester), '18.50');
    expect(_notes(tester), 'My purchase note');
  });
  testWidgets('a retained read callback cannot start under another business', (
    tester,
  ) async {
    var workspace = 'workspace';
    final reader = _Reader(() async => _recognized);
    final container = await _mount(
      tester,
      reader: reader,
      workspace: () => workspace,
    );
    await _attach(tester);
    await tester.pumpAndSettle();
    await _tap(tester, 'Keep details as they are');
    await tester.pumpAndSettle();
    final section = tester.widget<ExpenseReceiptSection>(
      find.byType(ExpenseReceiptSection),
    );
    final read = section.onReadDetails!;
    workspace = 'second';
    container.invalidate(workspaceIdProvider);
    await tester.pumpAndSettle();
    read();
    await tester.pumpAndSettle();
    expect(reader.calls, 1);
    expect(find.byType(ReceiptReviewSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('switching away and back cannot revive an earlier OCR request', (
    tester,
  ) async {
    var workspace = 'workspace';
    final complete = Completer<ReceiptRecognizedText>();
    final container = await _mount(
      tester,
      reader: _Reader(() => complete.future),
      workspace: () => workspace,
    );
    await _attach(tester);
    workspace = 'second';
    container.invalidate(workspaceIdProvider);
    await tester.pump();
    await container.read(workspaceIdProvider.future);
    workspace = 'workspace';
    container.invalidate(workspaceIdProvider);
    await tester.pump();
    await container.read(workspaceIdProvider.future);
    complete.complete(_recognized);
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptReviewSheet), findsNothing);
    expect(_amount(tester), '');
    expect(find.text('receipt.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final change in ['business', 'user']) {
    testWidgets(
      'late OCR result cannot open a review after the $change changes',
      (tester) async {
        var workspace = 'workspace';
        final auth = _Auth();
        final complete = Completer<ReceiptRecognizedText>();
        final container = await _mount(
          tester,
          reader: _Reader(() => complete.future),
          auth: auth,
          workspace: () => workspace,
        );
        await _attach(tester);
        if (change == 'business') {
          workspace = 'second';
          container.invalidate(workspaceIdProvider);
        } else {
          auth.user = 'second-user';
        }
        complete.complete(_recognized);
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptReviewSheet), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'an open OCR review hides receipt text when the account changes',
    (tester) async {
      final auth = _Auth();
      final container = await _mount(
        tester,
        reader: _Reader(() async => _recognized),
        auth: auth,
      );
      await _attach(tester);
      await tester.pumpAndSettle();
      auth.user = 'second-user';
      container.invalidate(receiptAuthIdentityProvider);
      await tester.pumpAndSettle();
      expect(find.text('Account changed'), findsOneWidget);
      expect(find.text('Use selected details'), findsNothing);
      expect(find.text('ACME Supplies'), findsNothing);
      auth.user = 'first-user';
      container.invalidate(receiptAuthIdentityProvider);
      await tester.pumpAndSettle();
      expect(find.text('Account changed'), findsOneWidget);
      expect(find.text('Use selected details'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
