import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/workloop_form_field.dart';

class MoneyFormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool? isRequired;

  const MoneyFormSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.isRequired,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopFieldLabel(
          title,
          isRequired: isRequired,
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle!,
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class MoneyAmountField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const MoneyAmountField({super.key, required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<WorkloopThemeTokens>() ??
        WorkloopThemeTokens.dark;
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      style: TextStyle(
        color: AppColors.of(context).t1,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
      decoration: InputDecoration(
        prefixText: '£ ',
        prefixStyle: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 25,
          fontWeight: FontWeight.w600,
        ),
        hintText: '0.00',
        hintStyle: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.of(context).t1.withValues(alpha: 0.035),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: _border(AppColors.of(context).border),
        enabledBorder: _border(AppColors.of(context).border),
        focusedBorder: _border(tokens.accentInk, width: 1.5),
      ),
    );
  }
}

class MoneyTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isRequired;
  final IconData icon;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const MoneyTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.isRequired = false,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopFormField(
      label: label,
      isRequired: isRequired,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 2 : 1,
        textCapitalization: TextCapitalization.sentences,
        onChanged: onChanged,
        style: TextStyle(color: AppColors.of(context).t1, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Padding(
            padding: EdgeInsets.only(bottom: maxLines > 1 ? 34 : 0),
            child: Icon(icon, size: 17, color: AppColors.of(context).t3),
          ),
        ),
      ),
    );
  }
}

class MoneyDateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData icon;
  final bool? isRequired;

  const MoneyDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = LucideIcons.calendar,
    this.isRequired,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.of(context).t1.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.of(context).border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.of(context).t3, size: 17),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WorkloopFieldLabel(
                    label,
                    isRequired: isRequired,
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: AppColors.of(context).t1,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: AppColors.of(context).t3,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class MoneySaveAction extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const MoneySaveAction({
    super.key,
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: enabled && !loading ? onTap : null,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.of(context).t1,
        disabledForegroundColor: AppColors.of(context).t4,
        minimumSize: const Size(56, AppSpacing.minTouch),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: loading
          ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
    );
  }
}

OutlineInputBorder _border(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: color, width: width),
  );
}
