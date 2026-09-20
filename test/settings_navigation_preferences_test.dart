import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/notifications/notifications_screen.dart';
import 'package:workloop/features/settings/settings_screen.dart';
import 'package:workloop/features/settings/widgets/email_settings_section.dart';
import 'package:workloop/features/settings/widgets/settings_account_tab.dart';
import 'package:workloop/features/settings/widgets/settings_app_tab.dart';
import 'package:workloop/features/settings/widgets/settings_appearance_view.dart';
import 'package:workloop/shared/email/email_preferences_repository.dart';
import 'package:workloop/shared/notifications/local_reminder_service.dart';
import 'package:workloop/shared/notifications/remote_push_registration.dart';
import 'package:workloop/shared/notifications/remote_push_service.dart';
import 'package:workloop/shared/providers/maps_preference_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/theme_mode_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/slate_repositories.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Auth extends AuthRepository {
  _Auth()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  String? get currentUserId => 'owner-a';
  @override
  String? get currentFirstName => 'Alex';
  @override
  String get currentEmail => 'alex@example.com';
  @override
  Stream<AuthState> get authChanges => const Stream.empty();
}

class _Store implements MapsPreferenceStore, ThemeModeStore {
  String? saved;
  bool failRead = false;
  bool failWrite = false;
  int reads = 0;
  final writes = <String>[];
  Completer<String?>? reading;
  Completer<void>? writing;
  @override
  Future<String?> read(String key) async {
    reads++;
    if (failRead) throw StateError('disk unavailable');
    return reading == null ? saved : reading!.future;
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(value);
    await writing?.future;
    if (failWrite) throw StateError('disk unavailable');
    saved = value;
  }
}

class _LocalReminders extends LocalReminderService {
  final permissionEvents = StreamController<void>.broadcast();
  @override
  Stream<void> get permissionChanges => permissionEvents.stream;
  @override
  Future<void> dispose() async {
    await permissionEvents.close();
    await super.dispose();
  }

  LocalReminderPermission status = LocalReminderPermission.granted;
  LocalReminderPermission requested = LocalReminderPermission.granted;
  bool failCheck = false;
  int checks = 0;
  int requests = 0;
  @override
  bool get isSupported => status != LocalReminderPermission.unsupported;
  @override
  Future<LocalReminderPermission> permissionStatus() async {
    checks++;
    if (failCheck) throw StateError('permission status failed');
    return status;
  }

  @override
  Future<LocalReminderPermission> requestPermission() async {
    requests++;
    status = requested;
    if (status == LocalReminderPermission.granted) permissionEvents.add(null);
    return status;
  }
}

class _RemotePush extends RemotePushService {
  _RemotePush() : super(firebaseReady: false);
  bool supported = true;
  bool failRequest = false;
  int requests = 0;
  @override
  bool get isSupported => supported;
  @override
  Future<RemotePushPermission> requestPermission() async {
    requests++;
    if (failRequest) throw StateError('remote connection unavailable');
    return RemotePushPermission.granted;
  }
}

class _Notifications implements NotificationsRepository {
  Map<String, dynamic> saved = {...defaultNotificationPrefs};
  final writes = <Map<String, dynamic>>[];
  bool failWrite = false;
  Completer<void>? writing;
  @override
  Future<Map<String, dynamic>?> preferences(String workspaceId) async => {
    ...saved,
  };
  @override
  Future<void> upsertPreferences(
    String workspaceId,
    Map<String, dynamic> values,
  ) async {
    writes.add({...values});
    await writing?.future;
    if (failWrite) throw StateError('offline');
    saved.addAll(values);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Emails implements EmailPreferencesRepository {
  int reads = 0;
  bool fail = false;
  bool enabled = true;
  final writes = <bool>[];
  @override
  Future<Map<String, dynamic>> get() async {
    reads++;
    if (fail) throw StateError('email preference offline');
    return {'enabled': enabled, 'suppressed': false, 'program': 'account'};
  }

  @override
  Future<void> setEnabled(bool value) async {
    writes.add(value);
    enabled = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BusinessSettings implements WorkspaceSettingsRepository {
  int reads = 0;
  bool fail = false;
  final saved = <String, dynamic>{
    'customer_reminder_minutes': [1440, 60],
    'timezone': 'Europe/London',
  };
  final writes = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> get(String workspaceId) async {
    reads++;
    if (fail) throw StateError('customer reminders offline');
    return {...saved};
  }

  @override
  Future<void> update(String workspaceId, Map<String, dynamic> values) async {
    writes.add({...values});
    saved.addAll(values);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const phoneSettings = MethodChannel('workloop/notifications');
  late _Store maps;
  late _Store appearance;
  late _LocalReminders local;
  late _RemotePush remote;
  late _Notifications notifications;
  late _Emails emails;
  late _BusinessSettings businessSettings;
  late List<String> nativeCalls;
  late GlobalKey<NavigatorState> navigator;
  var settingsOpened = true;

  setUp(() {
    maps = _Store()..saved = 'appleMaps';
    appearance = _Store()..saved = 'light';
    local = _LocalReminders();
    remote = _RemotePush();
    notifications = _Notifications();
    emails = _Emails();
    businessSettings = _BusinessSettings();
    nativeCalls = [];
    navigator = GlobalKey<NavigatorState>();
    settingsOpened = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(phoneSettings, (call) async {
          nativeCalls.add(call.method);
          return settingsOpened;
        });
  });
  tearDown(() async {
    await local.dispose();
    await remote.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(phoneSettings, null);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget screen, {
    double scale = 1,
    Size size = const Size(390, 844),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth()),
          mapsPreferenceStoreProvider.overrideWithValue(maps),
          themeModeStoreProvider.overrideWithValue(appearance),
          localReminderServiceProvider.overrideWithValue(local),
          remotePushServiceProvider.overrideWithValue(remote),
          notificationsRepositoryProvider.overrideWithValue(notifications),
          notificationPreferencesProvider.overrideWith((ref) async {
            await ref.watch(workspaceIdProvider.future);
            return notifications.preferences('workspace-a').then((v) => v!);
          }),
          workspaceIdProvider.overrideWith((ref) async => 'workspace-a'),
          notificationsProvider.overrideWith((ref) async => []),
          unreadNotificationsProvider.overrideWith((ref) async => 0),
          emailPreferencesRepositoryProvider.overrideWithValue(emails),
          workspaceSettingsRepositoryProvider.overrideWithValue(
            businessSettings,
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: screen),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      return;
    }
    // Returning from a lower hub row retains its scroll position. Search from
    // the beginning when the requested row is not currently built.
    final state = tester.state<ScrollableState>(find.byType(Scrollable).last);
    state.position.jumpTo(state.position.minScrollExtent);
    await tester.pump();
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await visible(tester, find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Finder panel(String title) => find.byWidgetPredicate(
    (widget) => widget is WorkloopPaperPanel && widget.title == title,
  );

  Finder choice(String key) =>
      find.byKey(ValueKey('notification-preference-$key'));
  SwitchListTile toggle(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(choice(key));
  Future<void> tapChoice(WidgetTester tester, String key) async {
    await visible(tester, choice(key));
    await tester.tap(choice(key));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'settings routes separate owner alerts, customers, marketing, account and privacy',
    (tester) async {
      await pump(tester, const SettingsScreen());
      await tap(tester, 'Alex');
      expect(
        tester
            .widget<SettingsAccountTab>(find.byType(SettingsAccountTab))
            .showDataOnly,
        isFalse,
      );
      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Export your data'), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tap(tester, 'Your alerts');
      expect(find.byType(NotificationSettingsView), findsOneWidget);
      expect(find.byType(EmailSettingsSection), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tap(tester, 'Booking reminders');
      final customers = tester.widget<EmailSettingsSection>(
        find.byType(EmailSettingsSection),
      );
      expect(customers.showCustomerEmails, isTrue);
      expect(customers.showAccountEmails, isFalse);
      expect(
        find.byKey(const ValueKey('customer-booking-reminders-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('account-email-updates')), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tap(tester, 'Emails to you');
      final owner = tester.widget<EmailSettingsSection>(
        find.byType(EmailSettingsSection),
      );
      expect(owner.showAccountEmails, isTrue);
      expect(owner.showCustomerEmails, isFalse);
      expect(
        find.byKey(const ValueKey('account-email-updates')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('customer-booking-reminders-panel')),
        findsNothing,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tap(tester, 'Privacy & data');
      expect(
        tester
            .widget<SettingsAccountTab>(find.byType(SettingsAccountTab))
            .showDataOnly,
        isTrue,
      );
      expect(find.text('Export your data'), findsOneWidget);
      expect(find.text('Your name'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Workloop emails route does not fetch customer settings', (
    tester,
  ) async {
    businessSettings.fail = true;
    await pump(tester, const SettingsScreen());
    await tap(tester, 'Emails to you');
    expect(emails.reads, 1);
    expect(businessSettings.reads, 0);
    expect(find.byKey(const ValueKey('account-email-updates')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'customer reminders route does not fetch account email preferences',
    (tester) async {
      emails.fail = true;
      await pump(tester, const SettingsScreen());
      await tap(tester, 'Booking reminders');
      expect(emails.reads, 0);
      expect(businessSettings.reads, 1);
      expect(
        find.byKey(const ValueKey('customer-booking-reminders-panel')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recipient groups lead to three independent saved choices', (
    tester,
  ) async {
    notifications.saved['appointment_reminder_15'] = true;
    await pump(tester, const SettingsScreen());
    expect(panel('For you'), findsOneWidget);
    expect(panel('For your customers'), findsOneWidget);
    final ownerPosition = tester.getTopLeft(find.text('Your alerts')).dy;
    final emailPosition = tester.getTopLeft(find.text('Emails to you')).dy;
    final customerHeading = tester.getTopLeft(panel('For your customers')).dy;
    expect(ownerPosition, lessThan(emailPosition));
    expect(emailPosition, lessThan(customerHeading));

    await tap(tester, 'Your alerts');
    await tapChoice(tester, 'all_notifications');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tap(tester, 'Booking reminders');
    await tap(tester, '1 day before');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tap(tester, 'Emails to you');
    await visible(tester, find.byKey(const ValueKey('account-email-updates')));
    await tester.tap(find.byKey(const ValueKey('account-email-updates')));
    await tester.pumpAndSettle();

    expect(notifications.writes, [
      {'all_notifications': false},
    ]);
    expect(notifications.saved['appointment_reminder_15'], isTrue);
    expect(notifications.saved['booking_request'], isTrue);
    expect(businessSettings.writes, [
      {
        'customer_reminder_minutes': [60],
      },
    ]);
    expect(businessSettings.saved['timezone'], 'Europe/London');
    expect(emails.writes, [false]);
    expect(local.requests, 0);
    expect(remote.requests, 0);
    expect(tester.takeException(), isNull);
  });

  for (final key in [
    'booking_request',
    'new_booking',
    'payment_received',
    'invoice_overdue',
    'morning_digest',
    'quiet_sundays',
    'quiet_hours_enabled',
  ]) {
    testWidgets(
      'editing $key preserves every unrelated channel and legacy choice',
      (tester) async {
        notifications.saved.addAll({
          key: true,
          'appointment_reminder_15': true,
          'legacy_saved_choice': true,
        });
        final previous = {...notifications.saved};
        await pump(tester, const NotificationSettingsView());
        await tapChoice(tester, key);
        expect(notifications.writes, [
          {key: false},
        ]);
        expect(notifications.saved, {...previous, key: false});
        expect(emails.reads, 0);
        expect(emails.writes, isEmpty);
        expect(businessSettings.reads, 0);
        expect(businessSettings.writes, isEmpty);
        expect(local.requests, 0);
        expect(remote.requests, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an in-flight business choice cannot submit twice', (
    tester,
  ) async {
    notifications.writing = Completer<void>();
    await pump(tester, const NotificationSettingsView());
    await visible(tester, choice('booking_request'));
    await tester.tap(choice('booking_request'));
    await tester.pump();
    expect(notifications.writes, [
      {'booking_request': false},
    ]);
    expect(toggle(tester, 'booking_request').onChanged, isNull);
    await tester.tap(choice('booking_request'));
    await tester.pump();
    expect(notifications.writes, hasLength(1));
    notifications.writing!.complete();
    await tester.pumpAndSettle();
    expect(toggle(tester, 'booking_request').value, isFalse);
    expect(toggle(tester, 'booking_request').onChanged, isNotNull);
  });

  testWidgets('channel explanations and controls share one flat group each', (
    tester,
  ) async {
    await pump(tester, const NotificationSettingsView());
    final business = panel('Business activity');
    final phone = panel('Phone reminders');
    final quiet = panel('Quiet hours');
    expect(
      find.descendant(
        of: business,
        matching: find.text('In-app inbox + push alerts'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: business, matching: choice('all_notifications')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: business,
        matching: choice('appointment_reminder_15'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: phone, matching: find.text('Phone only · for you')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: phone, matching: choice('appointment_reminder_15')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quiet, matching: find.text('Business push only')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quiet, matching: choice('quiet_hours_enabled')),
      findsOneWidget,
    );
    for (final row in find.byType(SwitchListTile).evaluate()) {
      expect(
        find.ancestor(
          of: find.byWidget(row.widget),
          matching: find.byType(WorkloopPaperPanel),
        ),
        findsOneWidget,
        reason: 'Each alert row belongs to one frame, without nested cards.',
      );
    }
    await tap(tester, 'In-app inbox');
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'denied phone permission does not disable in-app business choices',
    (tester) async {
      local.status = LocalReminderPermission.denied;
      final container = await pump(tester, const NotificationSettingsView());
      container
          .read(remotePushRegistrationStatusProvider.notifier)
          .update(RemotePushRegistrationStatus.registered);
      await tester.pumpAndSettle();
      await visible(tester, choice('booking_request'));
      expect(toggle(tester, 'booking_request').onChanged, isNotNull);
      await tapChoice(tester, 'booking_request');
      expect(notifications.writes, [
        {'booking_request': false},
      ]);
      expect(local.requests, 0);
      expect(remote.requests, 0);
      expect(notifications.saved['all_notifications'], isTrue);
    },
  );

  testWidgets(
    'maps loading does not display an invented saved choice and failure retries',
    (tester) async {
      maps.reading = Completer<String?>();
      await pump(tester, const SettingsAppTab(), settle: false);
      await tester.pump();
      expect(find.text('Loading your maps choice…'), findsOneWidget);
      expect(find.text('Ask every time'), findsNothing);
      maps.reading!.completeError(StateError('disk unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load your maps choice.'), findsOneWidget);
      maps.reading = null;
      await tap(tester, 'Try again');
      expect(maps.reads, 2);
      expect(find.text('Apple Maps'), findsOneWidget);
    },
  );

  testWidgets('maps save failure retains actual choice and permits retry', (
    tester,
  ) async {
    maps.failWrite = true;
    final container = await pump(tester, const SettingsAppTab());
    await tap(tester, 'Default maps app');
    await tap(tester, 'Google Maps');
    expect(
      await container.read(preferredMapsAppProvider.future),
      MapsAppPreference.appleMaps,
    );
    expect(
      find.text('Your maps choice could not be saved. Please try again.'),
      findsOneWidget,
    );
    maps.failWrite = false;
    await tap(tester, 'Default maps app');
    await tap(tester, 'Google Maps');
    expect(
      await container.read(preferredMapsAppProvider.future),
      MapsAppPreference.googleMaps,
    );
    expect(maps.writes, ['googleMaps', 'googleMaps']);
  });

  testWidgets(
    'appearance cannot overwrite a saved choice before initial load finishes',
    (tester) async {
      appearance.reading = Completer<String?>();
      final container = await pump(
        tester,
        const SettingsAppearanceView(),
        settle: false,
      );
      await tester.pump();
      expect(
        tester
            .widget<WorkloopListRow>(
              find.byKey(const ValueKey('appearance-dark')),
            )
            .onTap,
        isNull,
      );
      expect(appearance.writes, isEmpty);
      appearance.reading!.complete('dark');
      await tester.pumpAndSettle();
      expect(
        await container.read(workloopAppearanceProvider.future),
        WorkloopAppearance.dark,
      );
      expect(
        tester
            .widget<WorkloopListRow>(
              find.byKey(const ValueKey('appearance-light')),
            )
            .onTap,
        isNotNull,
      );
    },
  );

  testWidgets(
    'appearance save failure restores previous choice and blocks duplicate writes',
    (tester) async {
      final container = await pump(tester, const SettingsAppearanceView());
      appearance.writing = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('appearance-dark')));
      await tester.pump();
      expect(
        await container.read(workloopAppearanceProvider.future),
        WorkloopAppearance.dark,
      );
      expect(
        tester
            .widget<WorkloopListRow>(
              find.byKey(const ValueKey('appearance-light')),
            )
            .onTap,
        isNull,
      );
      expect(appearance.writes, ['dark']);
      appearance.writing!.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(
        await container.read(workloopAppearanceProvider.future),
        WorkloopAppearance.light,
      );
      expect(find.text('Appearance could not be saved.'), findsOneWidget);
      appearance.writing = null;
      await tester.tap(find.byKey(const ValueKey('appearance-dark')));
      await tester.pumpAndSettle();
      expect(appearance.saved, 'dark');
      expect(appearance.writes, ['dark', 'dark']);
    },
  );

  testWidgets(
    'phone settings opens native notification settings and reports failed handoff',
    (tester) async {
      local.status = LocalReminderPermission.denied;
      await pump(tester, const NotificationSettingsView());
      await tap(tester, 'Phone settings');
      expect(nativeCalls, ['openSettings']);
      settingsOpened = false;
      await tap(tester, 'Phone settings');
      expect(nativeCalls, ['openSettings', 'openSettings']);
      expect(
        find.text(
          'Open your phone’s Settings, choose Workloop, then Notifications.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'permission failure retries and app resume refreshes actual permission',
    (tester) async {
      local.failCheck = true;
      await pump(tester, const NotificationSettingsView());
      expect(find.text('Could not check phone permission'), findsOneWidget);
      local.failCheck = false;
      local.status = LocalReminderPermission.denied;
      await tap(tester, 'Try again');
      expect(local.checks, 2);
      expect(find.text('Phone alerts are off'), findsOneWidget);
      local.status = LocalReminderPermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(local.checks, 3);
      expect(find.text('Phone alerts allowed'), findsOneWidget);
      expect(find.textContaining('This phone is connected'), findsNothing);
    },
  );

  testWidgets(
    'permission granted from a task updates visible phone status without resuming',
    (tester) async {
      local.status = LocalReminderPermission.denied;
      await pump(tester, const NotificationSettingsView());
      expect(find.text('Phone alerts are off'), findsOneWidget);
      // A task or booking can request the same OS permission outside this widget.
      await local.requestPermission();
      await tester.pumpAndSettle();
      expect(find.text('Phone alerts allowed'), findsOneWidget);
      expect(find.text('Phone alerts are off'), findsNothing);
      expect(notifications.writes, isEmpty);
      expect(remote.requests, 0);
    },
  );

  testWidgets('server registration is distinguished from device permission', (
    tester,
  ) async {
    final container = await pump(tester, const NotificationSettingsView());
    expect(
      find.textContaining('Workloop is checking the connection'),
      findsOneWidget,
    );
    container
        .read(remotePushRegistrationStatusProvider.notifier)
        .update(RemotePushRegistrationStatus.registered);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delivery also depends on your connection'),
      findsOneWidget,
    );
    expect(find.text('Check connection'), findsNothing);
  });

  testWidgets(
    'master business switch disables children without blocking local booking reminder',
    (tester) async {
      notifications.saved['all_notifications'] = false;
      await pump(tester, const NotificationSettingsView());
      for (final key in [
        'booking_request',
        'new_booking',
        'payment_received',
        'invoice_overdue',
        'morning_digest',
        'quiet_sundays',
        'quiet_hours_enabled',
      ]) {
        await visible(tester, choice(key));
        expect(toggle(tester, key).onChanged, isNull, reason: key);
      }
      await visible(tester, choice('appointment_reminder_15'));
      expect(toggle(tester, 'appointment_reminder_15').onChanged, isNotNull);
      await tapChoice(tester, 'appointment_reminder_15');
      expect(notifications.writes, [
        {'appointment_reminder_15': true},
      ]);
      expect(local.requests, 1);
      expect(notifications.saved['all_notifications'], isFalse);
    },
  );

  testWidgets(
    'remote setup failure does not block an allowed personal reminder',
    (tester) async {
      remote.failRequest = true;
      notifications.saved['all_notifications'] = false;
      await pump(tester, const NotificationSettingsView());
      await tapChoice(tester, 'appointment_reminder_15');
      expect(local.requests, 1);
      expect(notifications.writes, [
        {'appointment_reminder_15': true},
      ]);
      expect(toggle(tester, 'appointment_reminder_15').value, isTrue);
    },
  );

  testWidgets(
    'Sunday preference follows morning overview without overwriting saved Sunday choice',
    (tester) async {
      notifications.saved['morning_digest'] = false;
      notifications.saved['quiet_sundays'] = true;
      await pump(tester, const NotificationSettingsView());
      await visible(tester, choice('quiet_sundays'));
      expect(toggle(tester, 'quiet_sundays').onChanged, isNull);
      expect(toggle(tester, 'quiet_sundays').value, isTrue);
      await tapChoice(tester, 'morning_digest');
      await visible(tester, choice('quiet_sundays'));
      expect(toggle(tester, 'quiet_sundays').onChanged, isNotNull);
      expect(toggle(tester, 'quiet_sundays').value, isTrue);
      expect(notifications.writes, [
        {'morning_digest': true},
      ]);
    },
  );

  testWidgets('failed notification save keeps saved value and permits retry', (
    tester,
  ) async {
    notifications.failWrite = true;
    await pump(tester, const NotificationSettingsView());
    await tapChoice(tester, 'booking_request');
    expect(toggle(tester, 'booking_request').value, isTrue);
    expect(
      find.text('That notification setting could not be saved. Try again.'),
      findsOneWidget,
    );
    notifications.failWrite = false;
    await tapChoice(tester, 'booking_request');
    expect(toggle(tester, 'booking_request').value, isFalse);
    expect(notifications.writes.length, 2);
  });

  testWidgets(
    'denied personal reminder permission never persists an enabled reminder',
    (tester) async {
      local.requested = LocalReminderPermission.denied;
      await pump(tester, const NotificationSettingsView());
      await tapChoice(tester, 'appointment_reminder_15');
      expect(notifications.writes, isEmpty);
      expect(toggle(tester, 'appointment_reminder_15').value, isFalse);
      expect(remote.requests, 0);
    },
  );

  testWidgets(
    'unsupported reminders do not advertise activation or unused controls',
    (tester) async {
      local.status = LocalReminderPermission.unsupported;
      local.requested = LocalReminderPermission.unsupported;
      remote.supported = false;
      await pump(tester, const NotificationSettingsView());
      expect(find.text('Phone alerts unavailable here'), findsOneWidget);
      expect(find.text('Turn on'), findsNothing);
      expect(find.text('Phone settings'), findsNothing);
      await tapChoice(tester, 'appointment_reminder_15');
      expect(notifications.writes, isEmpty);
      for (final key in [
        'no_show',
        'lead_followup',
        'weekly_summary',
        'task_due_morning',
      ]) {
        expect(choice(key), findsNothing);
      }
      expect(
        find.textContaining('Scheduled reminders are available'),
        findsOneWidget,
      );
    },
  );

  for (final screen in <String, Widget>{
    'settings': const SettingsScreen(),
    'notifications': const NotificationSettingsView(),
    'appearance': const SettingsAppearanceView(),
    'maps': const SettingsAppTab(),
  }.entries) {
    testWidgets('${screen.key} remains usable at320px and2xtext', (
      tester,
    ) async {
      await pump(tester, screen.value, size: const Size(320, 568), scale: 2);
      expect(tester.takeException(), isNull);
      if (screen.key == 'settings') {
        await tap(tester, 'Privacy & data');
        await visible(tester, find.text('Export your data'));
        expect(find.text('Export your data').hitTestable(), findsOneWidget);
      } else if (screen.key == 'notifications') {
        await visible(tester, choice('appointment_reminder_15'));
        expect(choice('appointment_reminder_15').hitTestable(), findsOneWidget);
      } else if (screen.key == 'maps') {
        await tap(tester, 'Default maps app');
        await visible(tester, find.text('Google Maps'));
        await tester.tap(find.text('Google Maps'));
        await tester.pumpAndSettle();
        expect(maps.saved, 'googleMaps');
      } else {
        await visible(tester, find.byKey(const ValueKey('appearance-dark')));
        await tester.tap(find.byKey(const ValueKey('appearance-dark')));
        await tester.pumpAndSettle();
        expect(appearance.saved, 'dark');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
