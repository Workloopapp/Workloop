import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Test-only in-memory backend for SharedPreferencesAsync.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/onboarding/screens/ob_first_booking.dart';
import 'package:workloop/features/onboarding/screens/ob_complete.dart';
import 'package:workloop/features/onboarding/screens/ob_profile.dart';
import 'package:workloop/features/onboarding/screens/ob_services.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/notifications_repository.dart';
import 'package:workloop/shared/repositories/onboarding_repository.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';

class _DraftNotifier extends OnboardingNotifier {
  final OnboardingState draft;
  _DraftNotifier(this.draft);
  @override
  OnboardingState build() => draft;
}

class _SignedOutAuth implements GoTrueClient {
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOutClient implements SupabaseClient {
  @override
  GoTrueClient get auth => _SignedOutAuth();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SavingOnboarding implements OnboardingRepository {
  bool saved = false;
  int calls = 0;
  @override
  Future<String?> complete({
    required String firstName,
    required String businessName,
    required String industry,
    required String handle,
    required List<Map<String, dynamic>> services,
    required Map<String, dynamic> workingHours,
    required double revenueTarget,
    Map<String, dynamic>? firstBooking,
  }) async {
    calls++;
    saved = true;
    return 'new-workspace';
  }
}

class _SavedNotifications implements NotificationsRepository {
  final bool fail;
  _SavedNotifications({this.fail = false});
  @override
  Future<void> upsertPreferences(
    String workspaceId,
    Map<String, dynamic> prefs,
  ) async {
    if (fail) throw StateError('Preferences unavailable after commit');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen,
  OnboardingState draft,
) async {
  final client = _SignedOutClient();
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      onboardingProvider.overrideWith(() => _DraftNotifier(draft)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: screen),
      ),
    ),
  );
  return container;
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  testWidgets('reminder failure does not repeat committed workspace creation', (
    tester,
  ) async {
    final repository = _SavingOnboarding();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(_SignedOutClient()),
          onboardingProvider.overrideWith(
            () => _DraftNotifier(
              const OnboardingState(
                firstName: 'Alex',
                businessName: 'Alex Services',
                handle: 'alex-services',
                industry: 'Gardener',
              ),
            ),
          ),
          onboardingRepositoryProvider.overrideWithValue(repository),
          notificationsRepositoryProvider.overrideWithValue(
            _SavedNotifications(fail: true),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ObComplete()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(find.text('Your workspace\nis ready.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(
      find.textContaining('Reminder preferences could not be saved'),
      findsOneWidget,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saved setup keeps completion visible until the owner chooses to enter',
    (tester) async {
      final client = _SignedOutClient();
      final repository = _SavingOnboarding();
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          onboardingProvider.overrideWith(
            () => _DraftNotifier(
              const OnboardingState(
                firstName: 'Alex',
                businessName: 'Alex Services',
                handle: 'alex-services',
                industry: 'Gardener',
              ),
            ),
          ),
          onboardingRepositoryProvider.overrideWithValue(repository),
          notificationsRepositoryProvider.overrideWithValue(
            _SavedNotifications(),
          ),
          workspaceProvider.overrideWith(
            (_) async => repository.saved ? {'id': 'new-workspace'} : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (_, ref, _) => ref
                    .watch(workspaceProvider)
                    .when(
                      data: (workspace) => workspace == null
                          ? const ObComplete()
                          : const Text('Workspace opened'),
                      error: (_, _) => const Text('Error'),
                      loading: () => const Text('Loading'),
                    ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.saved, isTrue);
      expect(find.text('Your workspace\nis ready.'), findsOneWidget);
      expect(find.text('Workspace opened'), findsNothing);
      await tester.ensureVisible(find.text('Go to my dashboard'));
      await tester.tap(find.text('Go to my dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Workspace opened'), findsOneWidget);
    },
  );

  testWidgets(
    'Other requires an occupation and keeps it through draft restoration',
    (tester) async {
      var continued = false;
      final container = await _pump(
        tester,
        ObProfile(onNext: () => continued = true, onBack: () {}),
        const OnboardingState(firstName: 'Alex', businessName: 'Alex Services'),
      );
      final picker = tester.widget<WorkloopPickerField<String>>(
        find.byType(WorkloopPickerField<String>),
      );
      picker.onChanged('Other');
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Continue'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-occupation')),
        '  Dog groomer  ',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      expect(continued, isTrue);
      expect(container.read(onboardingProvider).industry, 'Dog groomer');
      final restored = OnboardingState.fromJson(
        container.read(onboardingProvider).toJson(),
      );
      await _pump(
        tester,
        ObProfile(
          key: const ValueKey('restored-profile'),
          onNext: () {},
          onBack: () {},
        ),
        restored,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('custom-occupation')))
            .controller!
            .text,
        'Dog groomer',
      );
      expect(
        tester
            .widget<WorkloopPickerField<String>>(
              find.byType(WorkloopPickerField<String>),
            )
            .value,
        'Other',
      );
    },
  );

  test(
    'valeting and custom occupations use existing industry RPC contract',
    () {
      expect(industries, contains('Mobile Valeting & Detailing'));
      expect(
        industryServices['Mobile Valeting & Detailing']!.any(
          (s) => s['name'] == 'Full Valet',
        ),
        isTrue,
      );
      final payload = buildOnboardingRpcParams(
        businessName: 'Alex Auto',
        industry: 'Mobile Valeting & Detailing',
        handle: 'alex-auto',
        services: [],
        workingHours: {},
        revenueTarget: 0,
      );
      expect(payload['industry_name'], 'Mobile Valeting & Detailing');
      expect(payload['first_booking_value'], isNull);
      expect(
        OnboardingState.fromJson(
          const OnboardingState(industry: 'Dog groomer').toJson(),
        ).industry,
        'Dog groomer',
      );
    },
  );

  testWidgets(
    'adding a service keeps its multiline description in the draft and preview',
    (tester) async {
      final container = await _pump(
        tester,
        ObServices(onNext: () {}, onBack: () {}),
        const OnboardingState(servicesReviewed: true),
      );
      final add = find.widgetWithText(OutlinedButton, 'Add a service');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();

      await tester.enterText(_serviceField('Service name'), 'Full valet');
      final description = find.byKey(
        const ValueKey('onboarding-service-description'),
      );
      await tester.ensureVisible(description);
      await tester.enterText(
        description,
        '  Interior vacuum and clean.\nExterior wash and dry.  ',
      );
      await tester.ensureVisible(_serviceField('Price'));
      await tester.enterText(_serviceField('Price'), '75.50');
      await _saveServiceEditor(tester, creating: true);

      const expectedDescription =
          'Interior vacuum and clean.\nExterior wash and dry.';
      expect(container.read(onboardingProvider).services.single, {
        'name': 'Full valet',
        'description': expectedDescription,
        'duration': 60,
        'price': 75.5,
      });
      expect(find.text(expectedDescription), findsOneWidget);
      expect(tester.widget<Text>(find.text(expectedDescription)).maxLines, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('service description edit prefills, updates and clears', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      ObServices(onNext: () {}, onBack: () {}),
      const OnboardingState(
        servicesReviewed: true,
        services: [
          {
            'name': 'Full valet',
            'description': 'Inside and out.\nAllow time for drying.',
            'duration': 90,
            'price': 75.5,
          },
        ],
      ),
    );
    const updated = 'Interior refresh.\nExterior hand wash.';
    for (final (initial, entered, expected) in [
      ('Inside and out.\nAllow time for drying.', '  $updated  ', updated),
      (updated, ' \n\t ', null),
    ]) {
      await tester.ensureVisible(find.text('Full valet'));
      await tester.tap(find.text('Full valet'));
      await tester.pumpAndSettle();
      final description = find.byKey(
        const ValueKey('onboarding-service-description'),
      );
      expect(tester.widget<TextField>(description).controller!.text, initial);
      await tester.ensureVisible(description);
      await tester.enterText(description, entered);
      await _saveServiceEditor(tester);
      final saved = container.read(onboardingProvider).services.single;
      expect(saved['description'], expected);
      expect(saved['name'], 'Full valet');
      expect(saved['duration'], 90);
      expect(saved['price'], 75.5);
      expect(tester.takeException(), isNull);
    }
    expect(find.text(updated), findsNothing);
  });

  testWidgets('cancelling a service edit preserves the original description', (
    tester,
  ) async {
    const original = {
      'name': 'Full valet',
      'description': 'Inside and out.\nAllow time for drying.',
      'duration': 90,
      'price': 75.5,
    };
    final container = await _pump(
      tester,
      ObServices(onNext: () {}, onBack: () {}),
      const OnboardingState(servicesReviewed: true, services: [original]),
    );
    await tester.ensureVisible(find.text('Full valet'));
    await tester.tap(find.text('Full valet'));
    await tester.pumpAndSettle();
    final description = find.byKey(
      const ValueKey('onboarding-service-description'),
    );
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Unsaved replacement');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(description, findsNothing);
    expect(container.read(onboardingProvider).services.single, original);
    expect(find.text(original['description']! as String), findsOneWidget);
    expect(find.text('Unsaved replacement'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy service can still be saved without a description', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      ObServices(onNext: () {}, onBack: () {}),
      const OnboardingState(
        servicesReviewed: true,
        services: [
          {'name': 'Consultation', 'duration': 30, 'price': 0.0},
        ],
      ),
    );
    await tester.ensureVisible(find.text('Consultation'));
    await tester.tap(find.text('Consultation'));
    await tester.pumpAndSettle();
    final description = find.byKey(
      const ValueKey('onboarding-service-description'),
    );
    expect(tester.widget<TextField>(description).controller!.text, isEmpty);
    await _saveServiceEditor(tester);
    expect(container.read(onboardingProvider).services.single, {
      'name': 'Consultation',
      'description': null,
      'duration': 30,
      'price': 0.0,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'skipping services clears prior choices and does not restore suggestions',
    (tester) async {
      const draft = OnboardingState(
        servicesReviewed: true,
        services: [
          {'name': 'Full Valet', 'duration': 180, 'price': 120.0},
        ],
        firstBooking: {'clientName': 'Maya', 'serviceName': 'Full Valet'},
      );
      final container = await _pump(
        tester,
        ObServices(onNext: () {}, onBack: () {}),
        draft,
      );
      await tester.ensureVisible(find.text('Skip — add services later'));
      await tester.tap(find.text('Skip — add services later'));
      final state = container.read(onboardingProvider);
      expect(state.services, isEmpty);
      expect(state.firstBooking, isNull);
      expect(state.servicesReviewed, isTrue);
      await _pump(
        tester,
        ObServices(
          key: const ValueKey('restored-services'),
          onNext: () {},
          onBack: () {},
        ),
        OnboardingState.fromJson(state.toJson()),
      );
      expect(find.text('Consultation'), findsNothing);
      expect(find.text('Full Valet'), findsNothing);
    },
  );

  testWidgets(
    'skipping a previously chosen first booking removes it from final setup',
    (tester) async {
      final container = await _pump(
        tester,
        ObFirstBooking(onNext: () {}, onBack: () {}),
        const OnboardingState(
          services: [
            {'name': 'Session', 'duration': 60, 'price': 20},
          ],
          firstBooking: {
            'clientName': 'Maya',
            'serviceName': 'Session',
            'date': '2026-01-01',
            'hour': 9,
            'minute': 0,
          },
        ),
      );
      await tester.ensureVisible(find.text('Skip — I’ll do this later'));
      await tester.tap(find.text('Skip — I’ll do this later'));
      expect(container.read(onboardingProvider).firstBooking, isNull);
    },
  );
}

Future<void> _saveServiceEditor(
  WidgetTester tester, {
  bool creating = false,
}) async {
  final action = find.widgetWithText(
    SlateButton,
    creating ? 'Add service' : 'Save service',
  );
  // Finish the field's caret/focus scrolling before calculating the button's
  // reveal offset; otherwise that pending scroll can move it off-screen again.
  await tester.pumpAndSettle();
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('onboarding-service-description')),
    findsNothing,
  );
}

Finder _serviceField(String label) => find.descendant(
  of: find.widgetWithText(WorkloopFormField, label),
  matching: find.byType(TextField),
);
