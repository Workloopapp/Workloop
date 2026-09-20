import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/providers/workspace_settings_actions.dart';
import '../../../shared/sms/booking_sms_repository.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../providers/settings_providers.dart';

class SmsSettingsSection extends ConsumerStatefulWidget {
  const SmsSettingsSection({super.key});

  @override
  ConsumerState<SmsSettingsSection> createState() => _SmsSettingsSectionState();
}

class _SmsSettingsSectionState extends ConsumerState<SmsSettingsSection> {
  bool _saving = false;
  String? _error;

  Future<void> _save(Set<int> minutes, int minute, bool enabled) async {
    if (_saving) return;
    final capabilities = ref.read(bookingSmsCapabilitiesProvider);
    if (capabilities.isLoading ||
        capabilities.hasError ||
        capabilities.value?.available != true ||
        !capabilities.value!.allowedMinutes.contains(minute)) {
      return;
    }
    final workspaceId = ref.read(workspaceIdProvider).value;
    if (workspaceId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = {...minutes};
      if (enabled) {
        updated.add(minute);
      } else {
        updated.remove(minute);
      }
      await ref.read(updateWorkspaceSettingsProvider)(workspaceId, {
        'customer_sms_reminder_minutes': updated.toList()..sort(),
      });
      if (!mounted) return;
      try {
        await ref.read(settingsWorkspaceSettingsProvider.future);
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'Saved, but the settings could not be reloaded. Please try again.',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Text reminder settings could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _retry() {
    if (_saving) return;
    setState(() => _error = null);
    ref.invalidate(bookingSmsCapabilitiesProvider);
    ref.invalidate(settingsWorkspaceSettingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final capabilityState = ref.watch(bookingSmsCapabilitiesProvider);
    final settings = ref.watch(settingsWorkspaceSettingsProvider);
    final capabilities = capabilityState.hasError
        ? const BookingSmsCapabilities(
            availability: BookingSmsAvailability.couldNotCheck,
          )
        : capabilityState.value;
    final raw = settings.value?['customer_sms_reminder_minutes'];
    final minutes = raw is List ? raw.whereType<int>().toSet() : <int>{};
    final available =
        capabilities?.available == true &&
        raw is List &&
        !capabilityState.hasError &&
        !settings.hasError;
    final checking = capabilityState.isLoading || settings.isLoading;
    final canEdit = available && !checking && !_saving;
    final availabilityUnknown =
        capabilities == null ||
        capabilities.availability == BookingSmsAvailability.couldNotCheck ||
        settings.hasError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer booking texts',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).t1,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Send texts as well as emails, only to clients who agreed to booking reminders. Add their UK mobile number and permission in Clients.',
          style: TextStyle(color: AppColors.of(context).t2, height: 1.5),
        ),
        if (checking)
          const LinearProgressIndicator()
        else if (!available) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            settings.hasError
                ? 'Could not load your text reminder settings. Please try again.'
                : capabilities?.available == true
                ? 'Text reminders are not available yet. Your email reminders are unaffected.'
                : capabilities?.unavailableMessage ??
                      'Text reminders are not available yet.',
            style: TextStyle(color: AppColors.of(context).t2, height: 1.5),
          ),
          TextButton(
            onPressed: _saving ? null : _retry,
            child: const Text('Check again'),
          ),
        ],
        for (final entry in const {
          1440: 'Text 1 day before',
          60: 'Text 1 hour before',
        }.entries)
          SwitchListTile.adaptive(
            key: ValueKey('sms-reminder-${entry.key}'),
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value),
            value:
                (available || availabilityUnknown) &&
                minutes.contains(entry.key),
            onChanged:
                canEdit && capabilities!.allowedMinutes.contains(entry.key)
                ? (value) => _save(minutes, entry.key, value)
                : null,
          ),
        if (!available && !availabilityUnknown && minutes.isNotEmpty)
          Text(
            'Your saved reminder times are kept for when texts become available.',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        if (!checking && availabilityUnknown && minutes.isNotEmpty)
          Text(
            'Showing your saved reminder times. Availability has not been confirmed.',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        if (available)
          Text(
            'Times use your business timezone. Customers can stop texts without cancelling their booking.',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        if (_error != null)
          SlateErrorState(message: _error!, onRetry: _saving ? null : _retry),
      ],
    );
  }
}
