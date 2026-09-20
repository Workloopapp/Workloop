import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/finance_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/slate_ui.dart';

enum FinancePeriod { week, month, custom }

class MoneyPeriodSwitcher extends StatelessWidget {
  final FinancePeriod selected;
  final String? customLabel;
  final ValueChanged<FinancePeriod> onSelected;

  const MoneyPeriodSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    const segments = [
      WorkloopSegment(value: FinancePeriod.week, label: 'Week'),
      WorkloopSegment(value: FinancePeriod.month, label: 'Month'),
      WorkloopSegment(value: FinancePeriod.custom, label: 'Custom'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        var segmentWidth = AppSpacing.minTouch;
        for (final segment in segments) {
          final label = TextPainter(
            text: TextSpan(
              text: segment.label,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          segmentWidth = math.max(segmentWidth, label.width + 24);
          label.dispose();
        }
        final width = math.max(
          constraints.maxWidth,
          segmentWidth * segments.length,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: WorkloopNavigationControl<FinancePeriod>(
                  selected: selected,
                  segments: segments,
                  onChanged: onSelected,
                  enableSwipeSelection: width <= constraints.maxWidth,
                ),
              ),
            ),
            if (selected == FinancePeriod.custom &&
                customLabel?.trim().isNotEmpty == true)
              TextButton(
                key: const ValueKey('money-custom-date-range'),
                onPressed: () => onSelected(FinancePeriod.custom),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  minimumSize: const Size(0, AppSpacing.minTouch),
                  foregroundColor: SlateTheme.of(context).textSecondary,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        customLabel!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Text('Change', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class ExpenseCategorySummary extends StatelessWidget {
  final PeriodMoneySummary summary;
  final bool showHeading;

  const ExpenseCategorySummary({
    super.key,
    required this.summary,
    this.showHeading = true,
  });

  @override
  Widget build(BuildContext context) {
    final categories = summary.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          const WorkloopSectionHeader(label: 'Spending by category'),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (categories.isEmpty)
          Text(
            'No expenses in this period.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).t3,
            ),
          )
        else
          ...categories
              .take(4)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CategoryBar(
                    label: entry.key,
                    amount: entry.value,
                    total: summary.expenses,
                  ),
                ),
              ),
      ],
    );
  }
}

class DatePickTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const DatePickTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $value',
      hint: 'Choose date',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.of(context).bgInteract,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: AppColors.of(context).border),
          ),
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.of(context).t3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.of(context).t1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ModePills extends StatelessWidget {
  final String selected;
  final Map<String, String> options;
  final ValueChanged<String> onSelected;

  const ModePills({
    super.key,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopSegmentedControl<String>(
      selected: selected,
      segments: options.entries
          .map(
            (entry) =>
                WorkloopSegment<String>(value: entry.key, label: entry.value),
          )
          .toList(growable: false),
      onChanged: onSelected,
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String label;
  final double amount;
  final double total;

  const _CategoryBar({
    required this.label,
    required this.amount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.of(context).t2,
                ),
              ),
            ),
            Text(
              formatPounds(amount),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.of(context).t1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.capsule),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress,
            backgroundColor: AppColors.of(context).t1.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(AppColors.of(context).t1),
          ),
        ),
      ],
    );
  }
}
