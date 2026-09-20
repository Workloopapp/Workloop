import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/features/finance/documents/business_document_detail_screen.dart';
import 'package:workloop/features/finance/documents/business_document_pdf.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/business_documents_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/business_documents_repository.dart';

class _UnusedRepository extends Fake implements BusinessDocumentsRepository {}

BusinessDocument _doc({Map<String, dynamic> values = const {}}) =>
    BusinessDocument.fromMap({
      'id': 'invoice-1',
      'workspace_id': 'workspace-1',
      'type': 'invoice',
      'status': 'sent',
      'issued_at': '2026-09-10T12:00:00Z',
      'issue_date': '2026-09-10',
      'due_date': '2026-09-30',
      'service_date': '2026-09-10',
      'invoice_number': 'INV-001',
      'invoice_id': 'payment-1',
      'business_snapshot': {
        'name': 'Clearview',
        'legal_name': 'Alex Example',
        'address': '1 Example Road',
        'email': 'owner@example.test',
      },
      'client_snapshot': {'name': 'Sam', 'address': '2 Example Road'},
      'items': [
        {'description': 'Window cleaning', 'quantity': 1, 'unit_price': 100},
      ],
      'total': 100,
      'subtotal': 100,
      'amount_paid': 0,
      ...values,
    });

final _payment = Payment(
  id: 'payment-1',
  workspaceId: 'workspace-1',
  number: 'INV-001',
  issueDate: DateTime(2026, 9, 10),
  dueDate: DateTime(2026, 9, 30),
  total: 100,
  status: 'sent',
  sourceDocumentId: 'invoice-1',
);

Future<ProviderContainer> _mount(
  WidgetTester tester,
  BusinessDocument document, {
  Future<List<Payment>> Function()? loadPayments,
  GoRouter? router,
}) async {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      businessDocumentsRepositoryProvider.overrideWithValue(
        _UnusedRepository(),
      ),
      workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
      workspaceSettingsProvider.overrideWith(
        (ref) async => {'timezone': 'Europe/London'},
      ),
      businessNowProvider.overrideWithValue(DateTime.utc(2026, 9, 12, 12)),
      businessDocumentProvider.overrideWith((ref, id) async => document),
      invoicesProvider.overrideWith(
        (ref) async => loadPayments == null ? [_payment] : await loadPayments(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: router == null
          ? MaterialApp(
              theme: AppTheme.light,
              home: const BusinessDocumentDetailScreen(documentId: 'invoice-1'),
            )
          : MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('unpaid deposit becomes overdue before the final invoice due date', () {
    final doc = _doc(
      values: {
        'deposit_amount': 25,
        'deposit_type': 'fixed',
        'deposit_value': 25,
        'deposit_due_date': '2026-09-11',
      },
    );
    expect(doc.statusLabel(now: DateTime(2026, 9, 11)), 'Deposit due');
    expect(doc.statusLabel(now: DateTime(2026, 9, 12)), 'Deposit overdue');
    expect(
      _doc(
        values: {
          'deposit_amount': 25,
          'deposit_due_date': '2026-09-11',
          'amount_paid': 25,
        },
      ).statusLabel(now: DateTime(2026, 9, 12)),
      'Part paid',
    );
  });

  test(
    'quote readiness uses validity wording and non-VAT snapshots stay distinct from zero-rated VAT',
    () {
      expect(_doc().showsVat, isFalse);
      expect(
        _doc(
          values: {
            'business_snapshot': {'vat_number': 'GB123456789'},
          },
        ).showsVat,
        isTrue,
      );
      expect(_doc(values: {'tax_rate': 20}).showsVat, isTrue);
      expect(
        _doc(values: {'type': 'quote', 'due_date': null}).missingIssueDetails,
        contains('quote validity date'),
      );
    },
  );

  testWidgets('collection is before line items and refresh remains visible', (
    tester,
  ) async {
    await _mount(tester, _doc());
    expect(find.text('Record payment received').hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Record payment received')).dy,
      lessThan(tester.getTopLeft(find.text('Window cleaning\n1 × £100.00')).dy),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Refresh document').hitTestable(), findsOneWidget);
    expect(find.text('INV-001'), findsOneWidget);
  });

  testWidgets(
    'failed payment balance offers retry and never exposes cached collection',
    (tester) async {
      var calls = 0;
      final pending = Completer<List<Payment>>();
      final container = await _mount(
        tester,
        _doc(),
        loadPayments: () async {
          calls++;
          if (calls == 1) throw const SocketException('offline');
          if (calls == 2) return [_payment];
          return pending.future;
        },
      );
      expect(find.text('Record payment received'), findsNothing);
      await tester.tap(find.text('Retry payment balance'));
      await tester.pumpAndSettle();
      expect(
        find.text('Record payment received').hitTestable(),
        findsOneWidget,
      );
      container.invalidate(invoicesProvider);
      expect(container.read(invoicesProvider).isLoading, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Record payment received'), findsNothing);
      expect(find.text('Loading payment balance…'), findsOneWidget);
      pending.complete([_payment]);
      await tester.pumpAndSettle();
      expect(find.text('Record payment received'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'linked client and booking open the exact records and return to invoice',
    (tester) async {
      final doc = _doc(
        values: {'contact_id': 'client-42', 'appointment_id': 'booking-17'},
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const BusinessDocumentDetailScreen(documentId: 'invoice-1'),
          ),
          GoRoute(
            path: '/clients/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Client ${state.pathParameters['id']}')),
          ),
          GoRoute(
            path: '/bookings/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Booking ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await _mount(tester, doc, router: router);
      for (final entry in [
        ('View client', 'Client client-42'),
        ('View booking', 'Booking booking-17'),
      ]) {
        await tester.ensureVisible(find.text(entry.$1));
        await tester.tap(find.text(entry.$1));
        await tester.pumpAndSettle();
        expect(find.text(entry.$2), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('INV-001'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'non-VAT and zero-rated VAT PDFs both render from their snapshot',
    () async {
      for (final registered in [false, true]) {
        final document = _doc(
          values: {
            'business_snapshot': {
              'name': 'Clearview',
              if (registered) 'vat_number': 'GB123456789',
            },
          },
        );
        final bytes = await buildBusinessDocumentPdf(document);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        if (const bool.fromEnvironment('WRITE_INVOICE_PDF_FIXTURE')) {
          await File(
            '/tmp/workloop-invoice-${registered ? 'zero-vat' : 'non-vat'}.pdf',
          ).writeAsBytes(bytes);
        }
      }
    },
  );
}
