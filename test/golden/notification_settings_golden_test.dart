import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/settings_screen.dart';
import 'package:workloop/shared/email/email_preferences_repository.dart';
import 'package:workloop/shared/notifications/local_reminder_service.dart';
import 'package:workloop/shared/notifications/remote_push_registration.dart';
import 'package:workloop/shared/notifications/remote_push_service.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/theme_mode_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/workspace_settings_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Auth implements AuthRepository {
  @override
  String? get currentUserId => 'fictional-owner';
  @override
  String? get currentFirstName => 'Alex';
  @override
  String get currentEmail => 'alex@example.test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Appearance implements ThemeModeStore {
  final String value;
  _Appearance(this.value);
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String value) async {}
}

class _LocalReminders extends LocalReminderService {
  @override
  Stream<void> get permissionChanges => const Stream.empty();
  @override
  Future<LocalReminderPermission> permissionStatus() async =>
      LocalReminderPermission.granted;
}

class _RemotePush extends RemotePushService {
  _RemotePush() : super(firebaseReady: false);
  @override
  bool get isSupported => true;
}

class _BusinessSettings implements WorkspaceSettingsRepository {
  @override
  Future<Map<String, dynamic>?> get(String workspaceId) async => {
    'workspace_id': workspaceId,
    'customer_reminder_minutes': [1440, 60],
    'customer_contact_email': 'hello@example.test',
    'customer_contact_phone': '07700 900123',
    'timezone': 'Europe/London',
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Emails implements EmailPreferencesRepository {
  @override
  Future<Map<String, dynamic>> get() async => {
    'enabled': true,
    'program': 'account',
    'suppressed': false,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(_loadFonts);

  for (final appearance in ['light', 'dark']) {
    for (final destination in <String, String?>{
      'hub': null,
      'owner-alerts': 'Your alerts',
      'owner-alerts-bottom': 'Your alerts',
      'customer-messages': 'Booking reminders',
      'customer-messages-bottom': 'Booking reminders',
      'owner-emails': 'Emails to you',
    }.entries) {
      testWidgets('notification settings ${destination.key} $appearance', (
        tester,
      ) async {
        final theme = appearance == 'light' ? AppTheme.light : AppTheme.dark;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final local = _LocalReminders();
        final remote = _RemotePush();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(_Auth()),
            themeModeStoreProvider.overrideWithValue(_Appearance(appearance)),
            workspaceIdProvider.overrideWith(
              (ref) async => 'fictional-workspace',
            ),
            notificationPreferencesProvider.overrideWith(
              (ref) async => {...defaultNotificationPrefs},
            ),
            notificationsProvider.overrideWith((ref) async => const []),
            unreadNotificationsProvider.overrideWith((ref) async => 0),
            localReminderServiceProvider.overrideWithValue(local),
            remotePushServiceProvider.overrideWithValue(remote),
            workspaceSettingsRepositoryProvider.overrideWithValue(
              _BusinessSettings(),
            ),
            emailPreferencesRepositoryProvider.overrideWithValue(_Emails()),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(local.dispose);
        addTearDown(remote.dispose);
        container
            .read(remotePushRegistrationStatusProvider.notifier)
            .update(RemotePushRegistrationStatus.registered);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: const ValueKey('notification-settings-golden'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: const MediaQueryData(
                    size: Size(390, 844),
                    devicePixelRatio: 1,
                    padding: EdgeInsets.only(top: 47, bottom: 34),
                    viewPadding: EdgeInsets.only(top: 47, bottom: 34),
                    disableAnimations: true,
                  ),
                  child: WorkloopAppCanvas(child: child!),
                ),
                home: const SettingsScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (destination.value != null) {
          final row = find.text(destination.value!);
          await tester.scrollUntilVisible(
            row,
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(row);
          await tester.pumpAndSettle();
        }
        if (destination.key.endsWith('-bottom')) {
          final lastSection = find.byKey(
            ValueKey(
              destination.key == 'owner-alerts-bottom'
                  ? 'notification-preference-quiet_hours_enabled'
                  : 'customer-whatsapp-reminders-panel',
            ),
          );
          final scrollable = find.byType(Scrollable).last;
          await tester.scrollUntilVisible(
            lastSection,
            400,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final boundary = find.byKey(
          const ValueKey('notification-settings-golden'),
        );
        final filename =
            'notification-settings-${destination.key}-$appearance.png';
        // Optional review output is outside the baseline directory, so a new
        // design can be inspected before any golden is accepted or updated.
        if (const bool.fromEnvironment('WORKLOOP_SETTINGS_GOLDEN_REVIEW')) {
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(boundary)
                .toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(
                '/tmp/workloop-notification-settings-review',
              );
              await directory.create(recursive: true);
              await File(
                '${directory.path}/$filename',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await expectLater(boundary, matchesGoldenFile('files/$filename'));
      });
    }
  }
}

Future<void> _loadFonts() async {
  final manrope = FontLoader('Manrope')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  final mono = FontLoader('WorkloopMono')
    ..addFont(rootBundle.load('assets/fonts/WorkloopMono-Regular.ttf'));
  final fallback = FontLoader('Ahem')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  final lucide = FontLoader('packages/lucide_flutter/LucideIcons')
    ..addFont(rootBundle.load('packages/lucide_flutter/assets/lucide.ttf'));
  final material = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([
    manrope.load(),
    mono.load(),
    fallback.load(),
    lucide.load(),
    material.load(),
  ]);
}
