import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/features/finance/documents/business_document_pdf.dart';
import 'package:workloop/shared/documents/document_open_exception.dart';

BusinessDocument _multilineDocument({
  int itemCount = 1,
  String? address,
  String? logoUrl,
}) {
  return BusinessDocument(
    id: 'multiline',
    workspaceId: 'workspace',
    type: 'invoice',
    status: 'sent',
    number: 'INV-0099',
    issueDate: DateTime(2026, 9, 12),
    revision: 1,
    taxRate: 0,
    subtotalPence: 2500 * itemCount,
    taxPence: 0,
    totalPence: 2500 * itemCount,
    business: {'name': 'Clearview', 'logo_url': ?logoUrl},
    customer: {'name': 'Sam', 'address': address ?? '12 Example Road'},
    notes: List.filled(150, 'Terms').join('\n'),
    paymentInstructions: List.filled(100, 'Bank').join('\n'),
    items: List.generate(
      itemCount,
      (_) => BusinessDocumentItem(
        description: List.filled(100, 'x').join('\n'),
        quantityHundredths: 100,
        unitPricePence: 2500,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'invoice renders a frozen PNG logo and rejects corrupt image data within a bound',
    () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQKFgARAwQCgAfTgTBJMfkDQAAAABJRU5ErkJggg==',
      );
      final document = _multilineDocument(logoUrl: 'frozen-logo-url');
      final bytes = await buildBusinessDocumentPdf(
        document,
        logoLoader: (url) async {
          expect(url, 'frozen-logo-url');
          return png;
        },
      ).timeout(const Duration(seconds: 5));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      await expectLater(
        buildBusinessDocumentPdf(
          document,
          logoLoader: (_) async => Uint8List.fromList([137, 80, 78, 71]),
        ).timeout(const Duration(seconds: 5)),
        throwsA(isA<DocumentOpenException>()),
      );
    },
  );

  test(
    'accepted 100-line item and multiline terms paginate without hanging',
    () async {
      final bytes = await buildBusinessDocumentPdf(
        _multilineDocument(),
      ).timeout(const Duration(seconds: 5));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      if (const bool.fromEnvironment('WRITE_INVOICE_PDF_FIXTURE')) {
        await File('/tmp/workloop-invoice-multiline.pdf').writeAsBytes(bytes);
      }
    },
  );

  test(
    'unrenderable address returns an actionable error within a bound',
    () async {
      await expectLater(
        buildBusinessDocumentPdf(
          _multilineDocument(address: List.filled(500, 'x').join('\n')),
        ).timeout(const Duration(seconds: 5)),
        throwsA(
          isA<DocumentOpenException>().having(
            (error) => error.message,
            'message',
            contains('contact support'),
          ),
        ),
      );
    },
  );

  test('overlarge item set is rejected before expensive layout', () async {
    await expectLater(
      buildBusinessDocumentPdf(
        _multilineDocument(itemCount: 101),
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<DocumentOpenException>()),
    );
  });
  test(
    'issued invoice PDF renders real items and long documents locally',
    () async {
      final items = List.generate(
        40,
        (index) => BusinessDocumentItem(
          description: index == 0
              ? 'Window cleaning – front and rear, including frames'
              : 'Service visit ${index + 1}: agreed work and materials',
          quantityHundredths: 150,
          unitPricePence: 2500,
        ),
      );
      final totals = documentTotals(items, 20, true);
      final document = BusinessDocument(
        id: 'doc',
        workspaceId: 'workspace',
        type: 'invoice',
        status: 'sent',
        number: 'INV-0042',
        issueDate: DateTime(2026, 9, 8),
        dueDate: DateTime(2026, 9, 22),
        serviceDate: DateTime(2026, 9, 7),
        issuedAt: DateTime.utc(2026, 9, 8),
        revision: 2,
        taxRate: 20,
        pricesIncludeVat: true,
        subtotalPence: totals.subtotal,
        taxPence: totals.tax,
        totalPence: totals.total,
        depositType: 'percentage',
        depositValueHundredths: 3000,
        depositPence: 45000,
        depositDueDate: DateTime(2026, 9, 10),
        amountPaidPence: 20000,
        business: const {
          'name': 'Clearview Window Care',
          'legal_name': 'Alex Example',
          'address': '12 Example Lane\nLeeds\nLS1 1AA',
          'email': 'alex@example.com',
          'vat_number': 'GB123456789',
        },
        customer: const {
          'name': 'Sam Example',
          'address': '34 Sample Road\nLeeds\nLS2 2BB',
          'email': 'sam@example.com',
        },
        paymentInstructions:
            'Please quote INV-0042 when paying by bank transfer.\nAccount: Example account · Sort code: 00-00-00 · Account number: 00000000',
        notes:
            'Thank you for your business. Please contact us with any queries about this invoice.',
        items: items,
      );
      final bytes = await buildBusinessDocumentPdf(document);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(String.fromCharCodes(bytes).trimRight(), endsWith('%%EOF'));
      if (const bool.fromEnvironment('WRITE_INVOICE_PDF_FIXTURE')) {
        await File('/tmp/workloop-invoice-example.pdf').writeAsBytes(bytes);
      }
    },
  );
}
