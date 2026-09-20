/// Current business details for NEW documents. Issued documents keep their
/// own snapshot; these defaults never rewrite commercial history.
class BusinessDocumentDefaults {
  final Map<String, String> business;
  final String? businessStructure;
  final int paymentTermsDays;
  final int quoteValidityDays;
  final int taxRate;
  final String paymentInstructions;

  const BusinessDocumentDefaults({
    required this.business,
    this.businessStructure,
    this.paymentTermsDays = 7,
    this.quoteValidityDays = 30,
    this.taxRate = 0,
    this.paymentInstructions = '',
  });

  factory BusinessDocumentDefaults.fromMaps(
    Map<String, dynamic>? workspace,
    Map<String, dynamic>? settings,
  ) {
    String text(String key) => settings?[key]?.toString().trim() ?? '';
    int days(String key, int fallback, int minimum) =>
        (settings?[key] as num?)?.toInt().clamp(minimum, 365) ?? fallback;
    final vat = (settings?['default_tax_rate'] as num?)?.toInt() ?? 0;
    return BusinessDocumentDefaults(
      business: {
        'name': workspace?['name']?.toString().trim() ?? '',
        'address': text('business_address'),
        'email': text('customer_contact_email'),
        'phone': text('customer_contact_phone'),
        'legal_name': text('business_legal_name'),
        'company_number': text('business_company_number'),
        'vat_number': text('business_vat_number'),
      },
      businessStructure: settings?['business_structure'] as String?,
      paymentTermsDays: days('default_payment_terms_days', 7, 0),
      quoteValidityDays: days('default_quote_validity_days', 30, 1),
      taxRate: const [0, 5, 20].contains(vat) ? vat : 0,
      paymentInstructions: text('default_payment_instructions'),
    );
  }

  List<String> get missingDetails => [
    if ((business['name'] ?? '').isEmpty) 'business name',
    if ((business['legal_name'] ?? '').isEmpty) 'legal name',
    if ((business['address'] ?? '').isEmpty) 'business address',
    if ((business['email'] ?? '').isEmpty && (business['phone'] ?? '').isEmpty)
      'business email or phone',
    if (taxRate > 0 && (business['vat_number'] ?? '').isEmpty) 'VAT number',
  ];

  bool get isReady => missingDetails.isEmpty;
}
