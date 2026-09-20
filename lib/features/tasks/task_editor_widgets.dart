part of 'tasks_screen.dart';

class _TaskFormSectionLabel extends StatelessWidget {
  final String text;
  final String? subtitle;

  const _TaskFormSectionLabel(this.text, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
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

class _TaskSaveAction extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _TaskSaveAction({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.of(context).modTasks.withValues(alpha: 0.14)
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
                      color: AppColors.of(context).modTasks,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: enabled
                          ? AppColors.of(context).modTasks
                          : AppColors.of(context).t3,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TaskTemplatePicker extends StatelessWidget {
  final ValueChanged<_TaskTemplate> onSelect;

  const _TaskTemplatePicker({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopFieldLabel(
          'Start with',
          isRequired: false,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).t3,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _taskTemplates
              .map(
                (template) => _DateChoice(
                  label: template.label,
                  onTap: () => onSelect(template),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _DraftChecklistEditor extends StatelessWidget {
  final TextEditingController controller;
  final List<String> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _DraftChecklistEditor({
    required this.controller,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.listChecks,
              size: 15,
              color: AppColors.of(context).t3,
            ),
            SizedBox(width: 8),
            Expanded(
              child: WorkloopFieldLabel(
                'Checklist',
                isRequired: false,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.of(context).t1,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Saved with task',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.of(context).t3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
                style: TextStyle(color: AppColors.of(context).t1),
                decoration: const InputDecoration(
                  hintText: 'Add a step',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Add checklist step',
              onTap: onAdd,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAdd,
                  child: Container(
                    width: AppSpacing.minTouch,
                    height: AppSpacing.minTouch,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).slateLight,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      LucideIcons.plus,
                      size: 18,
                      color: AppColors.of(context).panelInk,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...items.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.circle,
                    size: 16,
                    color: AppColors.of(context).t3,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).t2,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Remove ${entry.value} from checklist',
                    child: WorkloopIconButton(
                      icon: LucideIcons.x,
                      semanticLabel: 'Remove ${entry.value} from checklist',
                      size: AppSpacing.minTouch,
                      onTap: () => onRemove(entry.key),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ClientPicker extends StatelessWidget {
  final List<dynamic> clients;
  final String? selectedClientId;
  final ValueChanged<String?> onChanged;

  const _ClientPicker({
    required this.clients,
    required this.selectedClientId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelectedClient =
        selectedClientId != null &&
        clients.any((client) => client.id == selectedClientId);
    final safeSelectedClientId = hasSelectedClient ? selectedClientId : null;

    return WorkloopFormField(
      label: 'Client',
      isRequired: false,
      child: WorkloopPickerField<String?>(
        value: safeSelectedClientId,
        title: 'Link a client',
        hint: 'Link to client',
        searchHint: 'Search clients',
        searchable: true,
        leadingIcon: LucideIcons.users,
        options: [
          const WorkloopPickerOption<String?>(
            value: null,
            label: 'No client',
            subtitle: 'Keep this as a general task',
          ),
          ...clients.map(
            (client) => WorkloopPickerOption<String?>(
              value: client.id as String,
              label: client.name as String,
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _DueDatePicker extends StatelessWidget {
  final DateTime? dueDate;
  final ValueChanged<DateTime?> onChanged;

  const _DueDatePicker({required this.dueDate, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    final selectedDate = dueDate == null ? null : _dateOnly(dueDate!);
    final customSelected =
        selectedDate != null &&
        selectedDate != today &&
        selectedDate != tomorrow &&
        selectedDate != nextWeek;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopFieldLabel(
          'Due date',
          isRequired: false,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).t3,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DateChoice(
              label: 'Today',
              selected: selectedDate == today,
              onTap: () => onChanged(today),
            ),
            _DateChoice(
              label: 'Tomorrow',
              selected: selectedDate == tomorrow,
              onTap: () => onChanged(tomorrow),
            ),
            _DateChoice(
              label: 'Next week',
              selected: selectedDate == nextWeek,
              onTap: () => onChanged(nextWeek),
            ),
            _DateChoice(
              label: 'Custom',
              selected: customSelected,
              onTap: () => _pickCustomDate(context),
            ),
            if (dueDate != null)
              _DateChoice(label: 'Clear date', onTap: () => onChanged(null)),
          ],
        ),
        if (dueDate != null) ...[
          const SizedBox(height: 8),
          Text(
            'Selected: ${_formatDate(dueDate!)}',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickCustomDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showWorkloopDatePicker(
      context: context,
      initialDate: dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) onChanged(_dateOnly(picked));
  }
}

class _TaskOptionsDisclosure extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _TaskOptionsDisclosure({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: 'More options',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
            child: Row(
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 16,
                  color: AppColors.of(context).t3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'More options',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: AppMotion.responsive(context, AppMotion.standard),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: AppColors.of(context).t3,
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

class _ReminderPicker extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _ReminderPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = [
      ('none', 'No reminder'),
      ('today', 'On due day'),
      ('day_before', 'Day before'),
      ('week_before', 'Week before'),
    ];

    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.45,
      duration: AppMotion.responsive(context, AppMotion.fast),
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkloopFieldLabel(
              'Reminder',
              isRequired: false,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.of(context).t3,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((option) {
                final active = value == option.$1;
                return WorkloopFilterChip(
                  label: option.$2,
                  selected: active,
                  onTap: () => onChanged(option.$1),
                );
              }).toList(),
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Text(
                'Reminders normally arrive on this device at 09:00.',
                style: TextStyle(fontSize: 12, color: AppColors.of(context).t3),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Choose a due date before adding a reminder.',
                style: TextStyle(fontSize: 12, color: AppColors.of(context).t3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DateChoice({
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopFilterChip(label: label, selected: selected, onTap: onTap);
  }
}

class _PriorityChoice extends StatelessWidget {
  final String value;
  final String label;
  final String selected;
  final Color color;
  final ValueChanged<String> onTap;

  const _PriorityChoice({
    required this.value,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    void handleTap() => onTap(value);
    return Semantics(
      button: true,
      selected: active,
      label: '$label priority',
      onTap: handleTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: handleTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? color.withValues(alpha: 0.15)
                    : AppColors.of(context).bgInteract,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: active ? color : Colors.transparent),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? color : AppColors.of(context).t2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
