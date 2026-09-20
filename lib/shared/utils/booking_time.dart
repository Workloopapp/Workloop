import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

bool _initialised = false;

timezone.Location bookingTimeLocation(String name) {
  if (!_initialised) {
    timezone_data.initializeTimeZones();
    _initialised = true;
  }
  try {
    return timezone.getLocation(name.trim());
  } on timezone.LocationNotFoundException {
    throw ArgumentError.value(name, 'timezone', 'Unknown booking time zone');
  }
}

timezone.TZDateTime bookingTimeInZone(DateTime instant, String zone) =>
    timezone.TZDateTime.from(instant.toUtc(), bookingTimeLocation(zone));

/// Civil fields in the business zone, stored in a UTC-shaped value so the
/// phone's own daylight-saving rules cannot normalise a valid business time.
/// This value is for display/comparison only; it is not the booking's instant.
DateTime bookingWallClockInZone(DateTime instant, String zone) {
  final local = bookingTimeInZone(instant, zone);
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
    local.millisecond,
    local.microsecond,
  );
}
