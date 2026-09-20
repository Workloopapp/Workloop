import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/repositories/onboarding_repository.dart';

void main() {
  test('onboarding draft round-trips setup data and progress', () {
    const draft = OnboardingState(
      firstName: 'Ash',
      businessName: 'Ash Services',
      industry: 'Cleaning & Home Services',
      handle: 'ash-services',
      services: [
        {
          'name': 'Standard clean',
          'description': 'Kitchen and bathrooms.\nFloors throughout.',
          'duration': 90,
          'price': 55.0,
        },
      ],
      workingHours: {
        'Mon': {'enabled': true, 'open': '09:00', 'close': '17:00'},
      },
      revenueTarget: 3000,
      firstBooking: {
        'clientName': 'Maya Lewis',
        'serviceName': 'Standard clean',
        'date': '2026-07-20',
        'hour': 9,
        'minute': 30,
      },
      importAfterSetup: true,
      notificationPreferences: {
        'all_notifications': true,
        'new_booking': false,
        'payment_received': true,
      },
      currentStep: 6,
    );

    final restored = OnboardingState.fromJson(draft.toJson());

    expect(restored.firstName, draft.firstName);
    expect(restored.services, draft.services);
    expect(restored.workingHours, draft.workingHours);
    expect(restored.firstBooking, draft.firstBooking);
    expect(restored.importAfterSetup, isTrue);
    expect(restored.notificationPreferences, draft.notificationPreferences);
    expect(restored.currentStep, 6);
    final payload = buildOnboardingRpcParams(
      businessName: restored.businessName,
      industry: restored.industry,
      handle: restored.handle,
      services: restored.services,
      workingHours: restored.workingHours,
      revenueTarget: restored.revenueTarget,
    );
    expect((payload['service_rows'] as List).single, {
      'name': 'Standard clean',
      'description': 'Kitchen and bathrooms.\nFloors throughout.',
      'duration_mins': 90,
      'price': 55.0,
    });
  });

  test(
    'service RPC descriptions are optional and preserve interior newlines',
    () {
      const draft = OnboardingState(
        services: [
          {'name': 'Legacy service', 'duration': 30, 'price': 0},
          {'name': 'Null description', 'description': null},
          {'name': 'Blank description', 'description': ' \n\t '},
          {
            'name': 'Described service',
            'description': '  First line.\n\nSecond line.  ',
            'duration': 45,
            'price': 25.5,
          },
        ],
      );
      final restored = OnboardingState.fromJson(draft.toJson());
      final payload = buildOnboardingRpcParams(
        businessName: 'Owner Services',
        industry: 'Other',
        handle: 'owner-services',
        services: restored.services,
        workingHours: {},
        revenueTarget: 0,
      );
      final rows = (payload['service_rows'] as List)
          .cast<Map<String, dynamic>>();
      expect(rows.map((row) => row['description']), [
        null,
        null,
        null,
        'First line.\n\nSecond line.',
      ]);
      expect(rows.first['duration_mins'], 30);
      expect(rows.first['price'], 0);
      expect(rows.last['duration_mins'], 45);
      expect(rows.last['price'], 25.5);
      expect(restored.services, draft.services);
    },
  );
}
