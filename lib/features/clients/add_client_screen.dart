import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/widgets/slate_ui.dart';
import 'widgets/client_form.dart';

class AddClientScreen extends ConsumerStatefulWidget {
  const AddClientScreen({super.key});

  @override
  ConsumerState<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends ConsumerState<AddClientScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _sourceController = TextEditingController();
  final _tagsController = TextEditingController();
  final _notesController = TextEditingController();
  final _importantNotesController = TextEditingController();
  String _status = 'active';
  String _preferredContactMethod = 'phone';
  DateTime? _birthday;
  bool _saving = false;
  bool _additionalInformationExpanded = false;
  bool _allowPop = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _sourceController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    _importantNotesController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      isValidClientEmail(_emailController.text);

  bool get _hasChanges =>
      _nameController.text.trim().isNotEmpty ||
      _phoneController.text.trim().isNotEmpty ||
      _emailController.text.trim().isNotEmpty ||
      _addressController.text.trim().isNotEmpty ||
      _sourceController.text.trim().isNotEmpty ||
      _tagsController.text.trim().isNotEmpty ||
      _notesController.text.trim().isNotEmpty ||
      _importantNotesController.text.trim().isNotEmpty ||
      _status != 'active' ||
      _preferredContactMethod != 'phone' ||
      _birthday != null;

  Future<void> _handleBack() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_hasChanges) {
      await _leaveScreen();
      return;
    }
    final decision = await showWorkloopDraftConfirmation(
      context,
      title: 'Save this client?',
      message: 'Your client details have not been saved yet.',
      saveLabel: 'Save client',
      canSave: _canSave && !_saving,
    );
    if (!mounted) return;
    switch (decision) {
      case WorkloopDraftDecision.save:
        await _save();
        return;
      case WorkloopDraftDecision.discard:
        await _leaveScreen();
        return;
      case WorkloopDraftDecision.stay:
        return;
    }
  }

  Future<void> _leaveScreen() async {
    if (!_allowPop && mounted) setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) workloopGoBack(context, fallbackLocation: '/clients');
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);

    try {
      final duplicate = await _findDuplicate();
      if (duplicate != null) {
        if (mounted) {
          setState(() => _saving = false);
          _showMessage(
            '${duplicate.name} already uses this phone number or email.',
            AppColors.of(context).t2,
          );
        }
        return;
      }

      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      await ref
          .read(clientsRepositoryProvider)
          .create(
            workspaceId: workspaceId,
            name: _nameController.text,
            phone: _phoneController.text,
            email: _emailController.text,
            address: _addressController.text,
            notes: _notesController.text,
            importantNotes: _importantNotesController.text,
            status: _status,
            preferredContactMethod: _preferredContactMethod,
            source: _sourceController.text,
            birthday: _birthday,
            tags: _tags,
          );
      ref.invalidate(clientsProvider);
      ref.invalidate(clientCrmRecordsProvider);
      if (mounted) {
        _showMessage(
          '${_nameController.text.trim()} added',
          AppColors.of(context).green,
        );
        await _leaveScreen();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _showMessage(
          'Couldn’t add this client. Please try again.',
          AppColors.of(context).error,
        );
      }
    }
  }

  List<String> get _tags => _tagsController.text
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();

  Future<Client?> _findDuplicate() async {
    final clients = await ref.read(clientsProvider.future);
    return findDuplicateClient(
      clients,
      phone: _phoneController.text,
      email: _emailController.text,
    );
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const Positioned.fill(child: WorkloopTexturedBackdrop()),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageX,
                      AppSpacing.screenTop,
                      AppSpacing.pageX,
                      0,
                    ),
                    child: WorkloopRouteHeader(
                      title: 'New client',
                      backSemanticLabel: 'Back to clients',
                      onBack: _handleBack,
                      trailing: _SaveAction(
                        label: 'Add',
                        loading: _saving,
                        enabled: _canSave,
                        onTap: _save,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageX,
                        0,
                        AppSpacing.pageX,
                        AppSpacing.xxl,
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ClientForm(
                        nameController: _nameController,
                        phoneController: _phoneController,
                        emailController: _emailController,
                        addressController: _addressController,
                        sourceController: _sourceController,
                        tagsController: _tagsController,
                        notesController: _notesController,
                        importantNotesController: _importantNotesController,
                        status: _status,
                        preferredContactMethod: _preferredContactMethod,
                        birthday: _birthday,
                        additionalInformationExpanded:
                            _additionalInformationExpanded,
                        autofocusName: true,
                        onStatusChanged: (value) =>
                            setState(() => _status = value),
                        onPreferredContactChanged: (value) =>
                            setState(() => _preferredContactMethod = value),
                        onBirthdayChanged: (value) =>
                            setState(() => _birthday = value),
                        onToggleAdditionalInformation: () => setState(
                          () => _additionalInformationExpanded =
                              !_additionalInformationExpanded,
                        ),
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveAction extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _SaveAction({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.of(context).accentPrimary.withValues(alpha: 0.14)
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
                      color: AppColors.of(context).accentPrimary,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: enabled
                          ? AppColors.of(context).accentPrimary
                          : AppColors.of(context).t4,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
