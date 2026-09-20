import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../shared/repositories/business_logo_repository.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'business_document.dart';
import '../../../shared/documents/document_open_exception.dart';

const _layoutError = DocumentOpenException(
  'This document has too much text to fit safely. Shorten long descriptions, '
  'addresses or notes in a draft, or contact support for an issued document.',
);

typedef _PdfRequest = ({
  BusinessDocument document,
  ByteData regular,
  ByteData bold,
  Uint8List? logo,
  SendPort result,
});

/// Generated locally from the frozen issued snapshot. No customer details are
/// sent to a rendering service and draft documents are visibly watermarked.
Future<Uint8List> buildBusinessDocumentPdf(
  BusinessDocument document, {
  Future<Uint8List?> Function(String?)? logoLoader,
}) async {
  final regular = await rootBundle.load(
    'assets/fonts/Manrope-Document-Regular.ttf',
  );
  final bold = await rootBundle.load(
    'assets/fonts/Manrope-Document-SemiBold.ttf',
  );
  final logo = await (logoLoader ?? _loadLogo)(document.business['logo_url']);
  final port = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn(_renderPdf, (
      document: document,
      regular: regular,
      bold: bold,
      logo: logo,
      result: port.sendPort,
    ));
    final result = await port.first.timeout(const Duration(seconds: 15));
    if (result is Uint8List) return result;
    throw _layoutError;
  } on TimeoutException {
    throw _layoutError;
  } finally {
    // A timed-out layout must not keep consuming CPU after the viewer recovers.
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}

Future<void> _renderPdf(_PdfRequest request) async {
  try {
    request.result.send(await _buildPdf(request));
  } catch (_) {
    request.result.send(null);
  }
}

/// Split at explicit line breaks and bound unbroken text as well. Continuation
/// rows keep every character without repeating quantities or financial amounts.
List<String> _descriptionChunks(String text) {
  final lines = <String>[];
  for (final line
      in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    final characters = line.runes.toList();
    if (characters.isEmpty) lines.add('');
    for (var start = 0; start < characters.length; start += 160) {
      lines.add(String.fromCharCodes(characters.skip(start).take(160)));
    }
  }
  return [
    for (var start = 0; start < lines.length; start += 6)
      lines.skip(start).take(6).join('\n'),
  ];
}

Future<Uint8List> _buildPdf(_PdfRequest request) async {
  final document = request.document;
  if (document.items.length > 100 ||
      document.items.any((item) => item.description.length > 300) ||
      document.notes.length > 5000 ||
      document.paymentInstructions.length > 3000) {
    throw _layoutError;
  }
  final regular = pw.Font.ttf(request.regular);
  final bold = pw.Font.ttf(request.bold);
  final pdf = pw.Document(
    title: document.reference,
    author: document.business['name'],
    creator: 'Workloop',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  const ink = PdfColor.fromInt(0xff302a26);
  const blue = PdfColor.fromInt(0xffdceaf1);
  String details(Map<String, String> data, List<String> keys) => keys
      .map((key) => data[key]?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .join('\n');
  pw.Widget pair(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label),
            pw.Text(value, style: pw.TextStyle(fontSize: strong ? 16 : 11)),
          ],
        ),
      );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      maxPages: 60,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (context) {
        // pdf's maxPages assertion is disabled in profile/release. Enforce a
        // real bound as well, including a pathological non-spanning header/row.
        if (context.pageNumber > 60) throw _layoutError;
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 18),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (request.logo != null) ...[
                pw.Image(
                  pw.MemoryImage(request.logo!),
                  width: 56,
                  height: 56,
                  fit: pw.BoxFit.contain,
                ),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Text(
                  document.business['name'] ?? '',
                  style: const pw.TextStyle(fontSize: 23, color: ink),
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    document.title.toUpperCase(),
                    style: const pw.TextStyle(fontSize: 18, color: ink),
                  ),
                  pw.Text(document.reference),
                  if (document.isDraft)
                    pw.Text(
                      'DRAFT - NOT ISSUED',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.red,
                      ),
                    ),
                  if (document.status == 'cancelled')
                    pw.Text(
                      'CANCELLED',
                      style: const pw.TextStyle(color: PdfColors.red),
                    ),
                ],
              ),
            ],
          ),
        );
      },
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Prepared with Workloop',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FROM',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    details(document.business, [
                      'legal_name',
                      'address',
                      'email',
                      'phone',
                    ]),
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                  ),
                  if ((document.business['company_number'] ?? '').isNotEmpty)
                    pw.Text(
                      'Company no. ${document.business['company_number']}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if ((document.business['vat_number'] ?? '').isNotEmpty)
                    pw.Text(
                      'VAT no. ${document.business['vat_number']}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    document.isQuote ? 'PREPARED FOR' : 'BILL TO',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    details(document.customer, [
                      'name',
                      'address',
                      'email',
                      'phone',
                    ]),
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Container(
          color: blue,
          padding: const pw.EdgeInsets.all(12),
          child: pw.Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              pw.Text(
                '${document.isDraft ? 'Proposed issue date' : 'Issued'}: ${documentDate(document.issueDate)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              if (document.dueDate != null)
                pw.Text(
                  '${document.isQuote ? 'Valid until' : 'Payment due'}: ${documentDate(document.dueDate!)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              if (document.serviceDate != null)
                pw.Text(
                  '${document.isQuote ? 'Work date' : 'Supply date'}: ${documentDate(document.serviceDate!)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 22),
        pw.TableHelper.fromTextArray(
          headers: [
            'Description',
            'Qty',
            document.showsVat ? 'Unit price\nex VAT' : 'Unit price',
            if (document.showsVat) 'VAT',
            document.showsVat ? 'Amount\nex VAT' : 'Amount',
          ],
          data: [
            for (final item in document.items)
              for (final (index, chunk) in _descriptionChunks(
                item.description,
              ).indexed)
                [
                  chunk,
                  if (index == 0) ...[
                    item.quantity,
                    item.netUnitPrice(
                      document.taxRate,
                      document.pricesIncludeVat,
                    ),
                    if (document.showsVat) '${document.taxRate}%',
                    documentMoney(
                      item.netTotalPence(
                        document.taxRate,
                        document.pricesIncludeVat,
                      ),
                    ),
                  ] else ...[
                    '',
                    '',
                    if (document.showsVat) '',
                    '',
                  ],
                ],
          ],
          border: null,
          headerDecoration: const pw.BoxDecoration(color: blue),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(2),
            if (document.showsVat) 3: const pw.FlexColumnWidth(1),
            document.showsVat ? 4 : 3: const pw.FlexColumnWidth(2),
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          oddRowDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xfffaf9f7),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 230,
            child: pw.Column(
              children: [
                pair('Subtotal', documentMoney(document.subtotalPence)),
                if (document.showsVat)
                  pair(
                    'VAT (${document.taxRate}%)',
                    documentMoney(document.taxPence),
                  ),
                pw.Divider(color: ink),
                pair(
                  'Total (GBP)',
                  documentMoney(document.totalPence),
                  strong: true,
                ),
                if (document.hasDeposit) ...[
                  pair(
                    document.isQuote ? 'Proposed deposit' : 'Deposit requested',
                    documentMoney(document.depositPence),
                  ),
                  if (document.depositDueDate != null)
                    pair('Deposit due', documentDate(document.depositDueDate!)),
                ],
                if (!document.isQuote &&
                    !document.isDraft &&
                    document.amountPaidPence != null &&
                    document.status != 'cancelled') ...[
                  pair(
                    'Payments received',
                    documentMoney(document.amountPaidPence!),
                  ),
                  pair(
                    'Balance remaining',
                    documentMoney(document.outstandingPence!),
                    strong: true,
                  ),
                  if ((document.depositOutstandingPence ?? 0) > 0)
                    pair(
                      'Deposit still due',
                      documentMoney(document.depositOutstandingPence!),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (document.paymentInstructions.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text(
            'Payment instructions',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            document.paymentInstructions,
            overflow: pw.TextOverflow.span,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ],
        if (document.notes.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text('Notes and terms', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.Text(
            document.notes,
            overflow: pw.TextOverflow.span,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ],
        if (document.isQuote) ...[
          pw.SizedBox(height: 20),
          pw.Text(
            'This is a quotation, not a request for payment.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ],
    ),
  );
  return pdf.save();
}

Future<Uint8List?> _loadLogo(String? value) async {
  if (value == null || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !isTrustedBusinessLogoUrl(value)) {
    throw const DocumentOpenException(
      'The saved business logo is not valid. Update the logo on this draft.',
    );
  }
  final client = http.Client();
  try {
    return await (() async {
      final response = await client.send(
        http.Request('GET', uri)..followRedirects = false,
      );
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > businessLogoMaxBytes) {
        throw const FormatException();
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > businessLogoMaxBytes) {
          throw const FormatException();
        }
        bytes.add(chunk);
      }
      final result = bytes.takeBytes();
      businessLogoMimeType(result);
      return result;
    })().timeout(const Duration(seconds: 8));
  } catch (_) {
    throw const DocumentOpenException(
      'Your business logo could not be loaded. Check your connection and try again.',
    );
  } finally {
    client.close();
  }
}
