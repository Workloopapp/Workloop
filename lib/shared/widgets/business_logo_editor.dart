import 'package:flutter/material.dart';

import 'workloop_form_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../repositories/business_logo_repository.dart';
import '../repositories/supabase_client_provider.dart';
import '../providers/workspace_provider.dart';

class BusinessLogo extends StatelessWidget {
  final String? logoUrl;
  final double size;
  const BusinessLogo({super.key, this.logoUrl, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(
      Icons.storefront_outlined,
      color: AppColors.of(context).t3,
    );
    return SizedBox(
      width: size,
      height: size,
      child: isTrustedBusinessLogoUrl(logoUrl)
          ? Image.network(
              logoUrl!,
              fit: BoxFit.contain,
              semanticLabel: 'Business logo',
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}

/// Used before a workspace exists and in the workspace's business settings.
class BusinessLogoEditor extends ConsumerStatefulWidget {
  final String? logoUrl;
  final Future<void> Function(String?) onChanged;
  final ValueChanged<bool>? onBusyChanged;
  const BusinessLogoEditor({
    super.key,
    this.logoUrl,
    required this.onChanged,
    this.onBusyChanged,
  });

  @override
  ConsumerState<BusinessLogoEditor> createState() => _BusinessLogoEditorState();
}

class _BusinessLogoEditorState extends ConsumerState<BusinessLogoEditor> {
  bool _busy = false;
  String? _error;

  Future<void> _change({bool remove = false}) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final workspaceId = ref.read(workspaceProvider).value?['id'];
    if (_busy || userId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    bool scopeCurrent() =>
        mounted &&
        ref.read(supabaseClientProvider).auth.currentUser?.id == userId &&
        ref.read(workspaceProvider).value?['id'] == workspaceId;
    try {
      String? url;
      if (!remove) {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 95,
          requestFullMetadata: false,
        );
        if (photo == null || !scopeCurrent()) return;
        if (await photo.length() > businessLogoMaxBytes) {
          throw const FormatException('Choose a logo smaller than 2 MB.');
        }
        final bytes = await photo.readAsBytes();
        if (!scopeCurrent()) return;
        url = await ref
            .read(businessLogoRepositoryProvider)
            .upload(bytes, userId: userId);
      }
      if (!scopeCurrent()) return;
      await widget.onChanged(url);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Could not save your logo. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          BusinessLogo(logoUrl: widget.logoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WorkloopFieldLabel(
                  'Business logo',
                  isRequired: false,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Shown on your booking page, invoices and quotes.',
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _change,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _busy
                  ? 'Saving logo…'
                  : widget.logoUrl?.isNotEmpty == true
                  ? 'Change logo'
                  : 'Add logo',
            ),
          ),
          if (widget.logoUrl?.isNotEmpty == true)
            TextButton(
              onPressed: _busy ? null : () => _change(remove: true),
              child: const Text('Remove'),
            ),
        ],
      ),
      if (_error != null)
        Text(_error!, style: TextStyle(color: AppColors.of(context).warning)),
    ],
  );
}
