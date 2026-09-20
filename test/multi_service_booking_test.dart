import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workloop/features/public_profile/public_profile_screen.dart';
import 'package:workloop/features/public_profile/public_booking_availability_provider.dart';
import 'package:workloop/shared/models/public_booking_availability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';
import 'package:workloop/shared/widgets/additional_services_picker.dart';

void main() {
  final start = DateTime.utc(2027, 1, 6, 9);
  test(
    'owner bundle sends service identifiers and retains primary compatibility',
    () {
      final payload = buildBookingWorkflowPayload(
        workspaceId: 'workspace',
        idempotencyKey: 'bundle-request-key',
        serviceId: 'first',
        serviceIds: ['first', 'second'],
        addOnIds: ['extra'],
        startTime: start,
        endTime: start.add(const Duration(minutes: 105)),
        price: 90,
        notificationTitle: 'Booking',
        notificationBody: 'Created',
      );
      expect(payload['service_id'], 'first');
      expect(payload['service_ids'], ['first', 'second']);
      expect(payload['add_on_ids'], ['extra']);
      expect(payload.containsKey('service_prices'), isFalse);
    },
  );
  test('owner booking preserves repeated service occurrences', () {
    final payload = buildBookingWorkflowPayload(
      workspaceId: 'workspace',
      idempotencyKey: 'repeated-service-request-key',
      serviceId: 'first',
      serviceIds: ['first', 'first'],
      startTime: start,
      endTime: start.add(const Duration(minutes: 120)),
      price: 100,
      notificationTitle: 'Booking',
      notificationBody: 'Created',
    );
    expect(payload['service_id'], 'first');
    expect(payload['service_ids'], ['first', 'first']);
  });
  test('database selection snapshots repeated services by occurrence', () {
    final migration = File(
      'supabase/migrations/'
      '20260920115353_allow_repeated_services_per_booking.sql',
    ).readAsStringSync();

    expect(migration, contains('v_service_count not between 1 and 8'));
    expect(migration, contains('unnest(p_service_ids) id where id is null'));
    expect(migration, contains('v_distinct_service_count <>'));
    expect(
      migration,
      isNot(contains('v_service_count <> (select count(distinct id)')),
    );
    expect(
      migration,
      contains(
        'from unnest(p_service_ids) with ordinality selected(id, ordinality)',
      ),
    );
    expect(migration, contains('language plpgsql security invoker'));
    expect(migration, contains('to service_role'));
  });
  test('public bundle preserves structured instant and legacy primary', () {
    final payload = buildPublicBookingRequestPayload(
      handle: 'clearview',
      name: 'Customer',
      phone: '07123456789',
      email: 'customer@example.invalid',
      requestToken: 'token',
      serviceId: 'first',
      serviceIds: ['first', 'second'],
      addOnIds: ['extra'],
      requestedFor: start,
      requestedTimezone: 'Europe/London',
    );
    expect(payload['serviceId'], 'first');
    expect(payload['serviceIds'], ['first', 'second']);
    expect(payload['requestedFor'], start.toIso8601String());
    expect(payload.containsKey('price'), isFalse);
  });
  test('legacy single service payload omits the new field', () {
    final payload = buildPublicBookingRequestPayload(
      handle: 'clearview',
      name: 'Customer',
      phone: '07123456789',
      email: 'customer@example.invalid',
      requestToken: 'token',
      serviceId: 'first',
    );
    expect(payload.containsKey('serviceIds'), isFalse);
  });
  test(
    'request snapshots display every service and retain combined totals',
    () {
      final request = BookingRequest.fromMap({
        'id': 'request',
        'workspace_id': 'workspace',
        'service_id': 'first',
        'services': {
          'name': 'Changed catalogue name',
          'duration_mins': 999,
          'price': 999,
        },
        'booking_request_items': [
          {
            'id': 'item-a',
            'item_kind': 'base',
            'source_service_id': 'first',
            'name': 'Clean',
            'duration_mins': 60,
            'price': 50,
            'position': 0,
          },
          {
            'id': 'item-b',
            'item_kind': 'service',
            'source_service_id': 'second',
            'name': 'Polish',
            'duration_mins': 30,
            'price': 30,
            'position': 1,
          },
          {
            'id': 'item-c',
            'item_kind': 'add_on',
            'source_service_id': 'second',
            'name': 'Wax',
            'duration_mins': 15,
            'price': 10,
            'position': 2,
          },
        ],
      });
      expect(request.serviceName, 'Clean + Polish');
      expect(request.serviceDurationMins, 105);
      expect(request.servicePrice, 90);
      expect(request.serviceItems.where((item) => !item.isAddOn).length, 2);
    },
  );
  testWidgets(
    'customer combines existing services and gets aggregate suggestions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PublicBookingAvailabilityQuery? observed;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publicBookingAvailabilityProvider.overrideWith((ref, query) {
              observed = query;
              return PublicBookingAvailability(
                timezone: 'Europe/London',
                durationMinutes: 90,
                generatedAt: DateTime.utc(2026, 9, 4),
                days: const [],
              );
            }),
          ],
          child: const MaterialApp(
            home: PublicProfileScreen(
              handle: 'bundle-studio',
              previewProfile: PublicProfile(
                profile: BusinessProfile(
                  id: 'profile',
                  workspaceId: 'workspace',
                  handle: 'bundle-studio',
                ),
                businessName: 'Bundle Studio',
                workingHours: {},
                services: [
                  Service(
                    id: 'first',
                    workspaceId: 'workspace',
                    name: 'Clean',
                    durationMins: 60,
                    price: 50,
                  ),
                  Service(
                    id: 'second',
                    workspaceId: 'workspace',
                    name: 'Polish',
                    durationMins: 30,
                    price: 30,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clean').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add another service'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Add another service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Polish').last);
      await tester.pumpAndSettle();
      expect(observed?.serviceId, 'first');
      expect(observed?.serviceIdsKey, 'first,second');
      await tester.scrollUntilVisible(
        find.text('Combined total · 1 hour 30 min · £80'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Combined total · 1 hour 30 min · £80'), findsOneWidget);
    },
  );
  testWidgets('service picker adds and removes one repeated occurrence', (
    tester,
  ) async {
    const service = Service(
      id: 'first',
      workspaceId: 'workspace',
      name: 'Clean',
      durationMins: 60,
      price: 50,
    );
    List<String>? changed;

    Future<void> pumpPicker(List<String> selectedIds) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdditionalServicesPicker(
              services: const [service],
              selectedIds: selectedIds,
              onChanged: (ids) => changed = ids,
            ),
          ),
        ),
      );
    }

    await pumpPicker(const ['first']);
    await tester.tap(find.text('Add another service'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clean').last);
    await tester.pumpAndSettle();
    expect(changed, ['first', 'first']);

    await pumpPicker(const ['first', 'first']);
    final duplicateChip = tester.widget<InputChip>(find.byType(InputChip));
    duplicateChip.onDeleted!();
    expect(changed, ['first']);
  });
}
