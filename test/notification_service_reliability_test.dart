import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
// Test-only platform channels supplied by the installed Firebase plugin.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:firebase_messaging_platform_interface/src/method_channel/method_channel_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/notifications/local_reminder_plan.dart';
import 'package:workloop/shared/notifications/local_reminder_service.dart';
import 'package:workloop/shared/notifications/remote_push_service.dart';

const _firebase = MethodChannel('plugins.flutter.io/firebase_messaging');
const _local = MethodChannel('dexterous.com/flutter/local_notifications');
const _settings = MethodChannel('workloop/notifications');
const _taskRoute = '/tasks/11000000-0000-4000-8000-000000000001';

LocalReminderPlan _plan(int id) => LocalReminderPlan(
  id: id,
  key: 'task:$id',
  kind: LocalReminderKind.task,
  scheduledAtUtc: DateTime.now().toUtc().add(Duration(hours: id)),
  title: 'Task due today',
  body: 'Open Workloop to review this task.',
  route: _taskRoute,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(
      _local,
      (call) async => switch (call.method) {
        'initialize' => true,
        'getNotificationAppLaunchDetails' => {'notificationLaunchedApp': false},
        'pendingNotificationRequests' => <Object>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(_firebase, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_local, null);
    messenger.setMockMethodCallHandler(_firebase, null);
    messenger.setMockMethodCallHandler(_settings, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'retrying a failed cold-start lookup preserves one listener and one launch tap',
    () async {
      var lookups = 0;
      messenger.setMockMethodCallHandler(_firebase, (call) async {
        if (call.method == 'Messaging#getInitialMessage') {
          if (++lookups == 1) {
            throw PlatformException(code: 'temporarily-unavailable');
          }
          return {
            'data': {
              'deep_link':
                  '/booking-requests/12000000-0000-4000-8000-000000000001',
            },
          };
        }
        return null;
      });
      final service = RemotePushService(firebaseReady: true);
      final routes = <String>[];
      var foreground = 0;
      var tokenChanges = 0;
      final subscriptions = [
        service.selectedRoutes.listen(routes.add),
        service.foregroundMessages.listen((_) => foreground++),
        service.permissionChanges.listen((_) => tokenChanges++),
      ];
      await expectLater(
        service.initialize(),
        throwsA(isA<FirebaseException>()),
      );
      await service.initialize();
      expect(
        service.takePendingLaunchRoute(),
        '/booking-requests/12000000-0000-4000-8000-000000000001',
      );
      expect(service.takePendingLaunchRoute(), isNull);
      FirebaseMessagingPlatform.onMessage.add(const RemoteMessage());
      FirebaseMessagingPlatform.onMessageOpenedApp.add(
        const RemoteMessage(data: {'deep_link': _taskRoute}),
      );
      MethodChannelFirebaseMessaging.tokenStreamController.add('fixture-token');
      await Future<void>.delayed(Duration.zero);
      expect(routes, [_taskRoute]);
      expect(foreground, 1);
      expect(tokenChanges, 1);
      expect(service.cachedToken, 'fixture-token');
      // A plugin stream error wakes retry, without escaping as an uncaught error.
      MethodChannelFirebaseMessaging.tokenStreamController.addError(
        StateError('temporary'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tokenChanges, 2);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await service.dispose();
    },
  );

  test(
    'local initialization can recover and consumes a cold-start tap once',
    () async {
      var attempts = 0;
      messenger.setMockMethodCallHandler(_local, (call) async {
        if (call.method == 'initialize') {
          if (++attempts == 1) throw PlatformException(code: 'temporary');
          return true;
        }
        if (call.method == 'getNotificationAppLaunchDetails') {
          return {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'notificationId': 1,
              'notificationResponseType': 0,
              'payload': 'workloop-reminder:$_taskRoute',
            },
          };
        }
        return null;
      });
      final service = LocalReminderService();
      await expectLater(
        service.initialize(),
        throwsA(isA<PlatformException>()),
      );
      await service.initialize();
      expect(attempts, 2);
      expect(service.takePendingLaunchRoute(), _taskRoute);
      expect(service.takePendingLaunchRoute(), isNull);
      await service.dispose();
    },
  );

  test(
    'partial reconcile counts cancellation and scheduling failures and preserves unrelated alerts',
    () async {
      final cancellations = <int>[];
      messenger.setMockMethodCallHandler(_local, (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'getNotificationAppLaunchDetails':
            return {'notificationLaunchedApp': false};
          case 'pendingNotificationRequests':
            return [
              {
                'id': 30,
                'title': '',
                'body': '',
                'payload': 'workloop-reminder:$_taskRoute',
              },
              {'id': 31, 'title': '', 'body': '', 'payload': 'another-feature'},
            ];
          case 'cancel':
            cancellations.add((call.arguments as Map)['id'] as int);
            throw PlatformException(code: 'cancel-failed');
          case 'zonedSchedule':
            throw PlatformException(code: 'schedule-failed');
        }
        return null;
      });
      final service = LocalReminderService();
      final result = await service.reconcile([_plan(1)]);
      expect(result.failed, 2);
      expect(result.cancelled, 0);
      expect(result.scheduled, 0);
      expect(cancellations, [30]);
      await service.dispose();
    },
  );

  test(
    'account change stops remaining platform operations in an in-flight reconcile',
    () async {
      final firstStarted = Completer<void>();
      final finishFirst = Completer<void>();
      final scheduled = <int>[];
      var current = true;
      messenger.setMockMethodCallHandler(_local, (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'getNotificationAppLaunchDetails':
            return {'notificationLaunchedApp': false};
          case 'pendingNotificationRequests':
            return <Object>[];
          case 'zonedSchedule':
            scheduled.add((call.arguments as Map)['id'] as int);
            if (scheduled.length == 1) {
              firstStarted.complete();
              await finishFirst.future;
            }
        }
        return null;
      });
      final service = LocalReminderService();
      final operation = service.reconcile([
        _plan(1),
        _plan(2),
      ], isCurrent: () => current);
      await firstStarted.future;
      current = false;
      finishFirst.complete();
      await operation;
      expect(scheduled, [1]);
      await service.dispose();
    },
  );

  test(
    'late permission response after local service disposal is harmless',
    () async {
      final started = Completer<void>();
      final decision = Completer<bool>();
      messenger.setMockMethodCallHandler(_local, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails') {
          return {'notificationLaunchedApp': false};
        }
        if (call.method == 'requestNotificationsPermission') {
          started.complete();
          return decision.future;
        }
        return null;
      });
      final service = LocalReminderService();
      final request = service.requestPermission();
      await started.future;
      await service.dispose();
      decision.complete(true);
      expect(await request, LocalReminderPermission.granted);
    },
  );

  test(
    'system settings works without Firebase configuration and handles missing native support',
    () async {
      final service = RemotePushService(firebaseReady: false);
      messenger.setMockMethodCallHandler(_settings, (call) async {
        expect(call.method, 'openSettings');
        return true;
      });
      expect(await service.openNotificationSettings(), isTrue);
      messenger.setMockMethodCallHandler(
        _settings,
        (_) async => throw MissingPluginException(),
      );
      expect(await service.openNotificationSettings(), isFalse);
      await service.dispose();
    },
  );
}
