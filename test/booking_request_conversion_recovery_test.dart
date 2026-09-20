import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/widgets/workloop_form_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/public_profile/booking_requests_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';
import 'package:workloop/shared/utils/booking_time.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

SupabaseClient _testClient() {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

class _RetryingConfirmationRepository extends ProfileRepository {
  _RetryingConfirmationRepository() : super(_testClient());

  int attempts = 0;
  final submittedNames = <String?>[];
  final submittedEmails = <String?>[];
  final submittedDurations = <int>[];
  final submittedPrices = <double>[];
  final submittedTitles = <String?>[];
  final reviewedDurations = <int>[];
  final submittedStarts = <DateTime>[];
  final reviewedStarts = <DateTime>[];
  String timezone = 'Europe/London';
  bool failTimezone = false;
  int timezoneReads = 0;

  @override
  Future<String> bookingRequestTimezone(BookingRequest request) async {
    timezoneReads++;
    if (failTimezone) throw StateError('offline');
    return timezone;
  }

  @override
  Future<BookingRequestConfirmationOutcome> confirmBookingRequest({
    required BookingRequest request,
    required DateTime startTime,
    required int durationMins,
    required double price,
    String? clientName,
    String? clientPhone,
    String? clientEmail,
    String? serviceTitle,
    String? location,
    String? extraNotes,
    bool createPaymentDue = false,
    bool enforceWorkingHours = true,
    bool allowOverlap = false,
  }) async {
    attempts += 1;
    submittedNames.add(clientName);
    submittedEmails.add(clientEmail);
    submittedDurations.add(durationMins);
    submittedPrices.add(price);
    submittedTitles.add(serviceTitle);
    submittedStarts.add(startTime);
    if (attempts == 1) throw StateError('offline');
    return const BookingRequestConfirmationOutcome(
      confirmationEmailStatus: BookingRequestConfirmationEmailStatus.sent,
    );
  }

  @override
  Future<AppointmentScheduleReview> reviewBookingRequestSchedule({
    required BookingRequest request,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    reviewedDurations.add(endTime.difference(startTime).inMinutes);
    reviewedStarts.add(startTime);
    return const AppointmentScheduleReview(
      outsideWorkingHoursCount: 0,
      conflictCount: 0,
    );
  }
}

class _HoldingReviewRepository extends _RetryingConfirmationRepository {
  final review = Completer<AppointmentScheduleReview>();
  _HoldingReviewRepository() {
    attempts = 1;
  }
  @override
  Future<AppointmentScheduleReview> reviewBookingRequestSchedule({
    required BookingRequest request,
    required DateTime startTime,
    required DateTime endTime,
  }) => review.future;
}

class _HoldingTimezoneRepository extends _RetryingConfirmationRepository {
  final timezoneResult = Completer<String>();
  @override
  Future<String> bookingRequestTimezone(BookingRequest request) =>
      timezoneResult.future;
}

Finder _confirmationField(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is WorkloopFormField && widget.label == label,
  ),
  matching: find.byType(TextField),
);

void main() {
  const request = BookingRequest(
    id: 'request-1',
    workspaceId: 'workspace-1',
    name: 'Alex Smith',
    phone: '07123 456789',
    email: 'alex@example.com',
    serviceName: 'Window clean',
    serviceDurationMins: 60,
    servicePrice: 45,
    preferredTimeText: '2026-09-11 at 07:41',
  );

  Future<void> openConfirmation(
    WidgetTester tester,
    BookingRequest request,
    _RetryingConfirmationRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: BookingRequestDetailScreen(request: request),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Book'));
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'website text prepopulates screenshot date and saves exact instant on retry',
    (tester) async {
      final repository = _RetryingConfirmationRepository();
      await openConfirmation(tester, request, repository);
      expect(find.text('11/09/2026'), findsOneWidget);
      expect(find.text('07:41'), findsOneWidget);
      expect(find.text('09:00'), findsNothing);
      expect(repository.timezoneReads, 1);
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.ensureVisible(find.text('Create booking'));
        await tester.tap(find.text('Create booking'));
        await tester.pumpAndSettle();
      }
      expect(
        repository.submittedStarts,
        List.filled(2, DateTime.utc(2026, 9, 11, 6, 41)),
      );
      expect(repository.reviewedStarts, repository.submittedStarts);
    },
  );

  testWidgets(
    'legacy form resolves the request workspace zone, not phone London',
    (tester) async {
      final repository = _RetryingConfirmationRepository()
        ..timezone = 'Pacific/Auckland'
        ..attempts = 1;
      await openConfirmation(tester, request, repository);
      expect(find.text('11/09/2026'), findsOneWidget);
      expect(find.text('07:41'), findsOneWidget);
      await tester.ensureVisible(find.text('Create booking'));
      await tester.tap(find.text('Create booking'));
      await tester.pumpAndSettle();
      expect(
        repository.submittedStarts.single,
        DateTime.utc(2026, 9, 10, 19, 41),
      );
    },
  );

  testWidgets(
    'modern repeated-hour instant wins over conflicting text and retains seconds',
    (tester) async {
      final instant = DateTime.utc(2026, 10, 25, 1, 30, 12, 345);
      final modern = BookingRequest.fromMap({
        ...request.toMap(),
        'requested_for': instant.toIso8601String(),
        'requested_timezone': 'Europe/London',
      });
      final repository = _RetryingConfirmationRepository()..attempts = 1;
      await openConfirmation(tester, modern, repository);
      expect(find.text('25/10/2026'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(repository.timezoneReads, 0);
      await tester.ensureVisible(find.text('Create booking'));
      await tester.tap(find.text('Create booking'));
      await tester.pumpAndSettle();
      expect(repository.submittedStarts.single, instant);
    },
  );

  for (final text in [
    null,
    'Friday morning',
    '2026-09-11',
    '2026-03-29 at 01:30',
    '2026-02-30 at 07:41',
  ]) {
    testWidgets('unclear or invalid request $text cannot invent a booking', (
      tester,
    ) async {
      final unclear = BookingRequest.fromMap({
        ...request.toMap(),
        'preferred_time_text': text,
      });
      final repository = _RetryingConfirmationRepository();
      await openConfirmation(tester, unclear, repository);
      expect(find.text('Choose time'), findsOneWidget);
      expect(find.text('09:00'), findsNothing);
      if (text == '2026-09-11') expect(find.text('11/09/2026'), findsOneWidget);
      final create = find.widgetWithText(SlateButton, 'Create booking');
      await tester.ensureVisible(create);
      expect(tester.widget<SlateButton>(create).onPressed, isNull);
      expect(repository.attempts, 0);
    });
  }

  testWidgets(
    'legacy repeated hour requires explicit occurrence before saving',
    (tester) async {
      final repeated = BookingRequest.fromMap({
        ...request.toMap(),
        'preferred_time_text': '2026-10-25 at 01:30',
      });
      final repository = _RetryingConfirmationRepository()..attempts = 1;
      await openConfirmation(tester, repeated, repository);
      expect(
        tester
            .widget<SlateButton>(
              find.widgetWithText(SlateButton, 'Create booking'),
            )
            .onPressed,
        isNull,
      );
      final selector = find.byType(WorkloopPickerField<DateTime>);
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second 01:30 · GMT (UTC+00:00)').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create booking'));
      await tester.tap(find.text('Create booking'));
      await tester.pumpAndSettle();
      expect(
        repository.submittedStarts.single,
        DateTime.utc(2026, 10, 25, 1, 30),
      );
    },
  );

  testWidgets(
    'unknown legacy zone load fails visibly and retries without a draft guess',
    (tester) async {
      final repository = _RetryingConfirmationRepository()..failTimezone = true;
      await openConfirmation(tester, request, repository);
      expect(find.text('Confirm booking'), findsNothing);
      expect(
        find.text(
          'Could not load the business time zone. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(repository.attempts, 0);
      repository.failTimezone = false;
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.text('11/09/2026'), findsOneWidget);
      expect(repository.timezoneReads, 2);
    },
  );

  testWidgets(
    'a freeform preference can be confirmed after explicit date and time choices',
    (tester) async {
      final unclear = BookingRequest.fromMap({
        ...request.toMap(),
        'preferred_time_text': 'Friday morning',
      });
      final repository = _RetryingConfirmationRepository()..attempts = 1;
      await openConfirmation(tester, unclear, repository);
      await tester.ensureVisible(find.text('Choose date'));
      await tester.tap(find.text('Choose date'));
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      final chosenDate = calendar.firstDate.add(const Duration(days: 1));
      calendar.onDateChanged(chosenDate);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use date'));
      await tester.tap(find.text('Use date'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SlateButton>(
              find.widgetWithText(SlateButton, 'Create booking'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Choose time'));
      await tester.tap(find.text('Choose time'));
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(2000, 1, 1, 7, 41));
      await tester.ensureVisible(find.text('Use time'));
      await tester.tap(find.text('Use time'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create booking'));
      await tester.tap(find.text('Create booking'));
      await tester.pumpAndSettle();
      expect(
        bookingWallClockInZone(
          repository.submittedStarts.single,
          'Europe/London',
        ),
        DateTime.utc(chosenDate.year, chosenDate.month, chosenDate.day, 7, 41),
      );
    },
  );

  testWidgets('late timezone lookup never opens a form over another route', (
    tester,
  ) async {
    final repository = _HoldingTimezoneRepository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const BookingRequestDetailScreen(request: request),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book'));
    await tester.pump();
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other screen')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.timezoneResult.complete('Europe/London');
    await tester.pumpAndSettle();
    expect(find.text('Other screen'), findsOneWidget);
    expect(find.text('Confirm booking'), findsNothing);
    expect(repository.attempts, 0);
  });

  testWidgets('failed booking conversion keeps the draft and can retry', (
    tester,
  ) async {
    final repository = _RetryingConfirmationRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const BookingRequestDetailScreen(request: request),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Book'));
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _confirmationField('Client name'),
      'Alex Smith Updated',
    );

    await tester.ensureVisible(find.text('Create booking').last);
    await tester.tap(find.text('Create booking').last);
    await tester.pumpAndSettle();

    expect(repository.attempts, 1);
    expect(
      find.text(
        'The booking was not created. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Alex Smith Updated'), findsOneWidget);

    await tester.ensureVisible(find.text('Create booking').last);
    await tester.tap(find.text('Create booking').last);
    await tester.pumpAndSettle();

    expect(repository.attempts, 2);
    expect(repository.submittedNames, [
      'Alex Smith Updated',
      'Alex Smith Updated',
    ]);
    expect(repository.submittedEmails, [
      'alex@example.com',
      'alex@example.com',
    ]);
    expect(find.text('Confirm booking'), findsNothing);
  });

  testWidgets('legacy request without email remains convertible', (
    tester,
  ) async {
    const legacyRequest = BookingRequest(
      id: 'legacy-request',
      workspaceId: 'workspace-1',
      name: 'Legacy Client',
      phone: '07123 000000',
      preferredTimeText: '2026-09-11 at 07:41',
    );
    final repository = _RetryingConfirmationRepository()..attempts = 1;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: BookingRequestDetailScreen(request: legacyRequest),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create booking').last);
    await tester.tap(find.text('Create booking').last);
    await tester.pumpAndSettle();

    expect(repository.attempts, 2);
    expect(repository.submittedEmails, [null]);
    expect(find.text('Confirm booking'), findsNothing);
  });

  testWidgets('conversion fields stack safely on a small phone at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            _RetryingConfirmationRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
              viewPadding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: BookingRequestDetailScreen(request: request),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Book'));
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Duration mins'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Customer email'), findsOneWidget);
    final emailField = tester.widget<TextField>(
      _confirmationField('Customer email'),
    );
    expect(emailField.readOnly, isTrue);
  });
  for (final minutes in [10, 960, 1440]) {
    testWidgets('bundle confirmation preserves $minutes minute snapshots', (
      tester,
    ) async {
      final bundle = BookingRequest.fromMap({
        'id': 'bundle-request',
        'workspace_id': 'workspace-1',
        'name': 'Alex Smith',
        'phone': '07123 456789',
        'email': 'alex@example.com',
        'preferred_time_text': '2026-09-11 at 07:41',
        'booking_request_items': [
          {
            'id': 'base-item',
            'item_kind': 'base',
            'name': 'Clean',
            'duration_mins': minutes ~/ 2,
            'price': 80,
            'position': 0,
          },
          {
            'id': 'second-item',
            'item_kind': 'service',
            'name': 'Polish',
            'duration_mins': minutes ~/ 2,
            'price': 120,
            'position': 1,
          },
        ],
      });
      final repository = _RetryingConfirmationRepository()..attempts = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: BookingRequestDetailScreen(request: bundle),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Book'));
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      for (final label in ['Service', 'Duration mins', 'Price']) {
        expect(
          tester.widget<TextField>(_confirmationField(label)).readOnly,
          isTrue,
        );
      }
      await tester.ensureVisible(find.text('Create booking').last);
      await tester.tap(find.text('Create booking').last);
      await tester.pumpAndSettle();
      expect(repository.submittedDurations, [minutes]);
      expect(repository.reviewedDurations, [minutes]);
      expect(repository.submittedPrices, [200]);
      expect(repository.submittedTitles, ['Clean + Polish']);
      expect(find.text('Confirm booking'), findsNothing);
    });
  }

  testWidgets(
    'single-service confirmation keeps owner custom details editable',
    (tester) async {
      final repository = _RetryingConfirmationRepository()..attempts = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: BookingRequestDetailScreen(request: request),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      for (final entry in {
        'Service': 'Custom clean',
        'Duration mins': '5',
        'Price': '25',
      }.entries) {
        final field = _confirmationField(entry.key);
        expect(tester.widget<TextField>(field).readOnly, isFalse);
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create booking').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create booking').last);
      await tester.pumpAndSettle();
      expect(repository.submittedDurations, [5]);
      expect(repository.reviewedDurations, [5]);
      expect(repository.submittedPrices, [25]);
      expect(repository.submittedTitles, ['Custom clean']);
    },
  );
  testWidgets(
    'closing a changed conversion protects the draft until discarded',
    (tester) async {
      final repository = _RetryingConfirmationRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BookingRequestDetailScreen(request: request),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _confirmationField('Client name'),
        'Updated client',
      );
      await tester.ensureVisible(find.byTooltip('Close Confirm booking'));
      await tester.tap(find.byTooltip('Close Confirm booking'));
      await tester.pumpAndSettle();
      expect(find.text('Keep this booking draft?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Updated client'), findsOneWidget);
      expect(repository.attempts, 0);
      await tester.tap(find.byTooltip('Close Confirm booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm booking'), findsNothing);
      expect(repository.attempts, 0);
    },
  );

  testWidgets('an in-flight conversion cannot be dismissed or edited', (
    tester,
  ) async {
    final repository = _HoldingReviewRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BookingRequestDetailScreen(request: request),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create booking'));
    await tester.tap(find.text('Create booking'));
    await tester.pumpAndSettle();
    expect(find.text('Creating booking…'), findsOneWidget);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Creating booking…'), findsOneWidget);
    expect(find.text('Keep this booking draft?'), findsNothing);
    await tester.drag(find.byType(SlateSheetFrame).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Creating booking…'), findsOneWidget);
    repository.review.complete(
      const AppointmentScheduleReview(
        outsideWorkingHoursCount: 0,
        conflictCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.attempts, 2);
    expect(repository.submittedNames, ['Alex Smith']);
    expect(find.text('Confirm booking'), findsNothing);
  });

  testWidgets('malformed request timezone shows a recoverable message', (
    tester,
  ) async {
    final malformed = BookingRequest(
      id: 'bad-zone',
      workspaceId: 'workspace-1',
      name: 'Alex Smith',
      phone: '07123 456789',
      requestedFor: DateTime.utc(2026, 9, 7, 10),
      requestedTimezone: 'Not/A_Zone',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: BookingRequestDetailScreen(request: malformed),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Requested time unavailable'), findsOneWidget);
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm booking'), findsNothing);
    expect(
      find.text(
        'This request’s time zone could not be read. Refresh the request before confirming it.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-finite prices and malformed optional emails do not submit', (
    tester,
  ) async {
    final repository = _RetryingConfirmationRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BookingRequestDetailScreen(
            request: BookingRequest(
              id: 'legacy',
              workspaceId: 'workspace-1',
              name: 'Alex',
              phone: '07123 456789',
              servicePrice: 45,
              preferredTimeText: '2026-09-11 at 07:41',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    await tester.enterText(_confirmationField('Price'), 'Infinity');
    await tester.ensureVisible(find.text('Create booking'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SlateButton>(
            find.widgetWithText(SlateButton, 'Create booking'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(_confirmationField('Price'), '45.50');
    await tester.enterText(
      _confirmationField('Customer email'),
      'invalid-email',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SlateButton>(
            find.widgetWithText(SlateButton, 'Create booking'),
          )
          .onPressed,
      isNull,
    );
    expect(repository.attempts, 0);
  });
}
