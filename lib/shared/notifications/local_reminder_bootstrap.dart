import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/slate_models.dart';
import '../providers/appointments_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/workspace_provider.dart';
import '../providers/workspace_refresh.dart';
import 'local_reminder_plan.dart';
import 'local_reminder_service.dart';
import 'notification_navigation.dart';

class WorkloopLocalReminderBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  final GoRouter router;

  const WorkloopLocalReminderBootstrap({
    super.key,
    required this.child,
    required this.router,
  });

  @override
  ConsumerState<WorkloopLocalReminderBootstrap> createState() =>
      _WorkloopLocalReminderBootstrapState();
}

class _WorkloopLocalReminderBootstrapState
    extends ConsumerState<WorkloopLocalReminderBootstrap>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _routeSubscription;
  String? _userId;
  int _accountEpoch = 0;
  StreamSubscription<void>? _permissionSubscription;
  String? _lastFingerprint;
  String? _queuedFingerprint;
  List<LocalReminderPlan>? _queuedPlans;
  String? _queuedUserId;
  String? _queuedWorkspaceId;
  int _queuedEpoch = 0;
  Timer? _retryTimer;
  String? _retryFingerprint;
  int _retryCount = 0;
  bool _syncing = false;
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
      _accountEpoch++;
      _retryTimer?.cancel();
      _retryCount = 0;
      _lastFingerprint = null;
      // Clear the prior account's OS reminders even if the new workspace fails
      // to load. In-flight plans stop at the next platform operation boundary.
      _queueReconcile('account:$_accountEpoch', const [], userId: userId);
      setState(() {});
    });
    final service = ref.read(localReminderServiceProvider);
    _routeSubscription = service.selectedRoutes.listen(_openRoute);
    _permissionSubscription = service.permissionChanges.listen((_) {
      if (!mounted) return;
      _retryTimer?.cancel();
      _retryCount = 0;
      setState(() => _lastFingerprint = null);
    });
    unawaited(_initializeReminderNavigation(service));
  }

  Future<void> _initializeReminderNavigation(
    LocalReminderService service,
  ) async {
    final expectedUserId =
        Supabase.instance.client.auth.currentSession?.user.id;
    try {
      await service.initialize();
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentSession == null) {
        _queueReconcile('signed-out:$_accountEpoch', const []);
      }
      final route = service.takePendingLaunchRoute();
      if (expectedUserId != null &&
          expectedUserId !=
              Supabase.instance.client.auth.currentSession?.user.id) {
        return;
      }
      if (route != null) _openRoute(route);
    } catch (_) {
      if (mounted && Supabase.instance.client.auth.currentSession == null) {
        _queueReconcile('signed-out:$_accountEpoch', const []);
      }
      if (kDebugMode) {
        debugPrint('Workloop local reminder setup deferred.');
      }
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
      // Preserve the screen the user was working on so the routed reminder
      // destination has a meaningful back button and iOS back-swipe target.
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _lastFingerprint = null;
    _retryTimer?.cancel();
    _retryCount = 0;
    if (Supabase.instance.client.auth.currentSession == null) {
      _queueReconcile('signed-out:$_accountEpoch', const []);
      return;
    }
    ref.invalidate(allTasksProvider);
    ref.invalidate(appointmentsProvider);
    ref.invalidate(notificationPreferencesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentSession?.user.id;
    if (userId == null || userId != _userId) return widget.child;
    _scheduleDeferredRoute();
    final workspace = ref.watch(workspaceIdProvider);
    final taskState = ref.watch(allTasksProvider);
    final appointmentState = ref.watch(appointmentsProvider);
    final preferenceState = ref.watch(notificationPreferencesProvider);

    // Retained AsyncData can belong to the previous account during reloads.
    // Only reconcile a complete, current workspace snapshot.
    if (!workspace.isLoading &&
        !workspace.hasError &&
        workspace.value != null &&
        !taskState.isLoading &&
        !taskState.hasError &&
        taskState.hasValue &&
        !appointmentState.isLoading &&
        !appointmentState.hasError &&
        appointmentState.hasValue &&
        !preferenceState.isLoading &&
        !preferenceState.hasError &&
        preferenceState.hasValue) {
      final workspaceId = workspace.value!;
      final appointments = <Appointment>[];
      for (final row in appointmentState.value ?? const []) {
        try {
          appointments.add(Appointment.fromMap(row));
        } catch (_) {
          // A malformed legacy row should not block reminders for valid work.
        }
      }
      final plans = buildLocalReminderPlans(
        tasks: taskState.value ?? const [],
        appointments: appointments,
        bookingRemindersEnabled:
            preferenceState.value?['appointment_reminder_15'] == true,
        now: DateTime.now(),
      );
      final planFingerprint = plans
          .map(
            (plan) =>
                '${plan.key}:${plan.scheduledAtUtc.microsecondsSinceEpoch}:'
                '${plan.title}:${plan.body}',
          )
          .join('|');
      final fingerprint = '$userId:$workspaceId:$planFingerprint';
      if (_lastFingerprint != fingerprint) {
        final epoch = _accountEpoch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isCurrent(epoch, userId, workspaceId)) {
            _queueReconcile(
              fingerprint,
              plans,
              userId: userId,
              workspaceId: workspaceId,
            );
          }
        });
      }
    }

    return widget.child;
  }

  bool _isCurrent(int epoch, String? userId, String? workspaceId) {
    if (!mounted ||
        epoch != _accountEpoch ||
        Supabase.instance.client.auth.currentSession?.user.id != userId) {
      return false;
    }
    if (workspaceId == null) return true; // account cleanup, not a data plan
    final activeWorkspace = ref.read(workspaceIdProvider);
    return !activeWorkspace.isLoading &&
        !activeWorkspace.hasError &&
        activeWorkspace.value == workspaceId;
  }

  void _queueReconcile(
    String fingerprint,
    List<LocalReminderPlan> plans, {
    String? userId,
    String? workspaceId,
  }) {
    if (_lastFingerprint == fingerprint && !_syncing) return;
    if (_retryFingerprint != fingerprint) {
      _retryTimer?.cancel();
      _retryFingerprint = fingerprint;
      _retryCount = 0;
    }
    _queuedFingerprint = fingerprint;
    _queuedPlans = plans;
    _queuedUserId = userId;
    _queuedWorkspaceId = workspaceId;
    _queuedEpoch = _accountEpoch;
    if (!_syncing) unawaited(_drainReconciliationQueue());
  }

  void _retryReconcile(
    String fingerprint,
    List<LocalReminderPlan> plans,
    int epoch,
    String? userId,
    String? workspaceId,
  ) {
    if (!_isCurrent(epoch, userId, workspaceId) ||
        _retryCount >= 4 ||
        (_queuedFingerprint != null && _queuedFingerprint != fingerprint)) {
      return;
    }
    _retryCount++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 1 << (_retryCount - 1)), () {
      if (_isCurrent(epoch, userId, workspaceId)) {
        _queueReconcile(
          fingerprint,
          plans,
          userId: userId,
          workspaceId: workspaceId,
        );
      }
    });
  }

  Future<void> _drainReconciliationQueue() async {
    _syncing = true;
    try {
      while (mounted && _queuedPlans != null) {
        final plans = _queuedPlans!;
        final fingerprint = _queuedFingerprint!;
        final userId = _queuedUserId;
        final workspaceId = _queuedWorkspaceId;
        final epoch = _queuedEpoch;
        _queuedPlans = null;
        _queuedFingerprint = null;
        if (!_isCurrent(epoch, userId, workspaceId)) continue;
        try {
          final service = ref.read(localReminderServiceProvider);
          final result = await service.reconcile(
            plans,
            isCurrent: () => _isCurrent(epoch, userId, workspaceId),
          );
          if (!_isCurrent(epoch, userId, workspaceId)) continue;
          final launchRoute = service.takePendingLaunchRoute();
          if (launchRoute != null) _openRoute(launchRoute);
          if (result.failed == 0) {
            _lastFingerprint = fingerprint;
            _retryTimer?.cancel();
            _retryCount = 0;
          } else {
            _retryReconcile(fingerprint, plans, epoch, userId, workspaceId);
          }
        } catch (_) {
          _retryReconcile(fingerprint, plans, epoch, userId, workspaceId);
          if (kDebugMode) {
            debugPrint('Workloop reminder reconciliation deferred.');
          }
        }
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_routeSubscription?.cancel());
    unawaited(_permissionSubscription?.cancel());
    super.dispose();
  }
}
