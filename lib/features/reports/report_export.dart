import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_models.dart';

/// Protect free text from spreadsheet formula execution; retain numeric cells.
String reportCsvCell(Object value) {
  var text = reportCell(value);
  if (value is String &&
      (RegExp(r'^[\s\uFEFF]*[=+@\-]').hasMatch(text) ||
          RegExp(r'^[\t\r\n]').hasMatch(text))) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

String buildReportCsv({
  required BusinessReport report,
  required ReportSource source,
  required ReportRange range,
  required DateTime generatedAt,
}) {
  final rows = <List<Object>>[
    ['Workloop report', report.kind.label],
    ['Business', source.businessName],
    ['Workspace ID', source.workspaceId],
    [
      'Period',
      report.kind == ReportKind.outstanding
          ? 'Money still owed today'
          : range.label,
    ],
    ['Generated at', generatedAt.toUtc().toIso8601String()],
    ['Business timezone', source.timezone],
    ['Currency', 'GBP'],
    ['How to read this report', report.basis],
    for (final notice in report.notices) ['Forecast note', notice],
    [],
    ['What this shows', 'Amount or count', 'Compared with earlier dates'],
    for (final metric in report.metrics)
      [metric.label, metric.value, metric.comparison ?? ''],
    [],
    report.columns,
    ...report.rows,
  ];
  return '\uFEFF${rows.map((row) => row.map(reportCsvCell).join(',')).join('\r\n')}\r\n';
}

Uint8List reportCsvBytes({
  required BusinessReport report,
  required ReportSource source,
  required ReportRange range,
  required DateTime generatedAt,
}) => Uint8List.fromList(
  utf8.encode(
    buildReportCsv(
      report: report,
      source: source,
      range: range,
      generatedAt: generatedAt,
    ),
  ),
);

/// A bounded, readable summary; CSV always contains every detail record.
Future<Uint8List> buildReportPdf({
  required BusinessReport report,
  required ReportSource source,
  required ReportRange range,
  required DateTime generatedAt,
}) async {
  final (regular, bold) = await (
    rootBundle.load('assets/fonts/Manrope-Document-Regular.ttf'),
    rootBundle.load('assets/fonts/Manrope-Document-SemiBold.ttf'),
  ).wait;
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(regular),
    bold: pw.Font.ttf(bold),
  );
  final pdf = pw.Document(
    title: report.kind.label,
    author: source.businessName,
    creator: 'Workloop',
    theme: theme,
  );
  // Bound all free text to keep long customer input from trapping PDF layout.
  String short(Object text, [int limit = 100]) {
    final value = reportCell(text).replaceAll(RegExp(r'\s+'), ' ');
    return value.runes.length > limit
        ? '${String.fromCharCodes(value.runes.take(limit))}…'
        : value;
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      maxPages: 20,
      header: (context) {
        if (context.pageNumber > 20) {
          throw StateError(
            'Report summary is too long. Use CSV for full records.',
          );
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Text(
            'workloop / ${report.kind.label}',
            style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
          ),
        );
      },
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'GBP · ${source.timezone} · Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => [
        pw.Text(
          short(source.businessName),
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          report.kind == ReportKind.outstanding
              ? 'Money still owed today'
              : range.label,
        ),
        pw.Text(
          'Generated ${generatedAt.toUtc().toIso8601String()} (UTC)',
          style: const pw.TextStyle(fontSize: 8),
        ),
        for (final notice in report.notices)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(notice, style: const pw.TextStyle(fontSize: 9)),
          ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: [
            'What this shows',
            'Amount / count',
            'Compared with earlier dates',
          ],
          data: [
            for (final m in report.metrics.take(40))
              [short(m.label), short(m.value), short(m.comparison ?? '')],
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xffc3d7e4),
          ),
        ),
        if (report.metrics.length > 40)
          pw.Text(
            'This summary shows the first 40 totals. Export the spreadsheet for every total.',
          ),
        pw.SizedBox(height: 16),
        pw.Text(
          'How to read this report',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(report.basis, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 18),
        pw.Text(
          report.kind == ReportKind.forecast
              ? 'Week by week (${report.rows.length})'
              : 'Your breakdown (${report.rows.length})',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'The PDF includes up to 40 entries and shortens long descriptions. Export the spreadsheet (CSV) for all entries, complete descriptions and reference IDs.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 8),
        if (report.rows.isEmpty) pw.Text(report.emptyMessage),
        if (report.rows.isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: report.columns.where((c) => !c.endsWith('ID')).toList(),
            data: [
              for (final row in report.rows.take(40))
                [
                  for (var i = 0; i < row.length; i++)
                    if (!report.columns[i].endsWith('ID'))
                      short(reportDisplayCell(row[i], report.columns[i]), 65),
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xffc3d7e4),
            ),
          ),
      ],
    ),
  );
  return pdf.save();
}
