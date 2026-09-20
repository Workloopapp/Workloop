import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_app_info.dart';
import 'package:workloop/features/settings/legal_document_screen.dart';
import 'package:workloop/features/settings/support_screen.dart';

String visibleHtmlText(String html) => html
    .replaceAll(RegExp('<[^>]+>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  for (final page in ['privacy', 'terms', 'delete-account']) {
    test(
      '$page static copy identifies the same operator and registered office',
      () {
        final html = File('web/$page.html').readAsStringSync();
        final text = visibleHtmlText(html);
        expect(text, contains(WorkloopAppInfo.operatorStatement));
        expect(text, contains(WorkloopAppInfo.registrationStatement));
        expect(text, contains(WorkloopAppInfo.registeredOfficeStatement));
        expect(
          text,
          contains(
            'Effective ${page == 'privacy' ? WorkloopAppInfo.privacyEffectiveDate : WorkloopAppInfo.legalEffectiveDate}',
          ),
        );
        expect(html, contains('href="mailto:${WorkloopAppInfo.supportEmail}"'));
        expect(text, isNot(contains('Tanfield')));
        expect(text, isNot(contains('Settings > Account')));
        expect(text, isNot(contains(r'${WorkloopAppInfo.')));
        expect(text, isNot(contains('Haani Enterprise Limited owns')));
      },
    );
  }

  test(
    'public policy separates company account control from tenant client records',
    () {
      final privacy = visibleHtmlText(
        File('web/privacy.html').readAsStringSync(),
      );
      expect(
        privacy,
        contains(
          '${WorkloopAppInfo.operatorName} is the data controller for account administration',
        ),
      );
      expect(
        privacy,
        contains('remains the data controller for its own client records'),
      );
      expect(
        privacy,
        contains(
          '${WorkloopAppInfo.operatorName} processes those records on that business’s behalf',
        ),
      );
      expect(privacy, contains('These reports are not fully anonymous'));
      expect(privacy, contains('installation or session identifiers'));
      expect(
        privacy,
        contains('weather does not track your device in the background'),
      );
      expect(
        privacy,
        contains('We do not enrol your clients in Workloop marketing'),
      );
      expect(privacy, contains('Settings > Privacy & data'));
      final terms = visibleHtmlText(File('web/terms.html').readAsStringSync());
      expect(
        terms,
        contains(
          'These terms are between you and ${WorkloopAppInfo.operatorName}',
        ),
      );
      expect(terms, contains('does not become the provider of that service'));
      expect(terms, contains('You retain ownership of content you enter'));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'support and legal identity stay accessible at320px and2× in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = brightness == Brightness.dark
            ? AppTheme.dark
            : AppTheme.light;

        Widget host(Widget screen) => MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: screen,
        );

        await tester.pumpWidget(host(const SupportScreen()));
        await tester.pumpAndSettle();
        final details = find.byKey(const ValueKey('workloop-operator-details'));
        await tester.scrollUntilVisible(
          details,
          350,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester.widget<SelectableText>(details).data,
          WorkloopAppInfo.operatorDetails,
        );
        expect(tester.getSize(details).width, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);

        // Return to the existing legal action and verify it opens the company's
        // current privacy information rather than replacing the brand or route.
        await tester.scrollUntilVisible(
          find.text('Privacy policy'),
          -350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Privacy policy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Privacy policy'));
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(
          find.textContaining(WorkloopAppInfo.operatorStatement),
          findsOneWidget,
        );
        expect(
          find.text('Effective ${WorkloopAppInfo.privacyEffectiveDate}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          host(
            const LegalDocumentScreen(document: WorkloopLegalDocument.terms),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'These terms are between you and ${WorkloopAppInfo.operatorName}',
          ),
          findsOneWidget,
        );
        expect(find.text('Terms of use'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
