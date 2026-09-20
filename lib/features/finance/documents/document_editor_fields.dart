import 'package:flutter/material.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import 'business_document.dart';

class DocumentTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool? isRequired;
  final String? helperText;
  final int maxLines;
  final int maxLength;
  final TextInputType? keyboardType;
  const DocumentTextField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.isRequired,
    this.helperText,
    this.maxLines = 1,
    this.maxLength = 200,
    this.keyboardType,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: WorkloopFormField(
      label: label,
      isRequired: isRequired ?? required,
      helperText: helperText,
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        decoration: const InputDecoration(counterText: ''),
        validator: (value) =>
            required && (value?.trim().isEmpty ?? true) ? 'Enter $label' : null,
      ),
    ),
  );
}

class DocumentLineControllers {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();
  DocumentLineControllers();
  DocumentLineControllers.fromItem(BusinessDocumentItem item) {
    description.text = item.description;
    quantity.text = item.quantity;
    price.text = documentMoneyInput(item.unitPricePence);
  }
  BusinessDocumentItem? get item {
    final count = parseDocumentMoney(quantity.text);
    final amount = parseDocumentMoney(price.text);
    if (count == null || count <= 0 || count > 1000000 || amount == null) {
      return null;
    }
    return BusinessDocumentItem(
      description: description.text.trim(),
      quantityHundredths: count,
      unitPricePence: amount,
    );
  }

  void dispose() {
    description.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class DocumentLineEditor extends StatelessWidget {
  final DocumentLineControllers line;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  const DocumentLineEditor({
    super.key,
    required this.line,
    required this.index,
    required this.onChanged,
    this.onRemove,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Item ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove item ${index + 1}',
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      DocumentTextField(
        controller: line.description,
        label: 'Description',
        required: true,
        maxLength: 300,
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: WorkloopFormField(
              label: 'Quantity',
              isRequired: true,
              child: TextFormField(
                controller: line.quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => onChanged(),
                validator: (_) {
                  final value = parseDocumentMoney(line.quantity.text);
                  return value == null || value <= 0 || value > 1000000
                      ? 'Use 0.01–10,000'
                      : null;
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WorkloopFormField(
              label: 'Unit price',
              isRequired: true,
              child: TextFormField(
                controller: line.price,
                decoration: const InputDecoration(prefixText: '£ '),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => onChanged(),
                validator: (_) => parseDocumentMoney(line.price.text) == null
                    ? 'Enter a valid price'
                    : null,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Divider(),
    ],
  );
}
