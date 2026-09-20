import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/business_feed/business_feed_screen.dart';
import 'package:workloop/features/clients/add_client_screen.dart';
import 'package:workloop/features/clients/clients_screen.dart';
import 'package:workloop/features/dashboard/dashboard_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/payment_collection_sheet.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/profile/booking_page_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/public_profile/public_profile_screen.dart';
import 'package:workloop/features/settings/settings_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/tasks/tasks_screen.dart';
import 'package:workloop/features/work/work_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/business_feed_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/setup_checklist_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';
import 'package:workloop/shared/repositories/services_repository.dart';
import 'package:workloop/main.dart' show MainShell;

void main() {
  testWidgets(
    'primary launch surfaces render across phone and text-scale matrix',
    (tester) async {
      final finance = FinanceSummary.from(
        payments: const [],
        expenses: const [],
        monthlyTarget: 5000,
        now: DateTime(2026, 7, 26),
      );
      final authRepository = AuthRepository(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      final servicesRepository = _ResponsiveServicesRepository(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      final devices = <_DeviceCase>[
        const _DeviceCase('small iPhone', Size(320, 568), TargetPlatform.iOS),
        const _DeviceCase(
          'standard iPhone',
          Size(390, 844),
          TargetPlatform.iOS,
        ),
        const _DeviceCase('large iPhone', Size(430, 932), TargetPlatform.iOS),
        const _DeviceCase(
          'small Android',
          Size(360, 640),
          TargetPlatform.android,
        ),
        const _DeviceCase(
          'standard Android',
          Size(412, 915),
          TargetPlatform.android,
        ),
        const _DeviceCase(
          'large Android',
          Size(480, 960),
          TargetPlatform.android,
        ),
      ];
      final surfaces = <_SurfaceCase>[
        _SurfaceCase('authentication', () => const AuthScreen()),
        _SurfaceCase(
          'dashboard',
          () =>
              DashboardScreen(onNavigate: (_) {}, onOpenMoneyFollowUps: () {}),
        ),
        _SurfaceCase('clients', () => const ClientsScreen()),
        _SurfaceCase('main shell', () => const MainShell()),
        _SurfaceCase('work', () => const WorkScreen()),
        _SurfaceCase('money', () => const FinanceScreen()),
        _SurfaceCase('business', () => const BusinessScreen()),
        _SurfaceCase('booking page', () => const BookingPageScreen()),
        _SurfaceCase(
          'booking detail',
          () => const AppointmentDetailScreen(
            appointment: _appointmentDetailFixture,
          ),
        ),
        _SurfaceCase(
          'payment setup',
          () => Scaffold(body: PaymentSetupCard(onTap: _noOp)),
        ),
        _SurfaceCase('tasks', () => const TasksScreen()),
        _SurfaceCase('notes', () => const NotesScreen(showBackButton: false)),
        _SurfaceCase('business feed', () => const BusinessFeedScreen()),
        _SurfaceCase('booking requests', () => const BookingRequestsScreen()),
        _SurfaceCase('settings', () => const SettingsScreen()),
        _SurfaceCase(
          'public profile',
          () => const PublicProfileScreen(
            handle: 'quality-studio',
            previewProfile: _previewProfile,
          ),
        ),
      ];
      final appearances = <(String, ThemeData)>[
        ('Light', AppTheme.light),
        ('Dark', AppTheme.dark),
      ];

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final device in devices) {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1;
        for (final scale in const [1.0, 2.0]) {
          for (final appearance in appearances) {
            for (final surface in surfaces) {
              await tester.pumpWidget(
                ProviderScope(
                  overrides: [
                    clientCrmRecordsProvider.overrideWith(
                      (ref) async => const [],
                    ),
                    workspaceProvider.overrideWith(
                      (ref) async => const {'id': 'workspace-1'},
                    ),
                    setupChecklistDismissedProvider.overrideWith(
                      (ref) async => true,
                    ),
                    dashboardClockProvider.overrideWith(
                      (ref) => Stream.value(DateTime(2026, 7, 30, 9)),
                    ),
                    dashboardAttentionProvider.overrideWith(
                      (ref) async => const [],
                    ),
                    unreadNotificationsProvider.overrideWith((ref) async => 0),
                    clientsProvider.overrideWith((ref) async => const []),
                    appointmentsProvider.overrideWith((ref) async => const []),
                    bookingRequestsProvider.overrideWith(
                      (ref) async => const [],
                    ),
                    appointmentTasksProvider.overrideWith(
                      (ref, appointmentId) async => const [],
                    ),
                    appointmentPaymentsProvider.overrideWith(
                      (ref, appointmentId) async => const [],
                    ),
                    invoicesProvider.overrideWith((ref) async => const []),
                    expensesProvider.overrideWith((ref) async => const []),
                    financeSummaryProvider.overrideWith((ref) async => finance),
                    settingsBusinessProfileProvider.overrideWith(
                      (ref) async => const BusinessProfile(
                        id: 'profile-1',
                        workspaceId: 'workspace-1',
                        handle: 'quality-studio',
                        bookingMode: 'manual',
                      ),
                    ),
                    settingsWorkspaceSettingsProvider.overrideWith(
                      (ref) async => const {
                        'revenue_target': 5000,
                        'working_hours': {
                          'Monday': {
                            'enabled': true,
                            'blocks': [
                              {'start': '09:00', 'end': '17:00'},
                            ],
                          },
                        },
                      },
                    ),
                    settingsServicesProvider.overrideWith(
                      (ref) async => const [
                        {
                          'id': 'service-1',
                          'workspace_id': 'workspace-1',
                          'name': 'Signature consultation',
                          'duration_mins': 60,
                          'price': 85.0,
                          'active': true,
                          'show_on_profile': true,
                        },
                      ],
                    ),
                    allTasksProvider.overrideWith((ref) async => const []),
                    allNotesProvider.overrideWith((ref) async => const []),
                    businessFeedProvider.overrideWith((ref) async => const []),
                    authRepositoryProvider.overrideWithValue(authRepository),
                    servicesRepositoryProvider.overrideWithValue(
                      servicesRepository,
                    ),
                  ],
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: appearance.$2.copyWith(platform: device.platform),
                    home: MediaQuery(
                      data: MediaQueryData(
                        size: device.size,
                        devicePixelRatio: 1,
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true,
                        padding: device.platform == TargetPlatform.iOS
                            ? const EdgeInsets.only(top: 47, bottom: 34)
                            : const EdgeInsets.only(top: 24, bottom: 24),
                      ),
                      child: surface.builder(),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final exception = tester.takeException();
              expect(
                exception,
                isNull,
                reason:
                    '${surface.name} failed in ${appearance.$1} on ${device.name} at ${scale}x text',
              );
            }
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets('client form remains reachable with keyboard and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 568),
            devicePixelRatio: 1,
            textScaler: TextScaler.linear(1.6),
            viewInsets: EdgeInsets.only(bottom: 280),
            disableAnimations: true,
          ),
          child: AddClientScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-run account action is visible without scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 568),
            devicePixelRatio: 1,
            disableAnimations: true,
          ),
          child: AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('auth-first-run-cta'));
    expect(action, findsOneWidget);
    expect(tester.getTopLeft(action).dy, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(568));
    expect(tester.takeException(), isNull);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Create your account.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noOp() {}

class _DeviceCase {
  final String name;
  final Size size;
  final TargetPlatform platform;

  const _DeviceCase(this.name, this.size, this.platform);
}

class _SurfaceCase {
  final String name;
  final Widget Function() builder;

  const _SurfaceCase(this.name, this.builder);
}

class _ResponsiveServicesRepository extends ServicesRepository {
  const _ResponsiveServicesRepository(super.client);

  @override
  Future<List<Map<String, dynamic>>> listRows(String workspaceId) async =>
      const [];
}

const _previewProfile = PublicProfile(
  profile: BusinessProfile(
    id: 'profile-1',
    workspaceId: 'workspace-1',
    handle: 'quality-studio',
    bio:
        'A deliberately long business description that checks wrapping '
        'without hiding the booking request action.',
    bookingMode: 'request',
  ),
  businessName: 'Quality Studio With A Long Trading Name',
  workingHours: {
    'Monday': {
      'enabled': true,
      'blocks': [
        {'start': '09:00', 'end': '17:00'},
      ],
    },
  },
  services: [
    Service(
      id: 'service-1',
      workspaceId: 'workspace-1',
      name: 'Signature consultation with a clear next-step plan',
      durationMins: 60,
      price: 49.99,
    ),
  ],
);

const _appointmentDetailFixture = <String, dynamic>{
  'id': 'appointment-detail-1',
  'workspace_id': 'workspace-1',
  'contact_id': 'client-1',
  'service_id': 'service-1',
  'title': 'Signature consultation',
  'start_time': '2026-07-30T10:00:00.000',
  'end_time': '2026-07-30T11:00:00.000',
  'status': 'scheduled',
  'price': 85.0,
  'contacts': {'name': 'Aisha Morgan'},
  'services': {'name': 'Signature consultation'},
};
