import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/providers/workspace_settings_actions.dart';
import '../../../shared/widgets/workloop_form_field.dart';

class BusinessEmailContactSettings extends ConsumerStatefulWidget {
  const BusinessEmailContactSettings({super.key, required this.settings});
  final Map<String, dynamic> settings;

  @override
  ConsumerState<BusinessEmailContactSettings> createState() =>
      _BusinessEmailContactSettingsState();
}

class _BusinessEmailContactSettingsState
    extends ConsumerState<BusinessEmailContactSettings> {
  Future<void> _edit() async {
    final workspaceId = ref.read(workspaceIdProvider).value;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContactDialog(
        email: widget.settings['customer_contact_email'] as String? ?? '',
        phone: widget.settings['customer_contact_phone'] as String? ?? '',
        save: (email, phone) async {
          if (!mounted ||
              workspaceId == null ||
              ref.read(workspaceIdProvider).value != workspaceId) {
            throw StateError('No workspace');
          }
          await ref.read(updateWorkspaceSettingsProvider)(workspaceId, {
            'customer_contact_email': email.isEmpty ? null : email,
            'customer_contact_phone': phone.isEmpty ? null : phone,
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text(
      'Business contact details',
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
    subtitle: Text(
      'Where customers can reach you, shown in emails and new invoices',
      style: TextStyle(
        fontSize: 13,
        height: 1.5,
        color: AppColors.of(context).t2,
      ),
    ),
    trailing: const Icon(LucideIcons.chevronRight, size: 18),
    onTap: _edit,
  );
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({
    required this.email,
    required this.phone,
    required this.save,
  });
  final String email;
  final String phone;
  final Future<void> Function(String email, String phone) save;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  late final _phone = TextEditingController(text: widget.phone);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_email.text.trim().toLowerCase(), _phone.text.trim());
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save. Your changes are still here. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Business contact details'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Customers see these details in booking and payment emails and new invoices. Email replies go to this address, outside Workloop. If blank, we use your verified account email where available. Private Apple relay addresses are not displayed.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _email,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                label: WorkloopFieldLabel('Business email', isRequired: false),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isEmpty ||
                        (text.length <= 254 &&
                            RegExp(
                              r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$',
                            ).hasMatch(text))
                    ? null
                    : 'Enter a valid email address';
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                label: WorkloopFieldLabel('Business phone', isRequired: false),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isEmpty ||
                        (text.length <= 40 &&
                            RegExp(r'^\+?[0-9 ()-]+$').hasMatch(text) &&
                            text.replaceAll(RegExp(r'\D'), '').length >= 7)
                    ? null
                    : 'Enter a valid phone number';
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save contact details'),
        ),
      ],
    ),
  );
}
