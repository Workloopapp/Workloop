import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/utils/workflow_idempotency.dart';
import '../../shared/providers/business_clock_provider.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/dashboard_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'widgets/money_editor_widgets.dart';
import 'documents/business_document_detail_screen.dart';

typedef _PaymentDraft = ({
  String amount,
  String description,
  String? clientId,
  String status,
  bool paymentStateChanged,
  String date,
  String dueDate,
});

class AddPaymentScreen extends ConsumerStatefulWidget {
  final String? initialClientId;
  final String? appointmentId;
  final Payment? payment;

  const AddPaymentScreen({
    super.key,
    this.initialClientId,
    this.appointmentId,
    this.payment,
  });

  @override
  ConsumerState<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends ConsumerState<AddPaymentScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedClientId;
  String _status = 'paid';
  bool _paymentStateChanged = false;
  DateTime _date = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  final _paymentCreationToken = createPublicRequestToken();
  bool _receivedDateNeedsReview = false;
  bool _saving = false;
  bool _allowPop = false;
  late _PaymentDraft _savedDraft;

  bool get _editing => widget.payment != null;

  @override
  void initState() {
    super.initState();
    final payment = widget.payment;
    if (payment == null) {
      _selectedClientId = widget.initialClientId;
    } else {
      _amountController.text = payment.total == 0
          ? ''
          : payment.total.toStringAsFixed(
              payment.total.truncateToDouble() == payment.total ? 0 : 2,
            );
      _descriptionController.text = payment.notes ?? '';
      _selectedClientId = payment.contactId ?? widget.initialClientId;
      _status = payment.status == 'paid' ? 'paid' : 'sent';
      _date = payment.status == 'paid'
          ? payment.receivedDate
          : payment.issueDate;
      _dueDate = payment.dueDate ?? payment.issueDate;
    }
    _amountController.addListener(_handleDraftChanged);
    _descriptionController.addListener(_handleDraftChanged);
    _savedDraft = _currentDraft;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSave =>
      _amountController.text.trim().isNotEmpty &&
      (double.tryParse(_amountController.text.trim()) ?? 0) > 0;

  _PaymentDraft get _currentDraft => (
    amount: _amountController.text.trim(),
    description: _descriptionController.text.trim(),
    clientId: _selectedClientId,
    status: _status,
    paymentStateChanged: _paymentStateChanged,
    date: _dateKey(_date),
    dueDate: _dateKey(_dueDate),
  );

  bool get _hasChanges => _currentDraft != _savedDraft;

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _handleBack() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_hasChanges) {
      await _leaveScreen();
      return;
    }
    final decision = await showWorkloopDraftConfirmation(
      context,
      title: _editing ? 'Save income changes?' : 'Save this income?',
      message: _editing
          ? 'You changed this money entry. Save before leaving?'
          : 'Your income details have not been saved yet.',
      saveLabel: _editing ? 'Save changes' : 'Record income',
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
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _save() async {
    if (!_canSave || _saving) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_status == 'paid' &&
        DateUtils.dateOnly(_date).isAfter(ref.read(businessTodayProvider))) {
      setState(() => _receivedDateNeedsReview = true);
      return false;
    }
    setState(() => _saving = true);
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null) {
        if (mounted) setState(() => _saving = false);
        return false;
      }

      final amount = double.parse(_amountController.text.trim());
      final description = _descriptionController.text.trim();
      if (_editing) {
        await ref
            .read(paymentsRepositoryProvider)
            .update(
              existingPayment: widget.payment!,
              amount: amount,
              status: _status,
              date: _date,
              paymentStateChanged: _paymentStateChanged,
              dueDate: _status == 'paid' ? _date : _dueDate,
              contactId: _selectedClientId,
              appointmentId: widget.payment!.appointmentId,
              notes: description,
            );
      } else {
        await ref
            .read(paymentsRepositoryProvider)
            .create(
              paymentId: _paymentCreationToken,
              workspaceId: workspaceId,
              amount: amount,
              status: _status,
              date: _date,
              dueDate: _status == 'paid' ? _date : _dueDate,
              contactId: _selectedClientId,
              appointmentId: widget.appointmentId,
              notes: description,
            );
      }

      ref.invalidate(invoicesProvider);
      ref.invalidate(dashboardRevenueProvider);
      ref.invalidate(clientCrmRecordsProvider);
      if (mounted) await _leaveScreen();
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not save this income. Please try again.',
            ),
            backgroundColor: AppColors.of(context).error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _pickDate({required bool dueDate}) async {
    final current = dueDate ? _dueDate : _date;
    final today = ref.read(businessTodayProvider);
    final lastDate = !dueDate && _status == 'paid'
        ? today
        : today.add(const Duration(days: 730));
    final picked = await showWorkloopDatePicker(
      context: context,
      initialDate: current.isAfter(lastDate) ? lastDate : current,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (dueDate) {
        _dueDate = picked;
      } else {
        _date = picked;
        _receivedDateNeedsReview = false;
        if (_dueDate.isBefore(_date)) _dueDate = _date;
      }
    });
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.payment?.sourceDocumentId case final String documentId) {
      return BusinessDocumentDetailScreen(documentId: documentId);
    }
    final clients = ref.watch(clientsProvider);
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
                      title: _editing ? 'Edit income' : 'Record income',
                      backSemanticLabel: 'Back to Money',
                      onBack: _handleBack,
                      trailing: MoneySaveAction(
                        label: _editing ? 'Save' : 'Add',
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MoneyFormSection(
                            title: 'Amount',
                            isRequired: true,
                            subtitle: 'The amount received or expected.',
                            child: MoneyAmountField(
                              controller: _amountController,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          MoneyFormSection(
                            title: 'Payment state',
                            isRequired: true,
                            subtitle: 'Choose whether the money is already in.',
                            child: WorkloopSegmentedControl<String>(
                              selected: _status,
                              segments: const [
                                WorkloopSegment(
                                  value: 'paid',
                                  label: 'Received',
                                ),
                                WorkloopSegment(
                                  value: 'sent',
                                  label: 'To collect',
                                ),
                              ],
                              onChanged: (value) => setState(() {
                                _status = value;
                                _paymentStateChanged = true;
                              }),
                            ),
                          ),
                          if (_editing &&
                              widget.payment!.collectedAmount > 0 &&
                              widget.payment!.status != 'paid' &&
                              !_paymentStateChanged) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '£${widget.payment!.collectedAmount.toStringAsFixed(2)} already received will be preserved.',
                              style: TextStyle(
                                color: AppColors.of(context).t3,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          MoneyFormSection(
                            title: 'Details',
                            subtitle:
                                'Connect this entry to a client when useful.',
                            child: Column(
                              children: [
                                WorkloopFormField(
                                  label: 'Client',
                                  isRequired: false,
                                  child: clients.when(
                                    data: (data) =>
                                        WorkloopPickerField<String?>(
                                          value: _selectedClientId,
                                          title: 'Choose a client',
                                          hint: 'No client',
                                          searchHint: 'Search clients',
                                          searchable: true,
                                          leadingIcon: LucideIcons.users,
                                          options: [
                                            const WorkloopPickerOption<String?>(
                                              value: null,
                                              label: 'No client',
                                              subtitle:
                                                  'Keep this entry unlinked',
                                            ),
                                            ...data.map(
                                              (client) =>
                                                  WorkloopPickerOption<String?>(
                                                    value: client.id,
                                                    label: client.name,
                                                  ),
                                            ),
                                          ],
                                          onChanged: (value) => setState(
                                            () => _selectedClientId = value,
                                          ),
                                        ),
                                    loading: () => const SlateLoadingBlock(
                                      height: 54,
                                      radius: AppRadius.md,
                                    ),
                                    error: (_, _) => const SlateErrorState(
                                      message: 'Could not load clients',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                MoneyDateField(
                                  label: _status == 'paid'
                                      ? 'Received date'
                                      : 'Created date',
                                  value: _formatDate(_date),
                                  onTap: () => _pickDate(dueDate: false),
                                ),
                                if (_status == 'paid' &&
                                    _receivedDateNeedsReview)
                                  Text(
                                    'Received income must be dated today or earlier. Use To collect for expected income.',
                                    style: TextStyle(
                                      color: AppColors.of(context).error,
                                    ),
                                  ),
                                if (_status != 'paid') ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  MoneyDateField(
                                    label: 'Due date',
                                    value: _formatDate(_dueDate),
                                    icon: LucideIcons.clock3,
                                    onTap: () => _pickDate(dueDate: true),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          MoneyFormSection(
                            title: 'Note',
                            subtitle: 'Optional context for this entry.',
                            child: MoneyTextField(
                              controller: _descriptionController,
                              label: 'Note',
                              hint: 'Booking, service or useful reference',
                              icon: LucideIcons.fileText,
                              maxLines: 3,
                            ),
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
}
