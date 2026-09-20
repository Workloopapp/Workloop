// Manual native QA target only. Restore the normal app after observing both
// surfaces. This target does not initialize Supabase or read a saved session.
import 'package:flutter/material.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/documents/business_document_detail_screen.dart';
import 'package:workloop/features/finance/expense_receipt_section.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';

import 'support/business_tools_native_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(nativeProbeHost(const _ManualProbe()));
}

class _ManualProbe extends StatefulWidget {
  const _ManualProbe();

  @override
  State<_ManualProbe> createState() => _ManualProbeState();
}

class _ManualProbeState extends State<_ManualProbe> {
  var _receipt = false;
  ReceiptFile? _pending;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _receipt
        ? SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.pageX),
              child: ExpenseReceiptSection(
                pending: _pending,
                onChanged: (file) => setState(() => _pending = file),
              ),
            ),
          )
        : const BusinessDocumentDetailScreen(documentId: nativeProbeDocumentId),
    bottomNavigationBar: SafeArea(
      top: false,
      child: TextButton(
        onPressed: () => setState(() => _receipt = !_receipt),
        child: Text(_receipt ? 'QA: Open invoice' : 'QA: Open receipt picker'),
      ),
    ),
  );
}
