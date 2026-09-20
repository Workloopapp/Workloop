import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/utils/working_hours.dart';

const List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const Map<String, String> _dayLabels = {
  'Mon': 'Monday',
  'Tue': 'Tuesday',
  'Wed': 'Wednesday',
  'Thu': 'Thursday',
  'Fri': 'Friday',
  'Sat': 'Saturday',
  'Sun': 'Sunday',
};

const Map<String, dynamic> _defaultHours = {
  'Mon': {'enabled': true, 'open': '09:00', 'close': '18:00'},
  'Tue': {'enabled': true, 'open': '09:00', 'close': '18:00'},
  'Wed': {'enabled': true, 'open': '09:00', 'close': '18:00'},
  'Thu': {'enabled': true, 'open': '09:00', 'close': '18:00'},
  'Fri': {'enabled': true, 'open': '09:00', 'close': '17:00'},
  'Sat': {'enabled': true, 'open': '09:00', 'close': '14:00'},
  'Sun': {'enabled': false, 'open': '09:00', 'close': '17:00'},
};

class ObHours extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const ObHours({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<ObHours> createState() => _ObHoursState();
}

class _ObHoursState extends ConsumerState<ObHours> {
  late Map<String, Map<String, dynamic>> _hours;
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingProvider).workingHours;
    _hours = {
      for (var day in _days)
        day: Map<String, dynamic>.from(
          draft[day] as Map? ?? _defaultHours[day] as Map,
        ),
    };
  }

  Future<void> _pickTime(String day, String type) async {
    final current = _hours[day]![type] as String;
    final parts = current.split(':');
    final picked = await showWorkloopTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      title: type == 'open' ? 'Choose opening time' : 'Choose closing time',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hours[day]![type] =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  void _continue() {
    final errors = validateWorkingHours(_hours);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    ref.read(onboardingProvider.notifier).setWorkingHours(_hours);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 580;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: compact ? AppSpacing.xs : AppSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  'When do you work?',
                  style: textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'All days can be off. Close after opening.',
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, weekConstraints) {
                    // Leave room for the column headings and divider strokes.
                    final rowHeight = ((weekConstraints.maxHeight - 48) / 7)
                        .clamp(AppSpacing.minTouch, 64.0);
                    return SingleChildScrollView(
                      key: const ValueKey('onboarding-hours-scroll'),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: WorkloopPaperPanel(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                if (!largeText) _WeekHeadings(tokens: tokens),
                                for (final (index, day) in _days.indexed) ...[
                                  _dayRow(day, rowHeight, largeText),
                                  if (_errors[day] case final error?)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        8,
                                      ),
                                      child: Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          error,
                                          style: TextStyle(
                                            color: AppColors.of(context).error,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (index < _days.length - 1)
                                    Divider(height: 1, color: tokens.divider),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: compact ? AppSpacing.xs : AppSpacing.md,
                  bottom: compact ? AppSpacing.xs : AppSpacing.md,
                ),
                child: Align(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: SlateButton(
                      key: const ValueKey('onboarding-hours-continue'),
                      label: 'Continue',
                      onPressed: _continue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dayRow(String day, double rowHeight, bool largeText) {
    final data = _hours[day]!;
    final enabled = data['enabled'] as bool;
    final tokens = SlateTheme.of(context);
    final toggle = _WorkingDayToggle(
      day: largeText ? _dayLabels[day]! : day,
      label: '${_dayLabels[day]} working day',
      enabled: enabled,
      onTap: () => setState(() => data['enabled'] = !enabled),
    );
    Widget time(String type) => _OnboardingTimeButton(
      label:
          '${_dayLabels[day]} ${type == 'open' ? 'opening' : 'closing'} time',
      value: data[type] as String,
      onTap: () => _pickTime(day, type),
    );
    if (largeText) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            toggle,
            if (enabled) ...[
              const SizedBox(height: AppSpacing.xs),
              _LabelledTime(label: 'From', child: time('open')),
              const SizedBox(height: AppSpacing.xs),
              _LabelledTime(label: 'Until', child: time('close')),
            ] else
              Text('Closed', style: TextStyle(color: tokens.textSecondary)),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(width: 88, child: toggle),
            const SizedBox(width: AppSpacing.xs),
            if (enabled) ...[
              Expanded(child: time('open')),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: time('close')),
            ] else
              Expanded(
                child: Text(
                  'Closed',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekHeadings extends StatelessWidget {
  final WorkloopThemeTokens tokens;
  const _WeekHeadings({required this.tokens});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 8),
    decoration: BoxDecoration(
      color: tokens.paperBlue,
      border: Border(bottom: BorderSide(color: tokens.frame)),
    ),
    child: Row(
      children: [
        const SizedBox(width: 88, child: WorkloopCaption('Day')),
        const SizedBox(width: AppSpacing.xs),
        const Expanded(child: Center(child: WorkloopCaption('From'))),
        const SizedBox(width: AppSpacing.xs),
        const Expanded(child: Center(child: WorkloopCaption('Until'))),
      ],
    ),
  );
}

class _WorkingDayToggle extends StatelessWidget {
  final String day;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _WorkingDayToggle({
    required this.day,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Semantics(
      button: true,
      toggled: enabled,
      label: label,
      value: enabled ? 'Open' : 'Closed',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
            child: Row(
              children: [
                Icon(
                  enabled
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 22,
                  color: enabled ? tokens.accentInk : tokens.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabelledTime extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelledTime({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(flex: 2, child: child),
    ],
  );
}

class _OnboardingTimeButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _OnboardingTimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      value: value,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: tokens.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
