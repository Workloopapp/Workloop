import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/slate_models.dart';
import '../repositories/slate_repositories.dart';
import '../utils/whatsapp_reminder.dart';
import 'workspace_provider.dart';

final whatsAppUrlLauncherProvider = Provider<Future<bool> Function(Uri)>((ref) {
  return (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
});

final bookingReminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final bookingWhatsAppReminderProvider = Provider<BookingWhatsAppReminder>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  final appointments = ref.watch(appointmentsRepositoryProvider);
  final clients = ref.watch(clientsRepositoryProvider);
  final workspaces = ref.watch(workspaceRepositoryProvider);
  final settings = ref.watch(workspaceSettingsRepositoryProvider);
  return BookingWhatsAppReminder(
    currentUserId: () => client.auth.currentUser?.id,
    currentWorkspaceId: () =>
        ref.mounted ? ref.read(workspaceIdProvider).value : null,
    loadAppointment: appointments.getById,
    loadClient: clients.getById,
    loadWorkspace: workspaces.currentWorkspace,
    loadSettings: settings.get,
    now: ref.watch(bookingReminderClockProvider),
  );
});

enum WhatsAppReminderIssue {
  unavailableBooking,
  missingClient,
  invalidPhone,
  missingBusinessDetails,
  changedBooking,
  changedAccount,
}

class WhatsAppReminderException implements Exception {
  final WhatsAppReminderIssue issue;
  final Appointment? appointment;
  const WhatsAppReminderException(this.issue, {this.appointment});
}

class BookingWhatsAppDraft {
  final String userId;
  final Appointment appointment;
  final String phone;
  final String message;
  const BookingWhatsAppDraft({
    required this.userId,
    required this.appointment,
    required this.phone,
    required this.message,
  });
  Uri get uri => whatsAppChatUri(phone, message: message);
}

/// Preparing or opening a draft never writes a reminder delivery record.
class BookingWhatsAppReminder {
  final String? Function() currentUserId;
  final String? Function() currentWorkspaceId;
  final Future<Appointment?> Function(String, String) loadAppointment;
  final Future<Client?> Function(String) loadClient;
  final Future<Workspace?> Function() loadWorkspace;
  final Future<Map<String, dynamic>?> Function(String) loadSettings;
  final DateTime Function() now;

  BookingWhatsAppReminder({
    required this.currentUserId,
    required this.currentWorkspaceId,
    required this.loadAppointment,
    required this.loadClient,
    required this.loadWorkspace,
    required this.loadSettings,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  bool isCurrent(String? userId, String workspaceId) =>
      userId != null &&
      currentUserId() == userId &&
      currentWorkspaceId() == workspaceId;

  Future<BookingWhatsAppDraft> prepare(String workspaceId, String id) =>
      _prepare(workspaceId, id).timeout(const Duration(seconds: 15));

  Future<BookingWhatsAppDraft> _prepare(String workspaceId, String id) async {
    final userId = currentUserId();
    void checkIdentity() {
      if (!isCurrent(userId, workspaceId)) {
        throw const WhatsAppReminderException(
          WhatsAppReminderIssue.changedAccount,
        );
      }
    }

    checkIdentity();
    final appointment = await loadAppointment(workspaceId, id);
    checkIdentity();
    if (appointment == null ||
        appointment.id != id ||
        appointment.workspaceId != workspaceId ||
        !canRemindBooking(appointment, now())) {
      throw WhatsAppReminderException(
        WhatsAppReminderIssue.unavailableBooking,
        appointment: appointment,
      );
    }
    final contactId = appointment.contactId;
    if (contactId == null || contactId.isEmpty) {
      throw WhatsAppReminderException(
        WhatsAppReminderIssue.missingClient,
        appointment: appointment,
      );
    }
    final (client, workspace, settings) = await (
      loadClient(contactId),
      loadWorkspace(),
      loadSettings(workspaceId),
    ).wait;
    checkIdentity();
    if (workspace?.id != workspaceId) {
      throw const WhatsAppReminderException(
        WhatsAppReminderIssue.changedAccount,
      );
    }
    if (client == null ||
        client.id != contactId ||
        client.workspaceId != workspaceId) {
      throw WhatsAppReminderException(
        WhatsAppReminderIssue.missingClient,
        appointment: appointment,
      );
    }
    final phone = normaliseWhatsAppPhone(client.phone);
    if (phone == null) {
      throw WhatsAppReminderException(
        WhatsAppReminderIssue.invalidPhone,
        appointment: appointment,
      );
    }
    final timeZone = settings?['timezone'] as String?;
    final businessName = workspace!.name.trim();
    if (timeZone == null || timeZone.trim().isEmpty || businessName.isEmpty) {
      throw const WhatsAppReminderException(
        WhatsAppReminderIssue.missingBusinessDetails,
      );
    }
    String message;
    try {
      message = bookingWhatsAppMessage(
        appointment: appointment,
        clientName: client.name,
        businessName: businessName,
        timeZone: timeZone,
      );
    } on Exception {
      throw const WhatsAppReminderException(
        WhatsAppReminderIssue.missingBusinessDetails,
      );
    }

    // Do not hand off a draft if the booking or recipient changed while loading.
    final (latest, latestClient) = await (
      loadAppointment(workspaceId, id),
      loadClient(contactId),
    ).wait;
    checkIdentity();
    if (latest == null || !canRemindBooking(latest, now())) {
      throw WhatsAppReminderException(
        WhatsAppReminderIssue.unavailableBooking,
        appointment: latest,
      );
    }
    if (latest.id != id ||
        latest.workspaceId != workspaceId ||
        latest.contactId != contactId ||
        latest.startTime != appointment.startTime ||
        latest.serviceName != appointment.serviceName ||
        latest.title != appointment.title ||
        latestClient?.id != contactId ||
        latestClient?.workspaceId != workspaceId ||
        normaliseWhatsAppPhone(latestClient?.phone) != phone ||
        latestClient?.name != client.name) {
      throw WhatsAppReminderException(
        WhatsAppReminderIssue.changedBooking,
        appointment: latest,
      );
    }
    return BookingWhatsAppDraft(
      userId: userId!,
      appointment: latest,
      phone: phone,
      message: message,
    );
  }
}
