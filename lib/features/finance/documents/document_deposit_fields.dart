import 'package:flutter/material.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import 'business_document.dart';

class DocumentDepositFields extends StatelessWidget {
  final String type;
  final TextEditingController value;
  final DateTime dueDate;
  final int totalPence;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onChanged;
  final VoidCallback onPickDate;

  const DocumentDepositFields({
    super.key,
    required this.type,
    required this.value,
    required this.dueDate,
    required this.totalPence,
    required this.onTypeChanged,
    required this.onChanged,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final requested = documentDepositPence(
      totalPence,
      type,
      parseDocumentMoney(value.text) ?? 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkloopFormField(
          label: 'Request a deposit',
          isRequired: false,
          child: DropdownButtonFormField<String>(
            initialValue: type,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('No deposit')),
              DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
              DropdownMenuItem(
                value: 'percentage',
                child: Text('Percentage of total'),
              ),
            ],
            onChanged: (next) => onTypeChanged(next ?? 'none'),
          ),
        ),
        if (type != 'none') ...[
          const SizedBox(height: 12),
          WorkloopFormField(
            label: type == 'percentage'
                ? 'Deposit percentage'
                : 'Deposit amount',
            isRequired: true,
            child: TextFormField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                prefixText: type == 'fixed' ? '£ ' : null,
                suffixText: type == 'percentage' ? '%' : null,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Deposit due\n${documentDate(dueDate)}'),
            ),
          ),
          Text(
            '${documentMoney(requested)} requested upfront. '
            '${documentMoney((totalPence - requested).clamp(0, totalPence))} follows by the final payment date.',
          ),
          const SizedBox(height: 8),
          const Text('Only record a payment after the money arrives.'),
        ],
      ],
    );
  }
}
