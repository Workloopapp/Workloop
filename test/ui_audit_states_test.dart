import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/features/clients/providers/client_detail_providers.dart';
import 'package:workloop/features/clients/widgets/client_appointments_tab.dart';
import 'package:workloop/features/notifications/notifications_screen.dart';
import 'package:workloop/features/settings/widgets/settings_services_section.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/notifications_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _FailingNotificationsRepository extends NotificationsRepository {
  _FailingNotificationsRepository()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<void> markAllRead(String workspaceId) async {
    throw StateError('offline');
  }
}

void main() {
  testWidgets('notification settings failure is explicit and retryable', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPreferencesProvider.overrideWith((ref) async {
            attempts++;
            throw StateError('offline');
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationSettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not load your saved choices. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    final retry = find.descendant(
      of: find.byType(SlateErrorState),
      matching: find.widgetWithText(TextButton, 'Try again'),
    );
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('notification list exposes state without redundant filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsProvider.overrideWith(
            (ref) async => [
              const SlateNotification(
                id: 'notification-1',
                workspaceId: 'workspace-1',
                type: 'booking',
                title: 'New booking',
                body: 'Alex booked a consultation.',
                deepLink: '/bookings/a1111111-1111-4111-8111-111111111111',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final notification = find.bySemanticsLabel(
      'Unread notification. New booking. Alex booked a consultation.',
    );
    expect(notification, findsOneWidget);
    final semantics = tester.getSemantics(notification);
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.hint, 'Marks as read and opens the related item');
    expect(find.text('All'), findsNothing);
    expect(find.text('Unread'), findsNothing);
  });

  testWidgets('notification header is safe at large text and reports failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsProvider.overrideWith(
            (ref) async => [
              const SlateNotification(
                id: 'notification-1',
                workspaceId: 'workspace-1',
                type: 'booking',
                title: 'New booking',
                body: 'Alex booked a consultation.',
              ),
            ],
          ),
          workspaceIdProvider.overrideWith((ref) async => 'workspace-1'),
          notificationsRepositoryProvider.overrideWithValue(
            _FailingNotificationsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: NotificationsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Notifications'), findsOneWidget);
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(
      find.text('Notifications could not be marked as read. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('client booking failure offers a visible retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientAppointmentsProvider.overrideWith((ref, clientId) async {
            attempts++;
            throw StateError('offline');
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ClientAppointmentsTab(clientId: 'client-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bookings could not be loaded.'), findsOneWidget);
    final retry = find.widgetWithText(TextButton, 'Try again');
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('service settings preserve pence and expose full-size actions', (
    tester,
  ) async {
    var additions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsServicesSection(
            services: const AsyncValue.data([
              {
                'id': 'service-1',
                'name': 'Launch consultation',
                'duration_mins': 60,
                'price': 49.99,
              },
            ]),
            onAdd: () => additions++,
            onEdit: (_) {},
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('£49.99'), findsOneWidget);
    final add = find.widgetWithText(TextButton, 'Add');
    expect(add, findsOneWidget);
    expect(tester.getSize(add).height, greaterThanOrEqualTo(44));
    await tester.tap(add);
    expect(additions, 1);
  });

  testWidgets('service settings failure offers a visible retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsServicesSection(
            services: AsyncValue.error(StateError('offline'), StackTrace.empty),
            onAdd: () {},
            onEdit: (_) {},
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('Services could not be loaded.'), findsOneWidget);
    final retry = find.widgetWithText(TextButton, 'Try again');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    expect(retries, 1);
  });
}
