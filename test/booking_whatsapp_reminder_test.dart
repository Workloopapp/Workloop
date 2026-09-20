import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/appointments/appointment_detail_screen.dart';
import 'package:workloop/features/appointments/widgets/booking_whatsapp_reminder_action.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/booking_whatsapp_reminder_provider.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/appointments_repository.dart';
import 'package:workloop/shared/utils/whatsapp_reminder.dart';

final now = DateTime.utc(2026, 9, 5, 12);
Appointment booking({
  String status = 'scheduled',
  DateTime? start,
  String? contact = 'client-a',
}) => Appointment(
  id: 'booking-a',
  workspaceId: 'workspace-a',
  contactId: contact,
  serviceName: 'Cut & colour + finish #1 ✨',
  startTime: start ?? DateTime.utc(2026, 9, 6, 8, 30),
  status: status,
);
Client client({
  String? phone = '07700 900123',
  String workspace = 'workspace-a',
  String id = 'client-a',
}) => Client(id: id, workspaceId: workspace, name: 'Amélie & Jo', phone: phone);

class ReminderFixture {
  Appointment? appointment = booking();
  Client? customer = client();
  Workspace? workspace = const Workspace(
    id: 'workspace-a',
    name: 'Jane’s Studio & Co',
  );
  Map<String, dynamic>? settings = {'timezone': 'Europe/London'};
  String? userId = 'owner-a';
  String? workspaceId = 'workspace-a';
  int appointmentReads = 0;
  int clientReads = 0;
  Future<Appointment?> Function(int)? onAppointmentRead;
  Future<Client?> Function(int)? onClientRead;
  late final service = BookingWhatsAppReminder(
    currentUserId: () => userId,
    currentWorkspaceId: () => workspaceId,
    loadAppointment: (_, _) async {
      appointmentReads++;
      return onAppointmentRead == null
          ? appointment
          : await onAppointmentRead!(appointmentReads);
    },
    loadClient: (_) async {
      clientReads++;
      return onClientRead == null ? customer : await onClientRead!(clientReads);
    },
    loadWorkspace: () async => workspace,
    loadSettings: (_) async => settings,
    now: () => now,
  );
  Future<BookingWhatsAppDraft> prepare() =>
      service.prepare('workspace-a', 'booking-a');
}

Matcher issue(WhatsAppReminderIssue value) => throwsA(
  isA<WhatsAppReminderException>().having((e) => e.issue, 'issue', value),
);

Future<void> pumpAction(
  WidgetTester tester,
  ReminderFixture fixture, {
  Future<bool> Function(Uri)? launch,
  Future<void> Function()? openClient,
  ValueChanged<Appointment>? refreshed,
  Appointment? snapshot,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingWhatsAppReminderProvider.overrideWithValue(fixture.service),
        bookingReminderClockProvider.overrideWithValue(() => now),
        whatsAppUrlLauncherProvider.overrideWithValue(
          launch ?? (_) async => true,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: BookingWhatsAppReminderAction(
                appointment: snapshot ?? fixture.appointment ?? booking(),
                onOpenClient: openClient,
                onAppointmentRefreshed: refreshed,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recipient and truthful message', () {
    test(
      'normalizes UK mobile and explicit global numbers without changing interior zeros',
      () {
        expect(normaliseWhatsAppPhone('07700 900123'), '+447700900123');
        expect(normaliseWhatsAppPhone('+44 7700 900123'), '+447700900123');
        expect(normaliseWhatsAppPhone('00 44 7700 900123'), '+447700900123');
        expect(normaliseWhatsAppPhone('+1 (202) 555-0123'), '+12025550123');
        expect(normaliseWhatsAppPhone('+44 20 7946 0123'), '+442079460123');
        expect(normaliseWhatsAppPhone('+33 6 12 34 56 78'), '+33612345678');
      },
    );
    test(
      'rejects missing, ambiguous, malformed, combined or extension numbers',
      () {
        for (final number in [
          null,
          '',
          '2025550123',
          '020 7946 0123',
          '0770090012',
          '+44(0)7700900123',
          '+447700900123 ext12',
          '+447700900123 +447700900456',
          '+0 7700900123',
          '+12',
          '+1234567890123456',
          '+447700900123?text=other',
          '+44/7700900123',
        ]) {
          expect(normaliseWhatsAppPhone(number), isNull, reason: '$number');
        }
      },
    );
    test(
      'roundtrips special characters, emoji and line breaks once through URI',
      () {
        const text = 'A&B + #1? 50% café ✨\nNext line';
        final uri = whatsAppChatUri('+447700900123', message: text);
        expect(uri.scheme, 'https');
        expect(uri.host, 'wa.me');
        expect(uri.path, '/447700900123');
        expect(uri.queryParameters, {'text': text});
        expect(Uri.parse(uri.toString()).queryParameters['text'], text);
        expect(whatsAppChatUri('+447700900123').hasQuery, isFalse);
        expect(() => whatsAppChatUri('07700900123'), throwsArgumentError);
      },
    );
    test(
      'uses business timezone across midnight and both DST-fold instants',
      () {
        expect(
          bookingReminderTime(
            DateTime.utc(2026, 9, 5, 23, 30),
            'Europe/London',
          ),
          'Sunday 6 September 2026 at 00:30 BST',
        );
        expect(
          bookingReminderTime(
            DateTime.utc(2026, 10, 25, 0, 30),
            'Europe/London',
          ),
          contains('01:30 BST'),
        );
        expect(
          bookingReminderTime(
            DateTime.utc(2026, 10, 25, 1, 30),
            'Europe/London',
          ),
          contains('01:30 GMT'),
        );
        expect(
          bookingReminderTime(
            DateTime.utc(2026, 9, 6, 8, 30),
            'America/New_York',
          ),
          contains('04:30 EDT (UTC-04:00)'),
        );
      },
    );
    test(
      'uses real business/service/name; omits unknown service and private notes',
      () {
        final message = bookingWhatsAppMessage(
          appointment: booking(),
          clientName: 'Amélie & Jo',
          businessName: 'Jane’s Studio & Co',
          timeZone: 'Europe/London',
        );
        expect(message, contains('Hi Amélie & Jo,'));
        expect(message, contains('Jane’s Studio & Co'));
        expect(message, contains('Cut & colour + finish #1 ✨'));
        expect(message, contains('Sunday 6 September 2026 at 09:30 BST'));
        final unnamed = Appointment(
          id: 'a',
          workspaceId: 'w',
          startTime: DateTime.utc(2026, 9, 6),
          notes: 'PRIVATE NOTE',
        );
        final plain = bookingWhatsAppMessage(
          appointment: unnamed,
          clientName: '',
          businessName: 'Real business',
          timeZone: 'Europe/London',
        );
        expect(plain, startsWith('Hi,\n'));
        expect(plain, isNot(contains('PRIVATE NOTE')));
        expect(plain, isNot(contains('Window clean')));
      },
    );
  });

  group('fresh booking preparation', () {
    test(
      'reads current scoped client and booking, without any mutation operation',
      () async {
        final fixture = ReminderFixture();
        final draft = await fixture.prepare();
        expect(draft.phone, '+447700900123');
        expect(draft.message, contains('09:30 BST'));
        expect(fixture.appointmentReads, 2);
        expect(fixture.clientReads, 2);
      },
    );
    for (final status in ['cancelled', 'completed', 'no_show', 'pending', '']) {
      test('blocks $status bookings', () async {
        final fixture = ReminderFixture()
          ..appointment = booking(status: status);
        await expectLater(
          fixture.prepare(),
          issue(WhatsAppReminderIssue.unavailableBooking),
        );
        expect(fixture.clientReads, 0);
      });
    }
    test('blocks elapsed, started and deleted bookings', () async {
      for (final appointment in [
        booking(start: now.subtract(const Duration(minutes: 1))),
        booking(start: now),
        null,
      ]) {
        final fixture = ReminderFixture()..appointment = appointment;
        await expectLater(
          fixture.prepare(),
          issue(WhatsAppReminderIssue.unavailableBooking),
        );
      }
    });
    test('blocks missing or foreign-workspace clients', () async {
      final unlinked = ReminderFixture()..appointment = booking(contact: null);
      await expectLater(
        unlinked.prepare(),
        issue(WhatsAppReminderIssue.missingClient),
      );
      for (final customer in [
        null,
        client(workspace: 'workspace-other'),
        client(id: 'client-other'),
      ]) {
        final fixture = ReminderFixture()..customer = customer;
        await expectLater(
          fixture.prepare(),
          issue(WhatsAppReminderIssue.missingClient),
        );
      }
    });
    test(
      'missing or invalid phone never makes a recipient-less sharing URL',
      () async {
        for (final phone in [null, '', '2025550123', '07700900123 ext2']) {
          final fixture = ReminderFixture()..customer = client(phone: phone);
          await expectLater(
            fixture.prepare(),
            issue(WhatsAppReminderIssue.invalidPhone),
          );
        }
      },
    );
    test(
      'uses a freshly edited number, not the number from another screen',
      () async {
        final fixture = ReminderFixture()
          ..customer = client(phone: '+33612345678');
        expect((await fixture.prepare()).uri.path, '/33612345678');
      },
    );
    test(
      'missing and invalid timezone cannot silently use device timezone',
      () async {
        for (final settings in [
          null,
          <String, dynamic>{},
          {'timezone': 'not/a-zone'},
        ]) {
          final fixture = ReminderFixture()..settings = settings;
          await expectLater(
            fixture.prepare(),
            issue(WhatsAppReminderIssue.missingBusinessDetails),
          );
        }
        final unnamed = ReminderFixture()
          ..workspace = const Workspace(id: 'workspace-a', name: '');
        await expectLater(
          unnamed.prepare(),
          issue(WhatsAppReminderIssue.missingBusinessDetails),
        );
      },
    );
    test('account/workspace changes during reads prevent handoff', () async {
      for (final changeUser in [true, false]) {
        final fixture = ReminderFixture();
        fixture.onClientRead = (_) async {
          if (changeUser) {
            fixture.userId = 'owner-b';
          } else {
            fixture.workspaceId = 'workspace-b';
          }
          return fixture.customer;
        };
        await expectLater(
          fixture.prepare(),
          issue(WhatsAppReminderIssue.changedAccount),
        );
      }
    });
    test(
      'reschedule or changed client while reading rejects old draft',
      () async {
        for (final changed in [
          booking(start: DateTime.utc(2026, 9, 7, 8)),
          booking(contact: 'client-b'),
        ]) {
          final fixture = ReminderFixture();
          fixture.onAppointmentRead = (read) async =>
              read == 1 ? booking() : changed;
          await expectLater(
            fixture.prepare(),
            issue(WhatsAppReminderIssue.changedBooking),
          );
        }
      },
    );
    test(
      'cancellation, deletion, and edited phone on recheck block handoff',
      () async {
        for (final latest in [booking(status: 'cancelled'), null]) {
          final fixture = ReminderFixture();
          fixture.onAppointmentRead = (read) async =>
              read == 1 ? booking() : latest;
          await expectLater(
            fixture.prepare(),
            issue(WhatsAppReminderIssue.unavailableBooking),
          );
        }
        final fixture = ReminderFixture();
        fixture.onClientRead = (read) async =>
            read == 1 ? client() : client(phone: '+447700900456');
        await expectLater(
          fixture.prepare(),
          issue(WhatsAppReminderIssue.changedBooking),
        );
      },
    );
    test(
      'single booking repository read scopes both workspace and id and only GETs',
      () async {
        final requests = <http.Request>[];
        final supabase = SupabaseClient(
          'https://test.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode([booking().toMap()]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(supabase.dispose);
        final result = await AppointmentsRepository(
          supabase,
        ).getById('workspace-a', 'booking-a');
        expect(result?.id, 'booking-a');
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(
          requests.single.url.queryParameters['workspace_id'],
          'eq.workspace-a',
        );
        expect(requests.single.url.queryParameters['id'], 'eq.booking-a');
      },
    );
  });

  group('booking reminder action', () {
    testWidgets(
      'real detail retains current client, service bundle, add-ons and latest notes after handoff',
      (tester) async {
        final row = {
          ...booking().toMap(),
          'contacts': {'name': 'Amélie & Jo'},
          'services': {'name': 'Cut'},
          'end_time': '2026-09-06T10:00:00Z',
          'appointment_items': [
            {
              'id': 's1',
              'workspace_id': 'workspace-a',
              'item_kind': 'base',
              'source_service_id': 'cut',
              'name': 'Cut',
              'duration_mins': 30,
              'price': 20,
              'position': 0,
            },
            {
              'id': 's2',
              'workspace_id': 'workspace-a',
              'item_kind': 'base',
              'source_service_id': 'colour',
              'name': 'Colour',
              'duration_mins': 45,
              'price': 35,
              'position': 1,
            },
            {
              'id': 's3',
              'workspace_id': 'workspace-a',
              'item_kind': 'add_on',
              'source_add_on_id': 'finish',
              'name': 'Finish',
              'duration_mins': 15,
              'price': 10,
              'position': 2,
            },
          ],
        };
        final latest = Appointment.fromMap({
          ...row,
          'notes': 'Updated private note',
          'price': 65,
        });
        final fixture = ReminderFixture()
          ..appointment = Appointment.fromMap(row);
        fixture.onAppointmentRead = (read) async =>
            read == 1 ? Appointment.fromMap(row) : latest;
        var launches = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workspaceIdProvider.overrideWith((_) async => 'workspace-a'),
              appointmentsProvider.overrideWith((_) async => []),
              clientsProvider.overrideWith((_) async => [client()]),
              allTasksProvider.overrideWith((_) async => []),
              invoicesProvider.overrideWith((_) async => []),
              bookingWhatsAppReminderProvider.overrideWithValue(
                fixture.service,
              ),
              bookingReminderClockProvider.overrideWithValue(() => now),
              whatsAppUrlLauncherProvider.overrideWithValue((_) async {
                launches++;
                return true;
              }),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: AppointmentDetailScreen(appointment: row),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.byKey(const Key('booking-whatsapp-reminder'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(launches, 1);
        final refreshed = tester
            .widget<BookingWhatsAppReminderAction>(
              find.byType(BookingWhatsAppReminderAction),
            )
            .appointment;
        expect(refreshed.clientName, 'Amélie & Jo');
        expect(refreshed.serviceName, 'Cut + Colour');
        expect(refreshed.serviceItems.map((item) => item.name), [
          'Cut',
          'Colour',
          'Finish',
        ]);
        expect(refreshed.serviceItems.last.sourceAddOnId, 'finish');
        expect(refreshed.serviceItems.first.sourceServiceId, 'cut');
        expect(refreshed.notes, 'Updated private note');
        expect(refreshed.price, 65);
        expect(find.text('Walk-in'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'opening another route during preparation prevents a hidden-page handoff',
      (tester) async {
        final pending = Completer<Appointment?>();
        final fixture = ReminderFixture()
          ..onAppointmentRead = (read) async =>
              read == 1 ? pending.future : booking();
        var launches = 0;
        await pumpAction(
          tester,
          fixture,
          launch: (_) async {
            launches++;
            return true;
          },
        );
        await tester.tap(find.text('Send WhatsApp reminder'));
        final context = tester.element(
          find.byType(BookingWhatsAppReminderAction),
        );
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Another screen')),
            ),
          ),
        );
        await tester.pump();
        pending.complete(booking());
        await tester.pumpAndSettle();
        expect(find.text('Another screen'), findsOneWidget);
        expect(launches, 0);
        expect(find.text('WhatsApp didn’t open'), findsNothing);
      },
    );
    testWidgets(
      'fallback belongs to booking screen and disappears on identity change or disposal',
      (tester) async {
        final fixture = ReminderFixture();
        Future<bool> launch(Uri _) async => false;
        await pumpAction(tester, fixture, launch: launch);
        await tester.tap(find.text('Send WhatsApp reminder'));
        await tester.pumpAndSettle();
        expect(find.text('WhatsApp didn’t open'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        fixture.userId = 'owner-b';
        await pumpAction(tester, fixture, launch: launch);
        await tester.pumpAndSettle();
        expect(find.text('+447700900123'), findsNothing);
        expect(find.byType(SelectableText), findsNothing);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Signed out'))),
        );
        expect(find.text('WhatsApp didn’t open'), findsNothing);
        expect(find.text('Signed out'), findsOneWidget);
      },
    );
    testWidgets(
      'explicit tap opens current draft; opening is never described as sent',
      (tester) async {
        final fixture = ReminderFixture();
        final urls = <Uri>[];
        await pumpAction(
          tester,
          fixture,
          launch: (url) async {
            urls.add(url);
            return true;
          },
        );
        expect(urls, isEmpty);
        expect(fixture.appointmentReads, 0);
        await tester.tap(find.text('Send WhatsApp reminder'));
        await tester.pumpAndSettle();
        expect(urls, hasLength(1));
        expect(
          urls.single.queryParameters['text'],
          contains('Jane’s Studio & Co'),
        );
        expect(find.textContaining('then tap Send.'), findsWidgets);
        expect(find.text('Reminder sent'), findsNothing);
        expect(find.text('Send WhatsApp reminder'), findsOneWidget);
      },
    );
    testWidgets('duplicate taps while data loads open only one draft', (
      tester,
    ) async {
      final pending = Completer<Appointment?>();
      final fixture = ReminderFixture()
        ..onAppointmentRead = (read) async =>
            read == 1 ? pending.future : booking();
      var launches = 0;
      await pumpAction(
        tester,
        fixture,
        launch: (_) async {
          launches++;
          return true;
        },
      );
      final button = find.byKey(const Key('booking-whatsapp-reminder'));
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(fixture.appointmentReads, 1);
      expect(launches, 0);
      pending.complete(booking());
      await tester.pumpAndSettle();
      expect(launches, 1);
    });
    testWidgets('missing phone opens real client action without launching', (
      tester,
    ) async {
      final fixture = ReminderFixture()..customer = client(phone: null);
      var launches = 0;
      var clientOpens = 0;
      await pumpAction(
        tester,
        fixture,
        launch: (_) async {
          launches++;
          return true;
        },
        openClient: () async {
          clientOpens++;
        },
      );
      await tester.tap(find.text('Send WhatsApp reminder'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add a UK mobile number'), findsOneWidget);
      await tester.tap(find.text('Open client'));
      await tester.pumpAndSettle();
      expect(clientOpens, 1);
      expect(launches, 0);
    });
    for (final throwsError in [false, true]) {
      testWidgets(
        'launch ${throwsError ? 'exception' : 'false'} keeps draft copyable only on explicit action',
        (tester) async {
          final fixture = ReminderFixture();
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await pumpAction(
            tester,
            fixture,
            launch: (_) async {
              if (throwsError) throw StateError('Unavailable');
              return false;
            },
          );
          await tester.tap(find.text('Send WhatsApp reminder'));
          await tester.pumpAndSettle();
          expect(find.text('WhatsApp didn’t open'), findsOneWidget);
          expect(copied, isNull);
          expect(
            find.textContaining('Workloop hasn’t sent this message.'),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Copy reminder'));
          await tester.tap(find.text('Copy reminder'));
          await tester.pumpAndSettle();
          expect(copied, contains('Cut & colour + finish #1 ✨'));
          expect(find.text('Reminder sent'), findsNothing);
        },
      );
    }
    testWidgets('dispose or account change during preparation never launches', (
      tester,
    ) async {
      for (final dispose in [false, true]) {
        final pending = Completer<Appointment?>();
        final fixture = ReminderFixture()
          ..onAppointmentRead = (_) => pending.future;
        var launches = 0;
        await pumpAction(
          tester,
          fixture,
          launch: (_) async {
            launches++;
            return true;
          },
        );
        await tester.tap(find.text('Send WhatsApp reminder'));
        await tester.pump();
        if (dispose) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          fixture.userId = 'owner-b';
        }
        pending.complete(booking());
        await tester.pumpAndSettle();
        expect(launches, 0);
        expect(tester.takeException(), isNull);
      }
    });
    testWidgets(
      'load failure can retry and never opens a stale cached booking',
      (tester) async {
        final fixture = ReminderFixture()
          ..onAppointmentRead = (_) async => throw StateError('Offline');
        var launches = 0;
        await pumpAction(
          tester,
          fixture,
          launch: (_) async {
            launches++;
            return true;
          },
        );
        await tester.tap(find.text('Send WhatsApp reminder'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not prepare'), findsOneWidget);
        expect(launches, 0);
        fixture.onAppointmentRead = null;
        await tester.tap(find.text('Send WhatsApp reminder'));
        await tester.pumpAndSettle();
        expect(launches, 1);
      },
    );
    testWidgets('completed or elapsed booking has no reminder action', (
      tester,
    ) async {
      for (final appointment in [
        booking(status: 'completed'),
        booking(start: now),
      ]) {
        await pumpAction(tester, ReminderFixture()..appointment = appointment);
        expect(
          find.byKey(const Key('booking-whatsapp-reminder')),
          findsNothing,
        );
      }
    });
    testWidgets(
      'compact screen and large text retain a readable tappable action',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpAction(tester, ReminderFixture(), textScale: 2);
        expect(tester.takeException(), isNull);
        final button = find.byKey(const Key('booking-whatsapp-reminder'));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      },
    );
  });
}
