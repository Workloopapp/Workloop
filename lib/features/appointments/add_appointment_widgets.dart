part of 'add_appointment_screen.dart';

class _PickedAppointmentTime {
  final int hour;
  final int minute;

  const _PickedAppointmentTime({required this.hour, required this.minute});
}

Future<_PickedAppointmentTime?> _showAppointmentTimePicker({
  required BuildContext context,
  required int initialHour,
  required int initialMinute,
}) {
  int tempHour = initialHour;
  int tempMinute = initialMinute;

  return showWorkloopBottomSheet<_PickedAppointmentTime>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setModal) => SlateSheetFrame(
        child: SizedBox(
          height: 240,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.of(context).t1,
                      ),
                    ),
                    WorkloopTextButton(
                      label: 'Done',
                      onPressed: () => Navigator.pop(
                        context,
                        _PickedAppointmentTime(
                          hour: tempHour,
                          minute: tempMinute,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        itemExtent: 48,
                        perspective: 0.003,
                        diameterRatio: 1.8,
                        physics: const FixedExtentScrollPhysics(),
                        controller: FixedExtentScrollController(
                          initialItem: tempHour,
                        ),
                        onSelectedItemChanged: (i) =>
                            setModal(() => tempHour = i),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 24,
                          builder: (context, i) {
                            final selected = i == tempHour;
                            return Center(
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: selected ? 24 : 18,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected
                                      ? AppColors.of(context).t1
                                      : AppColors.of(context).t3,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Text(
                      ':',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.of(context).t1,
                      ),
                    ),
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        itemExtent: 48,
                        perspective: 0.003,
                        diameterRatio: 1.8,
                        physics: const FixedExtentScrollPhysics(),
                        controller: FixedExtentScrollController(
                          initialItem: tempMinute ~/ 15,
                        ),
                        onSelectedItemChanged: (i) =>
                            setModal(() => tempMinute = i * 15),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 4,
                          builder: (context, i) {
                            final min = i * 15;
                            final selected = min == tempMinute;
                            return Center(
                              child: Text(
                                min.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: selected ? 24 : 18,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected
                                      ? AppColors.of(context).t1
                                      : AppColors.of(context).t3,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AppointmentSectionLabel extends StatelessWidget {
  final String text;
  final String? subtitle;
  final bool isRequired;

  const _AppointmentSectionLabel(
    this.text, {
    this.subtitle,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = text
        .toLowerCase()
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopFieldLabel(
          label,
          isRequired: isRequired,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.12,
            color: AppColors.of(context).t1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _BookingSaveAction extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _BookingSaveAction({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.of(context).modCalendar.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: enabled && !loading ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 58,
            minHeight: AppSpacing.minTouch,
          ),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: AppColors.of(context).modCalendar,
                      strokeWidth: 2,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: enabled
                            ? AppColors.of(context).modCalendar
                            : AppColors.of(context).t4,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AppointmentSkeleton extends StatelessWidget {
  final double height;

  const _AppointmentSkeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );
  }
}

class _AppointmentErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AppointmentErrorBox(this.message, {required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.circleAlert,
            color: AppColors.of(context).error,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.of(context).error,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _ResponsiveBookingPair extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _ResponsiveBookingPair({required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBody = MediaQuery.textScalerOf(context).scale(14);
        final stacked = constraints.maxWidth < 360 || scaledBody > 18;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 10), second],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _AppointmentTextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? prefix;
  final String? suffix;
  final String? label;
  final bool isRequired;
  final IconData? icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _AppointmentTextInput({
    required this.controller,
    required this.hint,
    this.prefix,
    this.suffix,
    this.label,
    this.isRequired = false,
    this.icon,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          WorkloopFieldLabel(
            label!,
            isRequired: isRequired,
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: TextStyle(color: AppColors.of(context).t1, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            prefixIcon: icon == null
                ? null
                : Icon(icon, color: AppColors.of(context).t3, size: 18),
            suffixText: suffix,
            prefixStyle: TextStyle(color: AppColors.of(context).t2),
            suffixStyle: TextStyle(color: AppColors.of(context).t3),
            hintStyle: TextStyle(
              color: AppColors.of(context).t3,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: AppColors.of(context).bgCard.withValues(alpha: 0.72),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.of(context).border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.of(context).border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(
                color: AppColors.of(context).accentPrimary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentDueToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PaymentDueToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.of(context).t1.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              color: AppColors.of(context).t2,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create payment due',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(context).t1,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Adds an unpaid Money item linked to this booking.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.of(context).t3,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _AppointmentAddOnSelector extends StatelessWidget {
  final List<ServiceAddOn> addOns;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onChanged;

  const _AppointmentAddOnSelector({
    required this.addOns,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optional add-ons',
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Add any extras included in this booking.',
            style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final addOn in addOns)
            Semantics(
              checked: selectedIds.contains(addOn.id),
              child: CheckboxListTile(
                value: selectedIds.contains(addOn.id),
                onChanged: (value) => onChanged(addOn.id, value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(
                  addOn.name,
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  [
                    if (addOn.durationMins > 0)
                      '+${formatFriendlyDuration(addOn.durationMins)}',
                    if (addOn.price > 0) '+${formatPounds(addOn.price)}',
                  ].join(' · '),
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
