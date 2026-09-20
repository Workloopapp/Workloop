// Local native-surface probe. It never boots Workloop's app/auth lifecycle,
// initializes Supabase, reads a saved session, or writes business records.
// Root must observe/cancel each native sheet, then restore the normal app build.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/finance/documents/business_document_detail_screen.dart';
import 'package:workloop/features/finance/expense_receipt_section.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

import 'support/business_tools_native_fixture.dart';

Future<void> _waitForNativeReturn(
  WidgetTester tester,
  bool Function() returned,
  String name,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 55));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();
    if (returned()) {
      debugPrint('BUSINESS_NATIVE_QA:$name:RETURNED');
      return;
    }
  }
  throw TestFailure(
    '$name did not return within 55 seconds. Cancel the native sheet.',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fictional invoice sharing and receipt file-picker cancellation',
    (tester) async {
      await tester.pumpWidget(
        nativeProbeHost(
          const BusinessDocumentDetailScreen(documentId: nativeProbeDocumentId),
        ),
      );
      await tester.pumpAndSettle();
      final share = find.widgetWithText(SlateButton, 'Share PDF');
      await tester.scrollUntilVisible(
        share,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      debugPrint('BUSINESS_NATIVE_QA:SHARE:OPENING_CANCEL_WITHIN_55_SECONDS');
      await tester.tap(share);
      await tester.pump();
      await _waitForNativeReturn(
        tester,
        () => tester.widget<SlateButton>(share).onPressed != null,
        'SHARE',
      );
      expect(find.text('Could not prepare the PDF. Try again.'), findsNothing);
      expect(tester.takeException(), isNull);

      ReceiptFile? selected;
      var picking = true;
      await tester.pumpWidget(
        nativeProbeHost(
          Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.pageX),
                child: ExpenseReceiptSection(
                  onChanged: (file) => selected = file,
                  onPickingChanged: (value) => picking = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attach receipt photo or PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Choose file'), findsOneWidget);
      debugPrint(
        'BUSINESS_NATIVE_QA:FILE_PICKER:OPENING_CANCEL_WITHIN_55_SECONDS',
      );
      await tester.tap(find.text('Choose file'));
      await tester.pump();
      await _waitForNativeReturn(tester, () => !picking, 'FILE_PICKER');
      expect(
        selected,
        isNull,
        reason: 'Cancel the picker without choosing any personal file.',
      );
      expect(
        find.text('Could not open this receipt. Try again.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      debugPrint('BUSINESS_NATIVE_QA:COMPLETE:RESTORE_NORMAL_APP_BUILD');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
