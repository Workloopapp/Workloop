import 'package:flutter/material.dart';

import 'business_document.dart';

/// The immutable work, parties and terms sit below the document's next action.
class BusinessDocumentBody extends StatelessWidget {
  const BusinessDocumentBody({super.key, required this.document});
  final BusinessDocument document;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      if (document.pricesIncludeVat && document.taxRate > 0)
        const Text('Item prices include VAT'),
      for (final item in document.items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${item.description}\n${item.quantity} × ${documentMoney(item.unitPricePence)}',
                ),
              ),
              const SizedBox(width: 12),
              Text(documentMoney(item.totalPence)),
            ],
          ),
        ),
      const Divider(),
      Text(
        'Subtotal ${documentMoney(document.subtotalPence)}${document.showsVat ? '\nVAT (${document.taxRate}%) ${documentMoney(document.taxPence)}' : ''}',
        textAlign: TextAlign.right,
      ),
      const SizedBox(height: 24),
      Text(
        'From\n${[document.business['name'], document.business['legal_name'], document.business['address'], document.business['email'], document.business['phone']].whereType<String>().where((value) => value.isNotEmpty).join('\n')}',
      ),
      const SizedBox(height: 16),
      Text(
        'To\n${[document.customer['name'], document.customer['address'], document.customer['email'], document.customer['phone']].whereType<String>().where((value) => value.isNotEmpty).join('\n')}',
      ),
      const SizedBox(height: 16),
      if (document.dueDate != null)
        Text(
          '${document.isQuote ? 'Valid until' : 'Payment due'}: ${documentDate(document.dueDate!)}',
        ),
      if (document.serviceDate != null)
        Text(
          '${document.isQuote ? 'Planned work' : 'Supply date'}: ${documentDate(document.serviceDate!)}',
        ),
      if (document.paymentInstructions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _LabeledText(
            label: 'Payment instructions',
            text: document.paymentInstructions,
          ),
        ),
      if (document.notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _LabeledText(label: 'Notes and terms', text: document.notes),
        ),
      const SizedBox(height: 24),
    ],
  );
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({required this.label, required this.text});
  final String label;
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(text),
    ],
  );
}
