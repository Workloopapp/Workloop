import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/documents/workloop_document_viewer.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'expense_records_repository.dart';
import 'receipt_extraction.dart';
import 'receipt_text_service.dart';
import 'tax_estimate.dart' show formatHundredths;
import 'widgets/money_editor_widgets.dart';

class ReceiptReviewResult {
  final int? amountMinor;
  final DateTime? paidDate;
  final String? noteAddition;
  const ReceiptReviewResult({
    this.amountMinor,
    this.paidDate,
    this.noteAddition,
  });
}

class ReceiptReviewSheet extends ConsumerStatefulWidget {
  final ReceiptFile receipt;
  final ReceiptRecognizedText recognized;
  final ReceiptExtraction extraction;
  final String workspaceId;
  final String userId;
  final String existingAmount;
  final String existingNotes;
  final DateTime existingDate;
  final bool dateAlreadyChosen;
  final DateTime today;
  const ReceiptReviewSheet({
    super.key,
    required this.receipt,
    required this.recognized,
    required this.extraction,
    required this.workspaceId,
    required this.userId,
    required this.existingAmount,
    required this.existingNotes,
    required this.existingDate,
    required this.dateAlreadyChosen,
    required this.today,
  });

  @override
  ConsumerState<ReceiptReviewSheet> createState() => _ReceiptReviewSheetState();
}

class _ReceiptReviewSheetState extends ConsumerState<ReceiptReviewSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _supplier;
  late final TextEditingController _reference;
  late DateTime _date;
  late bool _useAmount;
  late bool _useDate;
  late bool _useNotes;
  late bool _gbpConfirmed;
  String? _amountError;
  String? _dateError;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    final result = widget.extraction;
    _amount = TextEditingController(
      text: result.amountMinor == null
          ? ''
          : formatHundredths(result.amountMinor!.value),
    );
    _supplier = TextEditingController(text: result.supplier?.value ?? '');
    _reference = TextEditingController(text: result.reference?.value ?? '');
    _date = result.date?.value ?? widget.existingDate;
    _gbpConfirmed = result.currency == 'GBP';
    _useAmount =
        _gbpConfirmed &&
        result.amountMinor != null &&
        widget.existingAmount.trim().isEmpty &&
        !widget.recognized.isPartial;
    _useDate =
        !widget.dateAlreadyChosen &&
        result.date != null &&
        !result.ambiguousDate &&
        !_date.isAfter(widget.today) &&
        !widget.recognized.isPartial;
    _useNotes =
        widget.existingNotes.trim().isEmpty &&
        (result.supplier != null || result.reference != null);
  }

  @override
  void dispose() {
    _amount.dispose();
    _supplier.dispose();
    _reference.dispose();
    super.dispose();
  }

  bool get _current {
    final workspace = ref.read(workspaceIdProvider);
    return !_revoked &&
        !workspace.isLoading &&
        !workspace.hasError &&
        workspace.value == widget.workspaceId &&
        ref.read(authRepositoryProvider).currentUserId == widget.userId;
  }

  Future<void> _pickDate() async {
    if (!_useDate || !_current) return;
    final earliest = DateTime(2000);
    final picked = await showWorkloopDatePicker(
      context: context,
      initialDate: _date.isAfter(widget.today) ? widget.today : _date,
      firstDate: _date.isBefore(earliest) ? _date : earliest,
      lastDate: widget.today,
      title: 'Date actually paid',
    );
    if (picked != null && mounted && _current) {
      setState(() {
        _date = picked;
        _dateError = null;
      });
    }
  }

  void _apply() {
    if (!_current) return;
    final amount = _useAmount ? receiptAmountMinor(_amount.text) : null;
    setState(() {
      _amountError =
          _useAmount &&
              (amount == null ||
                  !_gbpConfirmed ||
                  widget.extraction.foreignCurrency)
          ? 'Enter the amount paid in GBP, with up to two decimal places.'
          : null;
      _dateError = _useDate && _date.isAfter(widget.today)
          ? 'Choose today or an earlier paid date.'
          : null;
    });
    if (_amountError != null || _dateError != null) return;
    final additions = [
      if (_supplier.text.trim().isNotEmpty)
        'Supplier: ${_supplier.text.trim()}',
      if (_reference.text.trim().isNotEmpty)
        'Receipt reference: ${_reference.text.trim()}',
    ].join('\n');
    Navigator.pop(
      context,
      ReceiptReviewResult(
        amountMinor: _useAmount ? amount : null,
        paidDate: _useDate ? _date : null,
        noteAddition: _useNotes && additions.isNotEmpty ? additions : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceIdProvider, (_, next) {
      if (next.isLoading || next.hasError || next.value != widget.workspaceId) {
        setState(() => _revoked = true);
      }
    });
    ref.listen(receiptAuthIdentityProvider, (_, next) {
      if (next.hasValue && next.value != widget.userId) {
        setState(() => _revoked = true);
      }
    });
    ref.watch(workspaceIdProvider);
    ref.watch(receiptAuthIdentityProvider);
    if (!_current) {
      return const SlateSheetFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkloopSheetHeader(title: 'Account changed'),
            Text(
              'Close this review and reopen the expense from your current business.',
            ),
          ],
        ),
      );
    }
    final extraction = widget.extraction;
    return SlateSheetFrame(
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkloopSheetHeader(
            title: 'Review receipt details',
            subtitle:
                'Read on your device. Check the suggestions, then choose what to use. Nothing is saved yet.',
          ),
          if (widget.recognized.processedPages <
              widget.recognized.pageCount) ...[
            Text(
              'Only ${widget.recognized.processedPages} of ${widget.recognized.pageCount} pages were read. Check the full receipt before using a total.',
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (widget.recognized.textTruncated) ...[
            const Text(
              'Some receipt text was too long to read in full. Check the original receipt before using its details.',
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final warning in extraction.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(warning),
            ),
          TextButton.icon(
            onPressed: () {
              if (!_current) return;
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => WorkloopDocumentViewerScreen(
                    workspaceId: widget.workspaceId,
                    title: 'Receipt',
                    fileName: widget.receipt.name,
                    mimeType: widget.receipt.mimeType,
                    loadBytes: () async => widget.receipt.bytes,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('View full receipt'),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!extraction.foreignCurrency) ...[
            if (extraction.currency == null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('This receipt amount is in GBP'),
                value: _gbpConfirmed,
                onChanged: (value) => setState(() {
                  _gbpConfirmed = value == true;
                  if (!_gbpConfirmed) _useAmount = false;
                }),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Use receipt amount'),
              subtitle: widget.existingAmount.trim().isEmpty
                  ? null
                  : Text(
                      'Your expense already has £${widget.existingAmount}. Leave unticked to keep it.',
                    ),
              value: _useAmount,
              onChanged: !_gbpConfirmed
                  ? null
                  : (value) => setState(() => _useAmount = value == true),
            ),
            WorkloopFormField(
              label: 'Amount paid',
              isRequired: _useAmount,
              helperText:
                  extraction.amountMinor?.source ??
                  'No single clear total was found. Check the receipt and enter the amount.',
              child: TextField(
                controller: _amount,
                enabled: _useAmount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  prefixText: '£ ',
                  hintText: '0.00',
                  errorText: _amountError,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Use receipt date as paid date'),
            subtitle: Text(
              widget.dateAlreadyChosen
                  ? 'You already chose a paid date. Leave unticked to keep it.'
                  : 'Only use this if it is the date you paid, not an invoice due date.',
            ),
            value: _useDate,
            onChanged: (value) => setState(() => _useDate = value == true),
          ),
          IgnorePointer(
            ignoring: !_useDate,
            child: MoneyDateField(
              label: 'Date paid',
              isRequired: _useDate,
              value: '${_date.day}/${_date.month}/${_date.year}',
              onTap: _pickDate,
            ),
          ),
          if (_dateError != null)
            Text(
              _dateError!,
              style: TextStyle(color: AppColors.of(context).error),
            ),
          if (extraction.date != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text('Receipt text: ${extraction.date!.source}'),
            ),
          const SizedBox(height: AppSpacing.md),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Add supplier and reference to note'),
            subtitle: widget.existingNotes.trim().isEmpty
                ? null
                : const Text(
                    'Your existing note will be kept. These details will be added below it.',
                  ),
            value: _useNotes,
            onChanged: (value) => setState(() => _useNotes = value == true),
          ),
          WorkloopFormField(
            label: 'Supplier',
            isRequired: false,
            child: TextField(
              controller: _supplier,
              enabled: _useNotes,
              maxLength: 120,
              decoration: const InputDecoration(
                hintText: 'Check the supplier name',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          WorkloopFormField(
            label: 'Receipt reference',
            isRequired: false,
            child: TextField(
              controller: _reference,
              enabled: _useNotes,
              maxLength: 80,
              decoration: const InputDecoration(
                hintText: 'Optional reference',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('View the text read'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(widget.recognized.text),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          WorkloopPrimaryButton(
            label: 'Use selected details',
            onPressed: _apply,
          ),
          const SizedBox(height: AppSpacing.sm),
          WorkloopPrimaryButton(
            label: 'Keep details as they are',
            secondary: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
