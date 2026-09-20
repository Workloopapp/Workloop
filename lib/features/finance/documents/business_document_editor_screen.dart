import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/providers/business_documents_provider.dart';
import '../../../shared/providers/business_clock_provider.dart';
import '../../../shared/providers/clients_provider.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/providers/workspace_settings_provider.dart';
import '../../../shared/utils/booking_time.dart';
import '../../../shared/providers/business_document_defaults_provider.dart';
import '../../../shared/providers/appointments_provider.dart';
import '../../settings/business_document_settings_screen.dart';
import 'document_deposit_fields.dart';
import '../../../shared/repositories/business_documents_repository.dart';
import '../../../shared/utils/workflow_idempotency.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import '../widgets/money_editor_widgets.dart';
import 'business_document.dart';
import 'business_document_detail_screen.dart';
import 'document_editor_fields.dart';

class BusinessDocumentEditorScreen extends ConsumerStatefulWidget {
  final BusinessDocument? document;
  final BusinessDocument? copyFrom;
  final String type;
  final Appointment? initialAppointment;
  final String? initialClientId;
  const BusinessDocumentEditorScreen({
    super.key,
    this.document,
    this.copyFrom,
    this.type = 'invoice',
    this.initialAppointment,
    this.initialClientId,
  });

  @override
  ConsumerState<BusinessDocumentEditorScreen> createState() =>
      _DocumentEditorState();
}

class _DocumentEditorState extends ConsumerState<BusinessDocumentEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _businessAddress = TextEditingController();
  final _businessEmail = TextEditingController();
  final _businessPhone = TextEditingController();
  final _legalName = TextEditingController();
  final _companyNumber = TextEditingController();
  final _vatNumber = TextEditingController();
  final _customerName = TextEditingController();
  final _customerAddress = TextEditingController();
  final _customerEmail = TextEditingController();
  final _customerPhone = TextEditingController();
  final _depositValue = TextEditingController();
  String _depositType = 'none';
  DateTime _depositDue = DateTime.now();
  final _instructions = TextEditingController();
  final _notes = TextEditingController();
  final _lines = <DocumentLineControllers>[];
  late final String _id;
  String? _workspaceId;
  String? _contactId;
  int _vat = 0;
  bool _pricesIncludeVat = false;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _allowPop = false;
  bool _loadFailed = false;
  bool _saveFailed = false;
  bool _checkingSaved = false;
  String? _error;
  DateTime _issued = DateTime.now();
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  DateTime _service = DateTime.now();

  String get _type =>
      widget.document?.type ?? widget.copyFrom?.type ?? widget.type;
  String get _title => _type == 'quote' ? 'quote' : 'invoice';
  List<TextEditingController> get _textControllers => [
    _businessName,
    _businessAddress,
    _businessEmail,
    _businessPhone,
    _legalName,
    _companyNumber,
    _vatNumber,
    _customerName,
    _customerAddress,
    _customerEmail,
    _customerPhone,
    _depositValue,
    _instructions,
    _notes,
  ];

  @override
  void initState() {
    super.initState();
    _id = widget.document?.id ?? createPublicRequestToken();
    _contactId =
        widget.document?.contactId ??
        widget.copyFrom?.contactId ??
        widget.initialAppointment?.contactId ??
        widget.initialClientId;
    _load();
  }

  Future<void> _load() async {
    try {
      final workspace = await ref.read(workspaceProvider.future);
      final defaults = await ref.read(businessDocumentDefaultsProvider.future);
      final settings = await ref.read(workspaceSettingsProvider.future);
      if (!mounted) return;
      final id = workspace?['id'] as String?;
      if (id == null) throw StateError('No workspace');
      _workspaceId = id;
      final document = widget.document;
      if (document != null &&
          (document.workspaceId != id || !document.isDraft)) {
        throw StateError('This document cannot be edited.');
      }
      final source = document ?? widget.copyFrom;
      if (source != null && source.workspaceId != id) {
        throw StateError('Account changed');
      }
      _applyBusiness(document?.business ?? defaults.business);
      _vat = document?.taxRate ?? widget.copyFrom?.taxRate ?? defaults.taxRate;
      _pricesIncludeVat =
          source?.pricesIncludeVat ?? (widget.initialAppointment != null);
      _issued = document?.issueDate ?? ref.read(workspaceTodayProvider);
      _due =
          document?.dueDate ??
          _issued.add(
            Duration(
              days: _type == 'quote'
                  ? defaults.quoteValidityDays
                  : defaults.paymentTermsDays,
            ),
          );
      _service =
          document?.serviceDate ??
          (widget.initialAppointment == null
              ? null
              : bookingTimeInZone(
                  widget.initialAppointment!.startTime,
                  widget.initialAppointment!.recurrenceTimezone ??
                      settings?['timezone'] as String? ??
                      'Europe/London',
                )) ??
          _issued;
      _instructions.text =
          source?.paymentInstructions ?? defaults.paymentInstructions;
      _notes.text = source?.notes ?? '';
      _depositType = source?.depositType ?? 'none';
      _depositValue.text = source != null && source.hasDeposit
          ? documentMoneyInput(source.depositValueHundredths)
          : '';
      _depositDue = document?.depositDueDate ?? _issued;
      if (source != null) {
        _customerName.text = source.customer['name'] ?? '';
        _customerAddress.text = source.customer['address'] ?? '';
        _customerEmail.text = source.customer['email'] ?? '';
        _customerPhone.text = source.customer['phone'] ?? '';
        _lines.addAll(source.items.map(DocumentLineControllers.fromItem));
      } else {
        final clients = await ref.read(clientsProvider.future);
        if (!mounted) return;
        for (final client in clients) {
          if (client.id == _contactId) _setClient(client);
        }
        final booking = widget.initialAppointment;
        if (booking != null &&
            booking.serviceItems.isNotEmpty &&
            (booking.serviceItems.fold<double>(
                          0,
                          (total, item) => total + item.price,
                        ) *
                        100)
                    .round() ==
                (booking.price * 100).round()) {
          _lines.addAll(
            booking.serviceItems.map(
              (item) => DocumentLineControllers.fromItem(
                BusinessDocumentItem(
                  description: item.name,
                  quantityHundredths: 100,
                  unitPricePence: (item.price * 100).round(),
                ),
              ),
            ),
          );
        } else if (booking != null) {
          _lines.add(
            DocumentLineControllers.fromItem(
              BusinessDocumentItem(
                description:
                    booking.title ?? booking.serviceName ?? 'Booked service',
                quantityHundredths: 100,
                unitPricePence: (booking.price * 100).round(),
              ),
            ),
          );
        }
      }
      if (_lines.isEmpty) _lines.add(DocumentLineControllers());
      if (ref.read(workspaceIdProvider).value != id) {
        throw StateError('Account changed');
      }
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
          _error =
              'Could not load the document details. Go back and try again.';
        });
      }
    }
  }

  void _setClient(Client client) {
    _contactId = client.id;
    _customerName.text = client.name;
    _customerAddress.text = client.address ?? '';
    _customerEmail.text = client.email ?? '';
    _customerPhone.text = client.phone ?? '';
  }

  void _applyBusiness(Map<String, String> business) {
    _businessName.text = business['name'] ?? '';
    _businessAddress.text = business['address'] ?? '';
    _businessEmail.text = business['email'] ?? '';
    _businessPhone.text = business['phone'] ?? '';
    _legalName.text = business['legal_name'] ?? '';
    _companyNumber.text = business['company_number'] ?? '';
    _vatNumber.text = business['vat_number'] ?? '';
  }

  Future<void> _refreshBusiness() async {
    final id = _workspaceId;
    if (id == null || ref.read(workspaceIdProvider).value != id) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use current business details?'),
        content: const Text(
          'Replace this draft’s business details and payment instructions with your saved settings. Customer details and items stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep draft details'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use saved details'),
          ),
        ],
      ),
    );
    if (approved != true ||
        !mounted ||
        ref.read(workspaceIdProvider).value != id) {
      return;
    }
    try {
      ref.invalidate(businessDocumentDefaultsProvider);
      final defaults = await ref.read(businessDocumentDefaultsProvider.future);
      if (!mounted || ref.read(workspaceIdProvider).value != id) return;
      setState(() {
        _applyBusiness(defaults.business);
        _instructions.text = defaults.paymentInstructions;
        _dirty = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load saved business details. Your draft is unchanged.',
        );
      }
    }
  }

  Future<void> _businessSettings() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BusinessDocumentSettingsScreen()),
    );
    if (mounted) ref.invalidate(businessDocumentDefaultsProvider);
  }

  Future<void> _addService(Service service) async {
    if (_lines.length >= 100) return;
    final empty =
        _lines.length == 1 &&
        _lines.first.description.text.trim().isEmpty &&
        _lines.first.price.text.trim().isEmpty;
    if (!empty && !_pricesIncludeVat && _vat > 0) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Use prices including VAT?'),
          content: const Text(
            'Saved service prices are the agreed final charge. This will treat every price already entered as including VAT too. Review the total before saving.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use prices including VAT'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    if (!mounted || ref.read(workspaceIdProvider).value != _workspaceId) return;
    setState(() {
      if (_lines.length == 1 &&
          _lines.first.description.text.trim().isEmpty &&
          _lines.first.price.text.trim().isEmpty) {
        _lines.removeLast().dispose();
      }
      _pricesIncludeVat = true;
      _lines.add(
        DocumentLineControllers.fromItem(
          BusinessDocumentItem(
            description: service.name,
            quantityHundredths: 100,
            unitPricePence: (service.price * 100).round(),
          ),
        ),
      );
      _dirty = true;
    });
  }

  @override
  void dispose() {
    for (final controller in _textControllers) {
      controller.dispose();
    }
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _back() async {
    if (_saving) return;
    if (_dirty) {
      final decision = await showWorkloopDraftConfirmation(
        context,
        title: 'Save this $_title?',
        message: 'Your document has unsaved changes.',
        saveLabel: 'Save draft',
        canSave: !_loading,
      );
      if (!mounted || decision == WorkloopDraftDecision.stay) return;
      if (decision == WorkloopDraftDecision.save) {
        await _save();
        return;
      }
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_saving || _checkingSaved || _loadFailed || _workspaceId == null) {
      return;
    }
    if (ref.read(workspaceIdProvider).value != _workspaceId) return;
    final items = _lines.map((line) => line.item).toList();
    // ListView can dispose offscreen FormFields; validate the complete draft
    // from its retained controllers, not only the currently visible fields.
    if (_customerName.text.trim().isEmpty ||
        _businessName.text.trim().isEmpty ||
        items.any((item) => item == null || item.description.isEmpty)) {
      _form.currentState?.validate();
      setState(
        () => _error =
            'Add the customer and business names, and a description, valid quantity and price for every item.',
      );
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_vat != 0 && _vatNumber.text.trim().isEmpty) {
      setState(
        () => _error = 'Enter your VAT registration number before adding VAT.',
      );
      return;
    }
    final total = documentTotals(
      items.cast<BusinessDocumentItem>(),
      _vat,
      _pricesIncludeVat,
    ).total;
    final depositValue = _depositType == 'none'
        ? 0
        : parseDocumentMoney(_depositValue.text);
    final deposit = depositValue == null
        ? 0
        : documentDepositPence(total, _depositType, depositValue);
    if (_depositType != 'none' &&
        (depositValue == null ||
            depositValue <= 0 ||
            deposit <= 0 ||
            deposit > total ||
            (_depositType == 'percentage' && depositValue > 10000))) {
      setState(
        () => _error =
            'Choose a deposit greater than zero and no more than the invoice total.',
      );
      return;
    }
    if (_due.isBefore(DateTime(_issued.year, _issued.month, _issued.day)) ||
        (_depositType != 'none' &&
            (_depositDue.isBefore(
                  DateTime(_issued.year, _issued.month, _issued.day),
                ) ||
                _depositDue.isAfter(
                  DateTime(_due.year, _due.month, _due.day, 23, 59),
                )))) {
      setState(
        () => _error =
            'Check the dates. The deposit is due between the issue date and final payment date.',
      );
      return;
    }
    final workspaceId = _workspaceId!;
    if (ref.read(workspaceIdProvider).value != workspaceId) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
      _error = null;
    });
    try {
      final document = await ref
          .read(businessDocumentsRepositoryProvider)
          .save(
            workspaceId: workspaceId,
            id: _id,
            revision: widget.document?.revision,
            document: {
              'type': _type,
              'contact_id': _contactId,
              'appointment_id':
                  widget.document?.appointmentId ??
                  widget.initialAppointment?.id,
              'issue_date': documentDate(_issued),
              'due_date': documentDate(_due),
              'service_date': documentDate(_service),
              'tax_rate': _vat,
              'prices_include_vat': _pricesIncludeVat,
              'deposit_type': _depositType,
              'deposit_value': documentMoneyInput(depositValue ?? 0),
              'deposit_due_date': _depositType == 'none'
                  ? null
                  : documentDate(_depositDue),
              'business_snapshot': {
                'logo_url':
                    ref.read(workspaceProvider).value?['logo_url'] as String? ??
                    '',
                'name': _businessName.text.trim(),
                'address': _businessAddress.text.trim(),
                'email': _businessEmail.text.trim(),
                'phone': _businessPhone.text.trim(),
                'legal_name': _legalName.text.trim(),
                'company_number': _companyNumber.text.trim(),
                'vat_number': _vatNumber.text.trim(),
              },
              'client_snapshot': {
                'name': _customerName.text.trim(),
                'address': _customerAddress.text.trim(),
                'email': _customerEmail.text.trim(),
                'phone': _customerPhone.text.trim(),
              },
              'payment_instructions': _instructions.text.trim(),
              'notes': _notes.text.trim(),
            },
            items: items.cast<BusinessDocumentItem>(),
          );
      if (!mounted || ref.read(workspaceIdProvider).value != workspaceId) {
        return;
      }
      ref.invalidate(businessDocumentsProvider);
      ref.invalidate(businessDocumentProvider(_id));
      setState(() {
        _allowPop = true;
        _dirty = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, document);
    } catch (_) {
      if (mounted && ref.read(workspaceIdProvider).value == workspaceId) {
        setState(() {
          _saveFailed = true;
          _error =
              'Could not confirm this save. Your edits are still here. '
              'Try again, or review the saved version before making more changes.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewSaved() async {
    final workspaceId = _workspaceId;
    if (_saving ||
        _checkingSaved ||
        workspaceId == null ||
        ref.read(workspaceIdProvider).value != workspaceId) {
      return;
    }
    setState(() => _checkingSaved = true);
    try {
      final saved = await ref
          .read(businessDocumentsRepositoryProvider)
          .get(workspaceId, _id);
      if (!mounted ||
          ref.read(workspaceIdProvider).value != workspaceId ||
          saved.workspaceId != workspaceId) {
        return;
      }
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Open the saved version?'),
          content: const Text(
            'This replaces the form with the saved version. '
            'Any unsaved changes on this screen will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open saved version'),
            ),
          ],
        ),
      );
      if (replace != true ||
          !mounted ||
          ref.read(workspaceIdProvider).value != workspaceId) {
        return;
      }
      ref.invalidate(businessDocumentsProvider);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => saved.isDraft
              ? BusinessDocumentEditorScreen(document: saved)
              : BusinessDocumentDetailScreen(documentId: saved.id),
        ),
      );
    } catch (_) {
      if (mounted && ref.read(workspaceIdProvider).value == workspaceId) {
        setState(
          () => _error =
              'Could not load a saved copy. Your edits are still here. '
              'Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _checkingSaved = false);
    }
  }

  Future<void> _pickDate(
    String label,
    DateTime value,
    void Function(DateTime) apply,
  ) async {
    final result = await showWorkloopDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (result != null && mounted) {
      setState(() {
        apply(result);
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider).value ?? <Client>[];
    final services = ref.watch(servicesProvider);
    final defaults = ref.watch(businessDocumentDefaultsProvider);
    final currentWorkspace = ref.watch(workspaceIdProvider);
    final accountChanged =
        !_loading &&
        _workspaceId != null &&
        currentWorkspace.value != _workspaceId;
    final totals = documentTotals(
      _lines.map((line) => line.item).whereType<BusinessDocumentItem>(),
      _vat,
      _pricesIncludeVat,
    );
    final subtotal = totals.subtotal;
    final tax = totals.tax;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.pageX),
                child: WorkloopRouteHeader(
                  title: widget.document == null
                      ? 'New $_title'
                      : 'Edit $_title',
                  onBack: _back,
                  trailing: MoneySaveAction(
                    label: 'Save draft',
                    loading: _saving,
                    enabled:
                        !_loading &&
                        !_loadFailed &&
                        !accountChanged &&
                        !_checkingSaved &&
                        _workspaceId != null,
                    onTap: _save,
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : accountChanged || _loadFailed
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.pageX),
                        child: Text(
                          accountChanged
                              ? 'Your account changed. Close this draft and reopen it in the correct account.'
                              : _error ??
                                    'Could not load this document. Close it and try again.',
                        ),
                      )
                    : AbsorbPointer(
                        absorbing: _saving || _checkingSaved,
                        child: Form(
                          key: _form,
                          onChanged: () {
                            if (!_dirty) setState(() => _dirty = true);
                          },
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageX,
                              0,
                              AppSpacing.pageX,
                              36,
                            ),
                            children: [
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: AppColors.of(context).error,
                                    ),
                                  ),
                                ),
                              if (_saveFailed)
                                TextButton(
                                  onPressed: _checkingSaved
                                      ? null
                                      : _reviewSaved,
                                  child: Text(
                                    _checkingSaved
                                        ? 'Checking saved version…'
                                        : 'Review saved draft',
                                  ),
                                ),
                              const Text(
                                'Required fields are needed to save a draft. Complete the details noted below before issuing and sharing.',
                              ),
                              const SizedBox(height: 16),
                              if (widget.document == null &&
                                  !(defaults.value?.isReady ?? false))
                                TextButton.icon(
                                  onPressed: _businessSettings,
                                  icon: const Icon(Icons.business_outlined),
                                  label: const Text(
                                    'Set up your invoice details once',
                                  ),
                                ),
                              const SizedBox(height: 24),
                              MoneyFormSection(
                                title: 'Customer',
                                child: Column(
                                  children: [
                                    if (clients.isNotEmpty)
                                      WorkloopFormField(
                                        label: 'Choose a client',
                                        isRequired: false,
                                        child: DropdownButtonFormField<String>(
                                          initialValue:
                                              clients.any(
                                                (client) =>
                                                    client.id == _contactId,
                                              )
                                              ? _contactId
                                              : null,
                                          isExpanded: true,
                                          items: clients
                                              .map(
                                                (client) => DropdownMenuItem(
                                                  value: client.id,
                                                  child: Text(
                                                    client.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (id) {
                                            for (final client in clients) {
                                              if (client.id == id) {
                                                setState(() {
                                                  _setClient(client);
                                                  _dirty = true;
                                                });
                                              }
                                            }
                                          },
                                        ),
                                      ),
                                    DocumentTextField(
                                      controller: _customerName,
                                      label: 'Customer name',
                                      required: true,
                                      maxLength: 200,
                                    ),
                                    DocumentTextField(
                                      controller: _customerAddress,
                                      label: 'Customer address',
                                      helperText: 'Needed before issuing.',
                                      maxLines: 3,
                                      maxLength: 500,
                                    ),
                                    DocumentTextField(
                                      controller: _customerEmail,
                                      label: 'Customer email',
                                      maxLength: 254,
                                      keyboardType: TextInputType.emailAddress,
                                    ),
                                    DocumentTextField(
                                      controller: _customerPhone,
                                      label: 'Customer phone',
                                      keyboardType: TextInputType.phone,
                                      maxLength: 40,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              MoneyFormSection(
                                title: 'Items',
                                subtitle:
                                    'Add services or materials. Choose whether their prices already include VAT.',
                                child: Column(
                                  children: [
                                    services.when(
                                      loading: () =>
                                          const LinearProgressIndicator(),
                                      error: (_, _) => TextButton(
                                        onPressed: () =>
                                            ref.invalidate(servicesProvider),
                                        child: const Text(
                                          'Retry saved services',
                                        ),
                                      ),
                                      data: (rows) {
                                        final available = rows
                                            .map(Service.fromMap)
                                            .where((s) => s.active)
                                            .toList();
                                        if (available.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        return WorkloopFormField(
                                          label: 'Add a saved service',
                                          isRequired: false,
                                          child: DropdownButtonFormField<String>(
                                            key: ValueKey(
                                              'service-picker-${_lines.length}',
                                            ),
                                            isExpanded: true,
                                            items: available
                                                .map(
                                                  (s) => DropdownMenuItem(
                                                    value: s.id,
                                                    child: Text(
                                                      '${s.name} · ${documentMoney((s.price * 100).round())}',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: _lines.length >= 100
                                                ? null
                                                : (id) {
                                                    for (final service
                                                        in available) {
                                                      if (service.id == id) {
                                                        _addService(service);
                                                      }
                                                    }
                                                  },
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    for (var i = 0; i < _lines.length; i++)
                                      DocumentLineEditor(
                                        key: ObjectKey(_lines[i]),
                                        line: _lines[i],
                                        index: i,
                                        onChanged: () =>
                                            setState(() => _dirty = true),
                                        onRemove: _lines.length <= 1
                                            ? null
                                            : () => setState(() {
                                                _lines.removeAt(i).dispose();
                                                _dirty = true;
                                              }),
                                      ),
                                    if (_lines.length < 100)
                                      TextButton.icon(
                                        onPressed: () => setState(() {
                                          _lines.add(DocumentLineControllers());
                                          _dirty = true;
                                        }),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add item'),
                                      ),
                                    SwitchListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Prices include VAT'),
                                      subtitle: const Text(
                                        'Keep the agreed total when copying a booking or saved service.',
                                      ),
                                      value: _pricesIncludeVat,
                                      onChanged: (value) => setState(() {
                                        _pricesIncludeVat = value;
                                        _dirty = true;
                                      }),
                                    ),
                                    WorkloopFormField(
                                      label: 'VAT rate for this document',
                                      isRequired: true,
                                      child: DropdownButtonFormField<int>(
                                        initialValue: _vat,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 0,
                                            child: Text('No VAT / 0%'),
                                          ),
                                          DropdownMenuItem(
                                            value: 5,
                                            child: Text('5%'),
                                          ),
                                          DropdownMenuItem(
                                            value: 20,
                                            child: Text('20%'),
                                          ),
                                        ],
                                        onChanged: (value) => setState(() {
                                          _vat = value ?? 0;
                                          _dirty = true;
                                        }),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'Subtotal ${documentMoney(subtotal)}\nVAT ${documentMoney(tax)}\nTotal ${documentMoney(subtotal + tax)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              MoneyFormSection(
                                title: 'Deposit',
                                subtitle:
                                    'Optional. This is part of the total, not an extra charge.',
                                child: DocumentDepositFields(
                                  type: _depositType,
                                  value: _depositValue,
                                  dueDate: _depositDue,
                                  totalPence: subtotal + tax,
                                  onTypeChanged: (value) => setState(() {
                                    _depositType = value;
                                    _dirty = true;
                                  }),
                                  onChanged: () =>
                                      setState(() => _dirty = true),
                                  onPickDate: () => _pickDate(
                                    'Deposit due',
                                    _depositDue,
                                    (date) => _depositDue = date,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              MoneyFormSection(
                                title: 'Dates',
                                child: Column(
                                  children: [
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Issue date'),
                                      trailing: Text(documentDate(_issued)),
                                      onTap: () => _pickDate(
                                        'Issue date',
                                        _issued,
                                        (date) => _issued = date,
                                      ),
                                    ),
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        _type == 'quote'
                                            ? 'Valid until'
                                            : 'Payment due',
                                      ),
                                      trailing: Text(documentDate(_due)),
                                      onTap: () => _pickDate(
                                        'Due date',
                                        _due,
                                        (date) => _due = date,
                                      ),
                                    ),
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        _type == 'quote'
                                            ? 'Planned work date'
                                            : 'Supply date',
                                      ),
                                      trailing: Text(documentDate(_service)),
                                      onTap: () => _pickDate(
                                        'Supply date',
                                        _service,
                                        (date) => _service = date,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              MoneyFormSection(
                                title: 'Your business',
                                subtitle:
                                    'These details appear on the document.',
                                child: Column(
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed: _refreshBusiness,
                                          child: const Text(
                                            'Use saved business details',
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _businessSettings,
                                          child: const Text(
                                            'Business settings',
                                          ),
                                        ),
                                      ],
                                    ),
                                    DocumentTextField(
                                      controller: _businessName,
                                      label: 'Business / trading name',
                                      required: true,
                                      maxLength: 200,
                                    ),
                                    DocumentTextField(
                                      controller: _legalName,
                                      label: 'Full / registered name',
                                      helperText: _type == 'invoice'
                                          ? 'Needed before issuing an invoice.'
                                          : null,
                                      maxLength: 200,
                                    ),
                                    DocumentTextField(
                                      controller: _businessAddress,
                                      label: 'Business address',
                                      helperText: 'Needed before issuing.',
                                      maxLines: 3,
                                      maxLength: 500,
                                    ),
                                    DocumentTextField(
                                      controller: _businessEmail,
                                      label: 'Business contact email',
                                      helperText: _type == 'invoice'
                                          ? 'Add a business email or phone before issuing.'
                                          : null,
                                      maxLength: 254,
                                      keyboardType: TextInputType.emailAddress,
                                    ),
                                    DocumentTextField(
                                      controller: _businessPhone,
                                      label: 'Business contact phone',
                                      keyboardType: TextInputType.phone,
                                      maxLength: 40,
                                    ),
                                    DocumentTextField(
                                      controller: _companyNumber,
                                      label: 'Company number',
                                      maxLength: 30,
                                    ),
                                    DocumentTextField(
                                      controller: _vatNumber,
                                      label: 'VAT registration number',
                                      isRequired: _vat != 0,
                                      maxLength: 30,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              MoneyFormSection(
                                title: 'Payment and terms',
                                child: Column(
                                  children: [
                                    DocumentTextField(
                                      controller: _instructions,
                                      label: 'Payment instructions',
                                      maxLines: 3,
                                      maxLength: 3000,
                                    ),
                                    DocumentTextField(
                                      controller: _notes,
                                      label: 'Notes and terms',
                                      maxLines: 4,
                                      maxLength: 2000,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              SlateButton(
                                label: 'Save draft',
                                onPressed: _saving ? null : _save,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
