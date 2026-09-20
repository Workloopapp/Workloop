import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/legal_document_screen.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  Widget buildScreen(WorkloopLegalDocument document) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: LegalDocumentScreen(document: document),
    );
  }

  testWidgets('privacy policy remains readable inside the app', (tester) async {
    await tester.pumpWidget(buildScreen(WorkloopLegalDocument.privacy));

    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Effective 12 September 2026'), findsOneWidget);
    expect(find.text('1. Who this policy covers'), findsOneWidget);
    expect(find.textContaining('Haani Enterprise Limited'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('2. Data you provide'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2. Data you provide'), findsOneWidget);
    expect(find.textContaining('transaction references'), findsOneWidget);
    expect(
      find.textContaining('customer asks for a contactless-payment receipt'),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not receive or store full card'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Business records and receipt reading'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('quote and invoice details'), findsOneWidget);
    expect(
      find.textContaining('store the raw recognised text'),
      findsOneWidget,
    );
    expect(find.textContaining('private workspace storage'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Optional local weather'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining(
        'weather does not track your device in the background',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'does not pass your Workloop identity or device IP address',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Open public copy'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Open public copy'), findsOneWidget);
  });

  testWidgets('terms remain readable inside the app', (tester) async {
    await tester.pumpWidget(buildScreen(WorkloopLegalDocument.terms));

    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Effective 12 September 2026'), findsOneWidget);
    expect(find.text('1. Agreement'), findsOneWidget);
    expect(find.text('2. The service'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('7. Card payments'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('7. Card payments'), findsOneWidget);
    expect(find.textContaining('responding to disputes'), findsOneWidget);
    expect(
      find.textContaining('payout timing and availability'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Open public copy'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Open public copy'), findsOneWidget);
  });

  testWidgets('caller controls the legal back-button announcement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const LegalDocumentScreen(
          document: WorkloopLegalDocument.privacy,
          backSemanticLabel: 'Back to help and support',
        ),
      ),
    );

    expect(
      tester
          .widget<WorkloopRouteHeader>(find.byType(WorkloopRouteHeader))
          .backSemanticLabel,
      'Back to help and support',
    );
  });
}
