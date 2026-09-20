import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/email/email_preferences_repository.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/providers/workspace_settings_actions.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../providers/settings_providers.dart';
import 'business_email_contact_settings.dart';

class EmailSettingsSection extends ConsumerStatefulWidget {
  final bool showAccountEmails;
  final bool showCustomerEmails;
  const EmailSettingsSection({
    super.key,
    this.showAccountEmails = true,
    this.showCustomerEmails = true,
  });
  @override
  ConsumerState<EmailSettingsSection> createState() =>
      _EmailSettingsSectionState();
}

class _EmailSettingsSectionState extends ConsumerState<EmailSettingsSection> {
  TextStyle get _rowStyle => TextStyle(
    color: AppColors.of(context).t1,
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );
  TextStyle get _helperStyle =>
      TextStyle(color: AppColors.of(context).t2, fontSize: 13, height: 1.5);
  bool _saving = false;
  Future<void> _save(Future<void> Function() action) async {
    if (_saving) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Email settings could not be saved. Please try again.',
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _loadError(String message, VoidCallback retry) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(liveRegion: true, child: Text(message, style: _helperStyle)),
      WorkloopTextButton(label: 'Try again', onPressed: retry),
    ],
  );

  Future<void> _saveReminderTimes(Set<int> minutes) => _save(() async {
    final id = ref.read(workspaceIdProvider).value;
    if (id == null) throw StateError('No workspace');
    await ref.read(updateWorkspaceSettingsProvider)(id, {
      'customer_reminder_minutes': minutes.toList()..sort(),
    });
  });

  Widget _customerBookingSettings(Map<String, dynamic>? data) {
    final raw = data?['customer_reminder_minutes'];
    if (raw is! List) {
      return Text(
        'Customer email settings are not available yet.',
        style: _helperStyle,
      );
    }
    final minutes = raw.whereType<num>().map((n) => n.toInt()).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            minutes.isEmpty
                ? 'Email reminders are off'
                : '${minutes.length} email reminder${minutes.length == 1 ? '' : 's'} selected',
            style: _rowStyle,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          minutes.isEmpty
              ? 'Select a time below to turn them on.'
              : 'Each selected time adds a separate reminder before the booking.',
          style: _helperStyle,
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final entry in const {
          1440: '1 day before',
          120: '2 hours before',
          60: '1 hour before',
        }.entries)
          SwitchListTile.adaptive(
            key: ValueKey('email-reminder-${entry.key}'),
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value, style: _rowStyle),
            value: minutes.contains(entry.key),
            onChanged: _saving
                ? null
                : (value) {
                    final updated = {...minutes};
                    if (value) {
                      updated.add(entry.key);
                    } else {
                      updated.remove(entry.key);
                    }
                    _saveReminderTimes(updated);
                  },
          ),
        if (minutes.isNotEmpty)
          WorkloopTextButton(
            key: const ValueKey('turn-off-customer-email-reminders'),
            label: 'Turn off email reminders',
            onPressed: _saving ? null : () => _saveReminderTimes({}),
          ),
      ],
    );
  }

  Widget _accountEmailSettings(Map<String, dynamic> data) {
    final suppressed = data['suppressed'] == true;
    final enabled = data['enabled'] == true;
    final welcomeOnly = enabled && data['program'] == 'welcome';
    // A limited welcome series is not consent to the ongoing account journey.
    final accountJourneyEnabled = enabled && data['program'] == 'account';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (welcomeOnly && !suppressed) ...[
          Text('Welcome series only', style: _rowStyle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'You are receiving the limited welcome series. Ongoing tips and updates are off. Turn them on below if you would like more from Workloop.',
            style: _helperStyle,
          ),
          WorkloopTextButton(
            key: const ValueKey('unsubscribe-welcome-series'),
            label: 'Unsubscribe from welcome series',
            onPressed: _saving
                ? null
                : () => _save(
                    () => ref.read(setAccountEmailPreferenceProvider)(false),
                  ),
          ),
          Divider(height: AppSpacing.lg, color: AppColors.of(context).border),
        ],
        SwitchListTile.adaptive(
          key: const ValueKey('account-email-updates'),
          contentPadding: EdgeInsets.zero,
          title: Text('Workloop tips and updates', style: _rowStyle),
          subtitle: Text(
            suppressed
                ? 'Delivery is paused. Contact support@workloop.uk for help.'
                : 'Getting-started help, business tips, product updates, referral ideas and occasional reminders to return. Unsubscribe at any time.',
            style: _helperStyle,
          ),
          value: accountJourneyEnabled,
          onChanged: _saving || suppressed
              ? null
              : (value) => _save(
                  () => ref.read(setAccountEmailPreferenceProvider)(value),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.showCustomerEmails
        ? ref.watch(settingsWorkspaceSettingsProvider)
        : null;
    final preference = widget.showAccountEmails
        ? ref.watch(accountEmailPreferenceProvider)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showCustomerEmails) ...[
          Text(
            'Reminders for the people who book with you. Workloop has no customer chat inbox; conversations stay in your email or WhatsApp.',
            style: _helperStyle,
          ),
          const SizedBox(height: AppSpacing.md),
          WorkloopPaperPanel(
            key: const ValueKey('customer-booking-reminders-panel'),
            title: 'Automatic email reminders',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sent before upcoming bookings to customers with an email address. Customers can unsubscribe at any time. Times follow your business timezone.',
                  style: _helperStyle,
                ),
                const SizedBox(height: AppSpacing.sm),
                settings!.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => _loadError(
                    'Could not load reminder settings.',
                    () => ref.invalidate(settingsWorkspaceSettingsProvider),
                  ),
                  data: _customerBookingSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          WorkloopPaperPanel(
            key: const ValueKey('customer-booking-updates-panel'),
            title: 'Booking updates & contact details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Booking confirmations, changes and cancellations use separate emails. Turning off reminders does not turn these off or cancel any bookings.',
                  style: _helperStyle,
                ),
                if (settings.asData?.value case final data?
                    when data.containsKey('customer_contact_email')) ...[
                  const SizedBox(height: AppSpacing.sm),
                  BusinessEmailContactSettings(settings: data),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          WorkloopPaperPanel(
            key: ValueKey('customer-whatsapp-reminders-panel'),
            title: 'WhatsApp reminders',
            tone: WorkloopPaperTone.warm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manual · Send in WhatsApp', style: _rowStyle),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Open an upcoming booking and choose Send WhatsApp reminder. Check the prepared message and your sending account in WhatsApp, then tap Send. Replies stay in WhatsApp. These reminders are never sent automatically.',
                  style: _helperStyle,
                ),
              ],
            ),
          ),
        ],
        if (widget.showAccountEmails) ...[
          if (widget.showCustomerEmails) const SizedBox(height: AppSpacing.lg),
          Text('You, the account holder', style: _rowStyle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Emails from Workloop to your account email address. This choice does not change the messages sent to your customers.',
            style: _helperStyle,
          ),
          const SizedBox(height: AppSpacing.md),
          WorkloopPaperPanel(
            key: const ValueKey('account-email-updates-panel'),
            title: 'Workloop tips and updates',
            child: preference!.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => _loadError(
                'Could not load your email preference.',
                () => ref.invalidate(accountEmailPreferenceProvider),
              ),
              data: _accountEmailSettings,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Essential account emails', style: _rowStyle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Account and security emails continue when tips and updates are off. These keep you informed about your account and sign-in activity.',
            style: _helperStyle,
          ),
        ],
      ],
    );
  }
}
