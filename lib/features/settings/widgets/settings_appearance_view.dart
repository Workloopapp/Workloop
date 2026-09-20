import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/theme_mode_provider.dart';
import '../../../shared/widgets/slate_ui.dart';

class SettingsAppearanceView extends ConsumerStatefulWidget {
  const SettingsAppearanceView({super.key});

  @override
  ConsumerState<SettingsAppearanceView> createState() =>
      _SettingsAppearanceViewState();
}

class _SettingsAppearanceViewState
    extends ConsumerState<SettingsAppearanceView> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final savedAppearance = ref.watch(workloopAppearanceProvider);
    final appearance = savedAppearance.value ?? WorkloopAppearance.system;
    final effectiveLabel = Theme.of(context).brightness == Brightness.dark
        ? 'Dark'
        : 'Light';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        0,
        AppSpacing.pageX,
        AppSpacing.xxl,
      ),
      children: [
        Text(
          appearance == WorkloopAppearance.system
              ? 'Follows your phone. Currently using $effectiveLabel mode.'
              : 'Choose the look that feels comfortable for you.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: SlateTheme.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const WorkloopSectionHeader(label: 'Choose appearance'),
        const SizedBox(height: AppSpacing.sm),
        for (final option in WorkloopAppearance.values) ...[
          _AppearanceOption(
            option: option,
            selected: appearance == option,
            onTap: _saving || savedAppearance.isLoading
                ? null
                : () => _setAppearance(context, ref, option),
          ),
          if (option != WorkloopAppearance.values.last)
            const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          'This choice is saved on this device. System follows your phone’s light and dark schedule.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: SlateTheme.of(context).textTertiary,
          ),
        ),
      ],
    );
  }

  Future<void> _setAppearance(
    BuildContext context,
    WidgetRef ref,
    WorkloopAppearance appearance,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(workloopAppearanceProvider.notifier)
          .setAppearance(appearance);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appearance could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AppearanceOption extends StatelessWidget {
  final WorkloopAppearance option;
  final bool selected;
  final VoidCallback? onTap;

  const _AppearanceOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label} appearance',
      child: WorkloopListRow(
        flat: true,
        key: ValueKey('appearance-${option.name}'),
        onTap: onTap,
        showDivider: option != WorkloopAppearance.values.last,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? tokens.accentStrong : tokens.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            _appearanceIcon(option),
            color: selected ? tokens.onAccent : tokens.textSecondary,
            size: 20,
          ),
        ),
        title: Text(
          option.label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: tokens.textPrimary),
        ),
        subtitle: Text(
          option.description,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.textTertiary),
        ),
        trailing: Icon(
          selected ? LucideIcons.circleCheck : LucideIcons.circle,
          color: selected ? tokens.accentInk : tokens.textTertiary,
          size: 20,
        ),
      ),
    );
  }
}

IconData _appearanceIcon(WorkloopAppearance appearance) => switch (appearance) {
  WorkloopAppearance.system => LucideIcons.monitor,
  WorkloopAppearance.light => LucideIcons.sun,
  WorkloopAppearance.dark => LucideIcons.moon,
};
