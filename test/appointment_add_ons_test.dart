import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/appointments/add_appointment_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';

void main() {
  const addOns = [
    ServiceAddOn(
      id: 'inside',
      workspaceId: 'workspace-1',
      serviceId: 'service-1',
      name: 'Inside windows',
      durationMins: 30,
      price: 15,
    ),
    ServiceAddOn(
      id: 'frames',
      workspaceId: 'workspace-1',
      serviceId: 'service-1',
      name: 'Frames',
      durationMins: 15,
      price: 8.50,
    ),
  ];

  test('owner booking totals include only selected service add-ons', () {
    final composition = appointmentComposition(
      baseDurationMins: 60,
      basePrice: 40,
      addOns: addOns,
      selectedAddOnIds: const {'inside'},
    );

    expect(composition.durationMins, 90);
    expect(composition.price, 55);
  });

  test('owner booking base service is unchanged without add-ons', () {
    final composition = appointmentComposition(
      baseDurationMins: 60,
      basePrice: 40,
      addOns: addOns,
      selectedAddOnIds: const {},
    );

    expect(composition.durationMins, 60);
    expect(composition.price, 40);
  });
}
