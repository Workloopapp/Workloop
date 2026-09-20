import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/workloop_app_info.dart';
import '../providers/workspace_provider.dart';
import '../providers/workspace_refresh.dart';
import '../repositories/push_token_repository.dart';
import 'local_reminder_service.dart';
import 'remote_push_service.dart';
import 'remote_push_registration.dart';
import 'notification_navigation.dart';

bool pushRegistrationContextMatches({
  required String contextKey,
  required String? userId,
  required String? workspaceId,
}) {
  if (userId == null || workspaceId == null) return false;
  return contextKey == '$userId:$workspaceId';
}

class WorkloopRemotePushBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  final GoRouter router;

  const WorkloopRemotePushBootstrap({
    super.key,
    required this.child,
    required this.router,
  });

  @override
  ConsumerState<WorkloopRemotePushBootstrap> createState() =>
      _WorkloopRemotePushBootstrapState();
}

class _WorkloopRemotePushBootstrapState
    extends ConsumerState<WorkloopRemotePushBootstrap>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSubscription;
  String? _userId;
  StreamSubscription<String>? _routeSubscription;
  StreamSubscription<void>? _messageSubscription;
  StreamSubscription<void>? _permissionSubscription;
  StreamSubscription<void>? _localPermissionSubscription;
  String? _registeredContext;
  String? _queuedContext;
  String? _retryContext;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _registering = false;
  String? _deferredRoute;
  bool _deferredRouteScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = Supabase.instance.client.auth;
    _userId = auth.currentSession?.user.id;
    _authSubscription = auth.onAuthStateChange.listen((_) {
      final userId = auth.currentSession?.user.id;
      if (!mounted || userId == _userId) return;
      if (_userId != null) _deferredRoute = null;
      _userId = userId;
      _registeredContext = null;
      _queuedContext = null;
      _retryContext = null;
      _retryTimer?.cancel();
      _retryCount = 0;
      _setRegistrationStatus(RemotePushRegistrationStatus.idle);
      setState(() {});
      // The bootstrap may have been mounted while signed out and therefore
      // not watching a workspace. Registration must not wait for app resume.
      if (userId != null) _queueCurrentRegistration();
    });
    final service = ref.read(remotePushServiceProvider);
    _routeSubscription = service.selectedRoutes.listen(_openRoute);
    _messageSubscription = service.foregroundMessages.listen((_) {
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentSession == null) return;
      refreshWorkspaceData(ref.invalidate);
    });
    void permissionChanged() {
      if (!mounted) return;
      _registeredContext = null;
      _retryTimer?.cancel();
      _retryCount = 0;
      _queueCurrentRegistration();
    }

    _permissionSubscription = service.permissionChanges.listen(
      (_) => permissionChanged(),
    );
    // Local reminder permission grants are the same OS permission as push.
    // Register after a task/booking grants it, without prompting again.
    _localPermissionSubscription = ref
        .read(localReminderServiceProvider)
        .permissionChanges
        .listen((_) => permissionChanged());
    unawaited(_initialize(service));
  }

  Future<void> _initialize(RemotePushService service) async {
    final expectedUserId =
        Supabase.instance.client.auth.currentSession?.user.id;
    try {
      await service.initialize();
      final route = service.takePendingLaunchRoute();
      if (!mounted ||
          (expectedUserId != null &&
              expectedUserId !=
                  Supabase.instance.client.auth.currentSession?.user.id)) {
        return;
      }
      if (route != null) _openRoute(route);
    } catch (error) {
      if (kDebugMode) debugPrint('Workloop push setup deferred.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _registeredContext = null;
    _retryTimer?.cancel();
    _retryCount = 0;
    _queueCurrentRegistration();
  }

  void _setRegistrationStatus(RemotePushRegistrationStatus status) {
    if (!mounted) return;
    ref.read(remotePushRegistrationStatusProvider.notifier).update(status);
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(workloopFirebaseReadyProvider);
    final session = Supabase.instance.client.auth.currentSession;
    if (!ready || session == null) {
      _registeredContext = null;
      return widget.child;
    }
    _scheduleDeferredRoute();

    final workspaceId = ref.watch(workspaceIdProvider);
    if (!workspaceId.isLoading &&
        !workspaceId.hasError &&
        workspaceId.hasValue &&
        workspaceId.value != null) {
      final contextKey = '${session.user.id}:${workspaceId.value}';
      if (_registeredContext != contextKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _queueRegistration(contextKey);
        });
      }
    }
    return widget.child;
  }

  void _queueCurrentRegistration() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    unawaited(
      ref
          .read(workspaceIdProvider.future)
          .then((workspaceId) {
            if (!mounted || workspaceId == null) return;
            _queueRegistration('${session.user.id}:$workspaceId');
          })
          .catchError((Object _) {
            // A failed workspace refresh is retried on resume/provider recovery.
            if (kDebugMode) debugPrint('Workloop push registration deferred.');
          }),
    );
  }

  void _queueRegistration(String contextKey) {
    if (_registeredContext == contextKey && !_registering) return;
    if (_retryContext != contextKey) {
      _retryTimer?.cancel();
      _retryContext = contextKey;
      _retryCount = 0;
    }
    _queuedContext = contextKey;
    if (!_registering) unawaited(_drainRegistrationQueue());
  }

  void _scheduleRegistrationRetry(String contextKey) {
    if (!mounted ||
        Supabase.instance.client.auth.currentSession?.user.id !=
            contextKey.split(':').first) {
      return;
    }
    if (_retryCount >= 4) {
      _setRegistrationStatus(RemotePushRegistrationStatus.failed);
      return;
    }
    _setRegistrationStatus(RemotePushRegistrationStatus.retrying);
    _retryCount += 1;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 1 << (_retryCount - 1)), () {
      if (mounted) _queueRegistration(contextKey);
    });
  }

  Future<void> _drainRegistrationQueue() async {
    _registering = true;
    try {
      while (mounted && _queuedContext != null) {
        final contextKey = _queuedContext!;
        _queuedContext = null;
        try {
          final parts = contextKey.split(':');
          if (parts.length != 2) continue;
          final session = Supabase.instance.client.auth.currentSession;
          if (session == null || session.user.id != parts[0]) continue;
          _setRegistrationStatus(RemotePushRegistrationStatus.registering);
          final service = ref.read(remotePushServiceProvider);
          final token = await service.registrationToken().timeout(
            const Duration(seconds: 15),
          );
          if (!mounted) break;
          final launchRoute = service.takePendingLaunchRoute();
          if (Supabase.instance.client.auth.currentSession?.user.id !=
              parts[0]) {
            continue;
          }
          if (launchRoute != null) _openRoute(launchRoute);
          if (token == null) {
            final permission = await service.permissionStatus().timeout(
              const Duration(seconds: 15),
            );
            if (!mounted ||
                Supabase.instance.client.auth.currentSession?.user.id !=
                    parts[0]) {
              continue;
            }
            if (permission == RemotePushPermission.granted) {
              _scheduleRegistrationRetry(contextKey);
            } else {
              _setRegistrationStatus(RemotePushRegistrationStatus.idle);
            }
            continue;
          }

          final activeWorkspaceId = await ref.read(workspaceIdProvider.future);
          if (!mounted) break;
          final activeUserId =
              Supabase.instance.client.auth.currentSession?.user.id;
          if (!pushRegistrationContextMatches(
            contextKey: contextKey,
            userId: activeUserId,
            workspaceId: activeWorkspaceId,
          )) {
            continue;
          }

          await ref
              .read(pushTokenRepositoryProvider)
              .register(
                workspaceId: parts[1],
                token: token,
                platform: service.platformName,
                appBuild: WorkloopAppInfo.buildNumber,
                apnsEnvironment: service.apnsEnvironment,
              )
              .timeout(const Duration(seconds: 15));
          if (!mounted) break;
          final latestUserId =
              Supabase.instance.client.auth.currentSession?.user.id;
          final latestWorkspaceId = await ref.read(workspaceIdProvider.future);
          if (!mounted) break;
          if (!pushRegistrationContextMatches(
                contextKey: contextKey,
                userId: latestUserId,
                workspaceId: latestWorkspaceId,
              ) ||
              (_queuedContext != null && _queuedContext != contextKey)) {
            continue;
          }
          _registeredContext = contextKey;
          _setRegistrationStatus(RemotePushRegistrationStatus.registered);
          _retryTimer?.cancel();
          _retryCount = 0;
        } catch (error) {
          if (mounted) _scheduleRegistrationRetry(contextKey);
          if (kDebugMode) {
            debugPrint('Workloop push token registration deferred.');
          }
        }
      }
    } finally {
      _registering = false;
    }
  }

  void _openRoute(String route) {
    if (!mounted) return;
    final expectedUserId =
        Supabase.instance.client.auth.currentSession?.user.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activeUserId =
          Supabase.instance.client.auth.currentSession?.user.id;
      if (expectedUserId != null && activeUserId != expectedUserId) return;
      if (activeUserId == null) {
        _deferredRoute = route;
        widget.router.go('/');
        return;
      }
      _deferredRoute = null;
      final presented = workloopNotificationPresentedRoute(widget.router);
      final sameLocation = widget.router.state.uri.path == route;
      if (presented?.settings.name == route ||
          (sameLocation && presented == null)) {
        return;
      }
      refreshWorkspaceData(ref.invalidate);
      if (sameLocation && presented?.settings is Page) {
        // The detail sheet may have been closed while its entity URL remains.
        // Re-enter that record instead of leaving the owner on its parent list.
        widget.router.pushReplacement(route);
        return;
      }
      widget.router.push(route);
    });
    // Notification/login callbacks can arrive after an otherwise idle frame.
    // A post-frame callback alone does not request another frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleDeferredRoute() {
    if (_deferredRoute == null || _deferredRouteScheduled) return;
    _deferredRouteScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredRouteScheduled = false;
      if (!mounted) return;
      final route = _deferredRoute;
      if (route != null) _openRoute(route);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSubscription?.cancel());
    _retryTimer?.cancel();
    unawaited(_routeSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_permissionSubscription?.cancel());
    unawaited(_localPermissionSubscription?.cancel());
    super.dispose();
  }
}
