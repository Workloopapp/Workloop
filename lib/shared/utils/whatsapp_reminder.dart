import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../models/slate_models.dart';

/// Accept explicit international numbers, plus the app's UK-mobile convention.
/// Ambiguous national numbers and extensions need correcting in client details.
String? normaliseWhatsAppPhone(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty || !RegExp(r'^\+?[0-9\s().-]+$').hasMatch(input)) {
    return null;
  }
  var number = input.replaceAll(RegExp(r'[\s().-]'), '');
  if (number.startsWith('00')) number = '+${number.substring(2)}';
  if (RegExp(r'^07\d{9}$').hasMatch(number)) {
    number = '+44${number.substring(1)}';
  }
  if (number.startsWith('+44') &&
      !RegExp(r'^\+44[1-9]\d{9}$').hasMatch(number)) {
    return null;
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(number) ? number : null;
}

Uri whatsAppChatUri(String internationalPhone, {String? message}) {
  if (normaliseWhatsAppPhone(internationalPhone) != internationalPhone) {
    throw ArgumentError.value(internationalPhone, 'internationalPhone');
  }
  return Uri.https(
    'wa.me',
    '/${internationalPhone.substring(1)}',
    message == null ? null : {'text': message},
  );
}

bool canRemindBooking(Appointment appointment, DateTime now) =>
    appointment.status == 'scheduled' && appointment.startTime.isAfter(now);

/// A detail screen needs the joined display data that the write map omits.
Map<String, dynamic> bookingReminderSnapshot(Appointment appointment) => {
  ...appointment.toMap(),
  'contacts': {'name': appointment.clientName},
  'services': {'name': appointment.serviceName},
  'appointment_items': [
    for (final item in appointment.serviceItems)
      {
        'id': item.id,
        'workspace_id': item.workspaceId,
        'item_kind': item.itemKind,
        'source_service_id': item.sourceServiceId,
        'source_add_on_id': item.sourceAddOnId,
        'name': item.name,
        'duration_mins': item.durationMins,
        'price': item.price,
        'position': item.position,
      },
  ],
};

bool _timeZonesReady = false;

String bookingReminderTime(DateTime instant, String timeZone) {
  if (!_timeZonesReady) {
    timezone_data.initializeTimeZones();
    _timeZonesReady = true;
  }
  final local = timezone.TZDateTime.from(
    instant,
    timezone.getLocation(timeZone),
  );
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final offset = local.timeZoneOffset;
  final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
  final offsetMinutes = (offset.inMinutes.abs() % 60).toString().padLeft(
    2,
    '0',
  );
  final zoneLabel = timeZone == 'Europe/London'
      ? local.timeZoneName
      : '${local.timeZoneName} (UTC${offset.isNegative ? '-' : '+'}$offsetHours:$offsetMinutes)';
  return '${weekdays[local.weekday - 1]} ${local.day} '
      '${months[local.month - 1]} ${local.year} at $hour:$minute '
      '$zoneLabel';
}

String bookingWhatsAppMessage({
  required Appointment appointment,
  required String clientName,
  required String businessName,
  required String timeZone,
}) {
  String line(String value) =>
      value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  final name = line(clientName);
  final business = line(businessName);
  if (business.isEmpty) throw ArgumentError('A business name is required.');
  final service = line(appointment.serviceName ?? appointment.title ?? '');
  return 'Hi${name.isEmpty ? '' : ' $name'},\n\n'
      'A reminder of your booking with $business:\n'
      '${service.isEmpty ? '' : '$service\n'}'
      '${bookingReminderTime(appointment.startTime, timeZone)}\n\n'
      'If you need to make a change, please contact $business directly.';
}
