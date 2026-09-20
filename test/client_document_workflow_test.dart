import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/clients/widgets/client_payments_tab.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/features/finance/documents/business_document_detail_screen.dart';
import 'package:workloop/features/finance/documents/business_document_editor_screen.dart';
import 'package:workloop/features/finance/documents/business_documents_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/settings/business_document_settings_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/business_documents_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

Finder _textField(String label) {
  final wrapped = find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is WorkloopFormField && widget.label == label,
    ),
    matching: find.byType(TextField),
  );
  if (wrapped.evaluate().isNotEmpty) return wrapped;
  return find.widgetWithText(TextField, label);
}

const _settings = <String, dynamic>{
  'workspace_id': 'workspace',
  'timezone': 'Europe/London',
  'business_structure': 'sole_trader',
  'business_legal_name': 'Alex Owner',
  'business_address': '10 High Street, Bristol',
  'customer_contact_email': 'hello@example.test',
  'default_payment_terms_days': 7,
  'default_quote_validity_days': 30,
  'default_payment_instructions': 'Bank transfer using your invoice reference.',
  'revenue_target': 1000,
};

BusinessDocument _document(
  String id,
  String client, {
  String type = 'invoice',
}) => BusinessDocument.fromMap({
  'id': id,
  'workspace_id': 'workspace',
  'contact_id': client,
  'type': type,
  'status': 'sent',
  'revision': 2,
  'issue_date': '2026-09-08',
  'due_date': '2026-09-15',
  'service_date': '2026-09-08',
  'issued_at': '2026-09-08T09:00:00Z',
  'invoice_number': 'INV-$id',
  'invoice_id': 'payment-$id',
  'tax_rate': 0,
  'subtotal': 150,
  'tax_amount': 0,
  'total': 150,
  'business_snapshot': {
    'name': 'Calm Cleaning',
    'legal_name': 'Alex Owner',
    'address': '10 High Street',
    'email': 'hello@example.test',
  },
  'client_snapshot': {
    'name': client == 'client-a' ? 'Sam Morgan' : 'Other customer',
    'address': '2 Meadow Road',
  },
  'items': [
    {
      'description': 'Deep clean',
      'quantity': 1,
      'unit_price': 150,
      'line_total': 150,
      'position': 0,
    },
  ],
});

class _Client extends Fake implements SupabaseClient {}

class _Documents extends BusinessDocumentsRepository {
  _Documents() : super(_Client());
  @override
  Future<List<BusinessDocument>> list(String workspaceId) async => [
    _document('100', 'client-a'),
    _document('200', 'client-b'),
    _document('300', 'client-a', type: 'quote'),
  ];
  @override
  Future<BusinessDocument> get(String workspaceId, String id) async =>
      _document(id, 'client-a');
}

Payment _payment({String status = 'sent'}) => Payment(
  id: 'payment-100',
  workspaceId: 'workspace',
  contactId: 'client-a',
  number: 'INV-100',
  sourceDocumentId: '100',
  status: status,
  issueDate: DateTime(2026, 9, 8),
  total: 150,
  amountPaid: status == 'cancelled' ? 0 : 30,
  depositAmount: 30,
);

Future<void> _show(
  WidgetTester tester,
  Widget screen, {
  double scale = 1,
  bool empty = false,
  bool vatDefaults = false,
  String status = 'sent',
}) async {
  tester.view.physicalSize = scale > 1
      ? const Size(320, 700)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceIdProvider.overrideWith((_) async => 'workspace'),
        workspaceProvider.overrideWith(
          (_) async => {'id': 'workspace', 'name': 'Calm Cleaning'},
        ),
        workspaceSettingsProvider.overrideWith(
          (_) async => {
            ..._settings,
            if (vatDefaults) 'default_tax_rate': 20,
            if (vatDefaults) 'business_vat_number': 'GB123456789',
          },
        ),
        businessClockProvider.overrideWith(
          (_) => Stream.value(DateTime(2026, 9, 8, 14)),
        ),
        businessDocumentsRepositoryProvider.overrideWithValue(_Documents()),
        clientsProvider.overrideWith(
          (_) async => [
            const Client(
              id: 'client-a',
              workspaceId: 'workspace',
              name: 'Sam Morgan',
              address: '2 Meadow Road',
            ),
            const Client(
              id: 'client-b',
              workspaceId: 'workspace',
              name: 'Other customer',
            ),
          ],
        ),
        invoicesProvider.overrideWith(
          (_) async => empty ? [] : [_payment(status: status)],
        ),
        expensesProvider.overrideWith(
          (_) async => [
            Expense(
              id: 'expense',
              workspaceId: 'workspace',
              amount: 24.5,
              category: 'Materials',
              notes: 'Cleaning supplies',
              expenseDate: DateTime(2026, 9, 8),
            ),
          ],
        ),
        paymentCollectionEnabledProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const ValueKey('client-workflow-capture'),
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
              child: const Text('Open screen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open screen'));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_CLIENT_WORKFLOW_QA')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('client-workflow-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/tmp/workloop-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/lucide_flutter/LucideIcons':
          'packages/lucide_flutter/assets/lucide.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  testWidgets('client money opens the linked managed invoice', (tester) async {
    await _show(
      tester,
      const Scaffold(
        body: ClientPaymentsTab(clientId: 'client-a', clientName: 'Sam Morgan'),
      ),
    );
    await tester.tap(find.text('INV-100'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BusinessDocumentDetailScreen>(
            find.byType(BusinessDocumentDetailScreen),
          )
          .documentId,
      '100',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('client documents filter records and carry client into create', (
    tester,
  ) async {
    await _show(
      tester,
      const Scaffold(
        body: ClientPaymentsTab(clientId: 'client-a', clientName: 'Sam Morgan'),
      ),
    );
    await tester.tap(find.text('Quotes & invoices'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BusinessDocumentsScreen>(find.byType(BusinessDocumentsScreen))
          .initialClientId,
      'client-a',
    );
    expect(find.text('Sam Morgan'), findsOneWidget);
    expect(find.text('Other customer'), findsNothing);
    await tester.tap(find.text('Quotes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('INV-300'), findsOneWidget);
    expect(find.textContaining('INV-100'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Create'));
    await tester.pumpAndSettle();
    final editor = tester.widget<BusinessDocumentEditorScreen>(
      find.byType(BusinessDocumentEditorScreen),
    );
    expect(editor.initialClientId, 'client-a');
    expect(editor.type, 'quote');
    expect(find.text('Sam Morgan'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final empty in [false, true]) {
    testWidgets(
      'client money ${empty ? 'empty' : 'populated'} remains reachable at 320px 2x',
      (tester) async {
        await _show(
          tester,
          const Scaffold(
            body: SafeArea(
              child: ClientPaymentsTab(
                clientId: 'client-a',
                clientName: 'Sam Morgan',
              ),
            ),
          ),
          scale: 2,
          empty: empty,
        );
        await _capture(
          tester,
          'client-money-${empty ? 'empty' : 'populated'}-large',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Quotes & invoices'));
        await tester.pumpAndSettle();
        await _capture(tester, 'client-documents-large');
        expect(find.byType(BusinessDocumentsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('cancelled client invoice is not labelled as paid', (
    tester,
  ) async {
    await _show(
      tester,
      const Scaffold(
        body: ClientPaymentsTab(clientId: 'client-a', clientName: 'Sam Morgan'),
      ),
      status: 'cancelled',
    );
    expect(find.textContaining(' · Cancelled'), findsOneWidget);
    expect(find.textContaining(' · Paid'), findsNothing);
  });

  testWidgets('large Money tabs scroll with a real horizontal swipe', (
    tester,
  ) async {
    await _show(
      tester,
      FinanceScreen(referenceDate: DateTime(2026, 9, 8, 14)),
      scale: 2,
    );
    final segments = find.byType(WorkloopNavigationControl<MoneySection>);
    final scroller = tester.state<ScrollableState>(
      find
          .descendant(
            of: find
                .ancestor(
                  of: segments,
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroller.position.maxScrollExtent, greaterThan(0));
    await tester.drag(segments, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(scroller.position.pixels, greaterThan(0));
    final owed = find.descendant(of: segments, matching: find.text('Owed'));
    expect(tester.getRect(owed).right, lessThanOrEqualTo(320));
  });

  testWidgets(
    'booking invoice keeps the agreed total when VAT defaults apply',
    (tester) async {
      await _show(
        tester,
        BusinessDocumentEditorScreen(
          initialAppointment: Appointment(
            id: 'booking-vat',
            workspaceId: 'workspace',
            contactId: 'client-a',
            title: 'Agreed window clean',
            price: 60,
            startTime: DateTime.utc(2026, 9, 9, 8),
            endTime: DateTime.utc(2026, 9, 9, 9),
            recurrenceTimezone: 'Europe/London',
          ),
        ),
        vatDefaults: true,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Subtotal £50.00'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 25,
      );
      expect(
        find.text('Subtotal £50.00\nVAT £10.00\nTotal £60.00'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deposit request remains legible in the actual 320px editor', (
    tester,
  ) async {
    await _show(
      tester,
      BusinessDocumentEditorScreen(
        initialAppointment: Appointment(
          id: 'booking-deposit',
          workspaceId: 'workspace',
          contactId: 'client-a',
          title: 'Agreed window clean',
          price: 60,
          startTime: DateTime.utc(2026, 9, 9, 8),
          endTime: DateTime.utc(2026, 9, 9, 9),
          recurrenceTimezone: 'Europe/London',
        ),
      ),
      vatDefaults: true,
      scale: 2,
    );
    final depositPicker = find.widgetWithText(
      DropdownButtonFormField<String>,
      'No deposit',
    );
    await tester.scrollUntilVisible(
      depositPicker,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 25,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(depositPicker);
    await tester.pumpAndSettle();
    await tester.tap(depositPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixed amount').last);
    await tester.pumpAndSettle();
    final amount = _textField('Deposit amount');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '20');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('requested upfront'));
    await _capture(tester, 'invoice-deposit-large');
    expect(
      find.text(
        '£20.00 requested upfront. £40.00 follows by the final payment date.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back protects typed invoice setup changes', (
    tester,
  ) async {
    await _show(tester, const BusinessDocumentSettingsScreen());
    final field = _textField('Full legal name');
    await tester.enterText(field, 'Changed legal name');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Save your invoice setup?'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('finance workflows have reachable actions at ${scale}x text', (
      tester,
    ) async {
      await _show(
        tester,
        FinanceScreen(referenceDate: DateTime(2026, 9, 8, 14)),
        scale: scale,
      );
      await _capture(
        tester,
        'money-overview-${scale == 1 ? 'normal' : 'large'}',
      );
      expect(tester.takeException(), isNull);
      final segments = find.byType(WorkloopNavigationControl<MoneySection>);
      await tester.ensureVisible(
        find.descendant(of: segments, matching: find.text('Invoices')),
      );
      await tester.tap(
        find.descendant(of: segments, matching: find.text('Invoices')),
      );
      await tester.pumpAndSettle();
      await _capture(
        tester,
        'money-invoices-${scale == 1 ? 'normal' : 'large'}',
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        segments,
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.descendant(of: segments, matching: find.text('Spent')),
      );
      await tester.tap(
        find.descendant(of: segments, matching: find.text('Spent')),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'money-spent-${scale == 1 ? 'normal' : 'large'}');
      expect(tester.takeException(), isNull);
    });
    testWidgets('invoice setup current appearance ${scale}x text', (
      tester,
    ) async {
      await _show(tester, const BusinessDocumentSettingsScreen(), scale: scale);
      await _capture(
        tester,
        'invoice-setup-${scale == 1 ? 'normal' : 'large'}',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
