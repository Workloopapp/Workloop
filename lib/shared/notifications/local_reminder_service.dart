import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../core/theme/app_theme.dart';
import 'local_reminder_plan.dart';

final localReminderServiceProvider = Provider<LocalReminderService>((ref) {
  final service = LocalReminderService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

enum LocalReminderPermission { granted, denied, unsupported }

class LocalReminderSyncResult {
  final int scheduled;
  final int cancelled;
  final int failed;

  const LocalReminderSyncResult({
    required this.scheduled,
    required this.cancelled,
    required this.failed,
  });
}

class LocalReminderService {
  static const _channelId = 'workloop_reminders';
  static const _channelName = 'Workloop reminders';
  static const _channelDescription =
      'Task and booking reminders chosen in Workloop.';

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _selectedRoutes =
      StreamController<String>.broadcast();
  final StreamController<void> _permissionChanges =
      StreamController<void>.broadcast();

  Future<void>? _initializing;
  String? _pendingLaunchRoute;
  bool _disposed = false;

  LocalReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  bool get isSupported {
    if (kIsWeb || _disposed) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Stream<String> get selectedRoutes => _selectedRoutes.stream;
  Stream<void> get permissionChanges => _permissionChanges.stream;

  Future<void> initialize() {
    if (!isSupported) return Future<void>.value();
    return _initializing ??= _initialize().catchError((Object error) {
      _initializing = null;
      throw error;
    });
  }

  Future<void> _initialize() async {
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_workloop'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final route = routeFromReminderPayload(response.payload);
        if (!_disposed && route != null) _selectedRoutes.add(route);
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (!_disposed && launchDetails?.didNotificationLaunchApp == true) {
      _pendingLaunchRoute = routeFromReminderPayload(
        launchDetails?.notificationResponse?.payload,
      );
    }
  }

  String? takePendingLaunchRoute() {
    final route = _pendingLaunchRoute;
    _pendingLaunchRoute = null;
    return route;
  }

  Future<LocalReminderPermission> permissionStatus() async {
    if (!isSupported) return LocalReminderPermission.unsupported;
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      return enabled == true
          ? LocalReminderPermission.granted
          : LocalReminderPermission.denied;
    }

    final options = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return options?.isEnabled == true
        ? LocalReminderPermission.granted
        : LocalReminderPermission.denied;
  }

  Future<LocalReminderPermission> requestPermission() async {
    if (!isSupported) return LocalReminderPermission.unsupported;
    await initialize();

    bool? granted;
    if (defaultTargetPlatform == TargetPlatform.android) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (granted == true) {
      if (!_disposed) _permissionChanges.add(null);
      return LocalReminderPermission.granted;
    }
    return LocalReminderPermission.denied;
  }

  Future<LocalReminderSyncResult> reconcile(
    List<LocalReminderPlan> plans, {
    bool Function()? isCurrent,
  }) async {
    if (!isSupported) {
      return const LocalReminderSyncResult(
        scheduled: 0,
        cancelled: 0,
        failed: 0,
      );
    }
    await initialize();
    bool stillCurrent() => !_disposed && (isCurrent?.call() ?? true);

    final desired = plans
        .where((plan) => plan.scheduledAtUtc.isAfter(DateTime.now().toUtc()))
        .take(workloopMaximumPendingReminders)
        .toList(growable: false);
    final desiredIds = desired.map((plan) => plan.id).toSet();
    final pending = await _plugin.pendingNotificationRequests();
    final stale = pending.where(
      (item) =>
          item.payload?.startsWith(workloopReminderPayloadPrefix) == true &&
          !desiredIds.contains(item.id),
    );

    var cancelled = 0;
    var failed = 0;
    for (final item in stale) {
      if (!stillCurrent()) break;
      try {
        await _plugin.cancel(item.id);
        cancelled++;
      } catch (_) {
        failed++;
        // Reconciliation continues so one platform-level failure does not
        // prevent other valid reminders from being refreshed.
      }
    }

    var scheduled = 0;
    for (final plan in desired) {
      if (!stillCurrent()) break;
      try {
        await _plugin.zonedSchedule(
          plan.id,
          plan.title,
          plan.body,
          tz.TZDateTime.from(plan.scheduledAtUtc, tz.UTC),
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
              color: AppColors.light.brandAccent,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBanner: true,
              presentList: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: plan.payload,
        );
        scheduled++;
      } catch (_) {
        failed++;
      }
    }

    return LocalReminderSyncResult(
      scheduled: scheduled,
      cancelled: cancelled,
      failed: failed,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _selectedRoutes.close();
    await _permissionChanges.close();
  }
}
