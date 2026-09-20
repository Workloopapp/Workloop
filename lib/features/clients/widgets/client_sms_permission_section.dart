import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sms/booking_sms_repository.dart';
import '../../../shared/widgets/slate_ui.dart';

class ClientSmsPermissionSection extends ConsumerWidget {
  final String contactId;
  final String phone;
  final VoidCallback onEdit;

  const ClientSmsPermissionSection({
    super.key,
    required this.contactId,
    required this.phone,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capability = ref.watch(bookingSmsCapabilitiesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Booking reminder texts',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).t1,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        capability.when(
          skipLoadingOnRefresh: false,
          skipError: false,
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => SlateErrorState(
            message:
                'Could not check text reminder availability. Please try again.',
            onRetry: () => ref.invalidate(bookingSmsCapabilitiesProvider),
          ),
          data: (data) => data.available
              ? _AvailableSmsPermission(
                  key: ValueKey((contactId, phone)),
                  contactId: contactId,
                  phone: phone,
                  onEdit: onEdit,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.unavailableMessage,
                      style: TextStyle(
                        color: AppColors.of(context).t2,
                        height: 1.5,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(bookingSmsCapabilitiesProvider),
                      child: const Text('Check again'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AvailableSmsPermission extends ConsumerStatefulWidget {
  final String contactId;
  final String phone;
  final VoidCallback onEdit;
  const _AvailableSmsPermission({
    super.key,
    required this.contactId,
    required this.phone,
    required this.onEdit,
  });

  @override
  ConsumerState<_AvailableSmsPermission> createState() =>
      _AvailableSmsPermissionState();
}

class _AvailableSmsPermissionState
    extends ConsumerState<_AvailableSmsPermission> {
  bool _changing = false;
  String? _error;
  BookingSmsContact get _contact =>
      (contactId: widget.contactId, phone: widget.phone);

  Future<void> _change(BookingSmsConsent consent, bool enabled) async {
    if (_changing ||
        consent.phone == null ||
        consent.providerStopped ||
        consent.phone != bookingSmsPhone(widget.phone)) {
      return;
    }
    final repository = ref.read(bookingSmsRepositoryProvider);
    final userId = repository.currentUserId;
    if (userId == null) return;
    setState(() {
      _changing = true;
      _error = null;
    });
    try {
      if (enabled) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => _ConfirmSmsPermissionDialog(phone: consent.phone!),
        );
        if (confirmed != true || !mounted) return;
      }
      final capability = ref.read(bookingSmsCapabilitiesProvider);
      if (repository.currentUserId != userId ||
          capability.isLoading ||
          capability.hasError ||
          capability.value?.available != true) {
        return;
      }
      await repository.setConsent(
        contactId: widget.contactId,
        enabled: enabled,
        expectedPhone: consent.phone!,
      );
      if (!mounted || repository.currentUserId != userId) return;
      ref.invalidate(bookingSmsConsentProvider(_contact));
      try {
        await ref.read(bookingSmsConsentProvider(_contact).future);
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'Permission saved, but it could not be reloaded. Please try again.',
          );
        }
      }
    } catch (_) {
      if (mounted && repository.currentUserId == userId) {
        // Refresh after failures too: the server may have rejected a changed
        // phone number or a customer STOP received since the screen opened.
        ref.invalidate(bookingSmsConsentProvider(_contact));
        setState(
          () => _error =
              'Could not save permission. Check the current mobile number and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = ref.watch(bookingSmsConsentProvider(_contact));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        permission.when(
          skipLoadingOnRefresh: false,
          skipError: false,
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => SlateErrorState(
            message:
                'Could not load this client’s text permission. Please try again.',
            onRetry: () => ref.invalidate(bookingSmsConsentProvider(_contact)),
          ),
          data: (data) {
            final validPhone = bookingSmsPhone(widget.phone);
            final numberMatches =
                validPhone != null && data.phone == validPhone;
            final enabled =
                numberMatches && data.consented && !data.providerStopped;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('client-sms-permission'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Customer agreed to booking reminder texts',
                  ),
                  subtitle: Text(
                    data.providerStopped
                        ? 'This customer stopped reminder texts. Their choice cannot be overridden here.'
                        : validPhone == null || data.phone == null
                        ? 'Add a UK mobile number starting +44 to use text reminders.'
                        : !numberMatches
                        ? 'The saved number has changed. Reopen this client to check their details.'
                        : enabled
                        ? 'Permission recorded for ${data.phone}. Choose the times in Business → Customer reminders.'
                        : 'Ask the customer before recording permission for ${data.phone}.',
                  ),
                  value: enabled,
                  onChanged: _changing || !numberMatches || data.providerStopped
                      ? null
                      : (value) => _change(data, value),
                ),
                if (validPhone == null || data.phone == null)
                  TextButton(
                    onPressed: _changing ? null : widget.onEdit,
                    child: const Text('Edit mobile number'),
                  ),
                if (enabled)
                  Text(
                    'Changing their mobile number clears this permission. These texts contain booking details, not marketing.',
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
              ],
            );
          },
        ),
        if (_error != null) SlateErrorState(message: _error!),
      ],
    );
  }
}

class _ConfirmSmsPermissionDialog extends StatefulWidget {
  final String phone;
  const _ConfirmSmsPermissionDialog({required this.phone});
  @override
  State<_ConfirmSmsPermissionDialog> createState() =>
      _ConfirmSmsPermissionDialogState();
}

class _ConfirmSmsPermissionDialogState
    extends State<_ConfirmSmsPermissionDialog> {
  bool _confirmed = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Record text reminder permission'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Only confirm if this customer has agreed to receive booking reminder texts at ${widget.phone}. Having their number does not mean they agreed.',
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile.adaptive(
          key: const ValueKey('confirm-customer-sms-permission'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Customer agreed to booking reminder texts'),
          value: _confirmed,
          onChanged: (value) => setState(() => _confirmed = value ?? false),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
        child: const Text('Save permission'),
      ),
    ],
  );
}
