import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/features/appointments/booking_invoice_handoff.dart';
import 'package:workloop/features/finance/documents/business_document_detail_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';

final _booking = Appointment(
  id: 'booking',
  workspaceId: 'workspace',
  contactId: 'client',
  clientName: 'Sam Morgan',
  title: 'Window clean',
  startTime: DateTime.utc(2027, 3, 21, 9),
  endTime: DateTime.utc(2027, 3, 21, 10),
  price: 100,
);
Payment _payment({
  String status = 'sent',
  double paid = 0,
  double total = 100,
  String contact = 'client',
  String? document,
  double stripePaid = 0,
  double deposit = 0,
}) => Payment(
  id: 'payment',
  workspaceId: 'workspace',
  appointmentId: 'booking',
  contactId: contact,
  number: 'PAY-1',
  status: status,
  issueDate: DateTime(2027, 3, 1),
  total: total,
  amountPaid: paid,
  stripeAmountPaid: stripePaid,
  sourceDocumentId: document,
  depositAmount: deposit,
);

void main() {
  test(
    'invoice handoff adopts only one untouched matching booking payment',
    () {
      expect(canCreateBookingInvoice(_booking, []), isTrue);
      expect(canCreateBookingInvoice(_booking, [_payment()]), isTrue);
      expect(
        canCreateBookingInvoice(_booking, [_payment(status: 'overdue')]),
        isTrue,
      );
      expect(
        canCreateBookingInvoice(_booking, [_payment(status: 'cancelled')]),
        isTrue,
      );
      for (final payment in [
        _payment(paid: 25),
        _payment(stripePaid: 25),
        _payment(total: 90),
        _payment(contact: 'different'),
        _payment(document: 'document'),
        _payment(status: 'paid'),
      ]) {
        expect(canCreateBookingInvoice(_booking, [payment]), isFalse);
      }
      expect(
        canCreateBookingInvoice(_booking, [_payment(), _payment()]),
        isFalse,
      );
    },
  );

  for (final paid in [0.0, 30.0]) {
    testWidgets(
      'booking shows ${paid == 0 ? 'due' : 'received'} deposit and opens its one invoice',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workspaceIdProvider.overrideWith((_) async => 'workspace'),
              workspaceSettingsProvider.overrideWith(
                (_) async => {'timezone': 'Europe/London'},
              ),
              clientsProvider.overrideWith((_) async => []),
              appointmentsProvider.overrideWith((_) async => []),
              allTasksProvider.overrideWith((_) async => []),
              servicesProvider.overrideWith((_) async => []),
              invoicesProvider.overrideWith(
                (_) async => [
                  _payment(document: 'document', deposit: 30, paid: paid),
                ],
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: AppointmentDetailScreen(appointment: _booking.toMap()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Money'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Money'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Open invoice'),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(paid == 0 ? '£30 deposit due' : '£30 deposit received'),
          findsOneWidget,
        );
        expect(
          find.text(paid == 0 ? '£100 left on invoice' : '£70 left on invoice'),
          findsOneWidget,
        );
        expect(find.text('Mark Payment Received'), findsNothing);
        expect(find.text('Create invoice'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Open invoice'));
        await tester.pumpAndSettle();
        final detail = tester.widget<BusinessDocumentDetailScreen>(
          find.byType(BusinessDocumentDetailScreen),
        );
        expect(detail.documentId, 'document');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
