import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/business_document_settings_screen.dart';
import 'package:workloop/shared/models/business_document_defaults.dart';
import 'package:workloop/shared/providers/business_document_defaults_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_actions.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

void main() {
  test('defaults reuse current shared details and preserve due-on-receipt', () {
    final defaults = BusinessDocumentDefaults.fromMaps(
      {'name': 'Current trading name'},
      {
        'business_legal_name': 'Alex Owner',
        'business_address': '1 High Street',
        'customer_contact_email': 'business@example.test',
        'customer_contact_phone': '01234567890',
        'default_payment_terms_days': 0,
        'default_quote_validity_days': 30,
        'default_payment_instructions': 'Use invoice reference',
      },
    );
    expect(defaults.business['name'], 'Current trading name');
    expect(defaults.business['email'], 'business@example.test');
    expect(defaults.business['phone'], '01234567890');
    expect(defaults.paymentTermsDays, 0);
    expect(defaults.isReady, isTrue);
    expect(defaults.businessStructure, isNull);
  });

  test('setup does not infer legal identity or private account contact', () {
    final defaults = BusinessDocumentDefaults.fromMaps({
      'name': 'Trading name',
      'email': 'private@example.test',
    }, {});
    expect(defaults.business['email'], isEmpty);
    expect(defaults.business['legal_name'], isEmpty);
    expect(
      defaults.missingDetails,
      containsAll([
        'legal name',
        'business address',
        'business email or phone',
      ]),
    );
  });

  testWidgets(
    'setup saves shared contact fields and validated reusable terms',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceIdProvider.overrideWith((ref) async => 'workspace'),
            businessDocumentDefaultsProvider.overrideWith(
              (ref) async => BusinessDocumentDefaults.fromMaps(
                {'name': 'Calm Cleaning'},
                {
                  'business_address': '1 High Street',
                  'customer_contact_email': 'hello@example.test',
                },
              ),
            ),
            updateWorkspaceSettingsProvider.overrideWithValue((
              workspace,
              values,
            ) async {
              expect(workspace, 'workspace');
              saved = values;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BusinessDocumentSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, 'Business address'), '1 High Street');
      expect(_text(tester, 'Business email'), 'hello@example.test');
      await tester.enterText(_field('Full legal name'), 'Alex Owner');
      await tester.scrollUntilVisible(
        _field('Invoice due after (days)'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(_field('Invoice due after (days)'), '0');
      await tester.enterText(_field('Quote valid for (days)'), '45');
      await tester.enterText(
        _field('How customers should pay'),
        'Bank transfer using your invoice number.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(SlateButton, 'Save details'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SlateButton, 'Save details'));
      await tester.pumpAndSettle();
      expect(saved?['business_legal_name'], 'Alex Owner');
      expect(saved?['customer_contact_email'], 'hello@example.test');
      expect(saved?['default_payment_terms_days'], 0);
      expect(saved?['default_quote_validity_days'], 45);
      expect(saved?.containsKey('name'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('setup resets unsaved personal details on workspace switch', (
    tester,
  ) async {
    var workspace = 'first';
    final container = ProviderContainer(
      overrides: [
        workspaceIdProvider.overrideWith((ref) async => workspace),
        businessDocumentDefaultsProvider.overrideWith((ref) async {
          final id = await ref.watch(workspaceIdProvider.future);
          return BusinessDocumentDefaults.fromMaps(
            {'name': id},
            {'business_legal_name': '$id Owner'},
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BusinessDocumentSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field('Full legal name'), 'Unsaved private name');
    workspace = 'second';
    container.invalidate(workspaceIdProvider);
    await tester.pumpAndSettle();
    expect(_text(tester, 'Full legal name'), 'second Owner');
    expect(find.text('Unsaved private name'), findsNothing);
  });

  testWidgets('setup fits narrow large text and blocks invalid terms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'workspace'),
          businessDocumentDefaultsProvider.overrideWith(
            (ref) async => BusinessDocumentDefaults.fromMaps({
              'name': 'Calm Cleaning',
            }, {}),
          ),
          updateWorkspaceSettingsProvider.overrideWithValue((_, _) async {
            saves++;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const BusinessDocumentSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      _field('Quote valid for (days)'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(_field('Quote valid for (days)'), '0');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(SlateButton, 'Save details'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SlateButton, 'Save details'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Enter 1–365 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup preserves changes and locks fields during pending save', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'workspace'),
          businessDocumentDefaultsProvider.overrideWith(
            (ref) async => BusinessDocumentDefaults.fromMaps({
              'name': 'Calm Cleaning',
            }, {}),
          ),
          updateWorkspaceSettingsProvider.overrideWithValue(
            (_, _) => pending.future,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BusinessDocumentSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field('Full legal name'), 'Alex Owner');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(SlateButton, 'Save details'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SlateButton, 'Save details'));
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('Full legal name')).enabled,
      isFalse,
    );
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Full legal name'), 'Alex Owner');
    expect(find.textContaining('Your changes are still here'), findsOneWidget);
  });
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is WorkloopFormField && widget.label == label,
  ),
  matching: find.byType(TextField),
);
String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;
