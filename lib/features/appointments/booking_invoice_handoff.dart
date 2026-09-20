import '../../shared/models/slate_models.dart';

/// A booking's existing unpaid entry can become its invoice without creating
/// a second balance. The server also checks in-flight Stripe collections.
bool canCreateBookingInvoice(Appointment booking, List<Payment> payments) {
  final active = payments
      .where(
        (payment) =>
            payment.status != 'cancelled' && payment.status != 'declined',
      )
      .toList();
  if (active.isEmpty) return true;
  if (active.length != 1) return false;
  final payment = active.single;
  return payment.sourceDocumentId == null &&
      (payment.status == 'sent' || payment.status == 'overdue') &&
      payment.collectedAmount == 0 &&
      payment.stripeAmountPaid == 0 &&
      payment.contactId == booking.contactId &&
      (payment.total * 100).round() == (booking.price * 100).round();
}
