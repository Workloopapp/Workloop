import 'shared/email/email_journey_bootstrap.dart';
import 'shared/diagnostics/crash_reporter.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'features/subscription/subscription_access.dart';
import 'features/subscription/subscription_gate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/workloop_font_license.dart';
import 'core/supabase/supabase_config.dart';
import 'core/supabase/secure_auth_storage.dart';
import 'core/supabase/secure_session_recovery_screen.dart';
import 'core/workloop_app_info.dart';
import 'features/auth/auth_screen.dart';
import 'features/settings/account_deletion_confirmation_screen.dart';
import 'shared/repositories/privacy_repository.dart';
import 'features/auth/auth_contact_email_screen.dart';
import 'features/auth/mfa_screens.dart';
import 'features/auth/password_recovery_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/clients/clients_screen.dart';
import 'features/clients/client_record_link_screen.dart';
import 'features/clients/add_client_screen.dart';
import 'features/appointments/add_appointment_screen.dart';
import 'features/appointments/appointments_screen.dart';
import 'features/business/business_screen.dart';
import 'features/finance/finance_screen.dart';
import 'features/getting_started/getting_started_guide.dart';
import 'features/notes/notes_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/work/work_screen.dart';
import 'features/work/work_workspace_switcher.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/calendar_sync/calendar_sync_screen.dart';
import 'features/imports/import_data_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/public_profile/booking_requests_screen.dart';
import 'features/public_profile/public_profile_screen.dart';
import 'shared/providers/debug_demo_data_provider.dart';
import 'shared/providers/workspace_refresh.dart';
import 'shared/providers/theme_mode_provider.dart';
import 'shared/providers/onboarding_provider.dart';
import 'shared/providers/workspace_provider.dart';
import 'shared/repositories/auth_repository.dart';
import 'shared/notifications/local_reminder_bootstrap.dart';
import 'shared/notifications/remote_push_bootstrap.dart';
import 'shared/notifications/remote_push_service.dart';
import 'shared/utils/public_profile_routes.dart';
import 'shared/widgets/slate_ui.dart';

const workloopMinimumLaunchDuration = Duration.zero;

Duration remainingLaunchDuration(
  Duration elapsed, {
  Duration minimum = workloopMinimumLaunchDuration,
}) {
  if (elapsed >= minimum) return Duration.zero;
  return minimum - elapsed;
}

void main() async {
  final launchClock = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  registerWorkloopFontLicenses();
  usePathUrlStrategy();
  SupabaseConfig.validate();
  final appInfoFuture = WorkloopAppInfo.initialize();
  final firebaseReadyFuture = initializeWorkloopFirebase();
  final crashReporter = WorkloopCrashReporter(FirebaseCrashReportSink());
  unawaited(
    crashReporter.initialize(
      firebaseReady: firebaseReadyFuture,
      enabled: workloopCrashReportingEnabled,
    ),
  );
  crashReporter.installHandlers();
  final secureAuth = kIsWeb
      ? null
      : WorkloopSecureAuthStorage(supabaseUrl: SupabaseConfig.supabaseUrl);
  Future<void> startApp() async {
    var initializingSupabase = false;
    try {
      await secureAuth?.initialize();
      initializingSupabase = true;
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        publishableKey: SupabaseConfig.supabasePublishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: secureAuth?.session,
          pkceAsyncStorage: secureAuth?.pkce,
        ),
      );
    } on SecureAuthStorageException {
      if (initializingSupabase) await Supabase.instance.dispose();
      runApp(SecureSessionRecoveryScreen(onRetry: startApp));
      return;
    }
    await appInfoFuture;
    final firebaseReady = await firebaseReadyFuture;
    final remaining = remainingLaunchDuration(launchClock.elapsed);
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    runApp(
      ProviderScope(
        overrides: [
          workloopFirebaseReadyProvider.overrideWithValue(firebaseReady),
          clearPersistedAuthProvider.overrideWithValue(
            secureAuth?.clearSession,
          ),
        ],
        child: const WorkloopApp(),
      ),
    );
  }

  await startApp();
}

class WorkloopApp extends ConsumerStatefulWidget {
  const WorkloopApp({super.key});

  @override
  ConsumerState<WorkloopApp> createState() => _WorkloopAppState();
}

/// Observe account ownership before route-level auth listeners rebuild. Token
/// refreshes for the same user keep the shared workspace cache intact.
StreamSubscription<AuthState> listenForWorkloopAuthChanges(
  GoTrueClient auth, {
  required VoidCallback onAccountChanged,
  required VoidCallback onPasswordRecovery,
}) {
  var userId = auth.currentSession?.user.id;
  return auth.onAuthStateChange.listen((state) {
    final currentUserId = auth.currentSession?.user.id;
    if (currentUserId != userId) {
      userId = currentUserId;
      onAccountChanged();
    }
    if (state.event == AuthChangeEvent.passwordRecovery) {
      onPasswordRecovery();
    }
  });
}

class _WorkloopAppState extends ConsumerState<WorkloopApp>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = listenForWorkloopAuthChanges(
      Supabase.instance.client.auth,
      onAccountChanged: () {
        // Account changes are reloads, not background refreshes of the same
        // user's data. New gates must wait instead of painting retained values.
        ref.invalidate(sessionIntegrityProvider, asReload: true);
        ref.invalidate(workspaceProvider, asReload: true);
      },
      onPasswordRecovery: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _router.go('/reset-password');
        });
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        Supabase.instance.client.auth.currentSession == null) {
      return;
    }
    // One app-level refresh, not one network fan-out for every retained route.
    ref.invalidate(sessionIntegrityProvider);
    ref.invalidate(workspaceProvider);
    refreshWorkspaceData(ref.invalidate);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(workloopAppearanceProvider);
    final themeMode = appearance.value?.themeMode ?? ThemeMode.system;
    return MaterialApp.router(
      title: 'Workloop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      themeAnimationDuration: Duration.zero,
      scrollBehavior: const WorkloopScrollBehavior(),
      routerConfig: _router,
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final overlayStyle = brightness == Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: SlateTheme.of(context).background,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: SlateTheme.of(context).background,
                systemNavigationBarIconBrightness: Brightness.dark,
              );
        return WorkloopAppCanvas(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: WorkloopNavigationAssistRegion(
              observer: _navigationObserver,
              child: WorkloopRemotePushBootstrap(
                router: _router,
                child: WorkloopLocalReminderBootstrap(
                  router: _router,
                  child: WorkloopKeyboardDismissRegion(
                    child: WorkloopEmailJourneyBootstrap(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final _navigationObserver = WorkloopNavigationObserver();

final _router = GoRouter(
  observers: [_navigationObserver],
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AuthGate()),
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(
      path: '/account-deletion-requested',
      builder: (context, state) => state.extra is AccountDeletionResult
          ? AccountDeletionConfirmationScreen(
              result: state.extra! as AccountDeletionResult,
            )
          : const AuthScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const PasswordRecoveryScreen(),
    ),
    GoRoute(
      path: '/security/2fa',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MfaSetupScreen()),
    ),
    GoRoute(path: '/onboarding', builder: (context, state) => const AuthGate()),
    GoRoute(
      path: '/home',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MainShell()),
    ),
    GoRoute(path: '/business-feed', redirect: (context, state) => '/home'),
    GoRoute(
      path: '/business',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MainShell(initialIndex: 6)),
    ),
    GoRoute(
      path: '/clients',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MainShell(initialIndex: 1)),
    ),
    GoRoute(
      path: '/clients/new',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: AddClientScreen()),
    ),
    GoRoute(
      path: '/clients/:clientId',
      builder: (context, state) => AuthGate(
        authenticatedChild: ClientRecordLinkScreen(
          clientId: state.pathParameters['clientId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/tasks',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MainShell(initialIndex: 4)),
    ),
    GoRoute(
      path: '/work',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MainShell(initialIndex: 2)),
    ),
    GoRoute(
      path: '/bookings/new',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: AddAppointmentScreen()),
    ),
    GoRoute(
      path: '/bookings/:bookingId',
      builder: (context, state) => AuthGate(
        authenticatedChild: AppointmentsScreen(
          initialAppointmentId: state.pathParameters['bookingId'],
          showBackButton: true,
        ),
      ),
    ),
    GoRoute(
      path: '/payments',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MainShell(initialIndex: 3)),
    ),
    GoRoute(
      path: '/payments/:paymentId',
      builder: (context, state) => AuthGate(
        authenticatedChild: FinanceScreen(
          initialPaymentId: state.pathParameters['paymentId'],
          showBackButton: true,
        ),
      ),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: NotificationsScreen()),
    ),
    GoRoute(
      path: '/notes',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: MainShell(initialIndex: 5)),
    ),
    GoRoute(
      path: '/notes/:noteId',
      builder: (context, state) => AuthGate(
        authenticatedChild: NotesScreen(
          initialNoteId: state.pathParameters['noteId'],
        ),
      ),
    ),
    GoRoute(
      path: '/booking-requests',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: BookingRequestsScreen()),
    ),
    GoRoute(
      path: '/booking-requests/:requestId',
      builder: (context, state) => AuthGate(
        authenticatedChild: BookingRequestsScreen(
          initialRequestId: state.pathParameters['requestId'],
        ),
      ),
    ),
    GoRoute(
      path: '/tasks/:taskId',
      builder: (context, state) => AuthGate(
        authenticatedChild: TasksScreen(
          initialTaskId: state.pathParameters['taskId'],
          showBackButton: true,
        ),
      ),
    ),
    GoRoute(
      path: '/calendar-sync',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: CalendarSyncScreen()),
    ),
    GoRoute(
      path: '/import-data',
      builder: (context, state) =>
          const AuthGate(authenticatedChild: ImportDataScreen()),
    ),
    GoRoute(
      path: '/p/:handle',
      builder: (context, state) {
        return PublicProfileScreen(
          handle: state.pathParameters['handle'] ?? '',
        );
      },
    ),
    GoRoute(
      path: '/:handle',
      redirect: (context, state) {
        final handle = state.pathParameters['handle'] ?? '';
        return isReservedPublicHandle(handle) ? '/' : null;
      },
      builder: (context, state) =>
          PublicProfileScreen(handle: state.pathParameters['handle'] ?? ''),
    ),
  ],
);

class AuthGate extends ConsumerStatefulWidget {
  final Widget authenticatedChild;

  const AuthGate({super.key, this.authenticatedChild = const MainShell()});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  String? _lastUserId;
  String? _providersReadyForUserId;
  String? _providerResetScheduledForUserId;
  String? _discardingInvalidUserId;
  bool _accountBootstrapFailed = false;
  String? _verifiedUserId;

  @override
  void initState() {
    super.initState();
    final currentUserId = Supabase.instance.client.auth.currentSession?.user.id;
    // Authenticated routes create their own gate. Seed it with the already
    // restored account so ordinary route pushes do not invalidate the shared
    // session and workspace providers or flash the opening screen again.
    _lastUserId = currentUserId;
    _providersReadyForUserId = currentUserId;
  }

  Future<void> _discardInvalidSession(String expectedUserId) async {
    bool stillInvalidAccount() =>
        mounted &&
        Supabase.instance.client.auth.currentUser?.id == expectedUserId;
    if (_discardingInvalidUserId == expectedUserId || !stillInvalidAccount()) {
      return;
    }
    _discardingInvalidUserId = expectedUserId;
    final repository = ref.read(authRepositoryProvider);
    try {
      await ref.read(onboardingProvider.notifier).clearDraft();
      if (!stillInvalidAccount()) return;
      await repository.signOutLocal(expectedUserId: expectedUserId);
      if (!mounted ||
          (Supabase.instance.client.auth.currentUser?.id != null &&
              !stillInvalidAccount())) {
        return;
      }
      ref.invalidate(sessionIntegrityProvider);
      ref.invalidate(workspaceProvider);
    } finally {
      if (_discardingInvalidUserId == expectedUserId) {
        _discardingInvalidUserId = null;
      }
    }
  }

  Future<void> _verifyChangedAccount(String userId) async {
    if (!mounted || _lastUserId != userId) return;
    setState(() => _accountBootstrapFailed = false);
    ref.invalidate(sessionIntegrityProvider, asReload: true);
    ref.invalidate(workspaceProvider, asReload: true);
    var completed = false;
    try {
      // A changed account must never reuse the previous account's retained
      // AsyncValue while its own identity/workspace requests are pending.
      await Future.wait<Object?>([
        ref.read(sessionIntegrityProvider.future),
        ref.read(workspaceProvider.future),
      ]);
      completed = true;
    } catch (_) {
      // Keep the account blocked, including after a failed first attempt.
    }
    if (!mounted || _lastUserId != userId) return;
    setState(() {
      _providersReadyForUserId = completed ? userId : null;
      _accountBootstrapFailed = !completed;
      _providerResetScheduledForUserId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // The SDK state changes before its asynchronous auth notification is
        // delivered; a previous stream snapshot must not revive an old user.
        final session = Supabase.instance.client.auth.currentSession;
        final currentUserId = session?.user.id;
        if (currentUserId != _lastUserId) {
          _lastUserId = currentUserId;
          _providersReadyForUserId = null;
          _verifiedUserId = null;
          if (currentUserId != null &&
              _providerResetScheduledForUserId != currentUserId) {
            _providerResetScheduledForUserId = currentUserId;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => unawaited(_verifyChangedAccount(currentUserId)),
            );
          } else if (currentUserId == null) {
            _providerResetScheduledForUserId = null;
            _accountBootstrapFailed = false;
            ref.invalidate(sessionIntegrityProvider);
            ref.invalidate(workspaceProvider);
          }
        }
        if (session == null) return const AuthScreen();
        if (_providersReadyForUserId != currentUserId) {
          if (_accountBootstrapFailed) {
            return _WorkspaceErrorScreen(
              message:
                  'Your account could not be opened. Check your connection and try again.',
              onRetry: () => unawaited(_verifyChangedAccount(session.user.id)),
              onSignOut: () => ref.read(authRepositoryProvider).signOutLocal(),
            );
          }
          return const _LoadingScreen();
        }
        final assurance = Supabase.instance.client.auth.mfa
            .getAuthenticatorAssuranceLevel();
        final needsMfa =
            assurance.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
            assurance.nextLevel == AuthenticatorAssuranceLevels.aal2;
        if (needsMfa) {
          return MfaChallengeScreen(onVerified: () => setState(() {}));
        }
        final sessionIntegrity = ref.watch(sessionIntegrityProvider);
        Widget verificationError() => _WorkspaceErrorScreen(
          message:
              'Your sign-in could not be verified. Check your connection and try again.',
          onRetry: () => ref.invalidate(sessionIntegrityProvider),
          onSignOut: () async {
            await ref.read(authRepositoryProvider).signOutLocal();
            ref.invalidate(sessionIntegrityProvider);
            ref.invalidate(workspaceProvider);
          },
        );
        return sessionIntegrity.when(
          // Keep a previously verified route mounted during a temporary
          // revalidation failure, but block it behind an opaque retry screen.
          // A false result still removes the route and discards the session.
          skipError: _verifiedUserId == currentUserId,
          loading: () => const _LoadingScreen(),
          error: (error, _) => verificationError(),
          data: (valid) {
            if (!valid) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  unawaited(_discardInvalidSession(session.user.id));
                }
              });
              return const _LoadingScreen();
            }
            if (!sessionIntegrity.isLoading && !sessionIntegrity.hasError) {
              _verifiedUserId = currentUserId;
            }
            return _VerifiedWorkspaceContent(
              identity: 'authenticated-workspace-$currentUserId',
              errorScreen: sessionIntegrity.hasError
                  ? verificationError()
                  : null,
              child:
                  accountNeedsVerifiedEmail(
                    Supabase.instance.client.auth.currentUser ?? session.user,
                  )
                  ? AuthContactEmailScreen(
                      onVerified: () {
                        if (!mounted) return;
                        ref.invalidate(sessionIntegrityProvider);
                        ref.invalidate(workspaceProvider);
                        setState(() {});
                      },
                    )
                  : WorkspaceGate(child: widget.authenticatedChild),
            );
          },
        );
      },
    );
  }
}

class WorkspaceGate extends ConsumerStatefulWidget {
  final Widget child;

  const WorkspaceGate({super.key, this.child = const MainShell()});

  @override
  ConsumerState<WorkspaceGate> createState() => _WorkspaceGateState();
}

class _WorkspaceGateState extends ConsumerState<WorkspaceGate> {
  bool _hasVerifiedWorkspace = false;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    Widget workspaceError() => _WorkspaceErrorScreen(
      message:
          'Your workspace could not be opened. Check your connection and try again.',
      onRetry: () => ref.invalidate(workspaceProvider),
      onSignOut: () async {
        await ref.read(authRepositoryProvider).signOut();
        ref.invalidate(workspaceProvider);
      },
    );
    return workspace.when(
      skipError: _hasVerifiedWorkspace,
      loading: () => const _LoadingScreen(),
      error: (e, _) => workspaceError(),
      data: (ws) {
        final accountId = ref.read(authRepositoryProvider).currentUserId;
        final subscriptionsEnabled = ref.watch(subscriptionsEnabledProvider);
        Widget withSubscriptionAccess(Widget child) =>
            subscriptionsEnabled && accountId != null
            ? SubscriptionGate(
                key: ValueKey('subscription-$accountId'),
                userId: accountId,
                child: child,
              )
            : child;
        if (ws == null) {
          return workspace.hasError
              ? workspaceError()
              // Verify the store trial before asking a new owner to set up
              // their business. The same gate protects an existing workspace.
              : withSubscriptionAccess(const OnboardingScreen());
        }
        if (!workspace.isLoading && !workspace.hasError) {
          _hasVerifiedWorkspace = true;
        }
        const seedDemoData = bool.fromEnvironment('SEED_DEMO_DATA');
        if (kDebugMode && seedDemoData) {
          ref.watch(debugDemoSeedProvider);
        }
        // Render usable navigation as soon as the workspace is verified.
        // Each section owns its honest loading/error state independently.
        final guideUserId = widget.child is MainShell
            ? ref.read(authRepositoryProvider).currentUserId
            : null;
        final content = _VerifiedWorkspaceContent(
          identity: 'workspace-${ws['id']}',
          errorScreen: workspace.hasError ? workspaceError() : null,
          child: guideUserId != null
              ? FirstUseGuideGate(
                  userId: guideUserId,
                  workspaceId: ws['id'].toString(),
                  child: widget.child,
                )
              : widget.child,
        );
        return withSubscriptionAccess(content);
      },
    );
  }
}

/// Preserve drafts and navigation while a known account/workspace temporarily
/// cannot be revalidated. The opaque error surface blocks interaction and
/// accessibility; changing the verified identity creates a fresh subtree.
class _VerifiedWorkspaceContent extends StatelessWidget {
  final String identity;
  final Widget child;
  final Widget? errorScreen;

  const _VerifiedWorkspaceContent({
    required this.identity,
    required this.child,
    this.errorScreen,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = errorScreen != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: ExcludeSemantics(
            excluding: blocked,
            child: IgnorePointer(
              ignoring: blocked,
              child: KeyedSubtree(key: ValueKey(identity), child: child),
            ),
          ),
        ),
        if (errorScreen != null) Positioned.fill(child: errorScreen!),
      ],
    );
  }
}

class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  FinanceInitialFocus _financeInitialFocus = FinanceInitialFocus.top;
  late final ValueNotifier<WorkWorkspaceSection> _workSectionController;
  late final List<Widget?> _destinations;
  late final List<ScrollController> _navigationScrollControllers;

  @override
  void initState() {
    super.initState();
    _currentIndex = _shellDestination(widget.initialIndex);
    _workSectionController = ValueNotifier(
      _workSectionForDestination(widget.initialIndex),
    );
    _destinations = List<Widget?>.filled(7, null);
    _navigationScrollControllers = List<ScrollController>.generate(
      7,
      (_) => ScrollController(),
    );
    _ensureDestination(_currentIndex);
  }

  @override
  void dispose() {
    _workSectionController.dispose();
    for (final controller in _navigationScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _ensureDestination(int index) {
    _destinations[index] ??= switch (index) {
      0 => DashboardScreen(
        onNavigate: _navigateTo,
        onOpenMoneyFollowUps: () =>
            _navigateTo(3, financeFocus: FinanceInitialFocus.followUps),
      ),
      1 => const ClientsScreen(),
      2 => WorkScreen(sectionController: _workSectionController),
      3 => FinanceScreen(initialFocus: _financeInitialFocus),
      4 || 5 => const SizedBox.shrink(),
      6 => const BusinessScreen(),
      _ => const SizedBox.shrink(),
    };
  }

  Object _navigationScopeId(int index) => 'main-shell-$index';

  int _shellDestination(int destination) => switch (destination) {
    4 || 5 => 2,
    _ => destination,
  };

  WorkWorkspaceSection _workSectionForDestination(int destination) =>
      switch (destination) {
        4 => WorkWorkspaceSection.tasks,
        5 => WorkWorkspaceSection.notes,
        _ => WorkWorkspaceSection.schedule,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WorkloopNavigationAssistRegion.activateScope(
      context,
      _navigationScopeId(_currentIndex),
      controller: _navigationScrollControllers[_currentIndex],
    );
  }

  void _navigateTo(
    int index, {
    FinanceInitialFocus financeFocus = FinanceInitialFocus.top,
  }) {
    // Reselecting Work returns its visible section to the top. Explicit Tasks
    // and Notes destinations below still open their requested section.
    if (index == 2 && _currentIndex == 2) {
      WorkloopNavigationAssistRegion.scrollToTop(context);
      return;
    }
    if (index == 2 || index == 4 || index == 5) {
      _workSectionController.value = _workSectionForDestination(index);
      index = 2;
    }
    if (index == 3 && _financeInitialFocus != financeFocus) {
      _financeInitialFocus = financeFocus;
      _destinations[3] = FinanceScreen(initialFocus: financeFocus);
    }
    _ensureDestination(index);
    if (index == _currentIndex) {
      WorkloopNavigationAssistRegion.scrollToTop(context);
      return;
    }
    setState(() {
      _currentIndex = index;
    });
    WorkloopNavigationAssistRegion.activateScope(
      context,
      _navigationScopeId(index),
      controller: _navigationScrollControllers[index],
    );
  }

  int _primaryNavIndexForDestination(int destination) => switch (destination) {
    0 => 0,
    1 => 1,
    2 || 4 || 5 => 2,
    3 => 3,
    6 => 4,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final destinationChildren = List<Widget>.generate(
      _destinations.length,
      (index) => PrimaryScrollController(
        controller: _navigationScrollControllers[index],
        child: WorkloopNavigationScope(
          id: _navigationScopeId(index),
          child: _destinations[index] ?? const SizedBox.shrink(),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: SlateTheme.of(context).background,
      extendBody: true,
      body: WorkloopInteractiveWorkspaceStack(
        key: const ValueKey('main-shell-tabs'),
        index: _currentIndex,
        previousIndex: null,
        onBack: () {},
        children: destinationChildren,
      ),
      bottomNavigationBar: WorkloopBottomNav(
        currentIndex: _primaryNavIndexForDestination(_currentIndex),
        items: [
          WorkloopNavItem(
            label: 'Today',
            icon: LucideIcons.home,
            color: AppColors.of(context).modHome,
          ),
          WorkloopNavItem(
            label: 'Clients',
            icon: LucideIcons.users,
            color: AppColors.of(context).modClients,
          ),
          WorkloopNavItem(
            label: 'Work',
            icon: LucideIcons.briefcase,
            color: AppColors.of(context).modCalendar,
          ),
          WorkloopNavItem(
            label: 'Money',
            icon: LucideIcons.circlePoundSterling,
            color: AppColors.of(context).modFinance,
          ),
          WorkloopNavItem(
            label: 'Business',
            icon: LucideIcons.store,
            color: AppColors.of(context).modHome,
          ),
        ],
        onTap: (i) {
          final destination = switch (i) {
            0 => 0,
            1 => 1,
            2 => 2,
            3 => 3,
            4 => 6,
            _ => 0,
          };
          _navigateTo(destination);
        },
      ),
    );
  }
}

class _WorkspaceErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  const _WorkspaceErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Scaffold(
      backgroundColor: SlateTheme.of(context).background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: WorkloopSurface(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.alertTriangle,
                    color: tokens.warning,
                    size: 32,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Could not open your workspace',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textTertiary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: WorkloopPrimaryButton(
                          label: 'Try again',
                          icon: LucideIcons.refreshCcw,
                          onPressed: onRetry,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: WorkloopPrimaryButton(
                          label: 'Sign out',
                          icon: LucideIcons.logOut,
                          secondary: true,
                          onPressed: () {
                            onSignOut();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Scaffold(
      backgroundColor: SlateTheme.of(context).background,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: AppMotion.responsive(context, AppMotion.deliberate),
          curve: AppMotion.curve,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  color: tokens.accent,
                  strokeWidth: 2.4,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'Opening Workloop',
                style: TextStyle(
                  color: tokens.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
