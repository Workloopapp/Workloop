import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';

Widget sectionLabel(String text) => WorkloopCaption(text);

Widget infoRow(BuildContext context, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 14, color: AppColors.of(context).t2),
      ),
      Flexible(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.of(context).t1,
          ),
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  ),
);

Widget tappableRow(
  BuildContext context, {
  required String label,
  required String value,
  required VoidCallback onTap,
  Color? valueColor,
}) => Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: AppColors.of(context).t2),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: valueColor ?? AppColors.of(context).t1,
            ),
          ),
          const SizedBox(width: 8),
          Icon(LucideIcons.pencil, size: 14, color: AppColors.of(context).t3),
        ],
      ),
    ),
  ),
);

Widget skeletonBox(BuildContext context, double height) => Container(
  height: height,
  decoration: BoxDecoration(
    color: AppColors.of(context).t1.withValues(alpha: 0.035),
    borderRadius: BorderRadius.circular(AppRadius.md),
  ),
);

Widget saveBtn(
  BuildContext context, {
  required String label,
  required VoidCallback onTap,
  bool loading = false,
  bool disabled = false,
  Color? color,
}) {
  final palette = AppColors.of(context);
  final effectiveColor = color ?? palette.accentPrimaryStrong;
  final foregroundColor = effectiveColor == palette.accentPrimaryStrong
      ? palette.onBrandAccent
      : palette.bg;
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: loading || disabled ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: effectiveColor,
        foregroundColor: foregroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        elevation: 0,
      ),
      child: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: foregroundColor,
                strokeWidth: 2,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
    ),
  );
}

Widget cancelBtn(BuildContext context) => SizedBox(
  width: double.infinity,
  height: 52,
  child: TextButton(
    onPressed: () => Navigator.pop(context),
    child: Text(
      'Cancel',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.of(context).t3,
      ),
    ),
  ),
);

Widget settingsField(
  BuildContext context, {
  required String label,
  required TextEditingController controller,
  bool? isRequired,
  String? hint,
  TextInputType? keyboardType,
  bool autofocus = false,
  int maxLines = 1,
  int? maxLength,
  String? errorText,
  String? helperText,
}) => WorkloopFormField(
  label: label,
  isRequired: isRequired,
  child: TextField(
    controller: controller,
    keyboardType: keyboardType,
    autofocus: autofocus,
    maxLines: maxLines,
    maxLength: maxLength,
    style: TextStyle(color: AppColors.of(context).t1, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      errorText: errorText,
      helperText: helperText,
      counterText: maxLength == null ? null : '',
      hintStyle: TextStyle(color: AppColors.of(context).t3),
      filled: true,
      fillColor: AppColors.of(context).t1.withValues(alpha: 0.028),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.of(context).border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.of(context).border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.of(context).accentPrimary,
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  ),
);
