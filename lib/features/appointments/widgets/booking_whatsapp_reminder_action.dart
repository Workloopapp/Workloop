import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/providers/booking_whatsapp_reminder_provider.dart';
import '../../../shared/utils/whatsapp_reminder.dart';

class BookingWhatsAppReminderAction extends ConsumerStatefulWidget {
  final Appointment appointment;
  final Future<void> Function()? onOpenClient;
  final ValueChanged<Appointment>? onAppointmentRefreshed;

  const BookingWhatsAppReminderAction({
    super.key,
    required this.appointment,
    this.onOpenClient,
    this.onAppointmentRefreshed,
  });

  @override
  ConsumerState<BookingWhatsAppReminderAction> createState() =>
      _BookingWhatsAppReminderActionState();
}

class _BookingWhatsAppReminderActionState
    extends ConsumerState<BookingWhatsAppReminderAction> {
  bool _busy = false;
  BookingWhatsAppDraft? _fallback;
  BookingWhatsAppReminder? _fallbackService;

  bool _current(
    BookingWhatsAppReminder service,
    String? userId,
    String workspaceId,
    String appointmentId,
  ) =>
      mounted &&
      ModalRoute.of(context)?.isCurrent != false &&
      widget.appointment.id == appointmentId &&
      widget.appointment.workspaceId == workspaceId &&
      service.isCurrent(userId, workspaceId);

  Future<void> _prepare({bool copy = false}) async {
    if (_busy) return;
    final service = ref.read(bookingWhatsAppReminderProvider);
    final launcher = ref.read(whatsAppUrlLauncherProvider);
    final userId = service.currentUserId();
    final workspaceId = widget.appointment.workspaceId;
    final appointmentId = widget.appointment.id;
    bool current() => _current(service, userId, workspaceId, appointmentId);
    if (!current()) return;
    final previousDraft = _fallback;
    setState(() => _busy = true);
    try {
      final draft = await service.prepare(workspaceId, appointmentId);
      if (!current()) return;
      widget.onAppointmentRefreshed?.call(draft.appointment);
      if (!current()) return;
      if (copy) {
        if (previousDraft == null || previousDraft.uri != draft.uri) {
          setState(() => _fallback = null);
          _snack(
            'The booking or client details changed. Open the reminder again to review it.',
          );
          return;
        }
        await Clipboard.setData(ClipboardData(text: draft.message));
        if (current()) {
          _snack('Reminder copied. You can now send it to the client.');
        }
        return;
      }
      setState(() => _fallback = null);
      bool opened;
      try {
        // HTTPS opens the app when available, or WhatsApp's website otherwise.
        opened = await launcher(draft.uri).timeout(const Duration(seconds: 10));
      } catch (_) {
        opened = false;
      }
      if (!current()) return;
      if (opened) {
        _snack(
          'Check the message and sending account in WhatsApp, then tap Send.',
        );
      } else {
        setState(() {
          _fallback = draft;
          _fallbackService = service;
        });
      }
    } on WhatsAppReminderException catch (error) {
      if (!current()) return;
      setState(() => _fallback = null);
      final message = switch (error.issue) {
        WhatsAppReminderIssue.unavailableBooking =>
          'Reminders are only available for upcoming, scheduled bookings. This booking may have changed or been removed.',
        WhatsAppReminderIssue.missingClient =>
          'Link this booking to a client with a phone number before sending a WhatsApp reminder.',
        WhatsAppReminderIssue.invalidPhone =>
          'Add a UK mobile number starting 07, or a full international number including its country code, in the client’s details.',
        WhatsAppReminderIssue.missingBusinessDetails =>
          'Your business details or booking time zone could not be verified. Check your business name in Business and contact Workloop support if this continues.',
        WhatsAppReminderIssue.changedBooking =>
          'The booking or client details changed while the reminder was being prepared. Check the details and try again.',
        WhatsAppReminderIssue.changedAccount =>
          'Your account changed. Open the booking again to prepare a reminder.',
      };
      final openClient =
          error.issue == WhatsAppReminderIssue.invalidPhone &&
          widget.onOpenClient != null;
      _snack(
        message,
        action: openClient
            ? SnackBarAction(
                label: 'Open client',
                onPressed: () {
                  if (current()) widget.onOpenClient?.call();
                },
              )
            : null,
      );
      if (error.appointment case final appointment?) {
        if (appointment.id == appointmentId &&
            appointment.workspaceId == workspaceId) {
          widget.onAppointmentRefreshed?.call(appointment);
        }
      }
    } catch (_) {
      if (current()) {
        _snack(
          'Could not prepare the reminder. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {SnackBarAction? action}) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), action: action));

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(bookingReminderClockProvider);
    if (!canRemindBooking(widget.appointment, now())) {
      return const SizedBox.shrink();
    }
    final fallback = _fallback;
    final showFallback =
        fallback != null &&
        _fallbackService != null &&
        _current(
          _fallbackService!,
          fallback.userId,
          fallback.appointment.workspaceId,
          fallback.appointment.id,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('booking-whatsapp-reminder'),
          onPressed: _busy ? null : _prepare,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chat_bubble_outline, size: 20),
          label: Text(
            _busy ? 'Preparing reminder…' : 'Send WhatsApp reminder',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Opens WhatsApp or its website. Check the message and your sending account, then tap Send.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).extension<WorkloopThemeTokens>()?.textSecondary,
          ),
        ),
        if (showFallback) ...[
          const SizedBox(height: 16),
          Text(
            'WhatsApp didn’t open',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'You can copy this reminder and contact the client directly. Workloop hasn’t sent this message.',
          ),
          const SizedBox(height: 12),
          Text(fallback.phone),
          const SizedBox(height: 8),
          SelectableText(fallback.message),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _prepare(copy: true),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy reminder'),
            ),
          ),
        ],
      ],
    );
  }
}
