import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/repositories/appointments_repository.dart';
import '../../shared/widgets/slate_ui.dart';

Future<bool> showBookingScheduleWarning(
  BuildContext context,
  AppointmentScheduleReview review,
) async {
  if (!review.hasWarnings) return true;
  final result = await showWorkloopBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SingleChildScrollView(
      child: SlateSheetFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              review.title,
              style: TextStyle(
                color: AppColors.of(sheetContext).t1,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              review.detail,
              style: TextStyle(
                color: AppColors.of(sheetContext).t3,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SlateButton(
              label: 'Book anyway',
              icon: LucideIcons.calendarCheck,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
            const SizedBox(height: AppSpacing.sm),
            SlateButton(
              label: 'Go back',
              secondary: true,
              onPressed: () => Navigator.pop(sheetContext, false),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
