import '../models/slate_models.dart';
import 'booking_time.dart';
import 'whatsapp_reminder.dart';

class ClientFollowUp {
  final Client client;
  final DateTime lastVisit;
  final int daysSinceVisit;
  final int? usualDays;

  const ClientFollowUp({
    required this.client,
    required this.lastVisit,
    required this.daysSinceVisit,
    this.usualDays,
  });
}

/// A suggestion for the owner, never evidence that a customer wants a message.
/// At least three completed visits establish a cadence; imported/stale client
/// records alone do not establish that someone is a regular customer.
List<ClientFollowUp> clientFollowUps({
  required List<Client> clients,
  required List<Appointment> appointments,
  required List<BookingRequest> requests,
  required List<SlateTask> tasks,
  required DateTime now,
  Map<String, DateTime> snoozedUntil = const {},
}) {
  final histories = <String, List<DateTime>>{};
  final booked = <String>{};
  for (final appointment in appointments) {
    final id = appointment.contactId;
    if (id == null) continue;
    final key = '${appointment.workspaceId}/$id';
    if (appointment.status == 'scheduled' &&
        (appointment.startTime.isAfter(now) ||
            !(appointment.endTime ?? appointment.startTime).isBefore(now))) {
      booked.add(key);
    }
    if (appointment.status == 'completed' &&
        !appointment.startTime.isAfter(now)) {
      histories.putIfAbsent(key, () => []).add(appointment.startTime);
    }
  }
  final result = <ClientFollowUp>[];
  for (final client in clients) {
    if (client.id.trim().isEmpty) continue;
    if (client.status != 'active' && client.status != 'lead') continue;
    final key = '${client.workspaceId}/${client.id}';
    if (booked.contains(key) ||
        (snoozedUntil[client.id]?.isAfter(now) ?? false) ||
        tasks.any(
          (task) =>
              task.workspaceId == client.workspaceId &&
              task.contactId == client.id &&
              (task.status != 'done' ||
                  (task.updatedAt != null &&
                      now.difference(task.updatedAt!).inDays < 7)),
        ) ||
        requests.any(
          (request) =>
              request.workspaceId == client.workspaceId &&
              request.needsDecision &&
              _sameContact(client, request),
        )) {
      continue;
    }
    final activity = client.lastActivityAt ?? client.createdAt;
    if (activity != null && now.difference(activity).inDays < 7) continue;
    if (client.status == 'lead') {
      if (activity != null && now.difference(activity).inDays >= 7) {
        result.add(
          ClientFollowUp(
            client: client,
            lastVisit: activity,
            daysSinceVisit: now.difference(activity).inDays,
          ),
        );
      }
      continue;
    }
    final visits = histories[key] ?? [];
    visits.sort((a, b) => b.compareTo(a));
    // Separate same-day services are one visit, not a daily booking pattern.
    final unique = <DateTime>[];
    for (final visit in visits) {
      if (unique.isEmpty || unique.last.difference(visit).inHours >= 24) {
        unique.add(visit);
      }
      if (unique.length == 7) break;
    }
    if (unique.length < 3) continue;
    final gaps = <int>[
      for (var i = 1; i < unique.length; i++)
        (unique[i - 1].difference(unique[i]).inHours / 24).round(),
    ]..sort();
    final middle = gaps.length ~/ 2;
    final usual = gaps.length.isOdd
        ? gaps[middle]
        : ((gaps[middle - 1] + gaps[middle]) / 2).round();
    // Highly irregular history is not enough evidence for a useful nudge.
    if (usual < 2 || usual > 180 || gaps.last > usual * 3) continue;
    final grace = (usual * .25).ceil().clamp(7, 30);
    final age = now.difference(unique.first).inDays;
    if (age < usual + grace) continue;
    result.add(
      ClientFollowUp(
        client: client,
        lastVisit: unique.first,
        daysSinceVisit: age,
        usualDays: usual,
      ),
    );
  }
  return result;
}

bool _sameContact(Client client, BookingRequest request) {
  final email = client.email?.trim().toLowerCase() ?? '';
  if (email.isNotEmpty && email == request.email.trim().toLowerCase()) {
    return true;
  }
  final phone = _matchingPhone(client.phone);
  return phone != null && phone == _matchingPhone(request.phone);
}

String? _matchingPhone(String? raw) {
  final international = normaliseWhatsAppPhone(raw);
  if (international != null) return international;
  // Exact national numbers still match after harmless formatting changes;
  // never infer a foreign country code or join letters/extensions/numbers.
  final value = raw?.trim() ?? '';
  if (!RegExp(r'^\+?[0-9\s().-]+$').hasMatch(value)) return null;
  final digits = value.replaceAll(RegExp(r'[\s().-]'), '');
  return digits.length >= 7 ? digits : null;
}

class TomorrowBrief {
  final List<Appointment> bookings;
  final String timezone;
  final int bookedMinutes;
  final String? workspaceId;

  const TomorrowBrief(
    this.bookings,
    this.timezone,
    this.bookedMinutes, {
    this.workspaceId,
  });
}

TomorrowBrief buildTomorrowBrief({
  required List<Appointment> appointments,
  required DateTime now,
  required String timezone,
  String? workspaceId,
}) {
  final today = bookingTimeInZone(now, timezone);
  final tomorrow = DateTime.utc(today.year, today.month, today.day + 1);
  final bookings =
      appointments.where((appointment) {
        if (appointment.status != 'scheduled' ||
            (workspaceId != null && appointment.workspaceId != workspaceId)) {
          return false;
        }
        final start = bookingTimeInZone(appointment.startTime, timezone);
        return start.year == tomorrow.year &&
            start.month == tomorrow.month &&
            start.day == tomorrow.day;
      }).toList()..sort((a, b) {
        final time = a.startTime.compareTo(b.startTime);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
  final minutes = bookings.fold<int>(0, (total, booking) {
    final duration = booking.endTime?.difference(booking.startTime).inMinutes;
    return total + (duration != null && duration > 0 ? duration : 0);
  });
  return TomorrowBrief(bookings, timezone, minutes, workspaceId: workspaceId);
}
