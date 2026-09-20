import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/utils/appointment_recurrence.dart';
import '../../shared/utils/booking_time.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';

/// A deliberately finite series: every saved occurrence is a normal booking,
/// so moving or skipping one cannot regenerate it or change its neighbours.
class RecurringBookingFields extends StatelessWidget {
  final int intervalWeeks;
  final int occurrences;
  final DateTime firstWallClock;
  final String? timezoneName;
  final ValueChanged<int> onIntervalChanged;
  final ValueChanged<int> onOccurrencesChanged;

  const RecurringBookingFields({
    super.key,
    required this.intervalWeeks,
    required this.occurrences,
    required this.firstWallClock,
    required this.timezoneName,
    required this.onIntervalChanged,
    required this.onOccurrencesChanged,
  });

  String get _summary {
    if (timezoneName == null || timezoneName!.trim().isEmpty) {
      return 'Set a business timezone in Settings before repeating bookings.';
    }
    try {
      final first = recurringBookingInstant(firstWallClock, timezoneName!);
      // Check every occurrence, including an intermediate daylight-saving gap.
      DateTime last = first;
      for (var index = 1; index < occurrences; index++) {
        last = appointmentOccurrenceStart(
          first,
          'FREQ=WEEKLY;INTERVAL=$intervalWeeks',
          index,
          timezoneName: timezoneName,
        );
      }
      final civil = bookingTimeInZone(last, timezoneName!);
      return '$occurrences bookings · last on ${civil.day}/${civil.month}/${civil.year}\n'
          '${timezoneName!} time. Move or cancel any one booking separately.';
    } on RecurringBookingTimeException catch (error) {
      return error.message;
    } on ArgumentError {
      return 'Your business timezone is unavailable. Check it in Settings.';
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const WorkloopFieldLabel(
        'Repeat',
        isRequired: false,
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final interval in [0, 1, 2, 3, 4])
            WorkloopFilterChip(
              label: interval == 0
                  ? 'Once'
                  : interval == 1
                  ? 'Weekly'
                  : 'Every $interval weeks',
              selected: intervalWeeks == interval,
              onTap: () => onIntervalChanged(interval),
            ),
        ],
      ),
      if (intervalWeeks > 0) ...[
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            const Expanded(
              child: WorkloopFieldLabel('Number of bookings', isRequired: true),
            ),
            IconButton(
              tooltip: 'Fewer bookings',
              onPressed: occurrences > 2
                  ? () => onOccurrencesChanged(occurrences - 1)
                  : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Semantics(
              liveRegion: true,
              label: '$occurrences bookings including the first',
              child: Text('$occurrences'),
            ),
            IconButton(
              tooltip: 'More bookings',
              onPressed: occurrences < 24
                  ? () => onOccurrencesChanged(occurrences + 1)
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Text(
          _summary,
          style: TextStyle(
            color:
                (Theme.of(context).extension<WorkloopThemeTokens>() ??
                        WorkloopThemeTokens.light)
                    .textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    ],
  );
}
