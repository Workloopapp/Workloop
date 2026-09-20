import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/appointments/widgets/appointment_detail_widgets.dart';

void main() {
  testWidgets('booking client affordance delegates canonical navigation', (
    tester,
  ) async {
    var openCount = 0;
    final priceController = TextEditingController();
    final serviceController = TextEditingController();
    addTearDown(priceController.dispose);
    addTearDown(serviceController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppointmentHeroCard(
            editing: false,
            clientName: 'Ava Mitchell',
            serviceName: 'Gutter clear',
            initials: 'AM',
            contactId: 'client-1',
            onOpenClient: () => openCount += 1,
            clients: const AsyncData([]),
            services: const AsyncData([]),
            priceController: priceController,
            serviceTitleController: serviceController,
            onClientChanged: (_) {},
            onServiceChanged: (_) {},
            onRetryClients: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('View client'));
    await tester.pump();

    expect(openCount, 1);
    expect(find.byType(Navigator), findsOneWidget);
  });

  test(
    'booking detail loads the complete client before opening the editor',
    () {
      final detailSource = File(
        'lib/features/appointments/appointment_detail_screen.dart',
      ).readAsStringSync();
      final heroSource = File(
        'lib/features/appointments/widgets/appointment_detail_widgets.dart',
      ).readAsStringSync();

      expect(detailSource, contains('repository.getById(clientId)'));
      expect(
        detailSource,
        contains('ClientDetailScreen(client: client.toMap())'),
      );
      expect(heroSource, isNot(contains('ClientDetailScreen')));
      expect(heroSource, isNot(contains("'phone': appt")));
    },
  );
}
