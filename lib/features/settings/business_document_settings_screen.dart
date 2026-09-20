import 'package:flutter/material.dart';

import '../../shared/widgets/workloop_form_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/business_document_defaults.dart';
import '../../shared/providers/business_document_defaults_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_settings_actions.dart';
import '../../shared/widgets/slate_ui.dart';
import '../finance/widgets/money_editor_widgets.dart';

/// One place to review details reused by new quotes, invoices and customer
/// emails. It deliberately never updates existing document snapshots.
class BusinessDocumentSettingsScreen extends ConsumerWidget {
  const BusinessDocumentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceIdProvider);
    return workspace.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        body: SafeArea(
          child: SlateErrorState(
            message: 'Could not load your business.',
            onRetry: () => ref.invalidate(workspaceIdProvider),
          ),
        ),
      ),
      data: (id) => id == null
          ? const Scaffold(
              body: SafeArea(child: Text('Open your business to continue.')),
            )
          : _SettingsEditor(key: ValueKey(id), workspaceId: id),
    );
  }
}

class _SettingsEditor extends ConsumerStatefulWidget {
  final String workspaceId;
  const _SettingsEditor({super.key, required this.workspaceId});

  @override
  ConsumerState<_SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends ConsumerState<_SettingsEditor> {
  final _form = GlobalKey<FormState>();
  final _legalName = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _vatNumber = TextEditingController();
  final _instructions = TextEditingController();
  final _paymentDays = TextEditingController();
  final _quoteDays = TextEditingController();
  BusinessDocumentDefaults? _defaults;
  String? _structure;
  String? _error;
  int _taxRate = 0;
  bool _vatRegistered = false;
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;

  List<TextEditingController> get _controllers => [
    _legalName,
    _address,
    _email,
    _phone,
    _company,
    _vatNumber,
    _instructions,
    _paymentDays,
    _quoteDays,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final defaults = await ref.read(businessDocumentDefaultsProvider.future);
      if (!mounted ||
          ref.read(workspaceIdProvider).value != widget.workspaceId) {
        return;
      }
      _legalName.text = defaults.business['legal_name'] ?? '';
      _address.text = defaults.business['address'] ?? '';
      _email.text = defaults.business['email'] ?? '';
      _phone.text = defaults.business['phone'] ?? '';
      _company.text = defaults.business['company_number'] ?? '';
      _vatNumber.text = defaults.business['vat_number'] ?? '';
      _instructions.text = defaults.paymentInstructions;
      _paymentDays.text = '${defaults.paymentTermsDays}';
      _quoteDays.text = '${defaults.quoteValidityDays}';
      _structure = defaults.businessStructure;
      _taxRate = defaults.taxRate;
      _vatRegistered = _vatNumber.text.isNotEmpty || _taxRate > 0;
      setState(() {
        _defaults = defaults;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load your saved details. Try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _back() async {
    if (_saving) return;
    if (_dirty) {
      final decision = await showWorkloopDraftConfirmation(
        context,
        title: 'Save your invoice setup?',
        message: 'These details will be reused on new documents.',
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
    if (_saving ||
        _defaults == null ||
        ref.read(workspaceIdProvider).value != widget.workspaceId) {
      return;
    }
    if (!_form.currentState!.validate()) {
      setState(() => _error = 'Check the highlighted details before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(updateWorkspaceSettingsProvider)(widget.workspaceId, {
        'business_structure': _structure,
        'business_legal_name': _nullable(_legalName),
        'business_address': _nullable(_address),
        'customer_contact_email': _nullable(_email)?.toLowerCase(),
        'customer_contact_phone': _nullable(_phone),
        'business_company_number': _structure == 'limited_company'
            ? _nullable(_company)
            : null,
        'business_vat_number': _vatRegistered ? _nullable(_vatNumber) : null,
        'default_tax_rate': _vatRegistered ? _taxRate : 0,
        'default_payment_instructions': _instructions.text.trim(),
        'default_payment_terms_days': int.parse(_paymentDays.text.trim()),
        'default_quote_validity_days': int.parse(_quoteDays.text.trim()),
      });
      if (!mounted ||
          ref.read(workspaceIdProvider).value != widget.workspaceId) {
        return;
      }
      ref.invalidate(businessDocumentDefaultsProvider);
      setState(() {
        _dirty = false;
        _allowPop = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save your details. Your changes are still here; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nullable(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || (!_dirty && !_saving),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
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
                    AppSpacing.md,
                  ),
                  child: WorkloopRouteHeader(
                    title: 'Invoice setup',
                    onBack: _back,
                  ),
                ),
                Expanded(
                  child: _defaults == null
                      ? _error == null
                            ? const Center(child: CircularProgressIndicator())
                            : SlateErrorState(message: _error!, onRetry: _load)
                      : SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.pageX,
                            0,
                            AppSpacing.pageX,
                            AppSpacing.xl,
                          ),
                          child: Form(
                            key: _form,
                            onChanged: () {
                              if (!_dirty) setState(() => _dirty = true);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _defaults!.business['name'] ?? '',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.of(context).t1,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Set these up once. New quotes and invoices will use your business details, and you can review them before issuing.',
                                  style: TextStyle(
                                    color: AppColors.of(context).t2,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                MoneyFormSection(
                                  title: 'Your business',
                                  subtitle:
                                      'Use the legal details you want customers to see.',
                                  child: Column(
                                    children: [
                                      WorkloopPickerField<String>(
                                        value: _structure,
                                        title: 'Business type',
                                        hint: 'Choose your business type',
                                        options: const [
                                          WorkloopPickerOption(
                                            value: 'sole_trader',
                                            label: 'Sole trader',
                                          ),
                                          WorkloopPickerOption(
                                            value: 'limited_company',
                                            label: 'Limited company',
                                          ),
                                          WorkloopPickerOption(
                                            value: 'other',
                                            label: 'Other business',
                                          ),
                                        ],
                                        enabled: !_saving,
                                        onChanged: (value) => setState(() {
                                          _structure = value;
                                          _dirty = true;
                                        }),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                      _field(
                                        _legalName,
                                        _structure == 'limited_company'
                                            ? 'Registered company name'
                                            : 'Full legal name',
                                        maxLength: 200,
                                        helper: _structure == 'limited_company'
                                            ? 'Exactly as registered with Companies House.'
                                            : 'For a sole trader, use your full name. Your trading name is shown as well.',
                                      ),
                                      if (_structure == 'limited_company')
                                        _field(
                                          _company,
                                          'Company registration number',
                                          maxLength: 40,
                                        ),
                                      _field(
                                        _address,
                                        'Business address',
                                        lines: 3,
                                        maxLength: 1000,
                                        helper:
                                            'Shown on your documents. Use an address where legal documents can reach you.',
                                      ),
                                    ],
                                  ),
                                ),
                                MoneyFormSection(
                                  title: 'Customer contact details',
                                  subtitle:
                                      'Reused by new invoices and customer emails. Choose the details customers should use.',
                                  child: Column(
                                    children: [
                                      _field(
                                        _email,
                                        'Business email',
                                        keyboard: TextInputType.emailAddress,
                                        maxLength: 254,
                                        validator: (value) {
                                          final text = (value ?? '').trim();
                                          return text.isEmpty ||
                                                  RegExp(
                                                    r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$',
                                                  ).hasMatch(text)
                                              ? null
                                              : 'Enter a valid email address';
                                        },
                                      ),
                                      _field(
                                        _phone,
                                        'Business phone',
                                        keyboard: TextInputType.phone,
                                        maxLength: 40,
                                        validator: (value) {
                                          final text = (value ?? '').trim();
                                          return text.isEmpty ||
                                                  (RegExp(
                                                        r'^\+?[0-9 ()-]+$',
                                                      ).hasMatch(text) &&
                                                      text
                                                              .replaceAll(
                                                                RegExp(r'\D'),
                                                                '',
                                                              )
                                                              .length >=
                                                          7)
                                              ? null
                                              : 'Enter a valid phone number';
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                MoneyFormSection(
                                  title: 'VAT',
                                  child: Column(
                                    children: [
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Registered for VAT'),
                                        subtitle: const Text(
                                          'Only charge VAT if your business is registered.',
                                        ),
                                        value: _vatRegistered,
                                        onChanged: _saving
                                            ? null
                                            : (value) => setState(() {
                                                _vatRegistered = value;
                                                _dirty = true;
                                              }),
                                      ),
                                      if (_vatRegistered) ...[
                                        _field(
                                          _vatNumber,
                                          'VAT registration number',
                                          isRequired: true,
                                          maxLength: 40,
                                          validator: (value) =>
                                              (value ?? '').trim().isEmpty
                                              ? 'Add your VAT number'
                                              : null,
                                        ),
                                        WorkloopPickerField<int>(
                                          value: _taxRate,
                                          title: 'Usual VAT rate',
                                          hint: 'Choose a VAT rate',
                                          enabled: !_saving,
                                          options: const [
                                            WorkloopPickerOption(
                                              value: 20,
                                              label: '20% standard rate',
                                            ),
                                            WorkloopPickerOption(
                                              value: 5,
                                              label: '5% reduced rate',
                                            ),
                                            WorkloopPickerOption(
                                              value: 0,
                                              label: '0% zero-rated',
                                            ),
                                          ],
                                          onChanged: (value) => setState(() {
                                            _taxRate = value;
                                            _dirty = true;
                                          }),
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                MoneyFormSection(
                                  title: 'Payment and quote defaults',
                                  child: Column(
                                    children: [
                                      _field(
                                        _paymentDays,
                                        'Invoice due after (days)',
                                        isRequired: true,
                                        keyboard: TextInputType.number,
                                        helper:
                                            'Use 0 for payment due on the invoice date.',
                                        validator: (value) =>
                                            _daysError(value, 0),
                                      ),
                                      _field(
                                        _quoteDays,
                                        'Quote valid for (days)',
                                        isRequired: true,
                                        keyboard: TextInputType.number,
                                        validator: (value) =>
                                            _daysError(value, 1),
                                      ),
                                      _field(
                                        _instructions,
                                        'How customers should pay',
                                        lines: 5,
                                        maxLength: 3000,
                                        helper:
                                            'For a transfer, include the account name, sort code and account number. These instructions appear on your documents. Never add a password or card details.',
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Optional fields can be left blank to save this setup. You may need some of these details before issuing an invoice; Workloop checks them then. Changing setup only affects new documents.',
                                  style: TextStyle(
                                    color: AppColors.of(context).t2,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                                if (_error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.md,
                                    ),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: AppColors.of(context).error,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: AppSpacing.lg),
                                SlateButton(
                                  label: _saving ? 'Saving…' : 'Save details',
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
        ],
      ),
    ),
  );

  String? _daysError(String? value, int minimum) {
    final days = int.tryParse((value ?? '').trim());
    return days == null || days < minimum || days > 365
        ? 'Enter $minimum–365 days'
        : null;
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    bool isRequired = false,
    int lines = 1,
    int? maxLength,
    TextInputType? keyboard,
    FormFieldValidator<String>? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: WorkloopFormField(
      label: label,
      isRequired: isRequired,
      helperText: helper,
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        maxLines: lines,
        maxLength: maxLength,
        keyboardType: keyboard,
        textCapitalization: keyboard == TextInputType.emailAddress
            ? TextCapitalization.none
            : TextCapitalization.sentences,
        validator: validator,
        decoration: InputDecoration(counterText: ''),
      ),
    ),
  );
}
