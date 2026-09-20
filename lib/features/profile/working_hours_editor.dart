import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/working_hours.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import '../settings/providers/settings_providers.dart';

class WorkingHoursEditor extends ConsumerStatefulWidget {
  const WorkingHoursEditor({super.key});

  @override
  ConsumerState<WorkingHoursEditor> createState() => _WorkingHoursEditorState();
}

class _WorkingHoursEditorState extends ConsumerState<WorkingHoursEditor> {
  final Map<String, bool> _enabled = {};
  final Map<String, List<_HoursBlock>> _blocks = {};
  bool _hydrated = false;
  bool _saving = false;
  bool _allowPop = false;
  String _initialSnapshot = '';
  Map<String, String> _errors = {};

  void _hydrate(Map<String, dynamic> settings) {
    if (_hydrated) return;
    final rawHours = Map<String, dynamic>.from(
      settings['working_hours'] as Map? ?? {},
    );
    for (final day in workingHourDays) {
      final shortDay = shortToLongDay.entries
          .firstWhere((entry) => entry.value == day)
          .key;
      final rawDay = rawHours[day] ?? rawHours[shortDay];
      final value = rawDay is Map
          ? Map<String, dynamic>.from(rawDay)
          : <String, dynamic>{};
      final source = value.isEmpty ? defaultWorkingHours()[day] : value;
      final parsed = workingHourBlocks(source)
          .map(
            (block) => _HoursBlock(
              start: _parseTime(
                block.start,
                const TimeOfDay(hour: 9, minute: 0),
              ),
              end: _parseTime(block.end, const TimeOfDay(hour: 17, minute: 0)),
            ),
          )
          .toList();
      _enabled[day] =
          value['enabled'] as bool? ?? parsed.isNotEmpty && day != 'Sunday';
      _blocks[day] = parsed.isEmpty
          ? [
              const _HoursBlock(
                start: TimeOfDay(hour: 9, minute: 0),
                end: TimeOfDay(hour: 17, minute: 0),
              ),
            ]
          : parsed;
    }
    _hydrated = true;
    _initialSnapshot = _snapshot();
  }

  String _snapshot() => jsonEncode({
    for (final day in workingHourDays)
      day: {
        'enabled': _enabled[day] ?? false,
        'blocks': (_blocks[day] ?? const <_HoursBlock>[])
            .map(
              (block) => {
                'start': _storageTime(block.start),
                'end': _storageTime(block.end),
              },
            )
            .toList(),
      },
  });

  bool get _hasChanges =>
      _hydrated &&
      _initialSnapshot.isNotEmpty &&
      _snapshot() != _initialSnapshot;

  Future<void> _attemptExit() async {
    final decision = await showWorkloopDraftConfirmation(
      context,
      title: 'Save working hours?',
      message: 'Your latest availability changes have not been saved yet.',
      saveLabel: 'Save hours',
    );
    if (!mounted) return;
    switch (decision) {
      case WorkloopDraftDecision.save:
        await _save();
        return;
      case WorkloopDraftDecision.discard:
        _allowPop = true;
        Navigator.pop(context);
        return;
      case WorkloopDraftDecision.stay:
        return;
    }
  }

  TimeOfDay _parseTime(String value, TimeOfDay fallback) {
    final parts = value.split(':');
    if (parts.length != 2) return fallback;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return fallback;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _storageTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTime(String day, int index, {required bool start}) async {
    final block = _blocks[day]![index];
    final picked = await _showScrollingTimePicker(
      start ? block.start : block.end,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _blocks[day]![index] = start
          ? block.copyWith(start: picked)
          : block.copyWith(end: picked);
    });
  }

  Future<TimeOfDay?> _showScrollingTimePicker(TimeOfDay initial) async {
    return showWorkloopTimePicker(context: context, initialTime: initial);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (!mounted) return;
      if (workspaceId == null) return;
      final nextHours = <String, dynamic>{};
      for (final day in workingHourDays) {
        final blocks = _blocks[day]!
            .map(
              (block) => {
                'start': _storageTime(block.start),
                'end': _storageTime(block.end),
              },
            )
            .toList();
        nextHours[day] = {
          'enabled': _enabled[day] ?? false,
          'blocks': blocks,
          if (blocks.isNotEmpty) 'start': blocks.first['start'],
          if (blocks.isNotEmpty) 'end': blocks.last['end'],
        };
      }
      final errors = validateWorkingHours(nextHours);
      setState(() => _errors = errors);
      if (errors.isNotEmpty) return;
      await ref.read(workspaceSettingsRepositoryProvider).update(workspaceId, {
        'working_hours': nextHours,
      });
      if (!mounted) return;
      ref.invalidate(settingsWorkspaceSettingsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Working hours updated')));
      _allowPop = true;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save working hours')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsWorkspaceSettingsProvider);
    return PopScope(
      canPop: _allowPop || !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _attemptExit();
      },
      child: settings.when(
        loading: () => Center(
          child: CircularProgressIndicator(
            color: AppColors.of(context).accentPrimary,
          ),
        ),
        error: (_, _) => WorkloopEmptyState(
          icon: LucideIcons.clock3,
          title: 'Could not load working hours',
          subtitle: 'Try again in a moment.',
          action: WorkloopTextButton(
            label: 'Try again',
            onPressed: () => ref.invalidate(settingsWorkspaceSettingsProvider),
          ),
        ),
        data: (data) {
          _hydrate(data ?? const {});
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'All days can be off. Tap hours to edit or add a break.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SlateTheme.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final rowHeight = ((constraints.maxHeight - 8) / 7).clamp(
                        AppSpacing.minTouch,
                        56.0,
                      );
                      return ListView(
                        key: const ValueKey('working-hours-week'),
                        padding: EdgeInsets.zero,
                        children: [
                          WorkloopPaperPanel(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (final (index, day)
                                    in workingHourDays.indexed) ...[
                                  _weekRow(day, rowHeight),
                                  if (_errors[day] case final error?)
                                    Padding(
                                      padding: const EdgeInsets.all(8),
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
                                  if (index < workingHourDays.length - 1)
                                    Divider(
                                      height: 1,
                                      color: SlateTheme.of(context).divider,
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: WorkloopPrimaryButton(
                    label: _saving ? 'Saving' : 'Save hours',
                    icon: LucideIcons.check,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _weekRow(String day, double rowHeight) {
    final enabled = _enabled[day] ?? false;
    final blocks = _blocks[day]!;
    final tokens = SlateTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    final summary = !enabled
        ? 'Closed'
        : '${_storageTime(blocks.first.start)}–${_storageTime(blocks.first.end)}'
              '${blocks.length > 1 ? '\n+${blocks.length - 1} ${blocks.length == 2 ? 'block' : 'blocks'}' : ''}';
    final toggle = Semantics(
      label: '$day working day',
      toggled: enabled,
      onTap: () => setState(() => _enabled[day] = !enabled),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => setState(() => _enabled[day] = !enabled),
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
                    largeText ? day : day.substring(0, 3),
                    style: TextStyle(fontSize: 14, color: tokens.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final hours = Semantics(
      label: 'Edit $day hours',
      value: enabled
          ? blocks
                .map(
                  (b) => '${_storageTime(b.start)} to ${_storageTime(b.end)}',
                )
                .join(', ')
          : 'Closed',
      button: true,
      onTap: () => _editDay(day),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _editDay(day),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    summary,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: tokens.textPrimary),
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: tokens.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      constraints: BoxConstraints(minHeight: rowHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: largeText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [toggle, hours],
            )
          : Row(
              children: [
                SizedBox(width: 88, child: toggle),
                Expanded(child: hours),
              ],
            ),
    );
  }

  Future<void> _editDay(String day) async {
    await showWorkloopBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          Future<void> pick(int index, {required bool start}) async {
            await _pickTime(day, index, start: start);
            if (context.mounted) setSheetState(() {});
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.pageX),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DayHoursEditor(
                      day: day,
                      enabled: _enabled[day] ?? false,
                      blocks: _blocks[day]!,
                      onEnabled: (value) => update(() => _enabled[day] = value),
                      onPickStart: (index) => pick(index, start: true),
                      onPickEnd: (index) => pick(index, start: false),
                      onAddBlock: () => update(
                        () => _blocks[day]!.add(
                          const _HoursBlock(
                            start: TimeOfDay(hour: 16, minute: 0),
                            end: TimeOfDay(hour: 20, minute: 0),
                          ),
                        ),
                      ),
                      onRemoveBlock: (index) =>
                          update(() => _blocks[day]!.removeAt(index)),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    WorkloopPrimaryButton(
                      label: 'Done',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayHoursEditor extends StatelessWidget {
  final String day;
  final bool enabled;
  final List<_HoursBlock> blocks;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<int> onPickStart;
  final ValueChanged<int> onPickEnd;
  final VoidCallback onAddBlock;
  final ValueChanged<int> onRemoveBlock;

  const _DayHoursEditor({
    required this.day,
    required this.enabled,
    required this.blocks,
    required this.onEnabled,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onAddBlock,
    required this.onRemoveBlock,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                day,
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              enabled ? 'Working' : 'Off',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Switch.adaptive(value: enabled, onChanged: onEnabled),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: AppSpacing.sm),
          const WorkloopFieldLabel('Working hours', isRequired: true),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each block must end after it starts. Blocks cannot overlap.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < blocks.length; index++) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final stackTimes =
                    constraints.maxWidth < 360 &&
                    MediaQuery.textScalerOf(context).scale(15) > 19;
                final start = _TimeButton(
                  label: 'Start',
                  semanticLabel: '$day start time, block ${index + 1}',
                  time: blocks[index].start,
                  onTap: () => onPickStart(index),
                );
                final end = _TimeButton(
                  label: 'End',
                  semanticLabel: '$day end time, block ${index + 1}',
                  time: blocks[index].end,
                  onTap: () => onPickEnd(index),
                );
                final remove = Tooltip(
                  message: 'Remove $day time block ${index + 1}',
                  child: WorkloopIconButton(
                    icon: LucideIcons.x,
                    semanticLabel: 'Remove $day time block ${index + 1}',
                    size: AppSpacing.minTouch,
                    onTap: () => onRemoveBlock(index),
                  ),
                );
                if (stackTimes) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      start,
                      const SizedBox(height: AppSpacing.sm),
                      end,
                      if (blocks.length > 1)
                        Align(alignment: Alignment.centerRight, child: remove),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: start),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: end),
                    if (blocks.length > 1) ...[
                      const SizedBox(width: AppSpacing.xs),
                      remove,
                    ],
                  ],
                );
              },
            ),
            if (index != blocks.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.sm),
          WorkloopTextButton(label: 'Add working block', onPressed: onAddBlock),
        ],
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.semanticLabel,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      value: time.format(context),
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.of(context).bgRaised.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.of(context).border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time.format(context),
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.clock3,
                  color: AppColors.of(context).t3,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoursBlock {
  final TimeOfDay start;
  final TimeOfDay end;

  const _HoursBlock({required this.start, required this.end});

  _HoursBlock copyWith({TimeOfDay? start, TimeOfDay? end}) {
    return _HoursBlock(start: start ?? this.start, end: end ?? this.end);
  }
}
