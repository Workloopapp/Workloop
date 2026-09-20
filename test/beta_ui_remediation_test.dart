import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only in-memory backend for SharedPreferencesAsync.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/calendar_sync/calendar_sync_screen.dart';
import 'package:workloop/features/imports/calendar_import_screen.dart';
import 'package:workloop/features/notifications/notifications_screen.dart';
import 'package:workloop/features/onboarding/screens/ob_handle.dart';
import 'package:workloop/features/settings/legal_document_screen.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  const calendarChannel = MethodChannel(
    'plugins.builttoroam.com/device_calendar',
  );
  const contactsChannel = MethodChannel('flutter_contacts');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(calendarChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(contactsChannel, null);
  });

  testWidgets('calendar denial offers a direct system settings recovery', (
    tester,
  ) async {
    final calendarCalls = <String>[];
    final contactsCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(calendarChannel, (call) async {
          calendarCalls.add(call.method);
          return false;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(contactsChannel, (call) async {
          contactsCalls.add(call.method);
          return null;
        });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [clientsProvider.overrideWith((ref) async => const [])],
        child: const MaterialApp(home: CalendarImportScreen()),
      ),
    );

    await tester.tap(find.text('Choose a calendar'));
    await tester.pumpAndSettle();

    expect(
      calendarCalls,
      containsAllInOrder(['hasPermissions', 'requestPermissions']),
    );
    expect(find.text('Open system settings'), findsOneWidget);

    await tester.tap(find.text('Open system settings'));
    await tester.pump();
    expect(contactsCalls, contains('permissions.openSettings'));
  });

  testWidgets('calendar copy failures are reported instead of escaping', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentsProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
        ],
        child: const MaterialApp(home: CalendarSyncScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy raw calendar data'));
    await tester.pumpAndSettle();

    expect(
      find.text('Calendar export data could not be copied'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking language distinguishes requests from confirmations', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ObHandle(onNext: () {}, onBack: () {}),
          ),
        ),
      ),
    );

    expect(find.textContaining('request a booking'), findsOneWidget);
    expect(find.textContaining('find and book you'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPreferencesProvider.overrideWith(
            (ref) async => defaultNotificationPrefs,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationSettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final (key, title, description) in [
      (
        'booking_request',
        'Booking requests',
        'New customer requests and requests waiting for a response.',
      ),
      (
        'new_booking',
        'Confirmed bookings',
        'A booking is created or confirmed.',
      ),
    ]) {
      final preference = find.byKey(ValueKey('notification-preference-$key'));
      await tester.scrollUntilVisible(
        preference,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: preference, matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preference, matching: find.text(description)),
        findsOneWidget,
      );
    }
    expect(find.textContaining('A client books from your page'), findsNothing);
  });

  testWidgets('signed-out legal links remain reachable on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AuthScreen())),
    );

    final firstRunAction = find.byKey(const ValueKey('auth-first-run-cta'));
    expect(firstRunAction, findsOneWidget);
    expect(tester.getRect(firstRunAction).bottom, lessThanOrEqualTo(568));

    await tester.tap(firstRunAction);
    await tester.pumpAndSettle();

    final termsLink = find.byKey(const ValueKey('auth-terms-link'));
    final privacyLink = find.byKey(const ValueKey('auth-privacy-link'));
    expect(termsLink, findsOneWidget);
    expect(privacyLink, findsOneWidget);

    await tester.scrollUntilVisible(
      termsLink,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(termsLink);
    await tester.pumpAndSettle();

    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(
      tester
          .widget<WorkloopRouteHeader>(find.byType(WorkloopRouteHeader))
          .backSemanticLabel,
      'Back to account access',
    );
  });
}
