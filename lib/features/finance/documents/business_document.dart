/// Document amounts use integer pence. Displayed totals must agree with the
/// server's per-line rounding; floating point never drives a saved total.
int? parseDocumentMoney(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

String documentMoneyInput(int pence) =>
    '${pence < 0 ? '-' : ''}${pence.abs() ~/ 100}.${(pence.abs() % 100).toString().padLeft(2, '0')}';

String documentMoney(int pence) => '£${documentMoneyInput(pence)}';

String documentDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

int _pence(dynamic value) => ((num.tryParse('$value') ?? 0) * 100).round();

int documentDepositPence(int totalPence, String type, int valueHundredths) =>
    type == 'percentage'
    ? (totalPence * valueHundredths + 5000) ~/ 10000
    : type == 'fixed'
    ? valueHundredths
    : 0;

({int subtotal, int tax, int total}) documentTotals(
  Iterable<BusinessDocumentItem> items,
  int taxRate,
  bool pricesIncludeVat,
) {
  var amount = 0;
  var extractedVat = 0;
  for (final item in items) {
    amount += item.totalPence;
    if (pricesIncludeVat) {
      extractedVat += item.includedVatPence(taxRate);
    }
  }
  if (pricesIncludeVat) {
    return (subtotal: amount - extractedVat, tax: extractedVat, total: amount);
  }
  final tax = (amount * taxRate + 50) ~/ 100;
  return (subtotal: amount, tax: tax, total: amount + tax);
}

class BusinessDocumentItem {
  final String description;
  final int quantityHundredths;
  final int unitPricePence;

  const BusinessDocumentItem({
    required this.description,
    required this.quantityHundredths,
    required this.unitPricePence,
  });

  int get totalPence => (quantityHundredths * unitPricePence + 50) ~/ 100;
  int includedVatPence(int rate) =>
      (totalPence * rate + (100 + rate) ~/ 2) ~/ (100 + rate);
  int netTotalPence(int rate, bool inclusive) =>
      inclusive ? totalPence - includedVatPence(rate) : totalPence;
  String netUnitPrice(int rate, bool inclusive) {
    if (!inclusive || rate == 0) return documentMoney(unitPricePence);
    // Four decimal places retain fractions of a penny in VAT-exclusive units.
    final tenThousandths =
        (unitPricePence * 10000 + (100 + rate) ~/ 2) ~/ (100 + rate);
    return '£${tenThousandths ~/ 10000}.${(tenThousandths % 10000).toString().padLeft(4, '0')}';
  }

  String get quantity => documentMoneyInput(
    quantityHundredths,
  ).replaceFirst(RegExp(r'\.?0+$'), '');

  factory BusinessDocumentItem.fromMap(Map<String, dynamic> row) =>
      BusinessDocumentItem(
        description: row['description'] as String? ?? '',
        quantityHundredths: _pence(row['quantity']),
        unitPricePence: _pence(row['unit_price']),
      );

  Map<String, dynamic> toMap() => {
    'description': description.trim(),
    'quantity': documentMoneyInput(quantityHundredths),
    'unit_price': documentMoneyInput(unitPricePence),
  };
}

class BusinessDocument {
  final String id;
  final String workspaceId;
  final String type;
  final String status;
  final String? number;
  final String? contactId;
  final String? appointmentId;
  final String? invoiceId;
  final String? sourceQuoteId;
  final DateTime issueDate;
  final DateTime? dueDate;
  final DateTime? serviceDate;
  final DateTime? issuedAt;
  final int revision;
  final int taxRate;
  final int subtotalPence;
  final int taxPence;
  final int totalPence;
  final Map<String, String> business;
  final Map<String, String> customer;
  final String notes;
  final String paymentInstructions;
  final List<BusinessDocumentItem> items;
  final String depositType;
  final int depositValueHundredths;
  final int depositPence;
  final DateTime? depositDueDate;
  final int? amountPaidPence;
  final bool pricesIncludeVat;

  const BusinessDocument({
    required this.id,
    required this.workspaceId,
    required this.type,
    required this.status,
    required this.issueDate,
    required this.revision,
    required this.taxRate,
    required this.subtotalPence,
    required this.taxPence,
    required this.totalPence,
    required this.business,
    required this.customer,
    required this.items,
    this.number,
    this.contactId,
    this.appointmentId,
    this.invoiceId,
    this.sourceQuoteId,
    this.dueDate,
    this.serviceDate,
    this.issuedAt,
    this.notes = '',
    this.paymentInstructions = '',
    this.depositType = 'none',
    this.depositValueHundredths = 0,
    this.depositPence = 0,
    this.depositDueDate,
    this.amountPaidPence,
    this.pricesIncludeVat = false,
  });

  bool get isQuote => type == 'quote';
  bool get isDraft => issuedAt == null && status == 'draft';
  String get title => isQuote ? 'Quote' : 'Invoice';
  String get reference => number ?? 'Draft ${title.toLowerCase()}';
  String get customerName => customer['name'] ?? 'Client';
  bool get hasDeposit => depositPence > 0;
  bool get showsVat =>
      taxRate > 0 || (business['vat_number'] ?? '').trim().isNotEmpty;
  int? get outstandingPence => amountPaidPence == null
      ? null
      : (totalPence - amountPaidPence!).clamp(0, totalPence);
  int? get depositOutstandingPence => amountPaidPence == null
      ? null
      : (depositPence - amountPaidPence!).clamp(0, depositPence);

  List<String> get missingIssueDetails => [
    if ((business['name'] ?? '').trim().isEmpty) 'business name',
    if ((business['address'] ?? '').trim().isEmpty) 'business address',
    if ((customer['name'] ?? '').trim().isEmpty) 'customer name',
    if ((customer['address'] ?? '').trim().isEmpty) 'customer address',
    if (!isQuote && (business['legal_name'] ?? '').trim().isEmpty) 'legal name',
    if (!isQuote &&
        (business['email'] ?? '').trim().isEmpty &&
        (business['phone'] ?? '').trim().isEmpty)
      'business contact email or phone',
    if (!isQuote && serviceDate == null) 'supply date',
    if (dueDate == null || dueDate!.isBefore(issueDate))
      isQuote ? 'quote validity date' : 'valid payment date',
    if (taxRate > 0 && (business['vat_number'] ?? '').trim().isEmpty)
      'VAT registration number',
    if (totalPence <= 0 || items.isEmpty) 'items with a positive total',
    if (hasDeposit &&
        (depositDueDate == null ||
            depositDueDate!.isBefore(issueDate) ||
            (dueDate != null && depositDueDate!.isAfter(dueDate!))))
      'deposit due date',
  ];

  String statusLabel({DateTime? now}) {
    if (isDraft) return 'Draft';
    if (status == 'cancelled') return 'Cancelled';
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    if (isQuote) {
      if (status == 'accepted') return 'Accepted';
      if (status == 'declined') return 'Declined';
      if (dueDate?.isBefore(day) ?? false) return 'Expired';
      return 'Awaiting response';
    }
    if (status == 'paid' || outstandingPence == 0) return 'Paid';
    if (amountPaidPence == null) return 'Issued';
    if (dueDate?.isBefore(day) ?? false) return 'Overdue';
    if ((depositOutstandingPence ?? 0) > 0) {
      if (depositDueDate?.isBefore(day) ?? false) return 'Deposit overdue';
      return 'Deposit due';
    }
    if ((amountPaidPence ?? 0) > 0) return 'Part paid';
    return 'Awaiting payment';
  }

  factory BusinessDocument.fromMap(Map<String, dynamic> row) {
    Map<String, String> snapshot(dynamic value) => value is Map
        ? value.map((key, value) => MapEntry('$key', value?.toString() ?? ''))
        : {};
    DateTime? date(dynamic value) => DateTime.tryParse('$value');
    final payment = row['payment_state'];
    final paid =
        row['amount_paid'] ?? (payment is Map ? payment['amount_paid'] : null);
    return BusinessDocument(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      type: row['type'] as String? ?? 'invoice',
      status: row['status'] as String? ?? 'draft',
      number: row['invoice_number'] as String?,
      contactId: row['contact_id'] as String?,
      appointmentId: row['appointment_id'] as String?,
      invoiceId: row['invoice_id'] as String?,
      sourceQuoteId: row['source_quote_id'] as String?,
      issueDate: date(row['issue_date']) ?? DateTime(1970),
      dueDate: date(row['due_date']),
      serviceDate: date(row['service_date']),
      issuedAt: date(row['issued_at']),
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      taxRate: (row['tax_rate'] as num?)?.toInt() ?? 0,
      subtotalPence: _pence(row['subtotal']),
      taxPence: _pence(row['tax_amount']),
      totalPence: _pence(row['total']),
      business: snapshot(row['business_snapshot']),
      customer: snapshot(row['client_snapshot']),
      notes: row['notes'] as String? ?? '',
      paymentInstructions: row['payment_instructions'] as String? ?? '',
      depositType: row['deposit_type'] as String? ?? 'none',
      depositValueHundredths: _pence(row['deposit_value']),
      depositPence: _pence(row['deposit_amount']),
      depositDueDate: date(row['deposit_due_date']),
      amountPaidPence: paid == null ? null : _pence(paid),
      pricesIncludeVat: row['prices_include_vat'] as bool? ?? false,
      items: (row['items'] as List? ?? const [])
          .map(
            (item) => BusinessDocumentItem.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}
