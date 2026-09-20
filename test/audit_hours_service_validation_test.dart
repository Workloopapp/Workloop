import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/onboarding/screens/ob_hours.dart';
import 'package:workloop/features/profile/working_hours_editor.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/settings/widgets/settings_business_tab.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/onboarding_repository.dart';
import 'package:workloop/shared/repositories/services_repository.dart';
import 'package:workloop/shared/repositories/workspace_settings_repository.dart';
import 'package:workloop/shared/utils/working_hours.dart';

final _badHours = <String, dynamic>{
  'Mon': {'enabled': true, 'open': '09:00', 'close': '08:00'},
};

class _Draft extends OnboardingNotifier {
  int saves = 0;
  @override
  OnboardingState build() => OnboardingState(workingHours: _badHours);
  @override
  void setWorkingHours(Map<String, dynamic> hours) {
    saves++;
  }
}

class _Services extends ServicesRepository {
  _Services()
    : super(
        SupabaseClient(
          'https://example.com',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final savedPrices = <double>[];
  @override
  Future<void> create({
    required String workspaceId,
    required String name,
    required double price,
    required int durationMins,
    String? description,
    bool showOnProfile = true,
    bool active = true,
  }) async {
    savedPrices.add(price);
  }

  @override
  Future<void> update(String serviceId, Map<String, dynamic> values) async {
    savedPrices.add((values['price'] as num).toDouble());
  }

  @override
  Future<List<ServiceAddOn>> listAddOns({
    required String workspaceId,
    required String serviceId,
    bool includeInactive = true,
  }) async => [];
}

class _HoursRepository extends WorkspaceSettingsRepository {
  _HoursRepository()
    : super(
        SupabaseClient(
          'https://example.com',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int saves = 0;
  @override
  Future<void> update(String workspaceId, Map<String, dynamic> values) async {
    saves++;
  }
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  test(
    'working-hour drafts reject malformed ranges and overlaps without repair',
    () {
      for (final range in [
        {'start': '09:00', 'end': '08:00'},
        {'start': '09:00', 'end': '09:00'},
        {'start': '25:00', 'end': '17:00'},
        {'start': '9:3', 'end': '17:00'},
        {'start': 900, 'end': '17:00'},
        {'end': '17:00'},
      ]) {
        expect(
          validateWorkingHours({
            'Monday': {
              'enabled': true,
              'blocks': [range],
            },
          }),
          contains('Monday'),
        );
      }
      expect(
        validateWorkingHours({
          'Monday': {
            'enabled': true,
            'blocks': [
              {'start': '12:00', 'end': '17:00'},
              {'start': '09:00', 'end': '13:00'},
            ],
          },
        }),
        contains('Monday'),
      );
      expect(
        validateWorkingHours({
          'Monday': {
            'enabled': true,
            'blocks': [
              {'start': '12:00', 'end': '17:00'},
              {'start': '09:00', 'end': '12:00'},
            ],
          },
          'Sun': {'enabled': false, 'open': 'bad', 'close': 'bad'},
        }),
        isEmpty,
      );
      expect(
        validateWorkingHours({
          'Mon': {'enabled': true, 'blocks': []},
        }),
        contains('Mon'),
      );
      expect(validateWorkingHours(_badHours), contains('Mon'));
      expect(_badHours['Mon']['close'], '08:00');
    },
  );
  test(
    'completion mapping and settings repository reject invalid hours before I/O',
    () async {
      expect(
        () => buildOnboardingRpcParams(
          businessName: 'Test',
          industry: 'Other',
          handle: 'test-studio',
          services: [],
          workingHours: _badHours,
          revenueTarget: 0,
        ),
        throwsFormatException,
      );
      final client = SupabaseClient(
        'https://example.com',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await expectLater(
        WorkspaceSettingsRepository(
          client,
        ).update('workspace-1', {'working_hours': _badHours}),
        throwsFormatException,
      );
      await client.dispose();
    },
  );
  testWidgets(
    'onboarding retains reversed hours and marks Monday without advancing',
    (tester) async {
      final draft = _Draft();
      var advanced = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [onboardingProvider.overrideWith(() => draft)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ObHours(onNext: () => advanced = true, onBack: () {}),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-hours-continue')));
      await tester.pumpAndSettle();
      expect(advanced, isFalse);
      expect(draft.saves, 0);
      expect(
        find.text('Monday: closing time must be after opening time.'),
        findsOneWidget,
      );
      expect(find.text('08:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final profile in [false, true]) {
    testWidgets(
      '${profile ? 'profile' : 'settings'} hours rejects invalid Monday without saving',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _HoursRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
              workspaceProvider.overrideWith(
                (ref) async => {'id': 'workspace-1', 'name': 'Studio'},
              ),
              settingsWorkspaceSettingsProvider.overrideWith(
                (ref) async => {'working_hours': _badHours},
              ),
              settingsBusinessProfileProvider.overrideWith((ref) async => null),
              settingsServicesProvider.overrideWith((ref) async => []),
              workspaceSettingsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: profile
                    ? const WorkingHoursEditor()
                    : const SettingsBusinessTab(
                        initialSection: SettingsBusinessSection.workingHours,
                        showOnlySelected: true,
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!profile) {
          await tester.tap(find.text('Availability'));
          await tester.pumpAndSettle();
        }
        final save = find.text(profile ? 'Save hours' : 'Save Hours');
        await tester.scrollUntilVisible(
          save,
          500,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(save);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Monday: closing time must be after opening time.'),
          -500,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(repository.saves, 0);
        expect(
          find.text('Monday: closing time must be after opening time.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? 'edit' : 'add'} service preserves invalid price and accepts explicit zero',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = _Services();
        final controller = SettingsBusinessController();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
              workspaceProvider.overrideWith(
                (ref) async => {'id': 'workspace-1', 'name': 'Studio'},
              ),
              settingsWorkspaceSettingsProvider.overrideWith(
                (ref) async => null,
              ),
              settingsBusinessProfileProvider.overrideWith((ref) async => null),
              settingsServicesProvider.overrideWith(
                (ref) async => [
                  if (editing)
                    {
                      'id': 'service-1',
                      'workspace_id': 'workspace-1',
                      'name': 'Haircut',
                      'price': 45,
                      'duration_mins': 60,
                      'show_on_profile': true,
                    },
                ],
              ),
              servicesRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SettingsBusinessTab(
                  initialSection: SettingsBusinessSection.services,
                  showOnlySelected: true,
                  controller: controller,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (editing) {
          await tester.tap(find.text('Haircut'));
        } else {
          controller.showAddService();
        }
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        if (!editing) await tester.enterText(fields.at(0), 'Consultation');
        final priceField = fields.at(2);
        final save = find.widgetWithText(
          ElevatedButton,
          editing ? 'Save Changes' : 'Add Service',
        );
        for (final bad in [
          'bad',
          '',
          '-1',
          'NaN',
          'Infinity',
          '1e2',
          '12.345',
        ]) {
          await tester.enterText(priceField, bad);
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(repo.savedPrices, isEmpty);
          expect(
            find.text('Use a valid price with up to two decimal places.'),
            findsOneWidget,
          );
          expect(tester.widget<TextField>(priceField).controller!.text, bad);
        }
        await tester.enterText(priceField, '0');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.savedPrices, [0]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
