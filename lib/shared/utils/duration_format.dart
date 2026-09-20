String formatFriendlyDuration(int totalMinutes) {
  final safeMinutes = totalMinutes.clamp(0, 24 * 60);
  final hours = safeMinutes ~/ 60;
  final minutes = safeMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return hours == 1 ? '1 hour' : '$hours hours';
  return '${hours == 1 ? '1 hour' : '$hours hours'} $minutes min';
}
