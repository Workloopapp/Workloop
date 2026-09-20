const List<String> workingHourDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const Map<String, String> shortToLongDay = {
  'Mon': 'Monday',
  'Tue': 'Tuesday',
  'Wed': 'Wednesday',
  'Thu': 'Thursday',
  'Fri': 'Friday',
  'Sat': 'Saturday',
  'Sun': 'Sunday',
};

class WorkingHourBlock {
  final String start;
  final String end;

  const WorkingHourBlock({required this.start, required this.end});

  Map<String, dynamic> toMap() => {'start': start, 'end': end};
}

/// Errors are keyed by the supplied day so editors can keep and mark the draft.
/// Closed days may retain unfinished times; enabled days need usable intervals.
Map<String, String> validateWorkingHours(Map<String, dynamic> hours) {
  final errors = <String, String>{};
  for (final entry in hours.entries) {
    final day = shortToLongDay[entry.key] ?? entry.key;
    final value = entry.value;
    if (!workingHourDays.contains(day) ||
        value is! Map ||
        value['enabled'] is! bool) {
      errors[entry.key] = '$day: choose whether this is a working day.';
      continue;
    }
    if (value['enabled'] != true) continue;
    final rawBlocks = value.containsKey('blocks')
        ? value['blocks']
        : [
            {
              'start': value['start'] ?? value['open'],
              'end': value['end'] ?? value['close'],
            },
          ];
    if (rawBlocks is! List || rawBlocks.isEmpty) {
      errors[entry.key] = '$day: add at least one working block.';
      continue;
    }
    final ranges = <({int start, int end})>[];
    for (final block in rawBlocks) {
      final start = block is Map && block['start'] is String
          ? _timeToMinutes(block['start'] as String)
          : null;
      final end = block is Map && block['end'] is String
          ? _timeToMinutes(block['end'] as String)
          : null;
      if (start == null || end == null) {
        errors[entry.key] = '$day: use valid times such as 09:00.';
        break;
      }
      if (end <= start) {
        errors[entry.key] = '$day: closing time must be after opening time.';
        break;
      }
      ranges.add((start: start, end: end));
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    for (var index = 1; index < ranges.length; index++) {
      if (ranges[index].start < ranges[index - 1].end) {
        errors[entry.key] = '$day: working blocks must not overlap.';
        break;
      }
    }
  }
  return errors;
}

List<WorkingHourBlock> workingHourBlocks(dynamic value) {
  final map = value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};
  if (map['enabled'] != true) return const [];

  final blocks = map['blocks'];
  if (blocks is List) {
    return blocks
        .whereType<Map>()
        .map((block) {
          final data = Map<String, dynamic>.from(block);
          final start = data['start'];
          final end = data['end'];
          return WorkingHourBlock(
            start: start is String ? start : '',
            end: end is String ? end : '',
          );
        })
        .where(
          (block) =>
              block.start.trim().isNotEmpty && block.end.trim().isNotEmpty,
        )
        .toList();
  }

  final start = _legacyTimeValue(map, const ['start', 'open'], '09:00');
  final end = _legacyTimeValue(map, const ['end', 'close'], '17:00');
  return [WorkingHourBlock(start: start, end: end)];
}

String formatWorkingHourValue(dynamic value) {
  final blocks = workingHourBlocks(value);
  if (blocks.isEmpty) return 'Closed';
  return blocks.map((block) => '${block.start} - ${block.end}').join(', ');
}

String formatFriendlyWorkingHourValue(dynamic value) {
  final blocks = workingHourBlocks(value);
  if (blocks.isEmpty) return 'Closed';
  return blocks
      .map(
        (block) =>
            '${formatFriendlyClockTime(block.start)} - ${formatFriendlyClockTime(block.end)}',
      )
      .join(', ');
}

String formatFriendlyClockTime(String value) {
  final minutes = _timeToMinutes(value);
  if (minutes == null) return value;
  final hour24 = minutes ~/ 60;
  final minute = minutes.remainder(60);
  final suffix = hour24 < 12 ? 'am' : 'pm';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  if (minute == 0) return '$hour12$suffix';
  return '$hour12:${minute.toString().padLeft(2, '0')}$suffix';
}

String weekdayName(DateTime date) => workingHourDays[date.weekday - 1];

dynamic workingHoursValueForDate(Map<String, dynamic> hours, DateTime date) {
  final longName = weekdayName(date);
  final shortName = shortToLongDay.entries
      .firstWhere((entry) => entry.value == longName)
      .key;
  return hours[longName] ?? hours[shortName];
}

bool isWithinWorkingHours({
  required Map<String, dynamic> hours,
  required DateTime start,
  required DateTime end,
}) {
  final localStart = start.toLocal();
  final localEnd = end.toLocal();
  return isWallClockWithinWorkingHours(
    hours: hours,
    start: localStart,
    end: localEnd,
  );
}

bool isWallClockWithinWorkingHours({
  required Map<String, dynamic> hours,
  required DateTime start,
  required DateTime end,
}) {
  if (!end.isAfter(start) ||
      start.year != end.year ||
      start.month != end.month ||
      start.day != end.day) {
    return false;
  }

  final value = workingHoursValueForDate(hours, start);
  final blocks = workingHourBlocks(value);
  if (blocks.isEmpty) return false;

  final startSeconds = start.hour * 3600 + start.minute * 60 + start.second;
  final endSeconds = end.hour * 3600 + end.minute * 60 + end.second;
  return blocks.any((block) {
    final blockStart = _timeToMinutes(block.start);
    final blockEnd = _timeToMinutes(block.end);
    if (blockStart == null || blockEnd == null || blockEnd <= blockStart) {
      return false;
    }
    return startSeconds >= blockStart * 60 && endSeconds <= blockEnd * 60;
  });
}

Map<String, dynamic> defaultWorkingHours() => {
  for (final day in workingHourDays)
    day: {
      'enabled': day != 'Sunday',
      'blocks': [
        {
          'start': day == 'Saturday' ? '09:00' : '08:00',
          'end': day == 'Saturday' ? '14:00' : '14:00',
        },
        if (day != 'Saturday' && day != 'Sunday')
          {'start': '16:00', 'end': '21:00'},
      ],
    },
};

int? _timeToMinutes(String value) {
  if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value)) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

String _legacyTimeValue(
  Map<String, dynamic> map,
  List<String> keys,
  String fallback,
) {
  for (final key in keys) {
    if (!map.containsKey(key)) continue;
    final value = map[key];
    return value is String ? value : '';
  }
  return fallback;
}
