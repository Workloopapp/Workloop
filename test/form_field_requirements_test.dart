import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

void main() {
  testWidgets('field requirements remain visible after entering text', (
    tester,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              WorkloopFormField(
                label: 'Client name',
                isRequired: true,
                child: TextField(controller: name),
              ),
              WorkloopFormField(
                label: 'Phone number',
                isRequired: false,
                child: TextField(controller: phone),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Sam');
    await tester.enterText(find.byType(TextField).last, '07700 900123');
    await tester.pump();
    expect(find.text('Client name'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
  });

  testWidgets('assistive technology receives the field requirement', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              WorkloopFormField(
                label: 'Client name',
                isRequired: true,
                child: TextField(),
              ),
              WorkloopFormField(
                label: 'Email address',
                isRequired: false,
                child: TextField(),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Client name \(required\)')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Email address \(optional\)')),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'requirements wrap at large text sizes (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2.5)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    children: [
                      WorkloopFormField(
                        label: 'Business registration number',
                        isRequired: true,
                        child: TextField(),
                      ),
                      SizedBox(height: 24),
                      WorkloopFormField(
                        label: 'Additional contact information',
                        isRequired: false,
                        child: TextField(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final label in [
          'Business registration number',
          'Additional contact information',
          'Required',
          'Optional',
        ]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          expect(
            tester.getSize(find.text(label)).width,
            lessThanOrEqualTo(284),
          );
        }
      },
    );
  }
}
