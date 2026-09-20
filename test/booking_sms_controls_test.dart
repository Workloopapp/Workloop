import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/clients/widgets/client_sms_permission_section.dart';
import 'package:workloop/features/clients/widgets/client_overview_tab.dart';
import 'package:workloop/features/clients/providers/client_detail_providers.dart';
import 'package:workloop/features/settings/customer_reminders_screen.dart';
import 'package:workloop/features/settings/widgets/email_settings_section.dart';
import 'package:workloop/features/settings/widgets/sms_settings_section.dart';
import 'package:workloop/shared/email/email_preferences_repository.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_actions.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/workspace_settings_repository.dart';
import 'package:workloop/shared/sms/booking_sms_repository.dart';

const ready = BookingSmsCapabilities(
  availability: BookingSmsAvailability.ready,
  allowedMinutes: {1440, 60},
);
const notReady = BookingSmsCapabilities(
  availability: BookingSmsAvailability.notReady,
);
const firstPhone = '+447700900123';
const secondPhone = '+447700900456';

class FakeSms implements BookingSmsRepository {
  @override
  String? currentUserId = 'user-a';
  BookingSmsCapabilities capability = ready;
  BookingSmsConsent consent = const BookingSmsConsent(
    phone: firstPhone,
    consented: false,
    providerStopped: false,
  );
  final writes = <({String id, bool enabled, String phone})>[];
  int reads = 0;
  bool fail = false;
  Completer<BookingSmsConsent>? pendingRead;
  Completer<void>? pendingWrite;
  @override
  Future<BookingSmsCapabilities> capabilities() async => capability;
  @override
  Future<BookingSmsConsent> getConsent(String contactId) async {
    reads++;
    if (fail) throw StateError('RPC not deployed');
    return pendingRead?.future ?? consent;
  }

  @override
  Future<BookingSmsConsent> setConsent({
    required String contactId,
    required bool enabled,
    required String expectedPhone,
  }) async {
    writes.add((id: contactId, enabled: enabled, phone: expectedPhone));
    if (pendingWrite != null) await pendingWrite!.future;
    if (fail) throw StateError('Permission not saved');
    consent = BookingSmsConsent(
      phone: expectedPhone,
      consented: enabled,
      providerStopped: false,
    );
    return consent;
  }
}

class FakeSmsSettings implements WorkspaceSettingsRepository {
  Map<String, dynamic> values = {
    'customer_reminder_minutes': [1440, 120, 60],
    'customer_sms_reminder_minutes': <int>[],
  };
  final writes = <Map<String, dynamic>>[];
  int reads = 0;
  Completer<void>? pendingWrite;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> get(String workspaceId) async {
    reads++;
    return {...values};
  }

  @override
  Future<void> update(String workspaceId, Map<String, dynamic> update) async {
    writes.add(update);
    if (pendingWrite != null) await pendingWrite!.future;
    if (fail) throw StateError('offline');
    values.addAll(update);
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget child,
    FakeSms sms, [
    FakeSmsSettings? settings,
  ]) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'workspace-a'),
          bookingSmsRepositoryProvider.overrideWithValue(sms),
          workspaceSettingsRepositoryProvider.overrideWithValue(
            settings ?? FakeSmsSettings(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget client({String phone = firstPhone}) => ClientSmsPermissionSection(
    contactId: 'contact-a',
    phone: phone,
    onEdit: () {},
  );
  SwitchListTile tile(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));

  testWidgets('text reminders stay off when service is not configured', (
    tester,
  ) async {
    final sms = FakeSms()..capability = notReady;
    final settings = FakeSmsSettings();
    settings.values['customer_sms_reminder_minutes'] = [1440];
    await show(tester, const SmsSettingsSection(), sms, settings);
    expect(
      find.text(
        'Text reminders are not available yet. Your email reminders are unaffected.',
      ),
      findsOneWidget,
    );
    for (final key in ['sms-reminder-1440', 'sms-reminder-60']) {
      expect(tile(tester, key).value, isFalse);
      expect(tile(tester, key).onChanged, isNull);
    }
    expect(settings.writes, isEmpty);
    expect(settings.values['customer_sms_reminder_minutes'], [1440]);
  });

  testWidgets(
    'unavailable client texting does not call an undeployed consent RPC',
    (tester) async {
      final sms = FakeSms()..capability = notReady;
      await show(tester, client(), sms);
      expect(
        find.text(
          'Text reminders are not available yet. Your email reminders are unaffected.',
        ),
        findsOneWidget,
      );
      expect(sms.reads, 0);
      expect(find.byKey(const ValueKey('client-sms-permission')), findsNothing);
    },
  );

  testWidgets('missing settings migration cannot enable texts', (tester) async {
    final settings = FakeSmsSettings()
      ..values.remove('customer_sms_reminder_minutes');
    await show(tester, const SmsSettingsSection(), FakeSms(), settings);
    expect(tile(tester, 'sms-reminder-1440').onChanged, isNull);
    expect(tile(tester, 'sms-reminder-60').value, isFalse);
    expect(settings.writes, isEmpty);
  });

  testWidgets(
    'availability failure keeps saved choices without claiming delivery',
    (tester) async {
      final sms = FakeSms()
        ..capability = const BookingSmsCapabilities(
          availability: BookingSmsAvailability.couldNotCheck,
        );
      final settings = FakeSmsSettings();
      settings.values['customer_sms_reminder_minutes'] = [1440];
      await show(tester, const SmsSettingsSection(), sms, settings);
      expect(
        find.text(
          'Could not check text reminder availability. Please try again.',
        ),
        findsOneWidget,
      );
      expect(tile(tester, 'sms-reminder-1440').onChanged, isNull);
      expect(tile(tester, 'sms-reminder-1440').value, isTrue);
      expect(
        find.text(
          'Showing your saved reminder times. Availability has not been confirmed.',
        ),
        findsOneWidget,
      );
      sms.capability = ready;
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(tile(tester, 'sms-reminder-1440').onChanged, isNotNull);
      expect(tile(tester, 'sms-reminder-1440').value, isTrue);
    },
  );

  testWidgets('unsupported number offers an edit without allowing permission', (
    tester,
  ) async {
    final sms = FakeSms()
      ..consent = const BookingSmsConsent(
        phone: null,
        consented: false,
        providerStopped: false,
      );
    await show(tester, client(phone: '07700900123'), sms);
    expect(tile(tester, 'client-sms-permission').onChanged, isNull);
    expect(find.text('Edit mobile number'), findsOneWidget);
    expect(
      find.text('Add a UK mobile number starting +44 to use text reminders.'),
      findsOneWidget,
    );
    expect(sms.writes, isEmpty);
  });

  testWidgets('configured 24-hour and 1-hour choices preserve email timings', (
    tester,
  ) async {
    final settings = FakeSmsSettings();
    await show(tester, const SmsSettingsSection(), FakeSms(), settings);
    await tester.tap(find.text('Text 1 day before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text 1 hour before'));
    await tester.pumpAndSettle();
    expect(settings.values['customer_sms_reminder_minutes'], [60, 1440]);
    expect(settings.values['customer_reminder_minutes'], [1440, 120, 60]);
    expect(
      settings.writes.every(
        (row) => row.keys.single == 'customer_sms_reminder_minutes',
      ),
      isTrue,
    );
    expect(tile(tester, 'sms-reminder-1440').value, isTrue);
    await tester.tap(find.text('Text 1 day before'));
    await tester.pumpAndSettle();
    expect(settings.values['customer_sms_reminder_minutes'], [60]);
  });

  testWidgets('failed text timing save keeps the saved switch state', (
    tester,
  ) async {
    final settings = FakeSmsSettings()..fail = true;
    await show(tester, const SmsSettingsSection(), FakeSms(), settings);
    await tester.tap(find.text('Text 1 day before'));
    await tester.pumpAndSettle();
    expect(tile(tester, 'sms-reminder-1440').value, isFalse);
    expect(
      find.text('Text reminder settings could not be saved. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a stored number requires explicit permission and confirmation', (
    tester,
  ) async {
    final sms = FakeSms();
    await show(tester, client(), sms);
    expect(tile(tester, 'client-sms-permission').value, isFalse);
    await tester.tap(find.byKey(const ValueKey('client-sms-permission')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save permission'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sms.writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('client-sms-permission')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-customer-sms-permission')),
    );
    await tester.pump();
    await tester.tap(find.text('Save permission'));
    await tester.pumpAndSettle();
    expect(sms.writes, [(id: 'contact-a', enabled: true, phone: firstPhone)]);
    expect(tile(tester, 'client-sms-permission').value, isTrue);
    expect(
      find.textContaining('Permission recorded for $firstPhone'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('client-sms-permission')));
    await tester.pumpAndSettle();
    expect(sms.writes.last.enabled, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('permission save is guarded against repeated taps', (
    tester,
  ) async {
    final sms = FakeSms()
      ..consent = const BookingSmsConsent(
        phone: firstPhone,
        consented: true,
        providerStopped: false,
      )
      ..pendingWrite = Completer<void>();
    await show(tester, client(), sms);
    final change = tile(tester, 'client-sms-permission').onChanged!;
    change(false);
    change(false);
    await tester.pump();
    expect(sms.writes, hasLength(1));
    sms.pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(tile(tester, 'client-sms-permission').value, isFalse);
  });

  testWidgets('changing the displayed phone cannot retain old permission', (
    tester,
  ) async {
    final phone = ValueNotifier(firstPhone);
    addTearDown(phone.dispose);
    final sms = FakeSms()
      ..consent = const BookingSmsConsent(
        phone: firstPhone,
        consented: true,
        providerStopped: false,
      );
    await show(
      tester,
      ValueListenableBuilder(
        valueListenable: phone,
        builder: (_, value, _) => client(phone: value),
      ),
      sms,
    );
    expect(tile(tester, 'client-sms-permission').value, isTrue);
    sms.pendingRead = Completer<BookingSmsConsent>();
    phone.value = secondPhone;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('client-sms-permission')), findsNothing);
    sms.pendingRead!.complete(
      const BookingSmsConsent(
        phone: secondPhone,
        consented: false,
        providerStopped: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(tile(tester, 'client-sms-permission').value, isFalse);
    expect(find.textContaining(secondPhone), findsOneWidget);
    expect(sms.reads, 2);
    expect(sms.writes, isEmpty);
  });

  testWidgets('provider STOP and stale contact numbers cannot be overridden', (
    tester,
  ) async {
    final sms = FakeSms()
      ..consent = const BookingSmsConsent(
        phone: firstPhone,
        consented: true,
        providerStopped: true,
      );
    await show(tester, client(), sms);
    expect(tile(tester, 'client-sms-permission').value, isFalse);
    expect(tile(tester, 'client-sms-permission').onChanged, isNull);
    expect(find.textContaining('cannot be overridden here'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    sms.consent = const BookingSmsConsent(
      phone: secondPhone,
      consented: true,
      providerStopped: false,
    );
    await show(tester, client(), sms);
    expect(tile(tester, 'client-sms-permission').value, isFalse);
    expect(tile(tester, 'client-sms-permission').onChanged, isNull);
    expect(find.textContaining('The saved number has changed'), findsOneWidget);
    expect(sms.writes, isEmpty);
  });

  testWidgets('missing consent RPC stays friendly and does not imply consent', (
    tester,
  ) async {
    final sms = FakeSms()..fail = true;
    await show(tester, client(), sms);
    expect(
      find.text(
        'Could not load this client’s text permission. Please try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('RPC not deployed'), findsNothing);
    expect(find.byKey(const ValueKey('client-sms-permission')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Business reminder screen excludes owner marketing preferences', (
    tester,
  ) async {
    final sms = FakeSms()..capability = notReady;
    var ownerPreferenceReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'workspace-a'),
          bookingSmsRepositoryProvider.overrideWithValue(sms),
          workspaceSettingsRepositoryProvider.overrideWithValue(
            FakeSmsSettings(),
          ),
          accountEmailPreferenceProvider.overrideWith((ref) async {
            ownerPreferenceReads++;
            return {'enabled': true, 'program': 'account'};
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CustomerRemindersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking reminders'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('customer-booking-reminders-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('customer-whatsapp-reminders-panel')),
      findsOneWidget,
    );
    expect(find.byType(SmsSettingsSection), findsNothing);
    expect(find.byKey(const ValueKey('account-email-updates')), findsNothing);
    expect(ownerPreferenceReads, 0);
    expect(tester.takeException(), isNull);
  });

  for (final channel in ['text', 'email']) {
    testWidgets('$channel save updates the cache after leaving the screen', (
      tester,
    ) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final settings = FakeSmsSettings()..pendingWrite = Completer<void>();
      settings.values['customer_reminder_minutes'] = <int>[];
      await show(
        tester,
        ValueListenableBuilder(
          valueListenable: visible,
          builder: (_, value, _) => value
              ? channel == 'text'
                    ? const SmsSettingsSection()
                    : const EmailSettingsSection(showAccountEmails: false)
              : const Text('Another screen'),
        ),
        FakeSms(),
        settings,
      );
      await tester.tap(
        find.text(channel == 'text' ? 'Text 1 day before' : '1 day before'),
      );
      await tester.pump();
      visible.value = false;
      await tester.pump();
      settings.pendingWrite!.complete();
      await tester.pumpAndSettle();
      visible.value = true;
      await tester.pumpAndSettle();
      final switchFinder = channel == 'text'
          ? find.byKey(const ValueKey('sms-reminder-1440'))
          : find.ancestor(
              of: find.text('1 day before'),
              matching: find.byType(SwitchListTile),
            );
      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      expect(settings.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'an account change while confirming permission cannot approve it',
    (tester) async {
      final sms = FakeSms();
      await show(tester, client(), sms);
      await tester.tap(find.byKey(const ValueKey('client-sms-permission')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-customer-sms-permission')),
      );
      await tester.pump();
      sms.currentUserId = 'different-user';
      await tester.tap(find.text('Save permission'));
      await tester.pumpAndSettle();
      expect(sms.writes, isEmpty);
      expect(tile(tester, 'client-sms-permission').value, isFalse);
    },
  );

  testWidgets('successful reload clears a previous text-settings error', (
    tester,
  ) async {
    final settings = FakeSmsSettings()..fail = true;
    await show(tester, const SmsSettingsSection(), FakeSms(), settings);
    await tester.tap(find.text('Text 1 day before'));
    await tester.pumpAndSettle();
    expect(
      find.text('Text reminder settings could not be saved. Please try again.'),
      findsOneWidget,
    );
    settings.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      find.text('Text reminder settings could not be saved. Please try again.'),
      findsNothing,
    );
    expect(settings.writes, hasLength(1));
    expect(tile(tester, 'sms-reminder-1440').value, isFalse);
  });

  testWidgets(
    'permission dialog remains usable on a small phone with large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final sms = FakeSms();
      await show(tester, client(), sms);
      await tester.tap(find.byKey(const ValueKey('client-sms-permission')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('confirm-customer-sms-permission')),
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-customer-sms-permission')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save permission'));
      await tester.pumpAndSettle();
      expect(sms.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Client Overview next booking excludes already finished future work',
    (tester) async {
      final now = DateTime.now();
      await show(
        tester,
        SizedBox(
          height: 520,
          child: ProviderScope(
            overrides: [
              clientAppointmentsProvider('contact-a').overrideWith(
                (ref) async => [
                  for (final (index, status) in [
                    'completed',
                    'no_show',
                    'cancelled',
                    'scheduled',
                  ].indexed)
                    {
                      'id': 'booking-$index',
                      'title': '$status appointment',
                      'status': status,
                      'start_time': now
                          .add(Duration(hours: index + 1))
                          .toIso8601String(),
                    },
                ],
              ),
              clientPaymentsProvider(
                'contact-a',
              ).overrideWith((ref) async => []),
              clientTasksProvider('contact-a').overrideWith((ref) async => []),
            ],
            child: ClientOverviewTab(
              clientId: 'contact-a',
              client: const {'name': 'Customer'},
              onEdit: () {},
              onOpenBookings: () {},
              onOpenPayments: () {},
              onOpenTasks: () {},
              onOpenAddress: (_) {},
            ),
          ),
        ),
        FakeSms()..capability = notReady,
      );
      expect(find.text('scheduled appointment'), findsOneWidget);
      expect(find.text('completed appointment'), findsNothing);
      expect(find.text('no_show appointment'), findsNothing);
      expect(find.text('3 more bookings scheduled'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'late settings save does not invalidate a different workspace',
    () async {
      var workspace = 'workspace-a';
      final settings = FakeSmsSettings()..pendingWrite = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => workspace),
          workspaceSettingsRepositoryProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);
      await container.read(workspaceSettingsProvider.future);
      final saving = container.read(updateWorkspaceSettingsProvider)(
        workspace,
        {
          'customer_sms_reminder_minutes': [1440],
        },
      );
      workspace = 'workspace-b';
      container.invalidate(workspaceIdProvider);
      await container.read(workspaceSettingsProvider.future);
      final reads = settings.reads;
      settings.pendingWrite!.complete();
      await saving;
      await container.read(workspaceSettingsProvider.future);
      expect(settings.reads, reads);
    },
  );

  test(
    'pending settings write can finish after its provider scope is disposed',
    () async {
      final settings = FakeSmsSettings()..pendingWrite = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => 'workspace-a'),
          workspaceSettingsRepositoryProvider.overrideWithValue(settings),
        ],
      );
      await container.read(workspaceSettingsProvider.future);
      final saving = container.read(updateWorkspaceSettingsProvider)(
        'workspace-a',
        {
          'customer_sms_reminder_minutes': [1440],
        },
      );
      container.dispose();
      settings.pendingWrite!.complete();
      await expectLater(saving, completes);
    },
  );

  test('UK mobile validation matches supported non-premium mobile ranges', () {
    expect(bookingSmsPhone('+44 (7700) 900-123'), firstPhone);
    expect(bookingSmsPhone('07700900123'), isNull);
    expect(bookingSmsPhone('+447012345678'), isNull);
    expect(bookingSmsPhone('+447612345678'), isNull);
    expect(bookingSmsPhone('+447624123456'), '+447624123456');
    expect(bookingSmsPhone('+442071234567'), isNull);
  });

  test(
    'undeployed capability endpoint is unavailable, network failure is unknown',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'test',
        httpClient: MockClient(
          (_) async => http.Response('{"error":"not found"}', 404),
        ),
      );
      addTearDown(client.dispose);
      expect(
        (await BookingSmsRepository(client).capabilities()).availability,
        BookingSmsAvailability.notReady,
      );
      final offline = SupabaseClient(
        'https://example.test',
        'test',
        httpClient: MockClient(
          (_) async => throw const FormatException('offline'),
        ),
      );
      addTearDown(offline.dispose);
      expect(
        (await BookingSmsRepository(offline).capabilities()).availability,
        BookingSmsAvailability.couldNotCheck,
      );
      expect(
        BookingSmsCapabilities.fromJson({'available': true}).available,
        isFalse,
      );
    },
  );

  test('consent RPC sends contact identity and exact viewed phone', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'phone': firstPhone,
            'consented': true,
            'provider_stopped': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final result = await BookingSmsRepository(client).setConsent(
      contactId: 'contact-a',
      enabled: true,
      expectedPhone: firstPhone,
    );
    expect(requests.single.url.path, '/rest/v1/rpc/set_booking_sms_consent');
    expect(jsonDecode(requests.single.body), {
      'p_contact_id': 'contact-a',
      'p_enabled': true,
      'p_expected_phone': firstPhone,
    });
    expect(result.consented, isTrue);
  });
}
