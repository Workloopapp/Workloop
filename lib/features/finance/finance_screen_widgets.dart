part of 'finance_screen.dart';

/// Flat disclosure rows keep supporting detail out of the default overview.
class _MoneyDisclosure extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool expanded;
  final VoidCallback onTap;
  const _MoneyDisclosure({
    super.key,
    required this.title,
    this.subtitle,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                  color: tokens.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoneySectionHero extends StatelessWidget {
  final String label;
  final double value;
  final String detail;

  const _MoneySectionHero({
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopPaperPanel(
      title: label,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatPounds(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 30,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  detail,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const WorkloopIllustration(
            kind: WorkloopIllustrationKind.receipt,
            size: 44,
          ),
        ],
      ),
    );
  }
}

class _MoneySummaryFigure extends StatelessWidget {
  final String label;
  final double value;
  final String? detail;
  final bool compact;
  final VoidCallback onTap;

  const _MoneySummaryFigure({
    required this.label,
    required this.value,
    required this.onTap,
    this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View ${label.toLowerCase()}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 48,
            minWidth: double.infinity,
          ),
          child: _figure(context),
        ),
      ),
    );
  }

  Widget _figure(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: tokens.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          formatPounds(value),
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: compact ? 22 : 30,
            fontWeight: FontWeight.w700,
            height: 1.15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            detail!,
            style: TextStyle(color: tokens.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _NetProfitGraphic extends StatelessWidget {
  final List<WorkloopStudioBarDatum> data;
  final String periodLabel;
  final bool showChart;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget breakdown;

  const _NetProfitGraphic({
    required this.data,
    required this.periodLabel,
    this.showChart = true,
    required this.expanded,
    required this.onToggle,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final total = roundToPence(
      data.fold<double>(0, (sum, item) => sum + item.value),
    );
    final spokenData = data
        .map((item) => '${item.label} ${_profitAmount(item.value)}')
        .join(', ');
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Net profit',
          style: TextStyle(color: tokens.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          _profitAmount(total),
          key: const ValueKey('money-net-profit-total'),
          style: TextStyle(
            color: total < 0 ? tokens.error : tokens.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Income minus expenses',
          style: TextStyle(color: tokens.textSecondary, fontSize: 12),
        ),
        const Divider(height: AppSpacing.lg),
        breakdown,
        if (showChart)
          _MoneyDisclosure(
            title: 'Profit trend',
            expanded: expanded,
            onTap: onToggle,
          ),
        if (showChart && expanded) ...[
          const SizedBox(height: AppSpacing.sm),
          _NetProfitBarChart(
            data: data,
            semanticsLabel:
                'Net profit for $periodLabel: ${_profitAmount(total)}. '
                'Income minus expenses. $spokenData',
          ),
        ],
      ],
    );
    return content;
  }
}

String _profitAmount(double value) =>
    value < 0 ? '-${formatPounds(value.abs())}' : formatPounds(value);

/// Signed bars share a zero line so expense-only days cannot look like income.
class _NetProfitBarChart extends StatelessWidget {
  final List<WorkloopStudioBarDatum> data;
  final String semanticsLabel;

  const _NetProfitBarChart({required this.data, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final high = data.fold<double>(
      0,
      (value, row) => math.max(value, row.value),
    );
    final low = data.fold<double>(
      0,
      (value, row) => math.min(value, row.value),
    );
    final extent = high - low;
    const plotHeight = 76.0;
    // Leave a little room at either edge for the zero line and zero-value dots.
    const plotInset = 2.0;
    const plotSpace = plotHeight - plotInset * 2;
    final zeroY =
        plotInset + (extent == 0 ? plotSpace : high / extent * plotSpace);
    final labelStyle = TextStyle(
      color: tokens.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      key: const ValueKey('money-net-profit-chart'),
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              children: [
                for (final item in data)
                  Expanded(
                    child: Text(
                      item.valueLabel ?? _profitAmount(item.value),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle.copyWith(
                        color: item.value < 0
                            ? tokens.error
                            : tokens.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: plotHeight,
              child: Stack(
                children: [
                  Positioned(
                    top: zeroY,
                    left: 0,
                    right: 0,
                    child: Container(
                      key: const ValueKey('money-net-profit-zero-line'),
                      height: 1,
                      color: tokens.divider,
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var index = 0; index < data.length; index++)
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final value = data[index].value;
                                final height = extent == 0
                                    ? 0.0
                                    : value.abs() / extent * plotSpace;
                                return Stack(
                                  children: [
                                    Positioned(
                                      top: value > 0 ? zeroY - height : zeroY,
                                      left:
                                          (constraints.maxWidth -
                                              math.min(
                                                20.0,
                                                constraints.maxWidth * 0.55,
                                              )) /
                                          2,
                                      child: Container(
                                        key: ValueKey(
                                          'money-net-profit-bar-$index',
                                        ),
                                        width: math.min(
                                          20.0,
                                          constraints.maxWidth * 0.55,
                                        ),
                                        height: math.max(1, height),
                                        decoration: BoxDecoration(
                                          color: value < 0
                                              ? tokens.error
                                              : value > 0
                                              ? tokens.accent
                                              : tokens.dividerStrong,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                for (final item in data)
                  Expanded(
                    child: Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeTargetProgress extends StatelessWidget {
  final double made;
  final double target;
  final VoidCallback onEditTarget;

  const _IncomeTargetProgress({
    required this.made,
    required this.target,
    required this.onEditTarget,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final hasTarget = target.isFinite && roundToPence(target) > 0;
    final left = roundToPence(target - made).clamp(0, double.infinity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          WorkloopIncomeTargetIndicator(
            amount: made,
            target: target,
            size: 40,
            fontSize: 12,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkloopSectionHeader(
                  label: 'Monthly target',
                  quiet: true,
                  actionLabel: hasTarget ? 'Edit' : 'Set target',
                  onAction: onEditTarget,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hasTarget
                      ? left > 0
                            ? '${formatPounds(left)} left to reach ${formatPounds(target)}'
                            : 'Target reached'
                      : 'Set a target to track progress.',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietMoneyState extends StatelessWidget {
  const _QuietMoneyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(LucideIcons.check, color: AppColors.of(context).t3, size: 17),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Nothing waiting to be collected.',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
