import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/maps_preference_provider.dart';
import '../../../shared/utils/maps_launcher.dart';
import '../../../shared/widgets/slate_ui.dart';

class SettingsAppTab extends ConsumerStatefulWidget {
  const SettingsAppTab({super.key});
  @override
  ConsumerState<SettingsAppTab> createState() => _SettingsAppTabState();
}

class _SettingsAppTabState extends ConsumerState<SettingsAppTab> {
  bool _saving = false;

  Future<void> _chooseMaps(MapsAppPreference preference) async {
    if (_saving) return;
    final selected = await showMapsPreferenceSheet(
      context,
      selected: preference,
    );
    if (selected == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(preferredMapsAppProvider.notifier).setPreference(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your maps choice could not be saved. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapsPreference = ref.watch(preferredMapsAppProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        0,
        AppSpacing.pageX,
        AppSpacing.xxl,
      ),
      children: [
        const WorkloopSectionHeader(label: 'Directions'),
        const SizedBox(height: AppSpacing.xs),
        mapsPreference.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('Loading your maps choice…'),
          ),
          error: (_, _) => SlateErrorState(
            message: 'Could not load your maps choice.',
            onRetry: () => ref.invalidate(preferredMapsAppProvider),
          ),
          data: (preference) => _PreferenceRow(
            icon: LucideIcons.navigation,
            title: 'Default maps app',
            subtitle: _saving ? 'Saving…' : preference.label,
            onTap: _saving ? null : () => _chooseMaps(preference),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Used when you open directions to a client or booking.',
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const WorkloopSectionHeader(label: 'Calendar'),
        const SizedBox(height: AppSpacing.xs),
        _PreferenceRow(
          icon: LucideIcons.calendarClock,
          title: 'Export bookings to a calendar',
          subtitle: 'Save a calendar file to use in another app.',
          onTap: () => context.push('/calendar-sync'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is a copy of your bookings at the time you export. Later changes in either app will not sync automatically.',
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      flat: true,
      onTap: onTap,
      showDivider: false,
      padding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.md,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.surfaceSubtle,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: tokens.textSecondary, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: tokens.textTertiary, fontSize: 13),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: tokens.textTertiary,
        size: 16,
      ),
    );
  }
}
