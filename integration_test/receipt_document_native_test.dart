// Isolated native integration: synthetic receipts only, no Supabase/session boot.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/features/finance/receipt_text_service.dart';
import 'package:workloop/shared/documents/workloop_document_viewer.dart';

import 'support/business_tools_native_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native PDF preview and receipt OCR use synthetic bytes',
    (tester) async {
      // This read-only simulator response also guards the existing payment
      // bridge against the same UIScene registration regression.
      final availability = await const MethodChannel(
        'com.ismaeel.workloop/payments',
      ).invokeMapMethod<String, dynamic>('availability');
      expect(availability?['supported'], isTrue);
      final document = pw.Document();
      document.addPage(
        pw.Page(
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final text in [
                'Workloop receipt fixture',
                'Date: 08 September 2026',
                'Materials GBP 25.00',
                'VAT GBP 5.00',
                'TOTAL GBP 30.00',
              ])
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 20),
                  child: pw.Text(text, style: const pw.TextStyle(fontSize: 24)),
                ),
            ],
          ),
        ),
      );
      final bytes = await document.save();
      final pages = await Printing.raster(bytes, dpi: 180).toList();
      expect(pages, hasLength(1));
      final png = await pages.single.toPng();
      final reader = ReceiptTextService();
      for (final file in [
        ReceiptFile.checked('fixture.pdf', bytes),
        ReceiptFile.checked('fixture.png', png),
      ]) {
        final ReceiptRecognizedText text;
        try {
          text = await reader.recognize(file);
        } on ReceiptRecognitionException catch (error) {
          fail('${file.name}: ${error.message}');
        }
        expect(text.text, contains('30.00'));
        expect(text.text, contains('September 2026'));
        expect(text.processedPages, 1);
        expect(text.isPartial, isFalse);
      }
      await tester.pumpWidget(
        nativeProbeHost(
          WorkloopDocumentViewerScreen(
            workspaceId: nativeProbeWorkspace,
            title: 'Receipt fixture',
            fileName: 'fixture.pdf',
            mimeType: 'application/pdf',
            loadBytes: () async => bytes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Receipt fixture'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Could not display this PDF.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
