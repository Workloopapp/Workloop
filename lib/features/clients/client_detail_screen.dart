import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/attachments/record_attachment.dart';
import '../../shared/attachments/record_attachments_screen.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/booking_whatsapp_reminder_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/maps_preference_provider.dart';
import '../../shared/providers/workspace_refresh.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/maps_launcher.dart';
import '../../shared/utils/whatsapp_reminder.dart';
import '../../shared/widgets/slate_ui.dart';
import 'widgets/client_appointments_tab.dart';
import 'widgets/client_form.dart';
import 'widgets/client_overview_tab.dart';
import 'widgets/client_payments_tab.dart';
import 'widgets/client_tasks_tab.dart';

export 'providers/client_detail_providers.dart';

class ClientDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> client;
  const ClientDetailScreen({super.key, required this.client});

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, dynamic> _client;
  bool _editing = false;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  late TextEditingController _sourceController;
  late TextEditingController _tagsController;
  late TextEditingController _notesController;
  late TextEditingController _importantNotesController;
  String _status = 'active';
  String _preferredContactMethod = 'phone';
  DateTime? _birthday;
  bool _saving = false;
  bool _moreDetailsExpanded = false;
  bool _allowPop = false;
  bool _openingWhatsApp = false;

  @override
  void initState() {
    super.initState();
    _client = Map<String, dynamic>.from(widget.client);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _nameController = TextEditingController(
      text: _client['name'] as String? ?? '',
    );
    _phoneController = TextEditingController(
      text: _client['phone'] as String? ?? '',
    );
    _emailController = TextEditingController(
      text: _client['email'] as String? ?? '',
    );
    _addressController = TextEditingController(
      text: _client['address'] as String? ?? '',
    );
    _sourceController = TextEditingController(
      text: _client['source'] as String? ?? '',
    );
    _tagsController = TextEditingController(
      text: ((_client['tags'] as List?) ?? const []).join(', '),
    );
    _notesController = TextEditingController(
      text: _client['notes'] as String? ?? '',
    );
    _importantNotesController = TextEditingController(
      text: _client['important_notes'] as String? ?? '',
    );
    _status = _client['status'] as String? ?? 'active';
    _preferredContactMethod =
        _client['preferred_contact_method'] as String? ?? 'phone';
    _birthday = DateTime.tryParse(_client['birthday']?.toString() ?? '');
    _moreDetailsExpanded =
        _sourceController.text.trim().isNotEmpty ||
        _tagsController.text.trim().isNotEmpty ||
        _birthday != null;
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
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

  void _handleTabChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSaveDraft =>
      _nameController.text.trim().isNotEmpty &&
      isValidClientEmail(_emailController.text);

  bool get _hasEditChanges {
    final currentTags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .join(',');
    final savedTags = ((_client['tags'] as List?) ?? const [])
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty)
        .join(',');
    final savedBirthday = DateTime.tryParse(
      _client['birthday']?.toString() ?? '',
    );
    return _nameController.text.trim() !=
            (_client['name'] as String? ?? '').trim() ||
        _phoneController.text.trim() !=
            (_client['phone'] as String? ?? '').trim() ||
        _emailController.text.trim() !=
            (_client['email'] as String? ?? '').trim() ||
        _addressController.text.trim() !=
            (_client['address'] as String? ?? '').trim() ||
        _sourceController.text.trim() !=
            (_client['source'] as String? ?? '').trim() ||
        currentTags != savedTags ||
        _notesController.text.trim() !=
            (_client['notes'] as String? ?? '').trim() ||
        _importantNotesController.text.trim() !=
            (_client['important_notes'] as String? ?? '').trim() ||
        _status != (_client['status'] as String? ?? 'active') ||
        _preferredContactMethod !=
            (_client['preferred_contact_method'] as String? ?? 'phone') ||
        _dateKey(_birthday) != _dateKey(savedBirthday);
  }

  String _dateKey(DateTime? date) => date == null
      ? ''
      : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _handleBack() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_editing || !_hasEditChanges) {
      await _leaveScreen();
      return;
    }
    final decision = await showWorkloopDraftConfirmation(
      context,
      title: 'Save client changes?',
      message: 'You changed this client. Save before returning to Clients?',
      canSave: _canSaveDraft && !_saving,
    );
    if (!mounted) return;
    switch (decision) {
      case WorkloopDraftDecision.save:
        if (await _save()) await _leaveScreen();
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

  // ── Save / Delete ─────────────────────────────────────────────────────────

  Future<bool> _save() async {
    if (_saving) return false;
    if (!_canSaveDraft) {
      _snack(
        'Check the client name and email address.',
        AppColors.of(context).error,
      );
      return false;
    }
    setState(() => _saving = true);
    try {
      final duplicate = findDuplicateClient(
        await ref.read(clientsProvider.future),
        phone: _phoneController.text,
        email: _emailController.text,
        excludingClientId: _client['id'] as String,
      );
      if (!mounted) return false;
      if (duplicate != null) {
        setState(() => _saving = false);
        _snack(
          '${duplicate.name} already uses this phone number or email.',
          AppColors.of(context).t2,
        );
        return false;
      }
      await ref
          .read(clientsRepositoryProvider)
          .update(_client['id'] as String, {
            'name': _nameController.text.trim(),
            'phone': _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            'email': _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            'address': _addressController.text.trim().isEmpty
                ? null
                : _addressController.text.trim(),
            'notes': _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            'important_notes': _importantNotesController.text.trim().isEmpty
                ? null
                : _importantNotesController.text.trim(),
            'status': _status,
            'preferred_contact_method': _preferredContactMethod,
            'source': _sourceController.text.trim().isEmpty
                ? null
                : _sourceController.text.trim(),
            'birthday': _birthday?.toIso8601String().split('T').first,
            'tags': _tagsController.text
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
          });
      if (!mounted) return true;
      setState(() {
        _client['name'] = _nameController.text.trim();
        _client['phone'] = _phoneController.text.trim();
        _client['email'] = _emailController.text.trim();
        _client['address'] = _addressController.text.trim();
        _client['source'] = _sourceController.text.trim();
        _client['tags'] = _tagsController.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList();
        _client['notes'] = _notesController.text.trim();
        _client['important_notes'] = _importantNotesController.text.trim();
        _client['status'] = _status;
        _client['preferred_contact_method'] = _preferredContactMethod;
        _client['birthday'] = _birthday?.toIso8601String().split('T').first;
        _editing = false;
        _saving = false;
      });
      refreshClientRelatedData(ref.invalidate);
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _saving = false);
      _snack(
        'Couldn’t save this client. Please try again.',
        AppColors.of(context).error,
      );
      return false;
    }
  }

  Future<void> _confirmDeleteClient() async {
    var deleting = false;
    String? deleteError;

    await showWorkloopBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => PopScope(
          canPop: !deleting,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete ${_client['name']}?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This removes the client. Their bookings, money records, '
                  'tasks and notes stay in Workloop without a client link.',
                  style: TextStyle(fontSize: 14, color: AppColors.of(ctx).t3),
                  textAlign: TextAlign.center,
                ),
                if (deleteError != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      deleteError!,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.of(ctx).error,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _actionBtn(
                  ctx,
                  label: 'Delete Client',
                  color: AppColors.of(ctx).error,
                  loading: deleting,
                  onTap: () async {
                    if (deleting) return;
                    setModal(() {
                      deleting = true;
                      deleteError = null;
                    });
                    try {
                      await ref
                          .read(clientsRepositoryProvider)
                          .delete(_client['id'] as String);
                    } catch (_) {
                      if (!ctx.mounted) return;
                      setModal(() {
                        deleting = false;
                        deleteError =
                            'Couldn’t delete this client. Nothing was removed. Please try again.';
                      });
                      return;
                    }
                    refreshClientRelatedData(ref.invalidate);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    await _leaveScreen();
                  },
                ),
                const SizedBox(height: 10),
                _cancelBtn(ctx, disabled: deleting),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Contact actions ───────────────────────────────────────────────────────

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _callPhone(String phone) async =>
      launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));

  Future<void> _sendEmail(String email) async =>
      launchUrl(Uri(scheme: 'mailto', path: email));

  Future<void> _sendText(String phone) async =>
      launchUrl(Uri(scheme: 'sms', path: phone.replaceAll(' ', '')));

  Future<void> _openWhatsApp() async {
    if (_openingWhatsApp) return;
    final auth = ref.read(supabaseClientProvider).auth;
    final userId = auth.currentUser?.id;
    final clientId = _client['id'] as String;
    final workspaceId = _client['workspace_id'] as String?;
    bool current() =>
        mounted &&
        ModalRoute.of(context)?.isCurrent != false &&
        userId != null &&
        auth.currentUser?.id == userId &&
        _client['id'] == clientId &&
        ref.read(workspaceIdProvider).value == workspaceId;
    if (!mounted || !current()) return;
    final repository = ref.read(clientsRepositoryProvider);
    final launcher = ref.read(whatsAppUrlLauncherProvider);
    setState(() => _openingWhatsApp = true);
    try {
      final latest = await repository
          .getById(clientId)
          .timeout(const Duration(seconds: 10));
      if (!mounted || !current()) return;
      if (latest == null ||
          latest.id != clientId ||
          latest.workspaceId != workspaceId) {
        _snack(
          'This client is no longer available.',
          AppColors.of(context).error,
        );
        return;
      }
      final number = normaliseWhatsAppPhone(latest.phone);
      if (number == null) {
        _snack(
          'Edit this client’s number: use a UK 07 mobile or include the international country code.',
          AppColors.of(context).error,
        );
        return;
      }
      final opened = await launcher(
        whatsAppChatUri(number),
      ).timeout(const Duration(seconds: 10));
      if (mounted && current() && !opened) {
        _snack(
          'WhatsApp didn’t open. You can use the client’s call or email action instead.',
          AppColors.of(context).error,
        );
      }
    } catch (_) {
      if (mounted && current()) {
        _snack(
          'Could not open WhatsApp. Check your connection and try again.',
          AppColors.of(context).error,
        );
      }
    } finally {
      if (mounted) setState(() => _openingWhatsApp = false);
    }
  }

  Future<void> _openDirections(String address) async {
    if (address.trim().isEmpty) return;
    try {
      var preference = await ref.read(preferredMapsAppProvider.future);
      if (!mounted) return;
      if (preference == MapsAppPreference.askEveryTime) {
        final choice = await showMapLaunchSheet(context, address);
        if (choice == null || !mounted) return;
        preference = choice.app;
        if (choice.remember) {
          await ref
              .read(preferredMapsAppProvider.notifier)
              .setPreference(preference);
        }
      }
      final launched = await launchMapDirections(preference, address);
      if (!launched && mounted) {
        _snack(
          'Couldn’t open directions on this device.',
          AppColors.of(context).t2,
        );
      }
    } catch (_) {
      if (mounted) {
        _snack(
          'Couldn’t open directions on this device.',
          AppColors.of(context).t2,
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final clientId = _client['id'] as String;
    final phone = _client['phone'] as String? ?? '';
    final email = _client['email'] as String? ?? '';
    final preferredMethod =
        _client['preferred_contact_method'] as String? ?? 'phone';
    final name = _client['name'] as String? ?? '?';
    final initials = name
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return PopScope(
      canPop: _allowPop || !_editing || !_hasEditChanges,
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
                      title: _editing ? 'Edit client' : 'Clients',
                      backSemanticLabel: 'Back to clients',
                      onBack: _handleBack,
                      trailing: _HeaderAction(
                        label: _editing ? 'Save' : 'Edit',
                        primary: _editing,
                        loading: _saving,
                        onTap: _saving || (_editing && !_canSaveDraft)
                            ? null
                            : () => _editing
                                  ? _save()
                                  : setState(() => _editing = true),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_editing)
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
                        child: _editForm(),
                      ),
                    )
                  else
                    Expanded(
                      child: NestedScrollView(
                        headerSliverBuilder: (context, innerBoxIsScrolled) => [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageX,
                              0,
                              AppSpacing.pageX,
                              AppSpacing.sm,
                            ),
                            sliver: SliverList.list(
                              children: [
                                _ClientCompactHeader(
                                  name: name,
                                  initials: initials,
                                  status:
                                      _client['status'] as String? ?? 'active',
                                  preferredContact: _contactLabel(
                                    preferredMethod,
                                  ),
                                  onCall: phone.isEmpty
                                      ? null
                                      : () => _callPhone(phone),
                                  preferredIcon: _preferredContactIcon(
                                    preferredMethod,
                                  ),
                                  onPreferred: switch (preferredMethod) {
                                    'email' =>
                                      email.isEmpty
                                          ? null
                                          : () => _sendEmail(email),
                                    'sms' =>
                                      phone.isEmpty
                                          ? null
                                          : () => _sendText(phone),
                                    'whatsapp' =>
                                      phone.isEmpty ? null : _openWhatsApp,
                                    _ =>
                                      phone.isEmpty
                                          ? null
                                          : () => _callPhone(phone),
                                  },
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _ClientWorkspaceNavigation(
                                  index: _tabController.index,
                                  onChanged: _tabController.animateTo,
                                ),
                              ],
                            ),
                          ),
                        ],
                        body: TabBarView(
                          controller: _tabController,
                          children: [
                            ClientOverviewTab(
                              clientId: clientId,
                              client: _client,
                              onEdit: () => setState(() => _editing = true),
                              onOpenBookings: () => _tabController.animateTo(1),
                              onOpenPayments: () => _tabController.animateTo(2),
                              onOpenTasks: () => _tabController.animateTo(3),
                              onOpenFiles:
                                  (_client['workspace_id'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                  ? () => Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => RecordAttachmentsScreen(
                                          workspaceId:
                                              _client['workspace_id'] as String,
                                          target: AttachmentTarget.client(
                                            clientId,
                                          ),
                                          recordTitle: name,
                                        ),
                                      ),
                                    )
                                  : null,
                              onOpenAddress: _openDirections,
                            ),
                            ClientAppointmentsTab(clientId: clientId),
                            ClientPaymentsTab(
                              clientId: clientId,
                              clientName: name,
                            ),
                            ClientTasksTab(
                              clientId: clientId,
                              clientName: name,
                            ),
                          ],
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

  // ── Edit form ─────────────────────────────────────────────────────────────

  Widget _editForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClientForm(
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
          additionalInformationExpanded: _moreDetailsExpanded,
          onStatusChanged: (value) => setState(() => _status = value),
          onPreferredContactChanged: (value) =>
              setState(() => _preferredContactMethod = value),
          onBirthdayChanged: (value) => setState(() => _birthday = value),
          onToggleAdditionalInformation: () =>
              setState(() => _moreDetailsExpanded = !_moreDetailsExpanded),
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.xl),
        const WorkloopDivider(),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: _confirmDeleteClient,
            child: Text(
              'Delete client',
              style: TextStyle(
                color: AppColors.of(context).error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ClientCompactHeader extends StatelessWidget {
  final String name;
  final String initials;
  final String status;
  final String preferredContact;
  final VoidCallback? onCall;
  final IconData preferredIcon;
  final VoidCallback? onPreferred;

  const _ClientCompactHeader({
    required this.name,
    required this.initials,
    required this.status,
    required this.preferredContact,
    required this.onCall,
    required this.preferredIcon,
    required this.onPreferred,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = status == 'active'
        ? AppColors.of(context).modClients
        : status == 'lead'
        ? AppColors.of(context).warning
        : AppColors.of(context).t3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const WorkloopIllustration(
                    kind: WorkloopIllustrationKind.folder,
                    size: 64,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      initials.isEmpty ? '?' : initials,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.of(context).t1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _statusLabel(status),
                    style: TextStyle(color: statusColor, fontSize: 13),
                  ),
                  Text(
                    'Prefers $preferredContact',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _CompactContactButton(
                icon: LucideIcons.phone,
                label: 'Call',
                onTap: onCall,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _CompactContactButton(
                icon: preferredIcon,
                label: preferredContact,
                onTap: onPreferred,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _CompactContactButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, textAlign: TextAlign.center),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppSpacing.minTouch),
        foregroundColor: AppColors.of(context).t1,
        side: BorderSide(color: AppColors.of(context).border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final String label;
  final bool primary;
  final bool loading;
  final VoidCallback? onTap;

  const _HeaderAction({
    required this.label,
    required this.primary,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || loading;
    return Material(
      color: primary && enabled
          ? AppColors.of(context).accentPrimary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
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
                      color: !enabled
                          ? AppColors.of(context).t4
                          : primary
                          ? AppColors.of(context).accentPrimary
                          : AppColors.of(context).t2,
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

class _ClientWorkspaceNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _ClientWorkspaceNavigation({
    required this.index,
    required this.onChanged,
  });

  static const _labels = ['Overview', 'Bookings', 'Money', 'Tasks'];

  @override
  Widget build(BuildContext context) {
    return WorkloopNavigationControl<int>(
      selected: index,
      onChanged: onChanged,
      segments: [
        for (final (tabIndex, label) in _labels.indexed)
          WorkloopSegment(value: tabIndex, label: label),
      ],
    );
  }
}

Widget _actionBtn(
  BuildContext context, {
  required String label,
  required VoidCallback? onTap,
  bool loading = false,
  Color? color,
}) {
  final colors = AppColors.of(context);
  final resolvedColor = color ?? colors.brandAccent;
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: resolvedColor,
        foregroundColor: resolvedColor == colors.error
            ? colors.bg
            : colors.onBrandAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        elevation: 0,
      ),
      child: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: colors.bg,
                strokeWidth: 2,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
    ),
  );
}

Widget _cancelBtn(BuildContext ctx, {bool disabled = false}) => SizedBox(
  width: double.infinity,
  height: 52,
  child: TextButton(
    onPressed: disabled ? null : () => Navigator.pop(ctx),
    child: Text(
      'Cancel',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.of(ctx).t3,
      ),
    ),
  ),
);

String _contactLabel(String value) {
  return switch (value) {
    'sms' => 'Text message',
    'email' => 'Email',
    'whatsapp' => 'WhatsApp',
    _ => 'Phone',
  };
}

IconData _preferredContactIcon(String value) {
  return switch (value) {
    'sms' => LucideIcons.messageSquare,
    'email' => LucideIcons.mail,
    'whatsapp' => LucideIcons.messageCircle,
    _ => LucideIcons.phone,
  };
}

String _statusLabel(String value) {
  return switch (value) {
    'lead' => 'LEAD',
    'inactive' => 'INACTIVE',
    _ => 'ACTIVE',
  };
}
