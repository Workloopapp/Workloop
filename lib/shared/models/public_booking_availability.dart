class PublicBookingAvailability {
  final String timezone;
  final int durationMinutes;
  final DateTime generatedAt;
  final List<PublicBookingAvailabilityDay> days;

  const PublicBookingAvailability({
    required this.timezone,
    required this.durationMinutes,
    required this.generatedAt,
    required this.days,
  });

  factory PublicBookingAvailability.fromMap(Map<String, dynamic> map) {
    final timezone = map['timezone'];
    final durationMinutes = map['durationMinutes'];
    final generatedAt = DateTime.tryParse(map['generatedAt']?.toString() ?? '');
    if (timezone is! String ||
        timezone.isEmpty ||
        durationMinutes is! int ||
        durationMinutes < 5 ||
        durationMinutes > 12960 ||
        generatedAt == null) {
      throw const FormatException('Invalid public availability response');
    }
    final rawDays = map['days'];
    final days = rawDays is List
        ? rawDays
              .take(5)
              .whereType<Map>()
              .map(
                (value) => PublicBookingAvailabilityDay.fromMap(
                  Map<String, dynamic>.from(value),
                ),
              )
              .where((day) => day.slotsUtc.isNotEmpty)
              .toList(growable: false)
        : const <PublicBookingAvailabilityDay>[];
    return PublicBookingAvailability(
      timezone: timezone,
      durationMinutes: durationMinutes,
      generatedAt: generatedAt.toUtc(),
      days: days,
    );
  }
}

class PublicBookingAvailabilityDay {
  final DateTime date;
  final List<DateTime> slotsUtc;

  const PublicBookingAvailabilityDay({
    required this.date,
    required this.slotsUtc,
  });

  factory PublicBookingAvailabilityDay.fromMap(Map<String, dynamic> map) {
    final date = DateTime.tryParse(map['date']?.toString() ?? '');
    if (date == null) {
      throw const FormatException('Invalid public availability day');
    }
    final rawSlots = map['slots'];
    final slots = rawSlots is List
        ? rawSlots
              .take(6)
              .map((value) => DateTime.tryParse(value.toString()))
              .whereType<DateTime>()
              .map((value) => value.toUtc())
              .toList(growable: false)
        : const <DateTime>[];
    return PublicBookingAvailabilityDay(
      date: DateTime(date.year, date.month, date.day),
      slotsUtc: slots,
    );
  }
}
