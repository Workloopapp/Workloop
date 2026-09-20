import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_route.dart';

final workloopFirebaseReadyProvider = Provider<bool>((ref) => false);

final remotePushServiceProvider = Provider<RemotePushService>((ref) {
  final service = RemotePushService(
    firebaseReady: ref.watch(workloopFirebaseReadyProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

enum RemotePushPermission { granted, denied, notDetermined, unsupported }

// This is an explicit signing choice, not a Dart compilation mode: profile
// and release builds can both be development-signed. Store packaging sets
// production; local development signing must explicitly select sandbox.
String? apnsEnvironmentFromDefine(String value) => switch (value) {
  'production' || 'sandbox' => value,
  _ => null,
};

@pragma('vm:entry-point')
Future<void> workloopFirebaseBackgroundMessageHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();
}

Future<bool> initializeWorkloopFirebase() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android)) {
    return false;
  }
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
      workloopFirebaseBackgroundMessageHandler,
    );
    return true;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Workloop remote push is not configured: $error');
    }
    return false;
  }
}

class RemotePushService {
  final bool firebaseReady;
  final StreamController<String> _selectedRoutes =
      StreamController<String>.broadcast();
  final StreamController<void> _foregroundMessages =
      StreamController<void>.broadcast();
  final StreamController<void> _permissionChanges =
      StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Future<void>? _initializing;
  String? _pendingLaunchRoute;
  String? _cachedToken;
  bool _disposed = false;
  bool _listenersAttached = false;

  RemotePushService({required this.firebaseReady});

  bool get isSupported =>
      !kIsWeb &&
      !_disposed &&
      firebaseReady &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      (defaultTargetPlatform != TargetPlatform.iOS || apnsEnvironment != null);
  String? get apnsEnvironment => defaultTargetPlatform == TargetPlatform.iOS
      ? apnsEnvironmentFromDefine(
          const String.fromEnvironment('APNS_ENVIRONMENT'),
        )
      : null;
  String? get cachedToken => _cachedToken;
  String get platformName =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Stream<String> get selectedRoutes => _selectedRoutes.stream;
  Stream<void> get foregroundMessages => _foregroundMessages.stream;
  Stream<void> get permissionChanges => _permissionChanges.stream;

  Future<void> initialize() {
    if (!isSupported || _disposed) return Future<void>.value();
    return _initializing ??= _initialize().catchError((Object error) {
      _initializing = null;
      throw error;
    });
  }

  Future<void> _initialize() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Create the existing app channel before the first remote notification;
      // a user may never have scheduled a local reminder on this device.
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'workloop_reminders',
              'Workloop reminders',
              description: 'Task, booking and business activity from Workloop.',
              importance: Importance.high,
            ),
          );
    }
    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    if (_disposed) return;
    _attachListeners(messaging);
    final initialMessage = await messaging.getInitialMessage();
    if (_disposed) return;
    _pendingLaunchRoute = initialMessage == null
        ? null
        : remotePushRouteFromData(initialMessage.data);
  }

  void _attachListeners(FirebaseMessaging messaging) {
    // A failed cold-start lookup is retryable; its already-working listeners
    // must not be attached again on the next initialization attempt.
    if (_listenersAttached) return;
    _listenersAttached = true;
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((message) {
        if (!_disposed) _foregroundMessages.add(null);
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final route = remotePushRouteFromData(message.data);
        if (!_disposed && route != null) _selectedRoutes.add(route);
      }),
    );
    _subscriptions.add(
      messaging.onTokenRefresh.listen(
        (token) {
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            unawaited(
              _refreshAppleToken().catchError((Object _) {
                // The next app resume retries registration. Do not surface an
                // unhandled asynchronous plugin error or log a device token.
                if (kDebugMode) {
                  debugPrint('Workloop APNs token refresh deferred.');
                }
              }),
            );
            return;
          }
          _cacheToken(token);
        },
        onError: (Object _) {
          // Plugin token errors are recoverable registration failures. Wake the
          // bounded bootstrap retry instead of leaking an unhandled stream error.
          if (!_disposed) _permissionChanges.add(null);
        },
      ),
    );
  }

  String? takePendingLaunchRoute() {
    final route = _pendingLaunchRoute;
    _pendingLaunchRoute = null;
    return route;
  }

  Future<RemotePushPermission> permissionStatus() async {
    if (!isSupported) return RemotePushPermission.unsupported;
    await initialize();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return _permissionFromStatus(settings.authorizationStatus);
  }

  Future<RemotePushPermission> requestPermission() async {
    if (!isSupported) return RemotePushPermission.unsupported;
    await initialize();
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final result = _permissionFromStatus(settings.authorizationStatus);
    if (!_disposed) _permissionChanges.add(null);
    return result;
  }

  Future<bool> openNotificationSettings() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    try {
      return await const MethodChannel(
            'workloop/notifications',
          ).invokeMethod<bool>('openSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<String?> registrationToken() async {
    if (!isSupported) return null;
    await initialize();
    final permission = await permissionStatus();
    if (permission != RemotePushPermission.granted) return null;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      return _cacheToken(token, notify: false);
    }
    final token = (await FirebaseMessaging.instance.getToken())?.trim();
    return _cacheToken(token, notify: false);
  }

  Future<void> _refreshAppleToken() async {
    final token = await FirebaseMessaging.instance.getAPNSToken();
    _cacheToken(token);
  }

  String? _cacheToken(String? token, {bool notify = true}) {
    if (_disposed) return null;
    final value = token?.trim() ?? '';
    if (value.isEmpty) return null;
    _cachedToken = value;
    if (notify) _permissionChanges.add(null);
    return value;
  }

  RemotePushPermission _permissionFromStatus(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => RemotePushPermission.granted,
      AuthorizationStatus.denied ||
      AuthorizationStatus.deniedPermanently => RemotePushPermission.denied,
      AuthorizationStatus.notDetermined => RemotePushPermission.notDetermined,
    };
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _selectedRoutes.close();
    await _foregroundMessages.close();
    await _permissionChanges.close();
  }
}

String? remotePushRouteFromData(Map<String, dynamic> data) {
  final route = data['deep_link']?.toString().trim();
  if (route == null || route.isEmpty || !route.startsWith('/')) return null;
  return workloopNotificationDestination(route) ?? '/notifications';
}
