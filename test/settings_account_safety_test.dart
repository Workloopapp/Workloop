import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/settings/widgets/settings_account_tab.dart';
import 'package:workloop/features/settings/account_deletion_confirmation_screen.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/slate_repositories.dart';

SupabaseClient _client() => SupabaseClient(
  'https://example.supabase.co',
  'test',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

class _Auth extends AuthRepository {
  _Auth() : super(_client());
  String? owner = 'owner-a';
  String name = 'Alex';
  String email = 'alex@example.com';
  final events = StreamController<AuthState>.broadcast();
  Completer<void>? nameOperation;
  Completer<void>? codeOperation;
  Completer<void>? passwordOperation;
  bool failSignOut = false;
  int nameCalls = 0;
  int codeCalls = 0;
  int passwordCalls = 0;
  int signOutCalls = 0;
  String? expectedSignOutOwner;
  bool apple = false;
  bool appleCancelled = false;
  int appleRequests = 0;
  Completer<String>? appleOperation;
  @override
  bool get hasAppleIdentity => apple;
  @override
  Future<String> requestAppleDeletionAuthorization() async {
    appleRequests++;
    if (appleCancelled) {
      throw const AppleDeletionAuthorizationException(cancelled: true);
    }
    return appleOperation == null
        ? 'fixture-apple-code'
        : appleOperation!.future;
  }

  @override
  String? get currentUserId => owner;
  @override
  String? get currentFirstName => name;
  @override
  String get currentEmail => email;
  @override
  Stream<AuthState> get authChanges => events.stream;
  @override
  Future<void> updateFirstName(String firstName) async {
    nameCalls++;
    await nameOperation?.future;
    name = firstName;
  }

  @override
  Future<void> requestPasswordReauthentication() async {
    codeCalls++;
    await codeOperation?.future;
  }

  @override
  Future<void> updatePassword(String password, {String? nonce}) async {
    passwordCalls++;
    await passwordOperation?.future;
  }

  @override
  Future<void> signOutLocal({String? expectedUserId}) async {
    signOutCalls++;
    expectedSignOutOwner = expectedUserId;
    if (failSignOut) throw StateError('offline');
    if (owner == expectedUserId) owner = null;
  }

  void switchAccount() {
    owner = 'owner-b';
    events.add(AuthState(AuthChangeEvent.signedIn, null));
  }
}

class _Privacy extends PrivacyRepository {
  _Privacy() : super(_client());
  int exports = 0;
  int deletions = 0;
  Completer<String>? exportOperation;
  Completer<void>? deletionOperation;
  bool incomplete = false;
  bool appleMismatch = false;
  String? deletionCode;
  AccountDeletionResult deletionResult = const AccountDeletionResult();
  @override
  Future<String> exportWorkspaceData(String workspaceId) async {
    exports++;
    if (incomplete) throw const PrivacyExportIncompleteException(['contacts']);
    return exportOperation == null
        ? '{"workspace_id":"workspace-a"}'
        : exportOperation!.future;
  }

  @override
  Future<AccountDeletionResult> requestAccountDeletion({
    String? workspaceId,
    String? appleAuthorizationCode,
  }) async {
    deletions++;
    deletionCode = appleAuthorizationCode;
    if (appleMismatch) {
      throw const AccountDeletionException(appleIdentityMismatch: true);
    }
    await deletionOperation?.future;
    return deletionResult;
  }
}

class _BrokenDraftCleanup extends OnboardingNotifier {
  @override
  OnboardingState build() => const OnboardingState();
  @override
  Future<void> clearDraft() async => throw StateError('disk unavailable');
}

void main() {
  const picker = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  late _Auth auth;
  late _Privacy privacy;
  late List<MethodCall> fileSaves;
  late GoRouter router;
  var workspace = 'workspace-a';

  setUp(() {
    auth = _Auth();
    privacy = _Privacy();
    workspace = 'workspace-a';
    fileSaves = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, (call) async {
          fileSaves.add(call);
          return '/selected/workloop.json';
        });
  });
  tearDown(() async {
    await auth.events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool dataOnly = false,
    double scale = 1,
    Size size = const Size(390, 844),
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              Scaffold(body: SettingsAccountTab(showDataOnly: dataOnly)),
        ),
        GoRoute(
          path: '/account-deletion-requested',
          builder: (_, state) => AccountDeletionConfirmationScreen(
            result: state.extra! as AccountDeletionResult,
          ),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, _) => const Scaffold(body: Text('Sign in')),
        ),
        GoRoute(
          path: '/elsewhere',
          builder: (_, _) => const Scaffold(body: Text('Another screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          privacyRepositoryProvider.overrideWithValue(privacy),
          workspaceIdProvider.overrideWith((ref) async => workspace),
          sessionIntegrityProvider.overrideWith((ref) async => true),
          workspaceProvider.overrideWith((ref) async => {'id': workspace}),
          onboardingProvider.overrideWith(_BrokenDraftCleanup.new),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SettingsAccountTab)),
    );
  }

  Future<void> tapRow(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.widgetWithText(ElevatedButton, label);
  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets(
    'account and privacy destinations show only their relevant controls',
    (tester) async {
      await pump(tester);
      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Set or change password'), findsOneWidget);
      expect(find.text('Delete account'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, dataOnly: true);
      expect(find.text('Export your data'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Set or change password'), findsNothing);
    },
  );

  testWidgets(
    'long identity and every account action remain accessible at large text',
    (tester) async {
      auth.name = 'Alexanderson-Verylongfirstname';
      auth.email = 'averylongpersonal.emailaddress@example.co.uk';
      await pump(tester, scale: 2, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
      await tapRow(tester, 'Sign out');
      expect(find.text('Sign out?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'name failure keeps draft and allows one retry, not duplicate saves',
    (tester) async {
      await pump(tester);
      await tapRow(tester, 'Your name');
      await tester.enterText(field('First name'), 'Sam');
      auth.nameOperation = Completer<void>();
      await tester.tap(button('Save name'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(auth.nameCalls, 1);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      final sheetContext = tester.element(field('First name'));
      await Navigator.of(sheetContext).maybePop();
      await tester.pump();
      expect(
        find.text('Save name'),
        findsNothing,
      ); // Spinner while still saving.
      expect(field('First name'), findsOneWidget);
      auth.nameOperation!.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your name could not be saved'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(field('First name')).controller!.text,
        'Sam',
      );
      auth.nameOperation = null;
      await tester.tap(button('Save name'));
      await tester.pumpAndSettle();
      expect(auth.nameCalls, 2);
      expect(auth.name, 'Sam');
      expect(field('First name'), findsNothing);
    },
  );

  testWidgets('name form fits keyboard and large text with reachable save', (
    tester,
  ) async {
    await pump(tester, scale: 2, size: const Size(320, 568), keyboard: 260);
    await tapRow(tester, 'Your name');
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(button('Save name'));
    await tester.pumpAndSettle();
    expect(button('Save name').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sign-out failure remains in sheet with retry and scopes current owner',
    (tester) async {
      auth.failSignOut = true;
      await pump(tester);
      await tapRow(tester, 'Sign out');
      await tester.tap(button('Sign out'));
      await tester.pumpAndSettle();
      expect(
        find.text('We couldn’t sign you out. Please try again.'),
        findsOneWidget,
      );
      expect(auth.expectedSignOutOwner, 'owner-a');
      auth.failSignOut = false;
      await tester.tap(button('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      expect(auth.signOutCalls, 2);
    },
  );

  testWidgets(
    'password code requests recover and labels do not assume a password exists',
    (tester) async {
      auth.codeOperation = Completer<void>();
      await pump(tester);
      await tester.tap(find.text('Set or change password'));
      await tester.pump();
      expect(auth.codeCalls, 1);
      auth.codeOperation!.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('A security code could not be sent'),
        findsOneWidget,
      );
      auth.codeOperation = null;
      await tester.tap(find.text('Set or change password'));
      await tester.pumpAndSettle();
      expect(field('Email security code'), findsOneWidget);
      expect(auth.codeCalls, 2);
    },
  );

  testWidgets(
    'password validation sends no request, pending update blocks resend and cancel',
    (tester) async {
      await pump(tester);
      await tapRow(tester, 'Set or change password');
      await tester.ensureVisible(find.text('Save password'));
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
      expect(auth.passwordCalls, 0);
      expect(
        find.text('Enter the 6-digit security code from your email.'),
        findsOneWidget,
      );
      await tester.enterText(field('Email security code'), '123456');
      await tester.enterText(field('New password'), 'Goodpassword!123');
      await tester.enterText(field('Confirm password'), 'Goodpassword!123');
      auth.passwordOperation = Completer<void>();
      await tester.ensureVisible(find.text('Save password'));
      await tester.tap(find.text('Save password'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(auth.passwordCalls, 1);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Send a new code'),
            )
            .onPressed,
        isNull,
      );
      auth.passwordOperation!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Password updated'), findsOneWidget);
      expect(field('New password'), findsNothing);
    },
  );

  testWidgets(
    'account switch closes owned personal sheet and suppresses late name feedback',
    (tester) async {
      await pump(tester);
      await tapRow(tester, 'Your name');
      auth.nameOperation = Completer<void>();
      await tester.enterText(field('First name'), 'Sam');
      await tester.tap(button('Save name'));
      await tester.pump();
      auth.switchAccount();
      await tester.pumpAndSettle();
      expect(field('First name'), findsNothing);
      expect(find.textContaining('Your account has changed'), findsOneWidget);
      auth.nameOperation!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Name updated'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'export saves actual returned JSON and incomplete export saves nothing',
    (tester) async {
      await pump(tester, dataOnly: true);
      await tapRow(tester, 'Export your data');
      expect(fileSaves.length, 1);
      expect(
        utf8.decode((fileSaves.single.arguments as Map)['bytes'] as List<int>),
        '{"workspace_id":"workspace-a"}',
      );
      expect(find.text('Data export saved'), findsOneWidget);
      privacy.incomplete = true;
      await tapRow(tester, 'Export your data');
      expect(fileSaves.length, 1);
      expect(find.textContaining('The export was incomplete'), findsOneWidget);
    },
  );

  for (final interruption in [
    'account',
    'workspace',
    'navigation',
    'dispose',
  ]) {
    testWidgets(
      'delayed export cannot open file picker after $interruption change',
      (tester) async {
        privacy.exportOperation = Completer<String>();
        final container = await pump(tester, dataOnly: true);
        await tester.tap(find.text('Export your data'));
        await tester.pump();
        expect(privacy.exports, 1);
        if (interruption == 'account') auth.switchAccount();
        if (interruption == 'workspace') {
          workspace = 'workspace-b';
          container.invalidate(workspaceIdProvider);
        }
        if (interruption == 'navigation') router.push('/elsewhere');
        if (interruption == 'dispose') {
          await tester.pumpWidget(const SizedBox());
        }
        await tester.pump();
        privacy.exportOperation!.complete('{"private":"owner-a"}');
        await tester.pumpAndSettle();
        expect(fileSaves, isEmpty);
        expect(find.text('Data export saved'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'deletion explains access loss and stays safe on optional cleanup failure',
    (tester) async {
      await pump(tester, dataOnly: true);
      await tapRow(tester, 'Delete account');
      expect(
        find.textContaining('lose access to this account'),
        findsOneWidget,
      );
      expect(find.textContaining('trusted backend'), findsNothing);
      await tester.enterText(field('Type DELETE to confirm'), 'DELETE');
      await tester.pump();
      privacy.deletionOperation = Completer<void>();
      await tester.ensureVisible(button('Request deletion'));
      await tester.tap(button('Request deletion'));
      await tester.pump();
      expect(privacy.deletions, 1);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      privacy.deletionOperation!.complete();
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      expect(auth.expectedSignOutOwner, 'owner-a');
      expect(find.textContaining('could not be confirmed'), findsNothing);
      expect(find.text('Request account deletion'), findsNothing);
    },
  );
  Future<void> confirmDeletion(WidgetTester tester) async {
    await tapRow(tester, 'Delete account');
    await tester.enterText(field('Type DELETE to confirm'), 'DELETE');
    await tester.pump();
    await tester.ensureVisible(button('Request deletion'));
    await tester.tap(button('Request deletion'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Apple cancellation leaves account intact until explicit manual fallback',
    (tester) async {
      auth.apple = true;
      auth.appleCancelled = true;
      privacy.deletionResult = const AccountDeletionResult(
        appleRevocation: AppleAccountRevocation.manualActionRequired,
      );
      await pump(tester, dataOnly: true);
      await confirmDeletion(tester);
      expect(auth.owner, 'owner-a');
      expect(auth.signOutCalls, 0);
      expect(privacy.deletions, 0);
      expect(
        find.textContaining('Apple confirmation was cancelled'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Continue deletion without Apple'));
      await tester.tap(find.text('Continue deletion without Apple'));
      await tester.pumpAndSettle();
      expect(privacy.deletions, 1);
      expect(privacy.deletionCode, isNull);
      expect(auth.owner, isNull);
      expect(find.text('Your request is recorded'), findsOneWidget);
      expect(find.text('Finish disconnecting Apple'), findsOneWidget);
      expect(find.text('Open Apple Account'), findsOneWidget);
    },
  );

  testWidgets(
    'fresh Apple code goes to deletion and revoked result stays clear',
    (tester) async {
      auth.apple = true;
      privacy.deletionResult = const AccountDeletionResult(
        appleRevocation: AppleAccountRevocation.revoked,
      );
      await pump(tester, dataOnly: true);
      await confirmDeletion(tester);
      expect(auth.appleRequests, 1);
      expect(privacy.deletionCode, 'fixture-apple-code');
      expect(find.text('Your request is recorded'), findsOneWidget);
      expect(find.text('Finish disconnecting Apple'), findsNothing);
      expect(find.textContaining('does not cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'Apple identity mismatch can retry or explicitly continue manual unlink',
    (tester) async {
      auth.apple = true;
      privacy.appleMismatch = true;
      await pump(tester, dataOnly: true);
      await confirmDeletion(tester);
      expect(auth.signOutCalls, 0);
      expect(auth.owner, 'owner-a');
      expect(
        find.textContaining('not linked to this Workloop account'),
        findsOneWidget,
      );
      expect(find.text('Continue deletion without Apple'), findsOneWidget);
      privacy.appleMismatch = false;
      await tester.ensureVisible(button('Request deletion'));
      await tester.tap(button('Request deletion'));
      await tester.pumpAndSettle();
      expect(auth.appleRequests, 2);
      expect(auth.signOutCalls, 1);
    },
  );

  testWidgets(
    'account switch during native Apple confirmation cannot delete next account',
    (tester) async {
      auth.apple = true;
      auth.appleOperation = Completer<String>();
      await pump(tester, dataOnly: true);
      await tapRow(tester, 'Delete account');
      await tester.enterText(field('Type DELETE to confirm'), 'DELETE');
      await tester.pump();
      await tester.ensureVisible(button('Request deletion'));
      await tester.tap(button('Request deletion'));
      await tester.pump();
      auth.switchAccount();
      await tester.pumpAndSettle();
      auth.appleOperation!.complete('unused-fixture');
      await tester.pumpAndSettle();
      expect(privacy.deletions, 0);
      expect(auth.signOutCalls, 0);
      expect(auth.owner, 'owner-b');
      expect(tester.takeException(), isNull);
    },
  );
}
