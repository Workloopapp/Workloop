import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/features/finance/documents/business_document_detail_screen.dart';
import 'package:workloop/features/finance/documents/business_document_editor_screen.dart';
import 'package:workloop/features/finance/documents/business_documents_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/business_documents_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

const _workspace = 'workspace-a';
BusinessDocument _document({
  String id = 'document-1',
  String status = 'draft',
  int revision = 1,
  List<BusinessDocumentItem>? items,
  Map<String, dynamic>? values,
}) {
  final lines =
      items ??
      const [
        BusinessDocumentItem(
          description: 'Deep clean and supplies',
          quantityHundredths: 150,
          unitPricePence: 3125,
        ),
      ];
  final subtotal = lines.fold<int>(0, (sum, line) => sum + line.totalPence);
  return BusinessDocument.fromMap({
    'id': id,
    'workspace_id': _workspace,
    'type': 'invoice',
    'status': status,
    'revision': revision,
    'issue_date': '2026-09-08',
    'due_date': '2026-09-15',
    'service_date': '2026-09-08',
    'issued_at': status == 'draft' ? null : '2026-09-08T12:00:00Z',
    'invoice_number': status == 'draft' ? null : 'INV-00001',
    'invoice_id': status == 'draft' ? null : 'payment-1',
    'tax_rate': 0,
    'subtotal': documentMoneyInput(subtotal),
    'tax_amount': 0,
    'total': documentMoneyInput(subtotal),
    'business_snapshot': {
      'name': 'Calm Cleaning',
      'legal_name': 'Alex Smith',
      'address': '10 High Street, Bristol',
      'email': 'hello@example.test',
      'vat_number': 'GB123456789',
    },
    'client_snapshot': {
      'name': 'Sam Morgan',
      'address': '2 Meadow Road, Bristol',
      'email': 'sam@example.test',
    },
    'items': lines.map((line) => line.toMap()).toList(),
    ...?(values),
  });
}

class _UnusedClient extends Fake implements SupabaseClient {}

class _Documents extends BusinessDocumentsRepository {
  _Documents() : super(_UnusedClient());
  final savedIds = <String>[];
  final savedPayloads = <Map<String, dynamic>>[];
  final issuedIds = <String>[];
  BusinessDocument? stored;
  bool loseSaveResponse = false;
  bool loseIssueResponse = false;
  bool loseReceiptResponse = false;
  final receiptCalls =
      <({int amount, DateTime date, String key, bool refund})>[];
  Completer<void>? saveWait;
  @override
  Future<List<BusinessDocument>> list(String workspaceId) async =>
      stored == null ? [] : [stored!];
  @override
  Future<BusinessDocument> get(String workspaceId, String id) async {
    if (workspaceId != _workspace) throw StateError('Wrong account');
    return stored ?? _document(id: id);
  }

  @override
  Future<BusinessDocument> save({
    required String workspaceId,
    required String id,
    required Map<String, dynamic> document,
    required List<BusinessDocumentItem> items,
    int? revision,
  }) async {
    savedIds.add(id);
    savedPayloads.add(document);
    stored = _document(
      id: id,
      revision: (revision ?? 0) + 1,
      items: items,
      values: document,
    );
    if (saveWait != null) await saveWait!.future;
    if (loseSaveResponse) {
      loseSaveResponse = false;
      throw const SocketException('Response lost');
    }
    return stored!;
  }

  @override
  Future<BusinessDocument> issue(BusinessDocument document) async {
    issuedIds.add(document.id);
    stored = _document(
      id: document.id,
      status: 'sent',
      revision: document.revision + 1,
      items: document.items,
    );
    if (loseIssueResponse) {
      loseIssueResponse = false;
      throw const SocketException('Response lost');
    }
    return stored!;
  }

  @override
  Future<BusinessDocument> recordReceived(
    BusinessDocument document,
    int amountPence,
    DateTime receivedDate,
    String key, {
    bool refund = false,
  }) async {
    receiptCalls.add((
      amount: amountPence,
      date: receivedDate,
      key: key,
      refund: refund,
    ));
    if (loseReceiptResponse) {
      loseReceiptResponse = false;
      throw const SocketException('Response lost');
    }
    return stored!;
  }
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is WorkloopFormField && widget.label == label,
  ),
  matching: find.byType(TextFormField),
);

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Documents repository,
  Widget screen, {
  double scale = 1,
  String Function()? currentWorkspace,
  List<Payment> payments = const [],
  String timezone = 'Europe/London',
  DateTime? now,
}) async {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      businessDocumentsRepositoryProvider.overrideWithValue(repository),
      if (now != null) businessNowProvider.overrideWithValue(now),
      workspaceIdProvider.overrideWith(
        (ref) async => currentWorkspace?.call() ?? _workspace,
      ),
      workspaceProvider.overrideWith(
        (ref) async => {'id': _workspace, 'name': 'Calm Cleaning'},
      ),
      workspaceSettingsProvider.overrideWith(
        (ref) async => {
          'timezone': timezone,
          'business_address': '10 High Street, Bristol',
        },
      ),
      clientsProvider.overrideWith((ref) async => const <Client>[]),
      servicesProvider.overrideWith((ref) async => []),
      invoicesProvider.overrideWith((ref) async => payments),
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
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: WorkloopAppCanvas(child: child!),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => screen),
              ),
              child: const Text('Open test screen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  await tester.tap(find.text('Open test screen'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

Future<void> _top(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (const bool.fromEnvironment('CAPTURE_DOCUMENT_QA')) {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/workloop-$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }
}

void main() {
  testWidgets('Money header creates the selected invoice or quote', (
    tester,
  ) async {
    await _mount(tester, _Documents(), const FinanceScreen());
    await tester.tap(find.text('Invoices').first);
    await tester.pumpAndSettle();
    final create = find.byWidgetPredicate(
      (widget) =>
          widget is WorkloopTopAction &&
          widget.semanticLabel == 'Create invoice or quote',
    );
    expect(create, findsOneWidget);
    expect(find.byType(WorkloopTopAction), findsOneWidget);
    expect(tester.getRect(create).right, greaterThan(260));
    expect(tester.getRect(create).top, lessThan(100));
    await tester.tap(find.text('Quotes'));
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BusinessDocumentEditorScreen>(
            find.byType(BusinessDocumentEditorScreen),
          )
          .type,
      'quote',
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'invoice due status follows business civil date across the date line',
    () async {
      var zone = 'Pacific/Kiritimati';
      final container = ProviderContainer(
        overrides: [
          businessNowProvider.overrideWithValue(
            DateTime.utc(2026, 9, 8, 11, 30),
          ),
          workspaceSettingsProvider.overrideWith(
            (ref) async => {'timezone': zone},
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(workspaceSettingsProvider.future);
      final invoice = _document(
        status: 'sent',
        values: {'due_date': '2026-09-08', 'amount_paid': 0},
      );
      expect(container.read(workspaceTodayProvider), DateTime(2026, 9, 9));
      expect(
        invoice.statusLabel(now: container.read(workspaceTodayProvider)),
        'Overdue',
      );
      zone = 'America/Los_Angeles';
      container.invalidate(workspaceSettingsProvider);
      await container.read(workspaceSettingsProvider.future);
      expect(container.read(workspaceTodayProvider), DateTime(2026, 9, 8));
      expect(
        invoice.statusLabel(now: container.read(workspaceTodayProvider)),
        'Awaiting payment',
      );
    },
  );
  setUpAll(() async {
    for (final item in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/lucide_flutter/LucideIcons':
          'packages/lucide_flutter/assets/lucide.ttf',
    }.entries) {
      final loader = FontLoader(item.key)..addFont(rootBundle.load(item.value));
      await loader.load();
    }
  });
  testWidgets('320px draft form keeps totals accurate and saves all fields', (
    tester,
  ) async {
    final repo = _Documents();
    await _mount(
      tester,
      repo,
      BusinessDocumentEditorScreen(document: _document()),
    );
    await _show(tester, find.textContaining('Subtotal £46.88'));
    expect(find.textContaining('Total £46.88'), findsOneWidget);
    await _capture(tester, 'invoice-editor-320');
    await _show(tester, _field('Notes and terms'));
    await tester.enterText(
      _field('Notes and terms'),
      'Please pay within seven days.',
    );
    await _show(tester, find.widgetWithText(SlateButton, 'Save draft'));
    await tester.tap(find.widgetWithText(SlateButton, 'Save draft'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(repo.savedIds, ['document-1']);
    expect(repo.savedPayloads.single['notes'], 'Please pay within seven days.');
    expect(repo.stored!.totalPence, 4688);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a copied invoice uses the new business date without rewriting the original',
    (tester) async {
      final repo = _Documents();
      final original = _document(status: 'sent');
      await _mount(
        tester,
        repo,
        BusinessDocumentEditorScreen(copyFrom: original),
        timezone: 'Pacific/Kiritimati',
        now: DateTime.utc(2026, 9, 8, 11, 30),
      );
      await _show(tester, find.widgetWithText(SlateButton, 'Save draft'));
      await tester.tap(find.widgetWithText(SlateButton, 'Save draft'));
      await tester.pumpAndSettle();
      expect(repo.savedPayloads.single['issue_date'], '2026-09-09');
      expect(repo.savedPayloads.single['due_date'], '2026-09-16');
      expect(original.issueDate, DateTime(2026, 9, 8));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large-text forms retain labels, dates and a reachable save action',
    (tester) async {
      final repo = _Documents();
      await _mount(
        tester,
        repo,
        BusinessDocumentEditorScreen(document: _document()),
        scale: 1.8,
      );
      await _show(tester, find.text('Dates'));
      await _capture(tester, 'invoice-editor-large-text');
      await _show(tester, find.widgetWithText(SlateButton, 'Save draft'));
      expect(find.widgetWithText(SlateButton, 'Save draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'gross VAT deposit stays sixty pounds and fits 320px at double text',
    (tester) async {
      final repo = _Documents();
      await _mount(
        tester,
        repo,
        BusinessDocumentEditorScreen(
          document: _document(
            items: const [
              BusinessDocumentItem(
                description: 'Agreed visit',
                quantityHundredths: 100,
                unitPricePence: 6000,
              ),
            ],
            values: {
              'prices_include_vat': true,
              'tax_rate': 20,
              'deposit_type': 'percentage',
              'deposit_value': 50,
              'deposit_amount': 30,
              'deposit_due_date': '2026-09-08',
            },
          ),
        ),
        scale: 2,
      );
      await _show(tester, find.textContaining('Total £60.00'));
      expect(find.textContaining('VAT £10.00'), findsOneWidget);
      await _show(tester, find.textContaining('Only record a payment'));
      expect(find.textContaining('£30.00 requested upfront'), findsOneWidget);
      await _capture(tester, 'invoice-deposit-large-text');
      await _show(tester, find.widgetWithText(SlateButton, 'Save draft'));
      await tester.tap(find.widgetWithText(SlateButton, 'Save draft'));
      await tester.pumpAndSettle();
      expect(repo.savedPayloads.single['prices_include_vat'], true);
      expect(repo.savedPayloads.single['deposit_value'], '50.00');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'lost deposit response freezes amount and date for the same-key retry',
    (tester) async {
      final repo = _Documents()
        ..stored = _document(
          status: 'sent',
          values: {
            'total': 100,
            'deposit_type': 'fixed',
            'deposit_value': 30,
            'deposit_amount': 30,
            'deposit_due_date': '2026-09-08',
            'amount_paid': 0,
          },
        )
        ..loseReceiptResponse = true;
      await _mount(
        tester,
        repo,
        const BusinessDocumentDetailScreen(documentId: 'document-1'),
        scale: 2,
        payments: [
          Payment(
            id: 'payment-1',
            workspaceId: _workspace,
            number: 'INV-1',
            status: 'sent',
            issueDate: DateTime(2026, 9, 8),
            total: 100,
            amountPaid: 0,
            sourceDocumentId: 'document-1',
            depositAmount: 30,
          ),
        ],
      );
      await _show(
        tester,
        find.widgetWithText(SlateButton, 'Record deposit received'),
      );
      await tester.tap(
        find.widgetWithText(SlateButton, 'Record deposit received'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final amount = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is WorkloopFormField && w.label == 'Amount received',
        ),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(amount).controller!.text, '30.00');
      await tester.tap(find.text('Record received'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amount).enabled, false);
      expect(find.text('Retry same entry'), findsOneWidget);
      await tester.tap(find.text('Retry same entry'));
      await tester.pumpAndSettle();
      expect(repo.receiptCalls.length, 2);
      expect(repo.receiptCalls.first, repo.receiptCalls.last);
      expect(repo.receiptCalls.first.amount, 3000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('offscreen invalid line is rejected before repository save', (
    tester,
  ) async {
    final repo = _Documents();
    await _mount(
      tester,
      repo,
      BusinessDocumentEditorScreen(document: _document()),
    );
    await _show(tester, _field('Quantity'));
    await tester.enterText(_field('Quantity'), '');
    await _show(tester, find.widgetWithText(SlateButton, 'Save draft'));
    await tester.tap(find.widgetWithText(SlateButton, 'Save draft'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(repo.savedIds, isEmpty);
    await _top(tester);
    expect(
      find.textContaining('valid quantity and price for every item'),
      findsOneWidget,
    );
  });
  testWidgets(
    'lost save response preserves edits and recovery needs an explicit choice',
    (tester) async {
      final repo = _Documents()..loseSaveResponse = true;
      await _mount(
        tester,
        repo,
        BusinessDocumentEditorScreen(document: _document()),
      );
      await _show(tester, find.widgetWithText(SlateButton, 'Save draft'));
      await tester.tap(find.widgetWithText(SlateButton, 'Save draft'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await _top(tester);
      expect(find.text('Review saved draft'), findsOneWidget);
      await tester.enterText(_field('Customer name'), 'Unsaved local name');
      await tester.tap(find.text('Review saved draft'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(
        find.textContaining('unsaved changes on this screen will be discarded'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(
        tester.widget<TextFormField>(_field('Customer name')).controller!.text,
        'Unsaved local name',
      );
      await tester.tap(find.text('Review saved draft'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.text('Open saved version'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(
        tester.widget<TextFormField>(_field('Customer name')).controller!.text,
        'Sam Morgan',
      );
      expect(repo.savedIds, ['document-1']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('account changes hide old draft fields and block save', (
    tester,
  ) async {
    final repo = _Documents();
    var workspace = _workspace;
    final container = await _mount(
      tester,
      repo,
      BusinessDocumentEditorScreen(document: _document()),
      currentWorkspace: () => workspace,
    );
    workspace = 'workspace-b';
    container.invalidate(workspaceIdProvider);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(_field('Customer name'), findsNothing);
    await tester.tap(find.text('Save draft').first, warnIfMissed: false);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(repo.savedIds, isEmpty);
  });
  testWidgets(
    'detail issue is confirmed and a lost-response retry keeps the same document',
    (tester) async {
      final repo = _Documents()
        ..stored = _document()
        ..loseIssueResponse = true;
      await _mount(
        tester,
        repo,
        const BusinessDocumentDetailScreen(documentId: 'document-1'),
      );
      await _show(tester, find.text('Issue invoice'));
      await tester.tap(find.text('Issue invoice'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(repo.issuedIds, isEmpty);
      await tester.tap(find.text('Issue').last);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(repo.issuedIds, ['document-1']);
      await _show(tester, find.text('Issue invoice'));
      await tester.tap(find.text('Issue invoice'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      await tester.tap(find.text('Issue').last);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(repo.issuedIds, ['document-1', 'document-1']);
      expect(find.text('INV-00001'), findsOneWidget);
      expect(find.text('Issue invoice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large-text document detail and listing keep actions accessible',
    (tester) async {
      final repo = _Documents()..stored = _document();
      await _mount(
        tester,
        repo,
        const BusinessDocumentDetailScreen(documentId: 'document-1'),
        scale: 1.8,
      );
      await _capture(tester, 'invoice-detail-large-text');
      await _show(tester, find.text('View draft PDF'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      final listRepo = _Documents()..stored = _document();
      await _mount(
        tester,
        listRepo,
        const BusinessDocumentsScreen(),
        scale: 1.8,
      );
      await _capture(tester, 'invoice-list-large-text');
      expect(find.text('Invoices & quotes'), findsOneWidget);
      await _show(tester, find.text('Sam Morgan'));
      expect(find.text('Sam Morgan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
