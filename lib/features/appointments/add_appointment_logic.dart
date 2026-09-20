part of 'add_appointment_screen.dart';

({int durationMins, double price}) appointmentComposition({
  required int baseDurationMins,
  required double basePrice,
  required Iterable<ServiceAddOn> addOns,
  required Set<String> selectedAddOnIds,
}) {
  var durationMins = baseDurationMins;
  var price = basePrice;
  for (final addOn in addOns) {
    if (!selectedAddOnIds.contains(addOn.id)) continue;
    durationMins += addOn.durationMins;
    price += addOn.price;
  }
  return (durationMins: durationMins, price: price);
}

class _LocationChoice {
  final String value;
  final String label;

  const _LocationChoice({required this.value, required this.label});
}

String _formatAppointmentDate(DateTime dt) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
