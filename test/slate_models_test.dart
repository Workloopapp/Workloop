import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/utils/calendar_export.dart';
import 'package:workloop/shared/utils/working_hours.dart';

void main() {
  group('Slate models', () {
    test('Client preserves CRM fields across map boundaries', () {
      final client = Client.fromMap({
        'id': 'client-1',
        'workspace_id': 'workspace-1',
        'name': 'Sarah Morgan',
        'phone': '07123 456789',
        'email': 'sarah@example.com',
        'address': '10 North Road',
        'notes': 'Prefers mornings',
        'important_notes': 'Patch test required',
        'status': 'active',
        'preferred_contact_method': 'sms',
        'source': 'Referral',
        'birthday': '1993-06-10',
        'tags': ['regular', 'morning'],
        'last_activity_at': '2026-05-20T10:00:00Z',
      });

      expect(client.name, 'Sarah Morgan');
      expect(client.address, '10 North Road');
      expect(client.importantNotes, 'Patch test required');
      expect(client.preferredContactMethod, 'sms');
      expect(client.source, 'Referral');
      expect(client.tags, ['regular', 'morning']);
      expect(client.toMap()['workspace_id'], 'workspace-1');
      expect(client.toMap()['notes'], 'Prefers mornings');
      expect(client.toMap()['birthday'], '1993-06-10');
    });

    test('Appointment reads joined client and service names', () {
      final appointment = Appointment.fromMap({
        'id': 'appt-1',
        'workspace_id': 'workspace-1',
        'contact_id': 'client-1',
        'service_id': 'service-1',
        'start_time': '2026-05-28T09:00:00Z',
        'end_time': '2026-05-28T10:00:00Z',
        'status': 'scheduled',
        'price': 45,
        'contacts': {'name': 'Sarah Morgan'},
        'services': {'name': 'Cut and finish'},
      });

      expect(appointment.clientName, 'Sarah Morgan');
      expect(appointment.serviceName, 'Cut and finish');
      expect(appointment.price, 45);
    });

    test('Payment keeps simple payment language on invoice-backed rows', () {
      final payment = Payment.fromMap({
        'id': 'pay-1',
        'workspace_id': 'workspace-1',
        'invoice_number': 'PAY-001',
        'status': 'paid',
        'issue_date': '2026-05-28',
        'total': '70.50',
        'amount_paid': 70.5,
        'contacts': {'name': 'Alex'},
      });

      expect(payment.number, 'PAY-001');
      expect(payment.total, 70.5);
      expect(payment.clientName, 'Alex');
    });

    test('user-facing text strips demo markers', () {
      final payment = Payment.fromMap({
        'id': 'pay-demo',
        'workspace_id': 'workspace-1',
        'invoice_number': 'PAY-001',
        'status': 'sent',
        'issue_date': '2026-05-28',
        'total': 70,
        'notes': '[Slate demo] Awaiting payment.',
      });
      final task = SlateTask.fromMap({
        'id': 'task-demo',
        'workspace_id': 'workspace-1',
        'title': 'Demo: Confirm colour formula',
        'status': 'open',
      });

      expect(payment.notes, 'Awaiting payment.');
      expect(task.title, 'Confirm colour formula');
    });

    test('Payment serializes back to the invoice-backed database shape', () {
      final payment = Payment.fromMap({
        'id': 'pay-2',
        'workspace_id': 'workspace-1',
        'contact_id': 'client-1',
        'appointment_id': 'booking-1',
        'payment_number': 'PAY-002',
        'status': 'sent',
        'issue_date': '2026-05-29',
        'due_date': '2026-06-05',
        'total': 120,
        'amount_paid': 0,
        'notes': 'Package deposit',
      });

      final map = payment.toMap();

      expect(map['invoice_number'], 'PAY-002');
      expect(map['issue_date'], '2026-05-29');
      expect(map['due_date'], '2026-06-05');
      expect(map['contact_id'], 'client-1');
      expect(map['appointment_id'], 'booking-1');
      expect(map['total'], 120);
    });

    test('Expense keeps lightweight money tracking fields', () {
      final expense = Expense.fromMap({
        'id': 'expense-1',
        'workspace_id': 'workspace-1',
        'amount': '42.75',
        'category': 'Materials',
        'expense_date': '2026-05-31',
        'notes': 'Colour supplies',
      });

      final map = expense.toMap();

      expect(expense.amount, 42.75);
      expect(expense.category, 'Materials');
      expect(expense.expenseDate, DateTime(2026, 5, 31));
      expect(map['expense_date'], '2026-05-31');
      expect(map['notes'], 'Colour supplies');
    });

    test('SlateTask reads linked client data and date fields', () {
      final task = SlateTask.fromMap({
        'id': 'task-1',
        'workspace_id': 'workspace-1',
        'title': 'Follow up about package',
        'status': 'open',
        'priority': 'high',
        'reminder_timing': 'day_before',
        'due_date': '2026-06-02',
        'created_at': '2026-05-30T09:00:00Z',
        'contact_id': 'client-1',
        'contacts': {'name': 'Maya'},
      });

      expect(task.clientName, 'Maya');
      expect(task.reminderTiming, 'day_before');
      expect(task.dueDate, DateTime(2026, 6, 2));
      expect(task.toMap()['due_date'], '2026-06-02');
      expect(task.toMap()['reminder_timing'], 'day_before');
    });

    test('TaskChecklistItem preserves task step state', () {
      final item = TaskChecklistItem.fromMap({
        'id': 'item-1',
        'workspace_id': 'workspace-1',
        'task_id': 'task-1',
        'title': 'Send reminder text',
        'completed': true,
        'position': 2,
      });

      expect(item.taskId, 'task-1');
      expect(item.completed, isTrue);
      expect(item.position, 2);
      expect(item.toMap()['title'], 'Send reminder text');
    });

    test('SlateNote preserves pinned notes and linked client data', () {
      final note = SlateNote.fromMap({
        'id': 'note-1',
        'workspace_id': 'workspace-1',
        'title': 'Colour formula',
        'body': 'Use 7N with low developer',
        'contact_id': 'client-1',
        'appointment_id': 'booking-1',
        'pinned': true,
        'contacts': {'name': 'Maya'},
      });

      expect(note.clientName, 'Maya');
      expect(note.pinned, isTrue);
      expect(note.toMap()['title'], 'Colour formula');
      expect(note.toMap()['appointment_id'], 'booking-1');
    });

    test('Service preserves public profile visibility fields', () {
      final service = Service.fromMap({
        'id': 'service-1',
        'workspace_id': 'workspace-1',
        'name': 'Consultation',
        'duration_mins': '45',
        'price': '35',
        'description': 'Initial consult',
        'show_on_profile': false,
      });

      expect(service.durationMins, 45);
      expect(service.price, 35);
      expect(service.showOnProfile, isFalse);
      expect(service.toMap()['show_on_profile'], isFalse);
    });

    test('Service parses bounded optional add-ons from a nested response', () {
      final service = Service.fromMap({
        'id': 'service-1',
        'workspace_id': 'workspace-1',
        'name': 'Window clean',
        'duration_mins': 60,
        'price': 50,
        'service_add_ons': [
          {
            'id': 'add-on-1',
            'workspace_id': 'workspace-1',
            'service_id': 'service-1',
            'name': 'Frames and sills',
            'duration_mins': 15,
            'price': 12,
            'position': 0,
          },
        ],
      });

      expect(service.addOns, hasLength(1));
      expect(service.addOns.single.name, 'Frames and sills');
      expect(service.addOns.single.durationMins, 15);
      expect(service.addOns.single.price, 12);
    });

    test('BusinessProfile defaults new V1 public profile controls safely', () {
      final profile = BusinessProfile.fromMap({
        'id': 'profile-1',
        'workspace_id': 'workspace-1',
        'handle': 'slate-demo',
        'cover_photo_url': 'https://example.com/cover.jpg',
        'gallery_image_urls': ['https://example.com/1.jpg', ''],
        'review_quotes': ['Great service'],
      });

      expect(profile.bookingMode, 'manual');
      expect(profile.coverPhotoUrl, 'https://example.com/cover.jpg');
      expect(profile.galleryImageUrls, ['https://example.com/1.jpg']);
      expect(profile.reviewQuotes, ['Great service']);
      expect(profile.reviewsEnabled, isFalse);
      expect(profile.galleryEnabled, isFalse);
      expect(profile.payNowEnabled, isFalse);
    });

    test('BookingRequest reads selected service and preferred timing', () {
      final request = BookingRequest.fromMap({
        'id': 'request-1',
        'workspace_id': 'workspace-1',
        'name': 'Nadia',
        'phone': '07123 000000',
        'email': 'nadia@example.com',
        'service_id': 'service-1',
        'preferred_time_text': 'Friday afternoon',
        'message': 'First visit',
        'status': 'contacted',
        'services': {
          'name': 'Initial consultation',
          'duration_mins': 75,
          'price': 80,
        },
      });

      expect(request.serviceName, 'Initial consultation');
      expect(request.serviceDurationMins, 75);
      expect(request.servicePrice, 80);
      expect(request.preferredTimeText, 'Friday afternoon');
      expect(request.email, 'nadia@example.com');
      expect(request.status, 'contacted');
      expect(request.toMap()['preferred_time_text'], 'Friday afternoon');
      expect(request.toMap()['email'], 'nadia@example.com');
    });

    test(
      'BookingRequest prefers immutable item snapshots and totals extras',
      () {
        final request = BookingRequest.fromMap({
          'id': 'request-1',
          'workspace_id': 'workspace-1',
          'name': 'Nadia',
          'phone': '07123 000000',
          'services': {
            'name': 'Changed catalog name',
            'duration_mins': 30,
            'price': 30,
          },
          'booking_request_items': [
            {
              'id': 'item-2',
              'workspace_id': 'workspace-1',
              'item_kind': 'add_on',
              'source_service_id': 'service-1',
              'source_add_on_id': 'add-on-1',
              'name': 'Frames and sills',
              'duration_mins': 15,
              'price': 12,
              'position': 1,
            },
            {
              'id': 'item-1',
              'workspace_id': 'workspace-1',
              'item_kind': 'base',
              'source_service_id': 'service-1',
              'name': 'Window clean',
              'duration_mins': 60,
              'price': 50,
              'position': 0,
            },
          ],
        });

        expect(request.serviceName, 'Window clean');
        expect(request.serviceDurationMins, 75);
        expect(request.servicePrice, 62);
        expect(request.serviceItems.map((item) => item.name), [
          'Window clean',
          'Frames and sills',
        ]);
      },
    );

    test('Appointment parses confirmed item snapshots in display order', () {
      final appointment = Appointment.fromMap({
        'id': 'appointment-1',
        'workspace_id': 'workspace-1',
        'start_time': '2026-05-28T09:00:00Z',
        'title': 'Saved booking title',
        'services': {'name': 'Renamed live service'},
        'appointment_items': [
          {
            'id': 'item-2',
            'workspace_id': 'workspace-1',
            'item_kind': 'add_on',
            'name': 'Frames and sills',
            'duration_mins': 15,
            'price': 12,
            'position': 1,
          },
          {
            'id': 'item-1',
            'workspace_id': 'workspace-1',
            'item_kind': 'base',
            'name': 'Window clean',
            'duration_mins': 60,
            'price': 50,
            'position': 0,
          },
        ],
      });

      expect(appointment.serviceItems.map((item) => item.name), [
        'Window clean',
        'Frames and sills',
      ]);
      expect(appointment.serviceName, 'Window clean');
      expect(appointment.serviceItems.last.isAddOn, isTrue);
    });

    test(
      'Appointment prefers its saved title before a mutable service join',
      () {
        final appointment = Appointment.fromMap({
          'id': 'appointment-2',
          'workspace_id': 'workspace-1',
          'start_time': '2026-05-28T10:00:00Z',
          'title': 'Original consultation',
          'services': {'name': 'Renamed catalog service'},
        });

        expect(appointment.serviceName, 'Original consultation');
      },
    );
  });

  test('working hours support split days with breaks', () {
    final hours = {
      'Monday': {
        'enabled': true,
        'blocks': [
          {'start': '08:00', 'end': '14:00'},
          {'start': '16:00', 'end': '21:00'},
        ],
      },
    };

    expect(
      isWithinWorkingHours(
        hours: hours,
        start: DateTime(2026, 6, 1, 9),
        end: DateTime(2026, 6, 1, 10),
      ),
      isTrue,
    );
    expect(
      isWithinWorkingHours(
        hours: hours,
        start: DateTime(2026, 6, 1, 14, 30),
        end: DateTime(2026, 6, 1, 15, 30),
      ),
      isFalse,
    );
    expect(
      formatWorkingHourValue(hours['Monday']),
      '08:00 - 14:00, 16:00 - 21:00',
    );
  });

  test('calendar export builds valid ICS events', () {
    final ics = buildWorkloopIcs([
      {
        'id': 'appointment-1',
        'title': 'Cut, colour',
        'start_time': '2026-06-01T09:00:00Z',
        'end_time': '2026-06-01T10:30:00Z',
        'contacts': {'name': 'Nadia'},
        'services': {'name': 'Colour refresh'},
      },
    ]);

    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('BEGIN:VEVENT'));
    expect(ics, contains(r'SUMMARY:Cut\, colour'));
    expect(ics, contains('DTSTART:20260601T090000Z'));
    expect(ics, contains('Client: Nadia'));
  });
}
