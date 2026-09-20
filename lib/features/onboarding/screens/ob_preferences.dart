import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/widgets/slate_ui.dart';

class ObPreferences extends ConsumerWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ObPreferences({super.key, required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        AppSpacing.xxl,
        AppSpacing.pageX,
        AppSpacing.xxl,
      ),
      children: [
        Text(
          'Bring your work with you',
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 27,
            height: 1.05,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Choose what you want to do next. You can change all of this later.',
          style: TextStyle(
            color: AppColors.of(context).t2,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _PreferenceSwitch(
          icon: LucideIcons.import,
          title: 'Import existing data',
          subtitle: 'Open the private import area after setup.',
          value: state.importAfterSetup,
          onChanged: notifier.setImportAfterSetup,
        ),
        const SizedBox(height: AppSpacing.xxl),
        const WorkloopSectionHeader(label: 'Useful notifications'),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Choose which business activity appears in your in-app notification centre.',
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PreferenceSwitch(
          icon: LucideIcons.calendarCheck,
          title: 'Bookings',
          subtitle: 'New bookings and booking requests.',
          value: state.notificationPreferences['new_booking'] ?? true,
          onChanged: (value) {
            notifier.setNotificationPreference('new_booking', value);
            notifier.setNotificationPreference('booking_request', value);
          },
        ),
        _PreferenceSwitch(
          icon: LucideIcons.banknote,
          title: 'Money',
          subtitle: 'Payments received and balances that need attention.',
          value: state.notificationPreferences['payment_received'] ?? true,
          onChanged: (value) {
            notifier.setNotificationPreference('payment_received', value);
            notifier.setNotificationPreference('invoice_overdue', value);
          },
        ),
        _PreferenceSwitch(
          icon: LucideIcons.listChecks,
          title: 'Tasks',
          subtitle: 'A calm reminder when work is due.',
          value: state.notificationPreferences['task_due_morning'] ?? true,
          onChanged: (value) =>
              notifier.setNotificationPreference('task_due_morning', value),
        ),
        const SizedBox(height: AppSpacing.xxl),
        WorkloopPrimaryButton(
          label: 'Continue',
          icon: LucideIcons.arrowRight,
          onPressed: onNext,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: WorkloopTextButton(label: 'Skip for now', onPressed: onNext),
        ),
      ],
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PreferenceSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      onTap: () => onChanged(!value),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: tokens.surfaceSubtle,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: tokens.textSecondary, size: 19),
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
        style: TextStyle(
          color: tokens.textTertiary,
          fontSize: 13,
          height: 1.35,
        ),
      ),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
      showDivider: false,
    );
  }
}
