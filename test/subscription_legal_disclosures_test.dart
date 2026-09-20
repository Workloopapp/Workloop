import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/legal_document_screen.dart';

String _plainHtml(String html) => html
    .replaceAll(RegExp('<[^>]+>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  test(
    'static subscription terms explain consent, renewal and retained access',
    () {
      final terms = _plainHtml(File('web/terms.html').readAsStringSync());
      expect(terms, contains('one-month free trial'));
      expect(terms, contains('by authorising the subscription with Apple'));
      expect(
        terms,
        contains('automatically renews as a paid monthly subscription'),
      );
      expect(terms, contains('current UK monthly price is £14.99'));
      expect(terms, contains('at least 24 hours before it ends'));
      expect(terms, contains('does not start a trial or authorise a charge'));
      expect(
        terms,
        contains('Deleting the Workloop app or account does not cancel'),
      );
      expect(terms, contains('seven and three days'));
      expect(terms, contains('delivery may be delayed or fail'));
      expect(terms, contains('Existing annual subscribers retain'));
      expect(
        terms,
        contains('lifetime access grant keep free lifetime access'),
      );
      expect(terms, contains('An existing 30-day trial already started'));
      expect(
        terms,
        isNot(contains('No payment details are required for this trial')),
      );
      expect(terms, isNot(contains('£149.99 per year')));
    },
  );

  testWidgets('trial terms remain readable and match the static public copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const LegalDocumentScreen(document: WorkloopLegalDocument.terms),
      ),
    );
    await tester.pumpAndSettle();
    final publicTerms = _plainHtml(File('web/terms.html').readAsStringSync());
    for (final bodyPrefix in [
      'Eligible new Apple subscribers',
      'Cancel an Apple free trial',
      'Existing beta testers with a lifetime access grant',
    ]) {
      final body = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data?.startsWith(bodyPrefix) ?? false),
      );
      await tester.scrollUntilVisible(
        body,
        500,
        maxScrolls: 150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(publicTerms, contains(tester.widget<SelectableText>(body).data));
      expect(tester.getSize(body).width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'privacy explains verified trial and service reminder processing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const LegalDocumentScreen(
            document: WorkloopLegalDocument.privacy,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final body = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data?.startsWith('For a Workloop subscription') ?? false),
      );
      await tester.scrollUntilVisible(
        body,
        500,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      final disclosure = tester.widget<SelectableText>(body).data!;
      expect(disclosure, contains('verified trial dates'));
      expect(disclosure, contains('subscription reminder records'));
      expect(disclosure, contains('use your account email'));
      expect(
        _plainHtml(File('web/privacy.html').readAsStringSync()),
        contains(disclosure),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
