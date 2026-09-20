import 'package:flutter/material.dart';

import '../utils/currency_format.dart';
import 'slate_ui.dart';
import 'workloop_studio_graphics.dart';

/// One monthly-target indicator for Today and Money. The ring is bounded, but
/// the percentage can exceed 100 once the owner has passed their target.
class WorkloopIncomeTargetIndicator extends StatelessWidget {
  final double amount;
  final double target;
  final double size;
  final double fontSize;

  const WorkloopIncomeTargetIndicator({
    super.key,
    required this.amount,
    required this.target,
    this.size = 56,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final goal = roundToPence(target);
    final received = roundToPence(amount);
    final hasTarget = goal.isFinite && goal > 0;
    final ratio = hasTarget ? received / goal : 0.0;
    final available =
        amount.isFinite && ratio.isFinite && (ratio * 100).isFinite;
    final fraction = available ? ratio.clamp(0.0, double.infinity) : 0.0;
    // Do not round a value just below the goal up to "100%".
    final percentage = (fraction * 100).floor();
    final colour = !hasTarget || !available
        ? tokens.divider
        : fraction >= 1
        ? tokens.success
        : fraction >= 0.5
        ? tokens.warning
        : tokens.error;
    final label = !hasTarget
        ? 'Monthly target not set'
        : !available
        ? 'Monthly target progress unavailable'
        : '$percentage percent of monthly target. '
              '${fraction >= 1 ? 'Target reached.' : 'Target not yet reached.'}';

    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: WorkloopStudioProgressArc(
          progress: fraction.clamp(0.0, 1.0),
          color: colour,
          size: size,
          strokeWidth: size <= 46 ? 4 : 6,
          child: Text(
            hasTarget && available ? '$percentage%' : '—',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
