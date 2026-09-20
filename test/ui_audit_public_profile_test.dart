import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/features/public_profile/public_profile_screen.dart';
import 'package:workloop/features/public_profile/public_booking_availability_provider.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';
import 'package:workloop/shared/models/public_booking_availability.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';

Finder _requestField(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is WorkloopFormField && widget.label == label,
  ),
  matching: find.byType(TextField),
);

const _profile = PublicProfile(
  profile: BusinessProfile(
    id: 'profile-1',
    workspaceId: 'workspace-1',
    handle: 'bright-studio',
  ),
  businessName: 'Bright Studio',
  workingHours: {
    'Sun': {'enabled': false},
    'Tue': {'enabled': true, 'open': '10:00', 'close': '18:00'},
    'Mon': {'enabled': true, 'open': '09:00', 'close': '17:00'},
  },
  services: [
    Service(
      id: 'service-1',
      workspaceId: 'workspace-1',
      name: 'Launch consultation',
      durationMins: 60,
      price: 49.99,
      addOns: [
        ServiceAddOn(
          id: 'add-on-1',
          workspaceId: 'workspace-1',
          serviceId: 'service-1',
          name: 'Written follow-up',
          durationMins: 15,
          price: 12,
        ),
      ],
    ),
  ],
);

class _SuccessfulRequestRepository extends ProfileRepository {
  _SuccessfulRequestRepository()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<void> createBookingRequest({
    required String handle,
    required String name,
    required String phone,
    required String email,
    required String requestToken,
    String? serviceId,
    List<String> addOnIds = const [],
    List<String> serviceIds = const [],
    DateTime? requestedFor,
    String? requestedTimezone,
    String? preferredTimeText,
    String? message,
  }) async {}
}

void main() {
  testWidgets(
    'public profile keeps exact prices and shows only published opening days',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PublicProfileScreen(
              handle: 'bright-studio',
              previewProfile: _profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('£49.99'), findsOneWidget);
      expect(find.text('£50'), findsNothing);

      expect(find.text('Wednesday'), findsNothing);
      expect(find.text('Closed on other days'), findsOneWidget);
      final dayPositions = [
        for (final day in const ['Monday', 'Tuesday'])
          tester.getTopLeft(find.text(day)).dy,
      ];
      expect(dayPositions, orderedEquals([...dayPositions]..sort()));
    },
  );

  testWidgets(
    'public service rows select the booking service without manual entry',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publicBookingAvailabilityProvider.overrideWith(
              (ref, query) async => PublicBookingAvailability(
                timezone: 'Europe/London',
                durationMinutes: 60,
                generatedAt: DateTime.utc(2026),
                days: const [],
              ),
            ),
          ],
          child: const MaterialApp(
            home: PublicProfileScreen(
              handle: 'bright-studio',
              previewProfile: _profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final service = find.text('Launch consultation').first;
      expect(service, findsOneWidget);
      await tester.tap(service);
      await tester.pumpAndSettle();

      expect(find.text('Launch consultation · 1 hour'), findsOneWidget);

      semantics.dispose();
    },
  );

  testWidgets('suggested times require a service and remain requests', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicBookingAvailabilityProvider.overrideWith(
            (ref, query) async => PublicBookingAvailability(
              timezone: 'Europe/London',
              durationMinutes: 60,
              generatedAt: DateTime.utc(2026, 9, 1, 12),
              days: [
                PublicBookingAvailabilityDay(
                  date: DateTime(2026, 9, 2),
                  slotsUtc: [DateTime.utc(2026, 9, 2, 9)],
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: PublicProfileScreen(
            handle: 'bright-studio',
            previewProfile: _profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Suggested times'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Choose a service to see suggested times.'),
      findsOneWidget,
    );
    expect(find.text('Request another time'), findsOneWidget);

    await tester.tap(find.text('Launch consultation').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Suggested times'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Looks open right now'), findsOneWidget);
    expect(find.textContaining('not held or confirmed'), findsOneWidget);
    final time = find.bySemanticsLabel(RegExp(r'^Suggested time '));
    expect(time, findsOneWidget);
    await tester.ensureVisible(time);
    await tester.pumpAndSettle();
    await tester.tap(time);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Preferred date and time'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Wed, Sep 2 at 10:00 AM'), findsOneWidget);
  });

  testWidgets('availability failure preserves the manual request flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicBookingAvailabilityProvider.overrideWith(
            (ref, query) => Future<PublicBookingAvailability>.error(
              const FunctionException(
                status: 404,
                details: 'Function not found',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: PublicProfileScreen(
            handle: 'bright-studio',
            previewProfile: _profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch consultation').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Suggested times are unavailable'),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.textContaining('Suggested times are unavailable'),
      findsOneWidget,
    );
    expect(find.text('Request another time'), findsOneWidget);
    expect(find.text('Choose a date and time'), findsOneWidget);
    expect(find.text('Send request'), findsOneWidget);
  });

  testWidgets('public extras show a clear aggregate duration and price', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicBookingAvailabilityProvider.overrideWith(
            (ref, query) async => PublicBookingAvailability(
              timezone: 'Europe/London',
              durationMinutes: 75,
              generatedAt: DateTime.utc(2026),
              days: const [],
            ),
          ),
        ],
        child: const MaterialApp(
          home: PublicProfileScreen(
            handle: 'bright-studio',
            previewProfile: _profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch consultation').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Optional extras · Launch consultation'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Total · 1 hour · £49.99'), findsOneWidget);
    await tester.ensureVisible(find.text('Written follow-up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Written follow-up'));
    await tester.pump();
    expect(find.text('Total · 1 hour 15 min · £61.99'), findsOneWidget);
  });

  testWidgets('public request form uses persistent labels and inline errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PublicProfileScreen(
            handle: 'bright-studio',
            previewProfile: _profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Send request'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    final name = _requestField('Name');
    final phone = _requestField('Phone');
    final email = _requestField('Email');
    expect(name, findsOneWidget);
    expect(phone, findsOneWidget);
    expect(email, findsOneWidget);
    expect(find.textContaining('Published hours are a guide'), findsOneWidget);

    await tester.tap(find.text('Send request'));
    await tester.pump();

    expect(find.text('Add your name'), findsOneWidget);
    expect(find.text('Add a phone number'), findsOneWidget);
    expect(find.text('Add your email address'), findsOneWidget);
    expect(
      find.text('Choose the date and time you would prefer'),
      findsOneWidget,
    );
  });

  testWidgets('public request requires a valid customer email', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PublicProfileScreen(
            handle: 'bright-studio',
            previewProfile: _profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Send request'),
      260,
      scrollable: find.byType(Scrollable).first,
    );

    final email = _requestField('Email');
    await tester.enterText(email, 'not-an-email');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(find.text('Send request'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send request'));
    await tester.pump();

    expect(find.text('Add a valid email address'), findsOneWidget);
  });

  testWidgets('request receipt remains pending and explains email purpose', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            _SuccessfulRequestRepository(),
          ),
        ],
        child: const MaterialApp(
          home: PublicProfileScreen(
            handle: 'bright-studio',
            previewProfile: _profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Your email is also used to send a confirmation if they accept',
      ),
      findsOneWidget,
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Send request'),
      260,
      scrollable: scrollable,
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Alex Smith');
    await tester.enterText(fields.at(1), '07123 456789');
    await tester.enterText(fields.at(2), 'alex@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(find.text('Choose a date and time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a date and time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use time'));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.ensureVisible(find.text('Send request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsOneWidget);
    expect(find.textContaining('Nothing is booked yet'), findsOneWidget);
    expect(
      find.textContaining('confirmation will be emailed to alex@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('empty service copy describes the current state honestly', (
    tester,
  ) async {
    const emptyProfile = PublicProfile(
      profile: BusinessProfile(
        id: 'profile-2',
        workspaceId: 'workspace-1',
        handle: 'empty-studio',
      ),
      businessName: 'Empty Studio',
      workingHours: {},
      services: [],
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PublicProfileScreen(
            handle: 'empty-studio',
            previewProfile: emptyProfile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No services are currently listed.'), findsOneWidget);
    expect(find.text('Services will appear here soon.'), findsNothing);
  });

  testWidgets('booking request Call action is labelled and 44 points tall', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const request = BookingRequest(
      id: 'request-1',
      workspaceId: 'workspace-1',
      name: 'Alex Smith',
      phone: '07123 456789',
      email: 'alex@example.com',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookingRequestsProvider.overrideWith((ref) async => const [request]),
        ],
        child: const MaterialApp(home: BookingRequestsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alex Smith'));
    await tester.pumpAndSettle();

    final call = find.bySemanticsLabel('Call Alex Smith');
    expect(call, findsOneWidget);
    expect(tester.getSize(call).height, greaterThanOrEqualTo(44));
    final email = find.bySemanticsLabel('Email Alex Smith');
    expect(email, findsOneWidget);
    expect(tester.getSize(email).height, greaterThanOrEqualTo(44));

    semantics.dispose();
  });

  testWidgets('legacy malformed email is shown without a mail action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const request = BookingRequest(
      id: 'request-legacy',
      workspaceId: 'workspace-1',
      name: 'Legacy Client',
      phone: '07123 000000',
      email: 'not-an-email',
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: BookingRequestDetailScreen(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Email Legacy Client'), findsNothing);
    semantics.dispose();
  });

  testWidgets('owner sees the requested wall clock in the workspace timezone', (
    tester,
  ) async {
    final request = BookingRequest(
      id: 'request-time',
      workspaceId: 'workspace-1',
      name: 'Summer Client',
      phone: '07123 000001',
      requestedFor: DateTime.utc(2026, 7, 15, 9, 30),
      requestedTimezone: 'Europe/London',
    );

    await tester.pumpWidget(
      MaterialApp(home: BookingRequestDetailScreen(request: request)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('10:30'), findsOneWidget);
    expect(find.textContaining('9:30'), findsNothing);
  });
}
