import 'package:flutter/material.dart';

import '../models/slate_models.dart';
import '../utils/currency_format.dart';
import '../utils/duration_format.dart';
import 'slate_ui.dart';
import 'workloop_form_field.dart';

/// Adds catalogue services to the existing primary service for one booking.
/// The first ID stays the primary relationship used by older app versions.
/// Repeated IDs represent repeated occurrences of the same service.
class AdditionalServicesPicker extends StatelessWidget {
  final List<Service> services;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const AdditionalServicesPicker({
    super.key,
    required this.services,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedIds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedIds.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in selectedIds.indexed.skip(1))
                InputChip(
                  label: Text(
                    services
                            .where((service) => service.id == entry.$2)
                            .firstOrNull
                            ?.name ??
                        'Service',
                  ),
                  onDeleted: () {
                    final updated = List<String>.of(selectedIds)
                      ..removeAt(entry.$1);
                    onChanged(updated);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (services.isNotEmpty && selectedIds.length < 8)
          WorkloopFormField(
            label: 'Additional services',
            isRequired: false,
            child: WorkloopPickerField<String>(
              value: null,
              title: 'Add another service',
              hint: 'Add another service',
              searchHint: 'Search services',
              options: [
                for (final service in services)
                  WorkloopPickerOption(
                    value: service.id,
                    label: service.name,
                    subtitle: [
                      formatFriendlyDuration(service.durationMins),
                      formatPounds(service.price),
                      if (selectedIds
                          .where((id) => id == service.id)
                          .isNotEmpty)
                        '${selectedIds.where((id) => id == service.id).length} already added',
                    ].join(' · '),
                  ),
              ],
              onChanged: (id) {
                onChanged([...selectedIds, id]);
              },
            ),
          ),
      ],
    );
  }
}
