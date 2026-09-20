import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/reports/cashflow_forecast.dart';
import 'package:workloop/features/reports/report_builder.dart';
import 'package:workloop/features/reports/report_export.dart';
import 'package:workloop/features/reports/report_models.dart';
import 'package:workloop/shared/models/slate_models.dart';

final _now = DateTime.utc(2026, 9, 12, 12);
final _range = ReportRange(DateTime.utc(2026, 9), DateTime.utc(2026, 9, 13));
Payment _payment(
  String id, {
  double total = 100,
  double paid = 0,
  String status = 'sent',
  DateTime? due,
  DateTime? received,
  String? document,
  List<PaymentReceipt> receipts = const [],
  String? contact = 'client',
  String? booking,
}) => Payment(
  id: id,
  workspaceId: 'business',
  number: 'INV-$id',
  status: status,
  issueDate: DateTime(2026, 8, 1),
  dueDate: due,
  incomeRecordedAt: received,
  total: total,
  amountPaid: paid,
  sourceDocumentId: document,
  receipts: receipts,
  contactId: contact,
  appointmentId: booking,
);
Appointment _booking(
  String id, {
  String? contact = 'client',
  DateTime? start,
  String status = 'completed',
  double price = 100,
  List<ServiceItemSnapshot> items = const [],
}) => Appointment(
  id: id,
  workspaceId: 'business',
  contactId: contact,
  startTime: start ?? DateTime.utc(2026, 9, 5, 10),
  endTime: (start ?? DateTime.utc(2026, 9, 5, 10)).add(
    const Duration(hours: 1),
  ),
  status: status,
  price: price,
  serviceName: 'Consultation',
  serviceItems: items,
);
ReportSource _source({
  List<Payment> payments = const [],
  List<Expense> expenses = const [],
  List<Appointment> bookings = const [],
  List<Client> clients = const [],
  List<SlateTask> tasks = const [],
}) => ReportSource(
  workspaceId: 'business',
  businessName: 'Example business',
  payments: payments,
  expenses: expenses,
  bookings: bookings,
  clients: clients,
  tasks: tasks,
);
BusinessReport _build(
  ReportKind kind,
  ReportSource source, {
  ReportRange? range,
  DateTime? now,
}) => buildBusinessReport(
  source: source,
  kind: kind,
  range: range ?? _range,
  now: now ?? _now,
);
String _metric(BusinessReport report, String label) =>
    report.metrics.singleWhere((m) => m.label == label).value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('calendar comparisons survive DST, leap years and year boundaries', () {
    final march = ReportRange(DateTime(2026, 3, 1), DateTime(2026, 4, 1));
    expect(march.end.difference(march.start).inDays, 31);
    expect(march.previous.end, march.start);
    expect(march.previous.end.difference(march.previous.start).inDays, 31);
    final leap = ReportPeriod.lastMonth.range(DateTime(2024, 3, 12));
    expect(leap.start, DateTime.utc(2024, 2));
    expect(leap.end.difference(leap.start).inDays, 29);
    expect(
      ReportPeriod.lastMonth.range(DateTime(2026, 1, 2)).start,
      DateTime.utc(2025, 12),
    );
    expect(() => ReportRange(_now, _now), throwsArgumentError);
  });

  test(
    'partial receipts and refunds use movement dates, never invoice totals',
    () {
      final source = _source(
        payments: [
          _payment(
            'one',
            document: 'doc',
            paid: 50,
            receipts: [
              PaymentReceipt(
                id: 'old',
                amount: 20,
                receivedAt: DateTime.utc(2026, 8, 15),
              ),
              PaymentReceipt(
                id: 'partial',
                amount: 40,
                receivedAt: DateTime.utc(2026, 9, 2),
              ),
              PaymentReceipt(
                id: 'refund',
                amount: -10,
                receivedAt: DateTime.utc(2026, 9, 4),
              ),
              PaymentReceipt(
                id: 'future',
                amount: 999,
                receivedAt: DateTime.utc(2026, 9, 20),
              ),
            ],
          ),
        ],
      );
      final report = _build(ReportKind.cash, source);
      expect(_metric(report, 'Customer payments'), '£40.00');
      expect(_metric(report, 'Money refunded'), '£10.00');
      expect(_metric(report, 'Money received after refunds'), '£30.00');
      expect(report.rows.length, 2);
      expect(
        _metric(
          _build(ReportKind.overview, source),
          'Money received after refunds',
        ),
        '£30.00',
      );
    },
  );

  test(
    'midnight receipt and booking use business timezone, date-only entries retain date',
    () {
      final source = _source(
        payments: [
          _payment(
            'boundary',
            status: 'paid',
            received: DateTime.utc(2026, 8, 31, 23, 30),
          ),
          Payment(
            id: 'legacy',
            workspaceId: 'business',
            number: 'legacy',
            status: 'paid',
            issueDate: DateTime(2026, 9, 1),
            total: 10,
          ),
        ],
        bookings: [
          _booking('boundary', start: DateTime.utc(2026, 8, 31, 23, 30)),
        ],
      );
      final day = ReportRange(DateTime(2026, 9, 1), DateTime(2026, 9, 2));
      expect(
        _metric(
          _build(ReportKind.cash, source, range: day),
          'Money received after refunds',
        ),
        '£110.00',
      );
      expect(_build(ReportKind.bookings, source, range: day).rows.length, 1);
      expect(
        _build(
          ReportKind.cash,
          source,
          range: day,
        ).rows.every((r) => r.first == '2026-09-01'),
        isTrue,
      );
    },
  );

  test('penny sums and negative cash surplus remain exact', () {
    final source = _source(
      payments: [
        for (var i = 0; i < 10; i++)
          _payment('$i', status: 'paid', total: .10, received: _now),
      ],
      expenses: [
        Expense(
          id: 'e',
          workspaceId: 'business',
          amount: 1.25,
          category: 'Materials',
          expenseDate: DateTime(2026, 9, 1),
        ),
      ],
    );
    final report = _build(ReportKind.overview, source);
    expect(_metric(report, 'Money received after refunds'), '£1.00');
    expect(_metric(report, 'Money left after expenses'), '−£0.25');
    expect(report.rows.single[3], -.25);
  });

  test(
    'future expenses excluded and signed corrections retained in categories',
    () {
      final source = _source(
        expenses: [
          Expense(
            id: 'e',
            workspaceId: 'business',
            amount: 50,
            category: 'Tools',
            expenseDate: DateTime(2026, 9, 2),
          ),
          Expense(
            id: 'correction',
            workspaceId: 'business',
            amount: -10,
            category: 'Tools',
            expenseDate: DateTime(2026, 9, 3),
          ),
          Expense(
            id: 'future',
            workspaceId: 'business',
            amount: 99,
            category: 'Tools',
            expenseDate: DateTime(2026, 9, 30),
          ),
        ],
      );
      final report = _build(
        ReportKind.expenses,
        source,
        range: ReportRange(DateTime(2026, 9), DateTime(2026, 10)),
      );
      expect(_metric(report, 'Total spending'), '£40.00');
      expect(_metric(report, 'Tools'), '£40.00');
      expect(report.rows.length, 2);
    },
  );

  test(
    'booking outcome rate excludes unresolved bookings and value excludes cancellations',
    () {
      final source = _source(
        bookings: [
          _booking('complete'),
          _booking('cancel', status: 'cancelled'),
          _booking('missed', status: 'no_show'),
          _booking('scheduled', status: 'scheduled'),
        ],
      );
      final report = _build(ReportKind.bookings, source);
      expect(_metric(report, 'Total bookings'), '4');
      expect(_metric(report, 'Completion rate'), '33.3%');
      expect(_metric(report, 'Value of completed work'), '£100.00');
      expect(_metric(report, 'Hours of completed work'), '1.0');
    },
  );

  test(
    'multi-service snapshots and add-ons count individually without multiplying booking totals',
    () {
      final source = _source(
        bookings: [
          _booking(
            'bundle',
            price: 80,
            items: [
              ServiceItemSnapshot(
                id: 'base',
                workspaceId: 'business',
                itemKind: 'base',
                sourceServiceId: 'a',
                name: 'Service A',
                durationMins: 30,
                price: 50,
                position: 0,
              ),
              ServiceItemSnapshot(
                id: 'second',
                workspaceId: 'business',
                itemKind: 'base',
                sourceServiceId: 'b',
                name: 'Service B',
                durationMins: 15,
                price: 20,
                position: 1,
              ),
              ServiceItemSnapshot(
                id: 'addon',
                workspaceId: 'business',
                itemKind: 'add_on',
                sourceAddOnId: 'x',
                name: 'Extra',
                durationMins: 15,
                price: 10,
                position: 2,
              ),
            ],
          ),
        ],
      );
      final report = _build(ReportKind.services, source);
      expect(_metric(report, 'Completed bookings'), '1');
      expect(_metric(report, 'Value of completed services'), '£80.00');
      expect(report.rows.length, 3);
      expect(report.rows.last[1], 'Add-on');
    },
  );

  test(
    'one service groups legacy, primary and additional snapshots together',
    () {
      final source = _source(
        bookings: [
          Appointment(
            id: 'legacy',
            workspaceId: 'business',
            serviceId: 'same-service',
            serviceName: 'Consultation',
            startTime: DateTime.utc(2026, 9, 2),
            status: 'completed',
            price: 50,
          ),
          for (final kind in ['base', 'service'])
            _booking(
              kind,
              items: [
                ServiceItemSnapshot(
                  id: kind,
                  workspaceId: 'business',
                  itemKind: kind,
                  sourceServiceId: 'same-service',
                  name: 'Consultation',
                  durationMins: 30,
                  price: 50,
                  position: 0,
                ),
              ],
            ),
        ],
      );
      final report = _build(ReportKind.services, source);
      expect(report.rows.length, 1);
      expect(report.rows.single[2], 3);
      expect(report.rows.single[3], 150.0);
      expect(report.rows.single[4], 50.0);
    },
  );

  test(
    'returning clients require earlier completed work, and refunds reduce ranking',
    () {
      final source = _source(
        clients: [
          Client(id: 'client', workspaceId: 'business', name: 'Alex'),
          Client(
            id: 'new',
            workspaceId: 'business',
            name: 'Sam',
            createdAt: DateTime.utc(2026, 9, 4),
          ),
        ],
        bookings: [
          _booking('old', start: DateTime.utc(2026, 8, 1)),
          _booking('current'),
          _booking('new', contact: 'new'),
          _booking('anonymous', contact: null),
        ],
        payments: [
          _payment('receipt', status: 'paid', received: _now),
          _payment('refund', status: 'paid', total: -20, received: _now),
        ],
      );
      final report = _build(ReportKind.clients, source);
      expect(_metric(report, 'Clients served'), '2');
      expect(_metric(report, 'Returning clients'), '1');
      expect(_metric(report, 'Clients who came back'), '50.0%');
      expect(_metric(report, 'Clients added'), '1');
      expect(report.rows.first[3], 80.0);
    },
  );

  test(
    'outstanding is current, excludes closed records and ages unpaid remainder',
    () {
      final source = _source(
        payments: [
          _payment('today', due: DateTime(2026, 9, 12)),
          _payment('thirty', paid: 30, due: DateTime(2026, 8, 13)),
          _payment('thirtyone', due: DateTime(2026, 8, 12)),
          _payment('cancelled', status: 'cancelled'),
          _payment('declined', status: 'declined'),
          _payment('paid', status: 'paid'),
        ],
      );
      final report = _build(
        ReportKind.outstanding,
        source,
        range: ReportRange(DateTime(2020), DateTime(2021)),
      );
      expect(_metric(report, 'Total still owed'), '£270.00');
      expect(_metric(report, 'Past the due date'), '£170.00');
      expect(_metric(report, '1–30 days overdue'), '£70.00');
      expect(_metric(report, '31–60 days overdue'), '£100.00');
      expect(report.rows.length, 3);
      expect(report.basis, contains('always shows today'));
    },
  );

  test('task report is due-date based and separates undated work', () {
    final report = _build(
      ReportKind.tasks,
      _source(
        tasks: [
          SlateTask(
            id: 'done',
            workspaceId: 'business',
            title: 'Done',
            status: 'done',
            dueDate: DateTime(2026, 9, 2),
          ),
          SlateTask(
            id: 'open',
            workspaceId: 'business',
            title: 'Follow up',
            dueDate: DateTime(2026, 9, 3),
          ),
          SlateTask(id: 'undated', workspaceId: 'business', title: 'Later'),
        ],
      ),
    );
    expect(_metric(report, 'Tasks due'), '2');
    expect(_metric(report, 'Past the due date'), '1');
    expect(_metric(report, 'To do without a due date'), '1');
    expect(report.rows.length, 2);
  });

  test(
    'CSV preserves complete records, quotes Unicode and neutralises formulas',
    () {
      final source = _source(
        clients: [
          Client(
            id: 'client',
            workspaceId: 'business',
            name: ' =HYPERLINK("bad")',
          ),
        ],
        payments: [
          for (var i = 0; i < 1050; i++)
            _payment('$i', status: 'paid', received: _now),
        ],
      );
      final report = _build(ReportKind.cash, source);
      final csv = buildReportCsv(
        report: report,
        source: source,
        range: _range,
        generatedAt: _now,
      );
      expect(report.rows.length, 1050);
      expect(csv, contains('INV-1049'));
      expect(csv, contains("' =HYPERLINK("));
      expect(csv, contains('"100.00"'));
      expect(reportCsvCell('a,"b"\nc'), '"a,""b""\nc"');
      expect(reportCsvCell(-20.0), '"-20.00"');
      expect(reportCsvCell('\t=1+1'), '"\'\t=1+1"');
    },
  );

  test(
    'all report kinds have consistent columns, numeric cells and useful empty states',
    () {
      for (final kind in ReportKind.values) {
        final report = _build(kind, _source());
        expect(report.metrics, isNotEmpty);
        expect(report.basis, isNotEmpty);
        if (kind != ReportKind.forecast) expect(report.rows, isEmpty);
        expect(report.emptyMessage, isNotEmpty);
        expect(
          report.metrics.any(
            (m) => m.value.contains('NaN') || m.value.contains('Infinity'),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'PDF summary renders maximum visible records and long text without overflow',
    () async {
      final source = _source(
        payments: [
          for (var i = 0; i < 80; i++)
            _payment('$i', status: 'paid', received: _now),
        ],
        clients: [
          Client(
            id: 'client',
            workspaceId: 'business',
            name: List.filled(500, 'Long customer name').join('\n'),
          ),
        ],
      );
      for (final kind in [
        ReportKind.overview,
        ReportKind.forecast,
        ReportKind.cash,
        ReportKind.outstanding,
      ]) {
        final forecast = kind == ReportKind.forecast
            ? buildCashflowForecast(
                source: source,
                now: _now,
                assumptions: const CashflowAssumptions(),
              )
            : null;
        final pdf = await buildReportPdf(
          report: forecast?.report ?? _build(kind, source),
          source: source,
          range: forecast?.range ?? _range,
          generatedAt: _now,
        ).timeout(const Duration(seconds: 15));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        if (const bool.fromEnvironment('WRITE_REPORT_PDF_FIXTURE')) {
          await File('/tmp/workloop-report-${kind.name}.pdf').writeAsBytes(pdf);
        }
      }
    },
  );
}
