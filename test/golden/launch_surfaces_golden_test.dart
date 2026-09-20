import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointments_screen.dart';
import 'package:workloop/features/auth/auth_screen.dart';
import 'package:workloop/features/business_feed/business_feed_screen.dart';
import 'package:workloop/features/business/business_screen.dart';
import 'package:workloop/features/clients/add_client_screen.dart';
import 'package:workloop/features/clients/clients_screen.dart';
import 'package:workloop/features/dashboard/dashboard_screen.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/notifications/notifications_screen.dart';
import 'package:workloop/features/onboarding/screens/ob_welcome.dart';
import 'package:workloop/features/profile/profile_screen.dart';
import 'package:workloop/features/profile/booking_page_screen.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/public_profile/public_profile_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/settings/settings_screen.dart';
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
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  setUpAll(_loadDeterministicFonts);

  testWidgets('authentication login surface', (tester) async {
    await _pumpSurface(tester, const AuthScreen());
    await _settleAuthBrandIcon(tester);

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/auth-login.png'),
    );
  });

  testWidgets('authentication registration surface', (tester) async {
    await _pumpSurface(tester, const AuthScreen());
    await _settleAuthBrandIcon(tester);
    final modeToggle = find.byKey(const ValueKey('auth-mode-toggle'));
    await tester.tap(modeToggle);
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/auth-register.png'),
    );
  });

  for (final (appearance, size, safeArea, theme) in [
    (
      'dark',
      const Size(390, 844),
      const EdgeInsets.only(top: 47, bottom: 34),
      AppTheme.dark,
    ),
    (
      'light',
      const Size(430, 932),
      const EdgeInsets.only(top: 59, bottom: 34),
      AppTheme.light,
    ),
  ]) {
    testWidgets('authentication iOS $appearance hierarchy surface', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pumpSurface(
          tester,
          const AuthScreen(),
          theme: theme,
          size: size,
          safeArea: safeArea,
        );
        await _settleAuthBrandIcon(tester);
        expect(find.byKey(const ValueKey('auth-apple')), findsOneWidget);
        expect(find.byKey(const ValueKey('auth-google')), findsOneWidget);
        final boundary = find.byKey(const ValueKey('golden-surface'));
        final filename = 'auth-ios-$appearance-hierarchy.png';
        await expectLater(boundary, matchesGoldenFile('files/$filename'));
      } finally {
        // Reset before Flutter checks debug-variable invariants.
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final (appearance, theme, filename) in [
    ('light', AppTheme.light, 'onboarding-operating-loop-light.png'),
    ('dark', AppTheme.dark, 'onboarding-business-organiser-dark.png'),
  ]) {
    testWidgets('onboarding business organiser $appearance surface', (
      tester,
    ) async {
      await _pumpSurface(
        tester,
        Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Stack(
            children: [
              const Positioned.fill(child: WorkloopTexturedBackdrop()),
              SafeArea(child: ObWelcome(onNext: () {})),
            ],
          ),
        ),
        theme: theme,
      );

      expect(find.text('Your business,\nin good order.'), findsOneWidget);
      expect(find.text('A CLEARER WORKING DAY'), findsOneWidget);
      final start = find.byKey(const ValueKey('onboarding-get-started'));
      expect(start.hitTestable(), findsOneWidget);
      expect(tester.getRect(start).bottom, lessThanOrEqualTo(844 - 34));
      await expectLater(
        find.byKey(const ValueKey('golden-surface')),
        matchesGoldenFile('files/$filename'),
      );
    });
  }

  testWidgets('shell navigation stays quiet in both appearances', (
    tester,
  ) async {
    final screen = Builder(
      builder: (context) => WorkloopAppCanvas(
        child: Scaffold(
          body: const WorkloopTexturedBackdrop(),
          bottomNavigationBar: WorkloopBottomNav(
            currentIndex: 1,
            items: [
              WorkloopNavItem(
                label: 'Today',
                icon: LucideIcons.home,
                color: AppColors.of(context).accentPrimary,
              ),
              WorkloopNavItem(
                label: 'Clients',
                icon: LucideIcons.users,
                color: AppColors.of(context).accentPrimary,
              ),
              WorkloopNavItem(
                label: 'Work',
                icon: LucideIcons.briefcase,
                color: AppColors.of(context).accentPrimary,
              ),
              WorkloopNavItem(
                label: 'Money',
                icon: LucideIcons.circlePoundSterling,
                color: AppColors.of(context).accentPrimary,
              ),
              WorkloopNavItem(
                label: 'Business',
                icon: LucideIcons.store,
                color: AppColors.of(context).accentPrimary,
              ),
            ],
            onTap: (_) {},
          ),
        ),
      ),
    );

    await _pumpSurface(tester, screen, theme: AppTheme.light);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/shell-navigation-light.png'),
    );

    await _pumpSurface(tester, screen, theme: AppTheme.dark);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/shell-navigation-dark.png'),
    );
  });

  testWidgets('populated client list surface', (tester) async {
    final records = [
      ClientCrmRecord(
        client: const Client(
          id: 'client-1',
          workspaceId: 'workspace-1',
          name: 'Maya Patel',
          tags: ['Regular'],
        ),
        bookingCount: 8,
        completedBookingCount: 7,
        nextBooking: Appointment(
          id: 'client-1-next',
          workspaceId: 'workspace-1',
          startTime: DateTime(2026, 8, 18, 10),
        ),
        lastBooking: Appointment(
          id: 'client-1-last',
          workspaceId: 'workspace-1',
          startTime: DateTime(2026, 7, 28, 10),
        ),
        lifetimeValue: 1240,
        outstandingBalance: 0,
        openTaskCount: 0,
        overdueTaskCount: 0,
      ),
      ClientCrmRecord(
        client: const Client(
          id: 'client-2',
          workspaceId: 'workspace-1',
          name: 'Sam Reed',
          tags: ['Follow-up'],
        ),
        bookingCount: 4,
        completedBookingCount: 3,
        nextBooking: Appointment(
          id: 'client-2-next',
          workspaceId: 'workspace-1',
          startTime: DateTime(2026, 8, 20, 14),
        ),
        lastBooking: Appointment(
          id: 'client-2-last',
          workspaceId: 'workspace-1',
          startTime: DateTime(2026, 8, 6, 14),
        ),
        lifetimeValue: 560,
        outstandingBalance: 85,
        openTaskCount: 1,
        overdueTaskCount: 0,
      ),
      ClientCrmRecord(
        client: const Client(
          id: 'client-3',
          workspaceId: 'workspace-1',
          name: 'Jordan Ellis',
          status: 'active',
          tags: ['Regular'],
        ),
        bookingCount: 1,
        completedBookingCount: 0,
        nextBooking: Appointment(
          id: 'client-3-next',
          workspaceId: 'workspace-1',
          startTime: DateTime(2026, 8, 22, 9, 30),
        ),
        lastBooking: null,
        lifetimeValue: 0,
        outstandingBalance: 0,
        openTaskCount: 0,
        overdueTaskCount: 0,
      ),
      const ClientCrmRecord(
        client: Client(
          id: 'client-4',
          workspaceId: 'workspace-1',
          name: 'Alex Morgan',
          status: 'lead',
          tags: ['New enquiry'],
        ),
        bookingCount: 0,
        completedBookingCount: 0,
        nextBooking: null,
        lastBooking: null,
        lifetimeValue: 0,
        outstandingBalance: 0,
        openTaskCount: 1,
        overdueTaskCount: 0,
      ),
      const ClientCrmRecord(
        client: Client(
          id: 'client-5',
          workspaceId: 'workspace-1',
          name: 'Priya Shah',
          status: 'lead',
          tags: ['Consultation'],
        ),
        bookingCount: 0,
        completedBookingCount: 0,
        nextBooking: null,
        lastBooking: null,
        lifetimeValue: 0,
        outstandingBalance: 0,
        openTaskCount: 0,
        overdueTaskCount: 0,
      ),
      const ClientCrmRecord(
        client: Client(
          id: 'client-6',
          workspaceId: 'workspace-1',
          name: 'Taylor Brooks',
          status: 'inactive',
          tags: ['Past client'],
        ),
        bookingCount: 3,
        completedBookingCount: 3,
        nextBooking: null,
        lastBooking: null,
        lifetimeValue: 290,
        outstandingBalance: 0,
        openTaskCount: 0,
        overdueTaskCount: 0,
      ),
    ];
    await _pumpSurface(
      tester,
      _marketingSurface(const ClientsScreen(), currentIndex: 1),
      theme: AppTheme.light,
      overrides: [
        clientCrmRecordsProvider.overrideWith((ref) async => records),
      ],
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/clients-populated.png'),
    );
  });

  testWidgets('notification list light surface', (tester) async {
    final now = DateTime.now();
    await _pumpSurface(
      tester,
      const NotificationsScreen(),
      theme: AppTheme.light,
      overrides: [
        notificationsProvider.overrideWith(
          (ref) async => [
            SlateNotification(
              id: 'notification-1',
              workspaceId: 'workspace-1',
              type: 'booking',
              title: 'New booking request',
              body: 'Maya wants a signature appointment on Friday.',
              deepLink:
                  '/booking-requests/a1111111-1111-4111-8111-111111111111',
              createdAt: now,
            ),
            SlateNotification(
              id: 'notification-2',
              workspaceId: 'workspace-1',
              type: 'payment_received',
              title: 'Payment received',
              body: '£85 was recorded for Samira Khan.',
              deepLink: '/payments/b1111111-1111-4111-8111-111111111111',
              read: true,
              createdAt: now.subtract(const Duration(days: 2)),
            ),
          ],
        ),
      ],
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/notifications-list-light.png'),
    );
  });

  testWidgets('dashboard daily focus surface', (tester) async {
    final now = DateTime(2026, 7, 30, 9);
    final authRepository = AuthRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    final payments = [
      Payment(
        id: 'payment-focus-1',
        workspaceId: 'workspace-1',
        contactId: 'client-1',
        number: 'PAY-101',
        status: 'paid',
        issueDate: now,
        incomeRecordedAt: now,
        total: 185,
        amountPaid: 185,
        clientName: 'Maya Patel',
      ),
      Payment(
        id: 'payment-focus-2',
        workspaceId: 'workspace-1',
        contactId: 'client-2',
        number: 'PAY-102',
        status: 'pending',
        issueDate: now.subtract(const Duration(days: 5)),
        dueDate: now.subtract(const Duration(days: 1)),
        total: 85,
        clientName: 'Sam Reed',
      ),
    ];
    final summary = FinanceSummary.from(
      payments: payments,
      expenses: const [],
      monthlyTarget: 5000,
      now: now,
    );

    final overrides = <Override>[
      authRepositoryProvider.overrideWithValue(authRepository),
      dashboardClockProvider.overrideWith((ref) => Stream.value(now)),
      workspaceProvider.overrideWith(
        (ref) async => const {'id': 'workspace-1'},
      ),
      setupChecklistDismissedProvider.overrideWith((ref) async => true),
      clientsProvider.overrideWith((ref) async => const []),
      appointmentsProvider.overrideWith(
        (ref) async => [
          {
            'id': 'appointment-focus',
            'workspace_id': 'workspace-1',
            'start_time': DateTime(2026, 7, 30, 10).toIso8601String(),
            'end_time': DateTime(2026, 7, 30, 11).toIso8601String(),
            'status': 'scheduled',
            'contacts': {'name': 'Maya Patel'},
            'services': {'name': 'Signature appointment'},
          },
          {
            'id': 'appointment-focus-2',
            'workspace_id': 'workspace-1',
            'start_time': DateTime(2026, 7, 30, 12, 30).toIso8601String(),
            'end_time': DateTime(2026, 7, 30, 13, 15).toIso8601String(),
            'status': 'scheduled',
            'contacts': {'name': 'Sam Reed'},
            'services': {'name': 'Follow-up'},
          },
          {
            'id': 'appointment-focus-3',
            'workspace_id': 'workspace-1',
            'start_time': DateTime(2026, 7, 30, 15).toIso8601String(),
            'end_time': DateTime(2026, 7, 30, 16).toIso8601String(),
            'status': 'scheduled',
            'contacts': {'name': 'Jordan Ellis'},
            'services': {'name': 'First appointment'},
          },
        ],
      ),
      invoicesProvider.overrideWith((ref) async => payments),
      financeSummaryProvider.overrideWith((ref) async => summary),
      dashboardAttentionProvider.overrideWith(
        (ref) async => [
          DashboardAttentionItem(
            type: DashboardAttentionType.bookingRequest,
            title: 'Review Alex’s request',
            detail: 'Window clean · Awaiting decision',
            source: const BookingRequest(
              id: 'request-focus-1',
              workspaceId: 'workspace-1',
              name: 'Alex',
              phone: '07000000000',
              serviceName: 'Window clean',
            ),
            sortTime: now,
          ),
        ],
      ),
      unreadNotificationsProvider.overrideWith((ref) async => 2),
      allTasksProvider.overrideWith(
        (ref) async => [
          SlateTask(
            id: 'task-focus-1',
            workspaceId: 'workspace-1',
            title: 'Confirm tomorrow’s address',
            dueDate: now,
          ),
          SlateTask(
            id: 'task-focus-2',
            workspaceId: 'workspace-1',
            title: 'Send Sam’s receipt',
            dueDate: now,
          ),
          SlateTask(
            id: 'task-focus-3',
            workspaceId: 'workspace-1',
            title: 'Order consultation packs',
            dueDate: now.add(const Duration(days: 1)),
          ),
        ],
      ),
      allNotesProvider.overrideWith(
        (ref) async => [
          SlateNote(
            id: 'note-focus-1',
            workspaceId: 'workspace-1',
            title: 'Maya’s appointment preferences',
            body: 'Prefers a quiet appointment.',
            createdAt: now,
            updatedAt: now,
          ),
          SlateNote(
            id: 'note-focus-2',
            workspaceId: 'workspace-1',
            title: 'August supply list',
            body: 'Consultation packs and aftercare cards.',
            createdAt: now,
            updatedAt: now,
          ),
          SlateNote(
            id: 'note-focus-3',
            workspaceId: 'workspace-1',
            title: 'Jordan’s first appointment',
            body: 'Allow ten minutes for the initial consultation.',
            createdAt: now,
            updatedAt: now,
          ),
          SlateNote(
            id: 'note-focus-4',
            workspaceId: 'workspace-1',
            title: 'Friday follow-ups',
            body: 'Check in with recent clients before the weekend.',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
      businessFeedProvider.overrideWith((ref) async => const []),
    ];
    final screen = DashboardScreen(
      onNavigate: (_) {},
      onOpenMoneyFollowUps: () {},
    );

    await _pumpSurface(
      tester,
      _marketingSurface(screen, currentIndex: 0),
      overrides: overrides,
    );

    expect(find.semantics.byLabel('Open profile'), findsNothing);
    expect(find.semantics.byLabel('Open settings'), findsNothing);
    expect(find.byIcon(LucideIcons.bellRing), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/dashboard-focus.png'),
    );

    await _pumpSurface(
      tester,
      _marketingSurface(screen, currentIndex: 0),
      overrides: overrides,
      theme: AppTheme.light,
    );
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/dashboard-focus-light.png'),
    );
  });

  testWidgets('populated booking schedule surface', (tester) async {
    final current = DateTime.now();
    final now = DateTime(current.year, current.month, current.day, 9);
    final start = DateTime(now.year, now.month, now.day, 10);
    await _pumpSurface(
      tester,
      _marketingSurface(const AppointmentsScreen(), currentIndex: 2),
      theme: AppTheme.light,
      overrides: [
        appointmentsProvider.overrideWith(
          (ref) async => [
            {
              'id': 'appointment-1',
              'workspace_id': 'workspace-1',
              'contact_id': 'client-1',
              'service_id': 'service-1',
              'title': 'Signature consultation',
              'start_time': start.toIso8601String(),
              'end_time': start
                  .add(const Duration(minutes: 75))
                  .toIso8601String(),
              'status': 'scheduled',
              'price': 149.99,
              'contacts': {'name': 'Maya Patel'},
              'services': {'name': 'Signature consultation'},
            },
            {
              'id': 'appointment-2',
              'workspace_id': 'workspace-1',
              'contact_id': 'client-2',
              'service_id': 'service-2',
              'title': 'Follow-up appointment',
              'start_time': start
                  .add(const Duration(hours: 3))
                  .toIso8601String(),
              'end_time': start
                  .add(const Duration(hours: 3, minutes: 45))
                  .toIso8601String(),
              'status': 'scheduled',
              'price': 85.0,
              'contacts': {'name': 'Sam Reed'},
              'services': {'name': 'Follow-up appointment'},
            },
            {
              'id': 'appointment-3',
              'workspace_id': 'workspace-1',
              'contact_id': 'client-3',
              'service_id': 'service-3',
              'title': 'First appointment',
              'start_time': start
                  .add(const Duration(hours: 5))
                  .toIso8601String(),
              'end_time': start.add(const Duration(hours: 6)).toIso8601String(),
              'status': 'scheduled',
              'price': 110.0,
              'contacts': {'name': 'Jordan Ellis'},
              'services': {'name': 'First appointment'},
            },
            {
              'id': 'appointment-4',
              'workspace_id': 'workspace-1',
              'contact_id': 'client-4',
              'service_id': 'service-1',
              'title': 'Signature consultation',
              'start_time': start
                  .add(const Duration(days: 1))
                  .toIso8601String(),
              'end_time': start
                  .add(const Duration(days: 1, minutes: 75))
                  .toIso8601String(),
              'status': 'scheduled',
              'price': 149.99,
              'contacts': {'name': 'Alex Morgan'},
              'services': {'name': 'Signature consultation'},
            },
            {
              'id': 'appointment-5',
              'workspace_id': 'workspace-1',
              'contact_id': 'client-5',
              'service_id': 'service-2',
              'title': 'Follow-up appointment',
              'start_time': start
                  .add(const Duration(days: 1, hours: 4))
                  .toIso8601String(),
              'end_time': start
                  .add(const Duration(days: 1, hours: 4, minutes: 45))
                  .toIso8601String(),
              'status': 'scheduled',
              'price': 85.0,
              'contacts': {'name': 'Priya Shah'},
              'services': {'name': 'Follow-up appointment'},
            },
          ],
        ),
        bookingRequestsProvider.overrideWith(
          (ref) async => const [
            BookingRequest(
              id: 'request-1',
              workspaceId: 'workspace-1',
              name: 'Aisha Morgan',
              phone: '+44 7700 900123',
            ),
            BookingRequest(
              id: 'request-2',
              workspaceId: 'workspace-1',
              name: 'Daniel Hughes',
              phone: '+44 7700 900124',
            ),
            BookingRequest(
              id: 'request-3',
              workspaceId: 'workspace-1',
              name: 'Maya Lewis',
              phone: '+44 7700 900125',
            ),
            BookingRequest(
              id: 'request-4',
              workspaceId: 'workspace-1',
              name: 'Theo Walsh',
              phone: '+44 7700 900126',
            ),
            BookingRequest(
              id: 'request-5',
              workspaceId: 'workspace-1',
              name: 'Yusuf Khan',
              phone: '+44 7700 900127',
            ),
          ],
        ),
      ],
    );

    expect(find.textContaining('£149.99'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('11:15'), findsOneWidget);
    final listRow = tester.widget<WorkloopListRow>(
      find.byKey(const ValueKey('list-booking-row-appointment-1')),
    );
    expect(listRow.flat, isTrue);
    expect(
      listRow.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('list-booking-row-appointment-1')),
          )
          .dy,
      lessThan(320),
    );
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/bookings-populated.png'),
    );

    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/bookings-tomorrow-populated.png'),
    );
  });

  testWidgets('Work workspace schedule surface', (tester) async {
    final now = DateTime.now();
    final noteReferenceDate = DateTime(2026, 8, 15, 9);
    final start = DateTime(now.year, now.month, now.day, 9, 30);
    await _pumpSurface(
      tester,
      _marketingSurface(
        WorkScreen(referenceDate: noteReferenceDate),
        currentIndex: 2,
      ),
      theme: AppTheme.light,
      overrides: [
        appointmentsProvider.overrideWith(
          (ref) async => [
            {
              'id': 'work-appointment-1',
              'workspace_id': 'workspace-1',
              'start_time': start.toIso8601String(),
              'end_time': start
                  .add(const Duration(minutes: 60))
                  .toIso8601String(),
              'status': 'scheduled',
              'price': 95.0,
              'contacts': {'name': 'Maya Patel'},
              'services': {'name': 'Signature appointment'},
            },
            {
              'id': 'work-appointment-2',
              'workspace_id': 'workspace-1',
              'start_time': start
                  .add(const Duration(hours: 3))
                  .toIso8601String(),
              'end_time': start
                  .add(const Duration(hours: 3, minutes: 45))
                  .toIso8601String(),
              'status': 'scheduled',
              'price': 65.0,
              'contacts': {'name': 'Sam Reed'},
              'services': {'name': 'Follow-up appointment'},
            },
            {
              'id': 'work-appointment-3',
              'workspace_id': 'workspace-1',
              'start_time': start
                  .add(const Duration(hours: 5, minutes: 30))
                  .toIso8601String(),
              'end_time': start
                  .add(const Duration(hours: 6, minutes: 30))
                  .toIso8601String(),
              'status': 'scheduled',
              'price': 110.0,
              'contacts': {'name': 'Jordan Ellis'},
              'services': {'name': 'First appointment'},
            },
          ],
        ),
        bookingRequestsProvider.overrideWith((ref) async => const []),
        allTasksProvider.overrideWith(
          (ref) async => [
            SlateTask(
              id: 'work-task-1',
              workspaceId: 'workspace-1',
              title: 'Confirm tomorrow’s address',
              dueDate: now,
            ),
            SlateTask(
              id: 'work-task-2',
              workspaceId: 'workspace-1',
              title: 'Send Sam’s receipt',
              priority: 'medium',
              dueDate: now,
              clientName: 'Sam Reed',
            ),
            SlateTask(
              id: 'work-task-3',
              workspaceId: 'workspace-1',
              title: 'Order consultation packs',
              priority: 'low',
              dueDate: now.add(const Duration(days: 1)),
            ),
          ],
        ),
        allNotesProvider.overrideWith(
          (ref) async => [
            SlateNote(
              id: 'work-note-1',
              workspaceId: 'workspace-1',
              title: 'Maya’s appointment preferences',
              body: 'Prefers a quiet appointment.',
              createdAt: noteReferenceDate,
              updatedAt: noteReferenceDate,
            ),
            SlateNote(
              id: 'work-note-2',
              workspaceId: 'workspace-1',
              title: 'August supply list',
              body: 'Consultation packs and aftercare cards.',
              createdAt: noteReferenceDate,
              updatedAt: noteReferenceDate,
            ),
            SlateNote(
              id: 'work-note-3',
              workspaceId: 'workspace-1',
              title: 'Jordan’s first appointment',
              body: 'Allow ten minutes for the initial consultation.',
              clientName: 'Jordan Ellis',
              createdAt: noteReferenceDate,
              updatedAt: noteReferenceDate,
            ),
          ],
        ),
      ],
    );

    expect(find.text('Work'), findsWidgets);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/work-schedule-light.png'),
    );

    await tester.tap(find.text('Tasks').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/work-tasks-light.png'),
    );

    await tester.tap(find.text('Notes').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/work-notes-light.png'),
    );
  });

  testWidgets('booking calendar light surface', (tester) async {
    final selected = DateTime(2026, 8, 8);
    await _pumpSurface(
      tester,
      AppointmentsScreen(
        key: const ValueKey('booking-calendar-light'),
        initialCalendarDate: selected,
        calendarReferenceDate: selected,
      ),
      theme: AppTheme.light,
      overrides: _bookingCalendarOverrides(),
    );
    await tester.tap(find.bySemanticsLabel('Calendar'));
    await tester.pumpAndSettle();

    expect(find.text('August'), findsOneWidget);
    expect(find.text('Samira Khan'), findsOneWidget);
    final calendarGrid = find.byKey(const ValueKey('2026-8'));
    final agendaDivider = find.byKey(const ValueKey('calendar-agenda-divider'));
    expect(
      tester.getTopLeft(agendaDivider).dy -
          tester.getBottomLeft(calendarGrid).dy,
      lessThanOrEqualTo(1.5),
    );
    final bookingRow = tester.widget<WorkloopListRow>(
      find.byKey(const ValueKey('calendar-booking-row-appointment-1')),
    );
    expect(bookingRow.flat, isTrue);
    expect(
      bookingRow.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('calendar-booking-row-appointment-1')),
          )
          .dy,
      lessThan(710),
    );
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/bookings-calendar-light.png'),
    );
  });

  testWidgets('booking calendar dark surface', (tester) async {
    final selected = DateTime(2026, 8, 8);
    await _pumpSurface(
      tester,
      AppointmentsScreen(
        key: const ValueKey('booking-calendar-dark'),
        initialCalendarDate: selected,
        calendarReferenceDate: selected,
      ),
      overrides: _bookingCalendarOverrides(),
    );
    await tester.tap(find.bySemanticsLabel('Calendar'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/bookings-calendar-dark.png'),
    );
  });

  testWidgets('empty money surface', (tester) async {
    final summary = FinanceSummary.from(
      payments: const [],
      expenses: const [],
      monthlyTarget: 5000,
      now: DateTime(2026, 7, 26),
    );
    await _pumpSurface(
      tester,
      const FinanceScreen(),
      overrides: [
        invoicesProvider.overrideWith((ref) async => const []),
        expensesProvider.overrideWith((ref) async => const []),
        financeSummaryProvider.overrideWith((ref) async => summary),
        workspaceSettingsProvider.overrideWith(
          (ref) async => const {'revenue_target': 5000},
        ),
      ],
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/money-empty.png'),
    );
  });

  testWidgets('populated money surface', (tester) async {
    final now = DateTime(2026, 8, 13, 12);
    final payments = [
      Payment(
        id: 'payment-1',
        workspaceId: 'workspace-1',
        contactId: 'client-1',
        number: 'PAY-001',
        status: 'paid',
        issueDate: now,
        incomeRecordedAt: now,
        total: 185,
        amountPaid: 185,
        clientName: 'Aisha Morgan',
      ),
      Payment(
        id: 'payment-2',
        workspaceId: 'workspace-1',
        contactId: 'client-2',
        number: 'PAY-002',
        status: 'pending',
        issueDate: now,
        dueDate: now.add(const Duration(days: 2)),
        total: 85,
        clientName: 'Omar Rahman',
      ),
      Payment(
        id: 'payment-3',
        workspaceId: 'workspace-1',
        contactId: 'client-3',
        number: 'PAY-003',
        status: 'paid',
        issueDate: now.subtract(const Duration(days: 2)),
        incomeRecordedAt: now.subtract(const Duration(days: 2)),
        total: 95,
        amountPaid: 95,
        clientName: 'Maya Patel',
      ),
      Payment(
        id: 'payment-4',
        workspaceId: 'workspace-1',
        contactId: 'client-4',
        number: 'PAY-004',
        status: 'paid',
        issueDate: now.subtract(const Duration(days: 3)),
        incomeRecordedAt: now.subtract(const Duration(days: 3)),
        total: 140,
        amountPaid: 140,
        clientName: 'Jordan Ellis',
      ),
      Payment(
        id: 'payment-5',
        workspaceId: 'workspace-1',
        contactId: 'client-5',
        number: 'PAY-005',
        status: 'pending',
        issueDate: now.subtract(const Duration(days: 1)),
        dueDate: now.add(const Duration(days: 1)),
        total: 110,
        clientName: 'Priya Shah',
      ),
    ];
    final expenses = [
      Expense(
        id: 'expense-1',
        workspaceId: 'workspace-1',
        amount: 32.5,
        category: 'Supplies',
        expenseDate: now,
        notes: 'Studio supplies',
      ),
      Expense(
        id: 'expense-2',
        workspaceId: 'workspace-1',
        amount: 18,
        category: 'Travel',
        expenseDate: now.subtract(const Duration(days: 1)),
        notes: 'Client travel',
      ),
    ];
    final summary = FinanceSummary.from(
      payments: payments,
      expenses: expenses,
      monthlyTarget: 5000,
      now: now,
    );
    await _pumpSurface(
      tester,
      _marketingSurface(FinanceScreen(referenceDate: now), currentIndex: 3),
      theme: AppTheme.light,
      overrides: [
        invoicesProvider.overrideWith((ref) async => payments),
        expensesProvider.overrideWith((ref) async => expenses),
        financeSummaryProvider.overrideWith((ref) async => summary),
        workspaceSettingsProvider.overrideWith(
          (ref) async => const {'revenue_target': 5000},
        ),
      ],
    );

    expect(find.textContaining('£420'), findsWidgets);
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('money-history-toggle')))
          .dy,
      lessThanOrEqualTo(758),
      reason:
          'The cash figures and payment-history entry fit above the phone navigation.',
    );
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/money-populated-light.png'),
    );
  });

  testWidgets('Business workspace hierarchy surface', (tester) async {
    await _pumpSurface(
      tester,
      _marketingSurface(const BusinessScreen(), currentIndex: 4),
      overrides: [
        workspaceProvider.overrideWith(
          (ref) async => const {'id': 'workspace-1', 'name': 'Workloop Studio'},
        ),
        settingsBusinessProfileProvider.overrideWith((ref) async => null),
        settingsWorkspaceSettingsProvider.overrideWith((ref) async => const {}),
        settingsServicesProvider.overrideWith((ref) async => const []),
        bookingRequestsProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(find.text('Your booking page'), findsOneWidget);
    expect(find.text('Run your business'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Working hours'), findsOneWidget);
    expect(find.text('Business profile'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/more-workspaces.png'),
    );
  });

  testWidgets('Business light appearance surface', (tester) async {
    await _pumpSurface(
      tester,
      _marketingSurface(const BusinessScreen(), currentIndex: 4),
      theme: AppTheme.light,
      overrides: [
        workspaceProvider.overrideWith(
          (ref) async => const {'id': 'workspace-1', 'name': 'Workloop Studio'},
        ),
        settingsBusinessProfileProvider.overrideWith(
          (ref) async => const BusinessProfile(
            id: 'profile-1',
            workspaceId: 'workspace-1',
            handle: 'workloop-studio',
            bio: 'Calm, thoughtful appointments built around every client.',
            bookingMode: 'manual',
          ),
        ),
        settingsWorkspaceSettingsProvider.overrideWith(
          (ref) async => const {
            'working_hours': {
              'monday': {'enabled': true},
              'tuesday': {'enabled': true},
              'wednesday': {'enabled': true},
              'thursday': {'enabled': true},
              'friday': {'enabled': true},
            },
          },
        ),
        settingsServicesProvider.overrideWith(
          (ref) async => const [
            {
              'id': 'service-1',
              'workspace_id': 'workspace-1',
              'name': 'Signature appointment',
              'duration_mins': 60,
              'price': 95.0,
              'active': true,
              'show_on_profile': true,
            },
            {
              'id': 'service-2',
              'workspace_id': 'workspace-1',
              'name': 'Follow-up appointment',
              'duration_mins': 45,
              'price': 65.0,
              'active': true,
              'show_on_profile': true,
            },
          ],
        ),
        bookingRequestsProvider.overrideWith(
          (ref) async => const [
            BookingRequest(
              id: 'business-request-1',
              workspaceId: 'workspace-1',
              name: 'Alex Morgan',
              phone: '+44 7700 900321',
            ),
            BookingRequest(
              id: 'business-request-2',
              workspaceId: 'workspace-1',
              name: 'Priya Shah',
              phone: '+44 7700 900654',
            ),
          ],
        ),
      ],
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/more-workspaces-light.png'),
    );
  });

  testWidgets('empty work surfaces', (tester) async {
    final cases = <String, Widget>{
      'tasks-empty': const TasksScreen(),
      'notes-empty': const NotesScreen(showBackButton: false),
      'feed-empty': const BusinessFeedScreen(),
    };
    for (final entry in cases.entries) {
      await _pumpSurface(
        tester,
        entry.value,
        overrides: [
          allTasksProvider.overrideWith((ref) async => const []),
          allNotesProvider.overrideWith((ref) async => const []),
          businessFeedProvider.overrideWith((ref) async => const []),
        ],
      );

      await expectLater(
        find.byKey(const ValueKey('golden-surface')),
        matchesGoldenFile('files/${entry.key}.png'),
      );
    }
  });

  testWidgets('populated task surface', (tester) async {
    final now = DateTime.now();
    await _pumpSurface(
      tester,
      const TasksScreen(),
      theme: AppTheme.light,
      overrides: [
        allTasksProvider.overrideWith(
          (ref) async => [
            SlateTask(
              id: 'task-1',
              workspaceId: 'workspace-1',
              title: 'Confirm Friday appointment details',
              priority: 'high',
              dueDate: now,
              contactId: 'client-1',
              clientName: 'Aisha Morgan',
            ),
            SlateTask(
              id: 'task-2',
              workspaceId: 'workspace-1',
              title: 'Send payment reminder',
              priority: 'medium',
              dueDate: now.add(const Duration(days: 1)),
              contactId: 'client-2',
              clientName: 'Omar Rahman',
            ),
          ],
        ),
      ],
    );

    expect(find.text('Confirm Friday appointment details'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/tasks-populated-light.png'),
    );
  });

  testWidgets('populated notes surface', (tester) async {
    final now = DateTime(2026, 8, 10, 12);
    await _pumpSurface(
      tester,
      NotesScreen(showBackButton: false, referenceDate: now),
      theme: AppTheme.light,
      overrides: [
        allNotesProvider.overrideWith(
          (ref) async => [
            SlateNote(
              id: 'note-1',
              workspaceId: 'workspace-1',
              title: 'Aisha appointment preferences',
              body: 'Prefers Friday afternoons and a quiet appointment.',
              contactId: 'client-1',
              clientName: 'Aisha Morgan',
              pinned: true,
              createdAt: now,
              updatedAt: now,
            ),
            SlateNote(
              id: 'note-2',
              workspaceId: 'workspace-1',
              title: 'August supply order',
              body: 'Order fresh consultation packs before Monday.',
              createdAt: now.subtract(const Duration(days: 1)),
              updatedAt: now.subtract(const Duration(days: 1)),
            ),
          ],
        ),
      ],
    );

    expect(find.text('Aisha appointment preferences'), findsOneWidget);
    final noteRows = tester.widgetList<WorkloopListRow>(
      find.byType(WorkloopListRow),
    );
    expect(noteRows, hasLength(2));
    expect(noteRows.every((row) => row.flat), isTrue);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/notes-populated-light.png'),
    );
  });

  testWidgets('booking request inbox empty surface', (tester) async {
    await _pumpSurface(
      tester,
      const BookingRequestsScreen(),
      overrides: [
        bookingRequestsProvider.overrideWith((ref) async => const []),
      ],
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/booking-requests-empty.png'),
    );
  });

  testWidgets('booking request inbox populated surface', (tester) async {
    await _pumpSurface(
      tester,
      const BookingRequestsScreen(),
      theme: AppTheme.light,
      overrides: [
        bookingRequestsProvider.overrideWith(
          (ref) async => [
            BookingRequest(
              id: 'request-1',
              workspaceId: 'workspace-1',
              name: 'Aisha Morgan',
              phone: '+44 7700 900123',
              serviceId: 'service-1',
              serviceName: 'Signature consultation',
              serviceDurationMins: 60,
              servicePrice: 85,
              preferredTimeText: 'Friday afternoon',
              message: 'I am flexible after 2pm.',
              createdAt: DateTime(2026, 8, 8, 10),
            ),
            BookingRequest(
              id: 'request-2',
              workspaceId: 'workspace-1',
              name: 'Omar Rahman',
              phone: '+44 7700 900456',
              serviceId: 'service-2',
              serviceName: 'Follow-up appointment',
              serviceDurationMins: 45,
              servicePrice: 65,
              preferredTimeText: 'Next Tuesday morning',
              status: 'contacted',
              createdAt: DateTime(2026, 8, 7, 16),
            ),
          ],
        ),
      ],
    );

    expect(find.text('Aisha Morgan'), findsOneWidget);
    expect(find.text('Omar Rahman'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/booking-requests-populated-light.png'),
    );
  });

  testWidgets('booking request detail surface', (tester) async {
    await _pumpSurface(
      tester,
      BookingRequestDetailScreen(
        request: BookingRequest(
          id: 'request-1',
          workspaceId: 'workspace-1',
          name: 'Aisha Morgan',
          phone: '+44 7700 900123',
          serviceId: 'service-1',
          serviceName: 'Signature consultation',
          serviceDurationMins: 60,
          servicePrice: 85,
          preferredTimeText: 'Friday afternoon',
          message:
              'I am flexible after 2pm and would prefer a quiet appointment.',
          createdAt: DateTime(2026, 8, 8, 10),
        ),
      ),
      theme: AppTheme.light,
    );

    expect(find.text('Mark contacted'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/booking-request-detail-light.png'),
    );
  });

  testWidgets('business profile overview surface', (tester) async {
    final authRepository = AuthRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    const profile = BusinessProfile(
      id: 'profile-1',
      workspaceId: 'workspace-1',
      handle: 'quality-studio',
      bio: 'Calm, expert help for your next project.',
      bookingMode: 'manual',
    );
    await _pumpSurface(
      tester,
      const ProfileScreen(),
      theme: AppTheme.light,
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        workspaceProvider.overrideWith(
          (ref) async => const {
            'id': 'workspace-1',
            'name': 'Quality Studio',
            'industry': 'Business consulting',
          },
        ),
        settingsBusinessProfileProvider.overrideWith((ref) async => profile),
        settingsWorkspaceSettingsProvider.overrideWith(
          (ref) async => const {
            'working_hours': {
              'monday': {'enabled': true},
              'tuesday': {'enabled': true},
              'wednesday': {'enabled': true},
              'thursday': {'enabled': true},
              'friday': {'enabled': true},
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
        bookingRequestsProvider.overrideWith(
          (ref) async => const [
            BookingRequest(
              id: 'request-1',
              workspaceId: 'workspace-1',
              name: 'Aisha Morgan',
              phone: '+44 7700 900123',
            ),
          ],
        ),
      ],
    );

    expect(find.text('Quality Studio'), findsOneWidget);
    expect(find.text('Business details'), findsOneWidget);
    expect(find.text('1 service available'), findsOneWidget);
    expect(find.text('5 working days'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/profile-overview-light.png'),
    );
  });

  testWidgets('booking page owner hub surface', (tester) async {
    await _pumpSurface(
      tester,
      const BookingPageScreen(),
      theme: AppTheme.light,
      overrides: [
        workspaceProvider.overrideWith(
          (ref) async => const {
            'id': 'workspace-1',
            'name': 'Quality Studio',
            'industry': 'Business consulting',
          },
        ),
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
            'working_hours': {
              'monday': {'enabled': true, 'open': '09:00', 'close': '17:00'},
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
        bookingRequestsProvider.overrideWith(
          (ref) async => const [
            BookingRequest(
              id: 'request-1',
              workspaceId: 'workspace-1',
              name: 'Aisha Morgan',
              phone: '+44 7700 900123',
            ),
          ],
        ),
      ],
    );

    expect(find.text('Accepting requests'), findsOneWidget);
    expect(find.text('workloop.uk/quality-studio'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/booking-page-owner-hub-light.png'),
    );
  });

  testWidgets('settings appearance surface', (tester) async {
    final authRepository = AuthRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    await _pumpSurface(
      tester,
      const SettingsScreen(),
      overrides: [authRepositoryProvider.overrideWithValue(authRepository)],
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/settings-dark-only.png'),
    );
  });

  testWidgets('settings light appearance surface', (tester) async {
    final authRepository = AuthRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    await _pumpSurface(
      tester,
      const SettingsScreen(),
      theme: AppTheme.light,
      overrides: [authRepositoryProvider.overrideWithValue(authRepository)],
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/settings-light.png'),
    );
  });

  testWidgets('new client form surface', (tester) async {
    await _pumpSurface(tester, const AddClientScreen());

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/client-form.png'),
    );
  });

  testWidgets('public booking profile surface', (tester) async {
    const preview = PublicProfile(
      profile: BusinessProfile(
        id: 'profile-1',
        workspaceId: 'workspace-1',
        handle: 'quality-studio',
        bio: 'Calm, expert help for your next project.',
        bookingMode: 'manual',
      ),
      businessName: 'Quality Studio',
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
          name: 'Signature consultation',
          durationMins: 60,
          price: 49.99,
          description: 'A focused session with a clear next-step plan.',
        ),
      ],
    );
    await _pumpSurface(
      tester,
      const PublicProfileScreen(
        handle: 'quality-studio',
        previewProfile: preview,
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('golden-surface')),
      matchesGoldenFile('files/public-booking-profile.png'),
    );
  });
}

Future<void> _settleAuthBrandIcon(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // The native vector illustration paints synchronously; no raster decode wait.
  expect(find.byKey(const ValueKey('auth-brand-icon')), findsOneWidget);
}

List<Override> _bookingCalendarOverrides() {
  final firstStart = DateTime(2026, 8, 8, 10);
  final secondStart = DateTime(2026, 8, 11, 14, 30);
  return [
    appointmentsProvider.overrideWith(
      (ref) async => [
        {
          'id': 'appointment-1',
          'workspace_id': 'workspace-1',
          'title': 'Signature consultation',
          'start_time': firstStart.toIso8601String(),
          'end_time': firstStart
              .add(const Duration(minutes: 75))
              .toIso8601String(),
          'status': 'scheduled',
          'price': 149.99,
          'contacts': {'name': 'Samira Khan'},
          'services': {'name': 'Signature consultation'},
        },
        {
          'id': 'appointment-2',
          'workspace_id': 'workspace-1',
          'title': 'Follow-up session',
          'start_time': secondStart.toIso8601String(),
          'end_time': secondStart
              .add(const Duration(minutes: 60))
              .toIso8601String(),
          'status': 'scheduled',
          'price': 80,
          'contacts': {'name': 'Maya Johnson'},
          'services': {'name': 'Follow-up session'},
        },
      ],
    ),
    bookingRequestsProvider.overrideWith((ref) async => const []),
  ];
}

Future<void> _pumpSurface(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  ThemeData? theme,
  Size size = const Size(390, 844),
  EdgeInsets safeArea = const EdgeInsets.only(top: 47, bottom: 34),
}) async {
  final resolvedTheme = theme ?? AppTheme.dark;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: resolvedTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 1,
            padding: safeArea,
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const ValueKey('golden-surface'),
            child: screen,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Widget _marketingSurface(Widget screen, {required int currentIndex}) {
  return Builder(
    builder: (context) => Scaffold(
      backgroundColor: AppColors.of(context).bg,
      body: screen,
      bottomNavigationBar: WorkloopBottomNav(
        currentIndex: currentIndex,
        items: [
          WorkloopNavItem(
            label: 'Today',
            icon: LucideIcons.home,
            color: AppColors.of(context).accentPrimary,
          ),
          WorkloopNavItem(
            label: 'Clients',
            icon: LucideIcons.users,
            color: AppColors.of(context).accentPrimary,
          ),
          WorkloopNavItem(
            label: 'Work',
            icon: LucideIcons.briefcase,
            color: AppColors.of(context).accentPrimary,
          ),
          WorkloopNavItem(
            label: 'Money',
            icon: LucideIcons.circlePoundSterling,
            color: AppColors.of(context).accentPrimary,
          ),
          WorkloopNavItem(
            label: 'Business',
            icon: LucideIcons.store,
            color: AppColors.of(context).accentPrimary,
          ),
        ],
        onTap: (_) {},
      ),
    ),
  );
}

Future<void> _loadDeterministicFonts() async {
  final manrope = FontLoader('Manrope')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  // Flutter's test binding uses the block-glyph Ahem font for any style that
  // relies on a platform fallback. Map that fallback to Workloop's bundled
  // typeface so golden images represent the shipped UI rather than test boxes.
  final mono = FontLoader('WorkloopMono')
    ..addFont(rootBundle.load('assets/fonts/WorkloopMono-Regular.ttf'));
  final platformFallback = FontLoader('Ahem')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  // The Apple button names this iOS system family explicitly. The headless
  // test engine has no system font, so use a bundled test-only fallback.
  final appleSystemFallback = FontLoader('.SF Pro Text')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  final lucide = FontLoader('packages/lucide_flutter/LucideIcons')
    ..addFont(rootBundle.load('packages/lucide_flutter/assets/lucide.ttf'));
  await Future.wait([
    manrope.load(),
    mono.load(),
    platformFallback.load(),
    appleSystemFallback.load(),
    lucide.load(),
  ]);
}
