import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Explicit wording for native controls that use a string label.
String workloopFieldLabel(String label, {required bool isRequired}) =>
    '$label (${isRequired ? 'required' : 'optional'})';

/// A field name and its requirement, using words as well as visual emphasis.
/// The separate texts wrap at large text sizes without shrinking either label.
class WorkloopFieldLabel extends StatelessWidget {
  final String label;
  final bool? isRequired;
  final TextStyle? style;

  const WorkloopFieldLabel(
    this.label, {
    super.key,
    this.isRequired,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      label: isRequired == null
          ? label
          : workloopFieldLabel(label, isRequired: isRequired!),
      child: ExcludeSemantics(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            Text(label, style: style ?? theme.textTheme.labelLarge),
            if (isRequired != null)
              Text(
                isRequired! ? 'Required' : 'Optional',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isRequired! ? colors.t1 : colors.t2,
                  fontWeight: isRequired! ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A persistent, wrapping label above a form control. The child should omit its
/// floating label so long labels never collide with the control's outline.
class WorkloopFormField extends StatelessWidget {
  final String label;
  final String? helperText;

  /// Null leaves non-form controls and legacy callers unannotated. Callers
  /// declare this from their save rules; the widget never infers validation.
  final bool? isRequired;
  final Widget child;

  const WorkloopFormField({
    super.key,
    required this.label,
    required this.child,
    this.helperText,
    this.isRequired,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: WorkloopFieldLabel(label, isRequired: isRequired),
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: isRequired == null
              ? label
              : workloopFieldLabel(label, isRequired: isRequired!),
          child: child,
        ),
        if (helperText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(helperText!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
