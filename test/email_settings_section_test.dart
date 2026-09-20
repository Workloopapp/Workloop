import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/widgets/email_settings_section.dart';
import 'package:workloop/shared/email/email_preferences_repository.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/workspace_settings_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class FakeSettings implements WorkspaceSettingsRepository {
  List<int> minutes = [1440, 60];
  bool fail = false;
  int reads = 0;
  Completer<void>? saving;
  final writes = <Map<String, dynamic>>[];
  String? email;
  String? phone;
  @override
  Future<Map<String, dynamic>?> get(String workspaceId) async {
    reads++;
    return {
      'customer_reminder_minutes': minutes,
      'customer_contact_email': email,
      'customer_contact_phone': phone,
    };
  }

  @override
  Future<void> update(String workspaceId, Map<String, dynamic> values) async {
    writes.add({...values});
    await saving?.future;
    if (fail) throw StateError('offline');
    if (values.containsKey('customer_reminder_minutes')) {
      minutes = List<int>.from(values['customer_reminder_minutes'] as List);
    }
    if (values.containsKey('customer_contact_email')) {
      email = values['customer_contact_email'] as String?;
      phone = values['customer_contact_phone'] as String?;
    }
  }
}

class FakeEmails implements EmailPreferencesRepository {
  bool enabled = true;
  bool suppressed = false;
  String program = 'account';
  bool failRead = false;
  bool failSave = false;
  int reads = 0;
  Completer<void>? saving;
  final writes = <bool>[];
  @override
  Future<Map<String, dynamic>> get() async {
    reads++;
    if (failRead) throw StateError('Email choices unavailable');
    return {'enabled': enabled, 'suppressed': suppressed, 'program': program};
  }

  @override
  Future<void> setEnabled(bool value) async {
    writes.add(value);
    await saving?.future;
    if (failSave) throw StateError('Offline');
    enabled = value;
    if (value) program = 'account';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> show(
    WidgetTester tester,
    FakeSettings settings,
    FakeEmails emails, {
    bool customer = true,
    bool account = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'test-workspace'),
          workspaceSettingsRepositoryProvider.overrideWithValue(settings),
          emailPreferencesRepositoryProvider.overrideWithValue(emails),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: EmailSettingsSection(
                  showCustomerEmails: customer,
                  showAccountEmails: account,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile tile(WidgetTester tester, String label) =>
      tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(SwitchListTile),
        ),
      );
  testWidgets('customer reminders persist independently from owner marketing', (
    tester,
  ) async {
    final settings = FakeSettings();
    final emails = FakeEmails();
    await show(tester, settings, emails);
    expect(
      find.byKey(const ValueKey('customer-whatsapp-reminders-panel')),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Check the prepared message and your sending account',
      ),
      findsOneWidget,
    );
    expect(find.text('Customer booking texts'), findsNothing);
    expect(find.byKey(const ValueKey('sms-reminder-1440')), findsNothing);
    expect(tile(tester, '1 day before').value, isTrue);
    expect(tile(tester, '2 hours before').value, isFalse);
    await tester.tap(find.text('2 hours before'));
    await tester.pumpAndSettle();
    expect(settings.minutes, [60, 120, 1440]);
    await tester.ensureVisible(
      find.byKey(const ValueKey('account-email-updates')),
    );
    await tester.tap(find.byKey(const ValueKey('account-email-updates')));
    await tester.pumpAndSettle();
    expect(emails.enabled, isFalse);
    expect(settings.minutes, [60, 120, 1440]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'turning off all reminders keeps contacts and owner emails and enables only the next chosen time',
    (tester) async {
      final settings = FakeSettings()
        ..email = 'hello@example.test'
        ..phone = '07700 900123';
      final emails = FakeEmails();
      await show(tester, settings, emails, account: false);
      expect(find.text('2 email reminders selected'), findsOneWidget);
      final stop = find.byKey(
        const ValueKey('turn-off-customer-email-reminders'),
      );
      await tester.ensureVisible(stop);
      await tester.tap(stop);
      await tester.pumpAndSettle();
      expect(settings.writes, [
        {'customer_reminder_minutes': <int>[]},
      ]);
      expect(find.text('Email reminders are off'), findsOneWidget);
      expect(stop, findsNothing);
      expect(tile(tester, '1 day before').value, isFalse);
      expect(tile(tester, '2 hours before').value, isFalse);
      expect(tile(tester, '1 hour before').value, isFalse);
      expect(settings.email, 'hello@example.test');
      expect(settings.phone, '07700 900123');
      expect(emails.reads, 0);
      expect(emails.writes, isEmpty);
      expect(
        find.byKey(const ValueKey('customer-booking-updates-panel')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('2 hours before'));
      await tester.tap(find.text('2 hours before'));
      await tester.pumpAndSettle();
      expect(settings.minutes, [120]);
      expect(find.text('1 email reminder selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved off state stays off when the screen opens', (
    tester,
  ) async {
    final settings = FakeSettings()..minutes = [];
    await show(tester, settings, FakeEmails(), account: false);
    expect(find.text('Email reminders are off'), findsOneWidget);
    expect(settings.writes, isEmpty);
    expect(tile(tester, '1 day before').value, isFalse);
    expect(tile(tester, '1 hour before').value, isFalse);
  });

  testWidgets('failed bulk reminder save retains selection and permits retry', (
    tester,
  ) async {
    final settings = FakeSettings()..fail = true;
    await show(tester, settings, FakeEmails(), account: false);
    final stop = find.byKey(
      const ValueKey('turn-off-customer-email-reminders'),
    );
    await tester.ensureVisible(stop);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(settings.minutes, [1440, 60]);
    expect(find.text('2 email reminders selected'), findsOneWidget);
    expect(
      find.text('Email settings could not be saved. Please try again.'),
      findsOneWidget,
    );
    settings.fail = false;
    settings.saving = Completer<void>();
    await tester.ensureVisible(stop);
    await tester.tap(stop);
    await tester.pump();
    expect(tester.widget<WorkloopTextButton>(stop).onPressed, isNull);
    expect(tile(tester, '1 day before').onChanged, isNull);
    expect(tile(tester, '2 hours before').onChanged, isNull);
    expect(tile(tester, '1 hour before').onChanged, isNull);
    await tester.tap(stop);
    await tester.pump();
    expect(settings.writes, hasLength(2));
    settings.saving!.complete();
    await tester.pumpAndSettle();
    expect(settings.minutes, isEmpty);
    expect(find.text('Email reminders are off'), findsOneWidget);
  });

  testWidgets(
    'failed reminder save preserves the saved value and explains retry',
    (tester) async {
      final settings = FakeSettings()..fail = true;
      await show(tester, settings, FakeEmails());
      await tester.tap(find.text('1 hour before'));
      await tester.pumpAndSettle();
      expect(tile(tester, '1 hour before').value, isTrue);
      expect(
        find.text('Email settings could not be saved. Please try again.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('suppressed email cannot be accidentally re-enabled', (
    tester,
  ) async {
    await show(
      tester,
      FakeSettings(),
      FakeEmails()
        ..enabled = false
        ..suppressed = true,
    );
    expect(tile(tester, 'Workloop tips and updates').onChanged, isNull);
    expect(
      find.text('Delivery is paused. Contact support@workloop.uk for help.'),
      findsOneWidget,
    );
  });

  testWidgets('customer-only controls never read or change owner marketing', (
    tester,
  ) async {
    final settings = FakeSettings();
    final emails = FakeEmails()..failRead = true;
    await show(tester, settings, emails, account: false);
    expect(emails.reads, 0);
    await tester.ensureVisible(find.text('1 day before'));
    await tester.tap(find.text('1 day before'));
    await tester.pumpAndSettle();
    expect(settings.writes, [
      {
        'customer_reminder_minutes': [60],
      },
    ]);
    expect(settings.minutes, [60]);
    expect(emails.writes, isEmpty);
    expect(find.byKey(const ValueKey('account-email-updates')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner-only emails never read or change customer reminders', (
    tester,
  ) async {
    final settings = FakeSettings();
    final emails = FakeEmails();
    await show(tester, settings, emails, customer: false);
    expect(settings.reads, 0);
    await tester.tap(find.byKey(const ValueKey('account-email-updates')));
    await tester.pumpAndSettle();
    expect(emails.writes, [false]);
    expect(settings.writes, isEmpty);
    expect(settings.minutes, [1440, 60]);
    expect(find.text('1 day before'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a welcome-only subscription does not silently enable ongoing tips',
    (tester) async {
      final settings = FakeSettings();
      final emails = FakeEmails()..program = 'welcome';
      await show(tester, settings, emails, customer: false);
      expect(find.text('Welcome series only'), findsOneWidget);
      expect(tile(tester, 'Workloop tips and updates').value, isFalse);
      expect(emails.writes, isEmpty);
      final stopWelcome = find.byKey(
        const ValueKey('unsubscribe-welcome-series'),
      );
      await tester.ensureVisible(stopWelcome);
      await tester.tap(stopWelcome);
      await tester.pumpAndSettle();
      expect(emails.writes, [false]);
      expect(emails.enabled, isFalse);
      expect(find.text('Welcome series only'), findsNothing);
      expect(tile(tester, 'Workloop tips and updates').value, isFalse);
      expect(settings.writes, isEmpty);
    },
  );

  testWidgets(
    'only an explicit choice upgrades a welcome series to ongoing tips',
    (tester) async {
      final settings = FakeSettings();
      final emails = FakeEmails()..program = 'welcome';
      await show(tester, settings, emails, customer: false);
      final updates = find.byKey(const ValueKey('account-email-updates'));
      await tester.ensureVisible(updates);
      await tester.tap(updates);
      await tester.pumpAndSettle();
      expect(emails.writes, [true]);
      expect(emails.program, 'account');
      expect(tile(tester, 'Workloop tips and updates').value, isTrue);
      expect(
        find.byKey(const ValueKey('unsubscribe-welcome-series')),
        findsNothing,
      );
      expect(settings.writes, isEmpty);
    },
  );

  testWidgets(
    'suppression cannot be bypassed through a welcome-only subscription',
    (tester) async {
      final emails = FakeEmails()
        ..program = 'welcome'
        ..suppressed = true;
      await show(tester, FakeSettings(), emails, customer: false);
      expect(tile(tester, 'Workloop tips and updates').onChanged, isNull);
      expect(
        find.byKey(const ValueKey('unsubscribe-welcome-series')),
        findsNothing,
      );
      expect(emails.writes, isEmpty);
    },
  );

  testWidgets(
    'customer reminder save disables duplicate and conflicting clicks',
    (tester) async {
      final settings = FakeSettings()..saving = Completer<void>();
      final emails = FakeEmails();
      await show(tester, settings, emails, account: false);
      await tester.ensureVisible(find.text('1 day before'));
      await tester.tap(find.text('1 day before'));
      await tester.pump();
      expect(settings.writes, hasLength(1));
      expect(tile(tester, '1 day before').onChanged, isNull);
      expect(tile(tester, '1 hour before').onChanged, isNull);
      await tester.tap(find.text('1 day before'));
      await tester.pump();
      expect(settings.writes, hasLength(1));
      settings.saving!.complete();
      await tester.pumpAndSettle();
      expect(settings.minutes, [60]);
      expect(tile(tester, '1 day before').value, isFalse);
      expect(tile(tester, '1 hour before').value, isTrue);
    },
  );

  testWidgets(
    'failed owner email save leaves the real choice and permits retry',
    (tester) async {
      final settings = FakeSettings();
      final emails = FakeEmails()..failSave = true;
      await show(tester, settings, emails, customer: false);
      await tester.tap(find.byKey(const ValueKey('account-email-updates')));
      await tester.pumpAndSettle();
      expect(tile(tester, 'Workloop tips and updates').value, isTrue);
      expect(
        find.text('Email settings could not be saved. Please try again.'),
        findsOneWidget,
      );
      emails.failSave = false;
      await tester.tap(find.byKey(const ValueKey('account-email-updates')));
      await tester.pumpAndSettle();
      expect(emails.writes, [false, false]);
      expect(tile(tester, 'Workloop tips and updates').value, isFalse);
      expect(settings.writes, isEmpty);
    },
  );

  for (final customer in [true, false]) {
    testWidgets(
      '${customer ? 'booking reminders' : 'owner emails'} stays actionable at 320px and 2x text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final settings = FakeSettings();
        final emails = FakeEmails();
        await show(
          tester,
          settings,
          emails,
          customer: customer,
          account: !customer,
        );
        final choice = customer
            ? find.text('1 hour before')
            : find.descendant(
                of: find.byKey(const ValueKey('account-email-updates')),
                matching: find.text('Workloop tips and updates'),
              );
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        if (customer) {
          expect(settings.minutes, [1440]);
          expect(emails.writes, isEmpty);
          final stop = find.byKey(
            const ValueKey('turn-off-customer-email-reminders'),
          );
          await tester.ensureVisible(stop);
          await tester.tap(stop);
          await tester.pumpAndSettle();
          expect(settings.minutes, isEmpty);
          expect(find.text('Email reminders are off'), findsOneWidget);
        } else {
          expect(emails.enabled, isFalse);
          expect(settings.writes, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'business contact validates, normalises and preserves failed edits',
    (tester) async {
      final settings = FakeSettings();
      await show(tester, settings, FakeEmails());
      await tester.ensureVisible(find.text('Business contact details'));
      await tester.tap(find.text('Business contact details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business email'),
        'invalid',
      );
      await tester.tap(find.text('Save contact details'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(settings.email, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business email'),
        ' HELLO@EXAMPLE.TEST ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business phone'),
        '07700 900123',
      );
      settings.fail = true;
      await tester.tap(find.text('Save contact details'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not save. Your changes are still here. Please try again.',
        ),
        findsOneWidget,
      );
      expect(find.text(' HELLO@EXAMPLE.TEST '), findsOneWidget);
      settings.fail = false;
      await tester.tap(find.text('Save contact details'));
      await tester.pumpAndSettle();
      expect(settings.email, 'hello@example.test');
      expect(settings.phone, '07700 900123');
      expect(settings.minutes, [1440, 60]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'business contact form stays usable with keyboard and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final settings = FakeSettings();
      await show(tester, settings, FakeEmails());
      await tester.ensureVisible(find.text('Business contact details'));
      await tester.tap(find.text('Business contact details'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 230);
      await tester.pumpAndSettle();
      final email = find.widgetWithText(TextFormField, 'Business email');
      await tester.ensureVisible(email);
      await tester.enterText(email, 'business@example.test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save contact details'));
      await tester.pumpAndSettle();
      expect(settings.email, 'business@example.test');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
