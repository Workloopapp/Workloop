import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import 'settings_helpers.dart';

class SettingsServicesSection extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> services;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final VoidCallback onRetry;
  final bool showAddAction;

  const SettingsServicesSection({
    super.key,
    required this.services,
    required this.onAdd,
    required this.onEdit,
    required this.onRetry,
    this.showAddAction = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            sectionLabel('Services'),
            if (showAddAction)
              WorkloopTextButton(label: 'Add', onPressed: onAdd),
          ],
        ),
        const SizedBox(height: 10),
        services.when(
          loading: () => skeletonBox(context, 60),
          error: (_, _) => SlateErrorState(
            message: 'Services could not be loaded.',
            onRetry: onRetry,
          ),
          data: (data) => data.isEmpty
              ? _EmptyServices(onAdd: onAdd, showAddAction: showAddAction)
              : _ServicesList(services: data, onEdit: onEdit),
        ),
      ],
    );
  }
}

class _EmptyServices extends StatelessWidget {
  final VoidCallback onAdd;
  final bool showAddAction;

  const _EmptyServices({required this.onAdd, required this.showAddAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Text(
            'No services yet',
            style: TextStyle(fontSize: 14, color: AppColors.of(context).t3),
          ),
          if (showAddAction) ...[
            const SizedBox(height: 12),
            WorkloopTextButton(
              label: 'Add your first service',
              onPressed: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}

class _ServicesList extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final ValueChanged<Map<String, dynamic>> onEdit;

  const _ServicesList({required this.services, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: services.asMap().entries.map((entry) {
        final index = entry.key;
        final service = entry.value;
        final isLast = index == services.length - 1;
        final rawPrice = service['price'];
        final price = formatPounds(rawPrice is num ? rawPrice : 0);

        return SlateListRow(
          onTap: () => onEdit(service),
          showDivider: !isLast,
          title: Text(
            service['name'] as String? ?? 'Service',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).t1,
            ),
          ),
          subtitle: Text(
            formatFriendlyDuration(
              (service['duration_mins'] as num?)?.toInt() ?? 60,
            ),
            style: TextStyle(fontSize: 12, color: AppColors.of(context).t3),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                price,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.of(context).t1,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                LucideIcons.pencil,
                size: 14,
                color: AppColors.of(context).t3,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
