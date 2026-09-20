import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';

class MonthlyTargetEditor extends StatefulWidget {
  final double initialTarget;
  final Future<void> Function(double target) onSave;

  const MonthlyTargetEditor({
    super.key,
    required this.initialTarget,
    required this.onSave,
  });

  @override
  State<MonthlyTargetEditor> createState() => _MonthlyTargetEditorState();
}

class _MonthlyTargetEditorState extends State<MonthlyTargetEditor> {
  late final _controller = TextEditingController(
    text: widget.initialTarget.isFinite && widget.initialTarget > 0
        ? currencyInputValue(widget.initialTarget)
        : '',
  );
  bool _saving = false;
  String? _inputError;

  @override
  void dispose() {
    // The field remains mounted during the sheet's closing animation.
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = double.tryParse(_controller.text.trim());
    if (amount == null || !amount.isFinite || amount < 0) {
      setState(() => _inputError = 'Enter zero or a positive monthly amount.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(roundToPence(amount));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('The target could not be updated.'),
            backgroundColor: AppColors.of(context).error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SlateSheetFrame(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly money target',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.of(context).t1,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              enabled: !_saving,
              onChanged: (_) {
                if (_inputError != null) setState(() => _inputError = null);
              },
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontSize: 25,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                prefixText: '£ ',
                hintText: '0',
                label: const WorkloopFieldLabel(
                  'Monthly target',
                  isRequired: true,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                errorText: _inputError,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Track money received this calendar month. Today and Money use the same target. Enter 0 to remove it.',
              style: TextStyle(fontSize: 12, color: AppColors.of(context).t3),
            ),
            const SizedBox(height: 18),
            SlateButton(
              label: _saving ? 'Saving...' : 'Save Target',
              icon: LucideIcons.target,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    ),
  );
}
