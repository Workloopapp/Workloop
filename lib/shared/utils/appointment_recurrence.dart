import 'package:timezone/timezone.dart' as timezone;

import 'booking_time.dart';

/// Returns the start of a recurring appointment while preserving the local
/// wall-clock time selected by the business owner.
///
/// Appointment timestamps are persisted as UTC, but a weekly booking at 09:00
/// must remain at 09:00 locally when daylight-saving time changes. Calendar
/// construction is used instead of adding a fixed 7-day duration for that
/// reason.
DateTime appointmentOccurrenceStart(
  DateTime startTime,
  String? rule,
  int index, {
  String? timezoneName,
}) {
  if (index < 0) {
    throw ArgumentError.value(index, 'index', 'Must not be negative.');
  }
  if (rule == null) return startTime;

  final frequency = _ruleValue(rule, 'FREQ');
  if (frequency != 'WEEKLY' && frequency != 'MONTHLY') {
    throw ArgumentError.value(
      rule,
      'rule',
      'Only weekly and monthly recurrence rules are supported.',
    );
  }

  final rawInterval = _ruleValue(rule, 'INTERVAL');
  final interval = rawInterval == null ? 1 : int.tryParse(rawInterval);
  if (interval == null) {
    throw ArgumentError.value(
      rule,
      'rule',
      'The recurrence interval must be a whole number.',
    );
  }
  if (interval < 1 || interval > 52) {
    throw ArgumentError.value(
      rule,
      'rule',
      'The recurrence interval must be between 1 and 52.',
    );
  }
  if (index == 0) return startTime;

  final local = timezoneName == null
      ? startTime.toLocal()
      : bookingTimeInZone(startTime, timezoneName);
  final DateTime occurrence;
  if (frequency == 'MONTHLY') {
    final targetMonth = local.month + (index * interval);
    final targetYear = local.year + ((targetMonth - 1) ~/ 12);
    final normalizedMonth = ((targetMonth - 1) % 12) + 1;
    final lastDay = DateTime.utc(targetYear, normalizedMonth + 1, 0).day;
    occurrence = DateTime.utc(
      targetYear,
      normalizedMonth,
      local.day.clamp(1, lastDay),
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  } else {
    occurrence = DateTime.utc(
      local.year,
      local.month,
      local.day + (7 * interval * index),
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  if (timezoneName != null) {
    return recurringBookingInstant(occurrence, timezoneName);
  }
  final deviceLocal = DateTime(
    occurrence.year,
    occurrence.month,
    occurrence.day,
    occurrence.hour,
    occurrence.minute,
    occurrence.second,
    occurrence.millisecond,
    occurrence.microsecond,
  );
  return startTime.isUtc ? deviceLocal.toUtc() : deviceLocal;
}

/// Interprets date/time picker fields in the business timezone. Rejecting a
/// spring-forward gap avoids silently creating a booking an hour later.
DateTime recurringBookingInstant(DateTime wallClock, String timezoneName) {
  final location = bookingTimeLocation(timezoneName);
  final instant = timezone.TZDateTime(
    location,
    wallClock.year,
    wallClock.month,
    wallClock.day,
    wallClock.hour,
    wallClock.minute,
    wallClock.second,
    wallClock.millisecond,
    wallClock.microsecond,
  );
  if (instant.year != wallClock.year ||
      instant.month != wallClock.month ||
      instant.day != wallClock.day ||
      instant.hour != wallClock.hour ||
      instant.minute != wallClock.minute) {
    throw const RecurringBookingTimeException(
      'A booking falls in the hour skipped when the clocks change. Choose another time.',
    );
  }
  return instant.toUtc();
}

class RecurringBookingTimeException implements Exception {
  final String message;
  const RecurringBookingTimeException(this.message);
}

/// Editing a title or note must preserve the selected instant even during the
/// repeated autumn hour, when two instants share the same visible clock fields.
DateTime editedAppointmentStart({
  required DateTime originalStart,
  required DateTime selectedWallClock,
  String? timezoneName,
}) {
  final originalDisplay = timezoneName == null
      ? originalStart.toLocal()
      : bookingTimeInZone(originalStart, timezoneName);
  if (originalDisplay.year == selectedWallClock.year &&
      originalDisplay.month == selectedWallClock.month &&
      originalDisplay.day == selectedWallClock.day &&
      originalDisplay.hour == selectedWallClock.hour &&
      originalDisplay.minute == selectedWallClock.minute) {
    return originalStart.toUtc();
  }
  if (timezoneName != null) {
    return recurringBookingInstant(selectedWallClock, timezoneName);
  }
  return DateTime(
    selectedWallClock.year,
    selectedWallClock.month,
    selectedWallClock.day,
    selectedWallClock.hour,
    selectedWallClock.minute,
  ).toUtc();
}

String? _ruleValue(String rule, String key) {
  for (final component in rule.split(';')) {
    final separator = component.indexOf('=');
    if (separator <= 0) continue;
    if (component.substring(0, separator).trim().toUpperCase() == key) {
      return component.substring(separator + 1).trim().toUpperCase();
    }
  }
  return null;
}
