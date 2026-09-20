import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/dashboard_provider.dart';
import '../../shared/providers/business_clock_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/workflow_idempotency.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'widgets/money_editor_widgets.dart';
import 'expense_receipt_section.dart';
import 'expense_records_repository.dart';
import 'receipt_extraction.dart';
import 'receipt_review_sheet.dart';
import 'receipt_text_service.dart';

typedef _ExpenseDraft = ({
  String amount,
  String category,
  String date,
  String notes,
});

class ExpenseEditorScreen extends ConsumerStatefulWidget {
  final Expense? expense;

  const ExpenseEditorScreen({super.key, this.expense});

  @override
  ConsumerState<ExpenseEditorScreen> createState() =>
      _ExpenseEditorScreenState();
}

class _ExpenseEditorScreenState extends ConsumerState<ExpenseEditorScreen> {
  static const _categories = ['Materials', 'Travel', 'Tools', 'Rent', 'Other'];

  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  late String _category;
  late DateTime _date;
  late _ExpenseDraft _savedDraft;
  bool _saving = false;
  bool _receiptPicking = false;
  bool _receiptReading = false;
  bool _receiptReviewOpen = false;
  String? _receiptReadingUser;
  String? _receiptReadingWorkspace;
  bool _dateAlreadyChosen = false;
  int _receiptReadRequest = 0;
  bool _paidDateNeedsReview = false;
  final _paidDateKey = GlobalKey();
  bool _allowPop = false;
  ReceiptFile? _receipt;
  String? _persistedExpenseId;
  final _expenseCreationToken = createPublicRequestToken();
  String? _openedWorkspaceId;

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _dateAlreadyChosen = expense != null;
    _openedWorkspaceId =
        expense?.workspaceId ?? ref.read(workspaceIdProvider).value;
    _amountController.text = expense == null
        ? ''
        : expense.amount.toStringAsFixed(
            expense.amount.truncateToDouble() == expense.amount ? 0 : 2,
          );
    _notesController.text = expense?.notes ?? '';
    _category = expense?.category ?? _categories.first;
    _date = expense?.expenseDate ?? ref.read(workspaceTodayProvider);
    _amountController.addListener(_handleDraftChanged);
    _notesController.addListener(_handleDraftChanged);
    _savedDraft = _currentDraft;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSave =>
      (double.tryParse(_amountController.text.trim()) ?? 0) > 0;

  _ExpenseDraft get _currentDraft => (
    amount: _amountController.text.trim(),
    category: _category,
    date:
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
    notes: _notesController.text.trim(),
  );

  bool get _hasChanges => _currentDraft != _savedDraft || _receipt != null;

  Future<void> _handleBack() async {
    if (_saving || _receiptPicking || _receiptReading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_hasChanges) {
      await _leaveScreen();
      return;
    }
    final decision = await showWorkloopDraftConfirmation(
      context,
      title: _editing ? 'Save expense changes?' : 'Save this expense?',
      message: _editing
          ? 'You changed this expense. Save before leaving?'
          : 'Your expense details have not been saved yet.',
      saveLabel: _editing ? 'Save changes' : 'Add expense',
      canSave: _canSave && !_saving && !_receiptPicking && !_receiptReading,
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
    if (!_canSave || _saving || _receiptPicking || _receiptReading) {
      return false;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (DateUtils.dateOnly(_date).isAfter(ref.read(workspaceTodayProvider))) {
      setState(() => _paidDateNeedsReview = true);
      await WidgetsBinding.instance.endOfFrame;
      final fieldContext = _paidDateKey.currentContext;
      if (fieldContext != null && fieldContext.mounted) {
        await Scrollable.ensureVisible(fieldContext, alignment: 0.3);
      }
      return false;
    }
    setState(() => _saving = true);
    var expenseSaved = false;
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null ||
          (_openedWorkspaceId != null && workspaceId != _openedWorkspaceId)) {
        if (mounted) setState(() => _saving = false);
        return false;
      }
      _openedWorkspaceId ??= workspaceId;
      final amount = double.parse(_amountController.text.trim());
      if (_editing || _persistedExpenseId != null) {
        await ref
            .read(expensesRepositoryProvider)
            .update(
              expenseId: widget.expense?.id ?? _persistedExpenseId!,
              amount: amount,
              category: _category,
              date: _date,
              notes: _notesController.text,
            );
      } else if (_receipt != null) {
        _persistedExpenseId = await ref
            .read(expensesRepositoryProvider)
            .createReturningId(
              expenseId: _expenseCreationToken,
              workspaceId: workspaceId,
              amount: amount,
              category: _category,
              date: _date,
              notes: _notesController.text,
            );
      } else {
        await ref
            .read(expensesRepositoryProvider)
            .create(
              expenseId: _expenseCreationToken,
              workspaceId: workspaceId,
              amount: amount,
              category: _category,
              date: _date,
              notes: _notesController.text,
            );
      }
      expenseSaved = true;
      _savedDraft = _currentDraft;
      ref.invalidate(expensesProvider);
      ref.invalidate(financeSummaryProvider);
      ref.invalidate(dashboardRevenueProvider);
      if (_receipt != null) {
        if (!mounted || ref.read(workspaceIdProvider).value != workspaceId) {
          return false;
        }
        final expenseId = widget.expense?.id ?? _persistedExpenseId!;
        await ref
            .read(expenseRecordsRepositoryProvider)
            .attach(workspaceId, expenseId, _receipt!);
        ref.invalidate(expenseReceiptsProvider(expenseId));
        _receipt = null;
      }
      if (mounted) await _leaveScreen();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              expenseSaved && _receipt != null
                  ? 'Expense saved, but the receipt could not be attached. Try saving again.'
                  : 'Could not save this expense. Please try again.',
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

  Future<void> _pickDate() async {
    final today = ref.read(workspaceTodayProvider);
    final defaultFirst = DateUtils.dateOnly(
      today.subtract(const Duration(days: 730)),
    );
    final picked = await showWorkloopDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: _date.isBefore(defaultFirst) ? _date : defaultFirst,
      lastDate: today,
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _dateAlreadyChosen = true;
        _paidDateNeedsReview = false;
      });
    }
  }

  void _receiptChanged(ReceiptFile? receipt) {
    _receiptReadRequest++;
    setState(() {
      _receipt = receipt;
      _receiptReading = false;
      _receiptReviewOpen = false;
    });
    if (receipt != null) unawaited(_readReceiptDetails());
  }

  void _keepManualDetails() {
    _receiptReadRequest++;
    setState(() {
      _receiptReading = false;
      _receiptReviewOpen = false;
    });
  }

  bool _receiptReadIsCurrent(
    ReceiptFile receipt,
    String workspace,
    String user,
    int request,
  ) {
    if (!mounted ||
        request != _receiptReadRequest ||
        !identical(_receipt, receipt)) {
      return false;
    }
    final active = ref.read(workspaceIdProvider);
    return !active.isLoading &&
        !active.hasError &&
        active.value == workspace &&
        ref.read(authRepositoryProvider).currentUserId == user;
  }

  Future<void> _readReceiptDetails() async {
    final receipt = _receipt;
    final workspace = ref.read(workspaceIdProvider);
    if (receipt == null ||
        _receiptReading ||
        _saving ||
        workspace.isLoading ||
        workspace.hasError ||
        workspace.value == null ||
        (_openedWorkspaceId != null && workspace.value != _openedWorkspaceId)) {
      return;
    }
    final user = ref.read(authRepositoryProvider).currentUserId;
    if (user == null) return;
    final workspaceId = workspace.value!;
    final request = ++_receiptReadRequest;
    setState(() {
      _receiptReading = true;
      _receiptReviewOpen = false;
      _receiptReadingUser = user;
      _receiptReadingWorkspace = workspaceId;
    });
    try {
      final recognized = await ref
          .read(receiptTextServiceProvider)
          .recognize(receipt);
      if (!mounted ||
          !_receiptReadIsCurrent(receipt, workspaceId, user, request)) {
        return;
      }
      final today = ref.read(workspaceTodayProvider);
      final extraction = extractReceiptText(recognized.text, today: today);
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _receiptReviewOpen = true);
      final reviewed = await showWorkloopBottomSheet<ReceiptReviewResult>(
        context: context,
        builder: (_) => ReceiptReviewSheet(
          receipt: receipt,
          recognized: recognized,
          extraction: extraction,
          workspaceId: workspaceId,
          userId: user,
          existingAmount: _amountController.text,
          existingDate: _date,
          dateAlreadyChosen: _dateAlreadyChosen,
          existingNotes: _notesController.text,
          today: today,
        ),
      );
      if (reviewed == null ||
          !_receiptReadIsCurrent(receipt, workspaceId, user, request)) {
        return;
      }
      setState(() {
        if (reviewed.amountMinor != null) {
          final minor = reviewed.amountMinor!;
          _amountController.text =
              '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
        }
        if (reviewed.paidDate != null) {
          _date = reviewed.paidDate!;
          _dateAlreadyChosen = true;
          _paidDateNeedsReview = false;
        }
        final addition = reviewed.noteAddition;
        if (addition != null && !_notesController.text.contains(addition)) {
          final existing = _notesController.text.trimRight();
          _notesController.text = existing.isEmpty
              ? addition
              : '$existing\n$addition';
        }
      });
    } catch (error) {
      if (mounted &&
          _receiptReadIsCurrent(receipt, workspaceId, user, request)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ReceiptRecognitionException
                  ? error.message
                  : 'Receipt reading could not finish. Your attachment is kept; enter the details yourself.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && request == _receiptReadRequest) {
        setState(() {
          _receiptReading = false;
          _receiptReviewOpen = false;
        });
      }
    }
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
    ref.listen(workspaceIdProvider, (_, next) {
      if (_receiptReading &&
          (next.isLoading ||
              next.hasError ||
              next.value != _receiptReadingWorkspace)) {
        _keepManualDetails();
      }
    });
    if (_receiptReading) {
      ref.listen(receiptAuthIdentityProvider, (_, next) {
        if (next.hasValue && next.value != _receiptReadingUser) {
          _keepManualDetails();
        }
      });
    }
    final workspace = ref.watch(workspaceIdProvider);
    if (workspace.hasValue) _openedWorkspaceId ??= workspace.value;
    if (_openedWorkspaceId != null && workspace.value != _openedWorkspaceId) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business changed')),
        body: const Center(
          child: Text('Reopen this expense from your current business.'),
        ),
      );
    }
    return PopScope(
      canPop:
          !_receiptPicking && !_receiptReading && (_allowPop || !_hasChanges),
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
                      title: _editing ? 'Edit expense' : 'Add expense',
                      backSemanticLabel: 'Back to Money',
                      onBack: _handleBack,
                      trailing: MoneySaveAction(
                        label: _editing ? 'Save' : 'Add',
                        loading: _saving,
                        enabled:
                            _canSave && !_receiptPicking && !_receiptReading,
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
                            subtitle: 'What the business spent.',
                            child: MoneyAmountField(
                              controller: _amountController,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          MoneyFormSection(
                            title: 'Details',
                            subtitle:
                                'Keep the expense easy to recognise later.',
                            child: Column(
                              children: [
                                WorkloopFormField(
                                  label: 'Expense category',
                                  isRequired: true,
                                  child: WorkloopPickerField<String>(
                                    value: _category,
                                    title: 'Expense category',
                                    hint: 'Choose category',
                                    leadingIcon: LucideIcons.tag,
                                    options: _categories
                                        .map(
                                          (category) => WorkloopPickerOption(
                                            value: category,
                                            label: category,
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) =>
                                        setState(() => _category = value),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Column(
                                  key: _paidDateKey,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    MoneyDateField(
                                      label: 'Date paid',
                                      value: _formatDate(_date),
                                      onTap: _pickDate,
                                    ),
                                    if (_paidDateNeedsReview) ...[
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(
                                        'The paid date is in the future. Choose today or the date the money actually left your business.',
                                        style: TextStyle(
                                          color: AppColors.of(context).error,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          MoneyFormSection(
                            title: 'Note',
                            subtitle:
                                'Keep enough detail to identify the purchase and why it was for your business.',
                            child: MoneyTextField(
                              controller: _notesController,
                              label: 'Note',
                              hint:
                                  'Supplier, what you bought and business purpose',
                              icon: LucideIcons.fileText,
                              maxLines: 3,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          ExpenseReceiptSection(
                            expenseId:
                                widget.expense?.id ?? _persistedExpenseId,
                            pending: _receipt,
                            busy: _saving || _receiptReading,
                            reading: _receiptReading && !_receiptReviewOpen,
                            onReadDetails: _readReceiptDetails,
                            onCancelReading: _keepManualDetails,
                            onPickingChanged: (picking) {
                              if (mounted) {
                                setState(() => _receiptPicking = picking);
                              }
                            },
                            onChanged: _receiptChanged,
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
