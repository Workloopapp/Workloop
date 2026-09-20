import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import 'report_models.dart';

class ReportMetrics extends StatelessWidget {
  final List<ReportMetric> metrics;
  const ReportMetrics({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopPaperPanel(
      title: 'Your numbers',
      child: Column(
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0) const Divider(height: AppSpacing.lg),
            if (MediaQuery.textScalerOf(context).scale(16) > 21) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  metrics[i].label,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  metrics[i].value,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      metrics[i].label,
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      metrics[i].value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
            if (metrics[i].comparison != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    metrics[i].comparison!,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class ReportRecord extends StatelessWidget {
  final List<String> columns;
  final List<Object> values;
  const ReportRecord({super.key, required this.columns, required this.values});

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reportDisplayCell(values.first, columns.first),
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 1; i < columns.length; i++)
            if (!columns[i].endsWith('ID') && reportCell(values[i]).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${columns[i].replaceAll(' GBP', '')}: ${reportDisplayCell(values[i], columns[i])}',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
