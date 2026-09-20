import 'package:flutter_test/flutter_test.dart';
// Test-only backend for the production SharedPreferencesAsync adapter.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/client_follow_up_provider.dart';
import 'package:workloop/shared/utils/client_follow_up.dart';

final _now = DateTime.utc(2026, 9, 6, 12);
Client _client({String status = 'active', DateTime? activity}) => Client(
  id: 'client',
  workspaceId: 'workspace',
  name: 'Sample customer',
  phone: '07700 900123',
  email: 'sample@example.test',
  status: status,
  createdAt: _now.subtract(const Duration(days: 300)),
  lastActivityAt: activity,
);

Appointment _visit(
  String id,
  int daysAgo, {
  String status = 'completed',
  String workspace = 'workspace',
}) => Appointment(
  id: id,
  workspaceId: workspace,
  contactId: 'client',
  startTime: _now.subtract(Duration(days: daysAgo)),
  status: status,
);

List<Appointment> _regular({int latest = 42, int gap = 28}) => [
  for (var i = 0; i < 4; i++) _visit('visit-$i', latest + gap * i),
];

List<ClientFollowUp> _followUps({
  List<Appointment>? bookings,
  Client? client,
  List<BookingRequest> requests = const [],
  List<SlateTask> tasks = const [],
  Map<String, DateTime> snoozes = const {},
  DateTime? now,
}) => clientFollowUps(
  clients: [client ?? _client()],
  appointments: bookings ?? _regular(),
  requests: requests,
  tasks: tasks,
  snoozedUntil: snoozes,
  now: now ?? _now,
);

class _Store implements ClientFollowUpSnoozeStore {
  final values = <ClientFollowUpScope, Map<String, DateTime>>{};
  bool fail = false;
  @override
  Future<Map<String, DateTime>> read(ClientFollowUpScope scope) async =>
      Map.of(values[scope] ?? {});
  @override
  Future<void> write(
    ClientFollowUpScope scope,
    Map<String, DateTime> value,
  ) async {
    if (fail) throw StateError('disk unavailable');
    values[scope] = Map.of(value);
  }
}

void main() {
  group('regular-client follow-up', () {
    test('adapts to fortnightly, monthly and quarterly visits with grace', () {
      for (final gap in [14, 28, 90]) {
        final grace = (gap * .25).ceil().clamp(7, 30);
        expect(
          _followUps(
            bookings: _regular(latest: gap + grace - 1, gap: gap),
          ),
          isEmpty,
        );
        final due = _followUps(
          bookings: _regular(latest: gap + grace, gap: gap),
        ).single;
        expect(due.usualDays, gap);
        expect(due.daysSinceVisit, gap + grace);
      }
    });
    test(
      'requires completed regular visits; old imported records are insufficient',
      () {
        expect(_followUps(bookings: []), isEmpty);
        expect(_followUps(bookings: _regular().take(2).toList()), isEmpty);
        for (final status in ['cancelled', 'no_show', 'scheduled']) {
          expect(
            _followUps(
              bookings: [
                _visit('a', 42, status: status),
                _visit('b', 70),
                _visit('c', 98),
              ],
            ),
            isEmpty,
          );
        }
      },
    );
    test('same visit split into services does not manufacture a cadence', () {
      expect(
        _followUps(
          bookings: [_visit('a', 42), _visit('b', 42), _visit('c', 70)],
        ),
        isEmpty,
      );
    });
    test('uses recent median, rejecting strongly irregular histories', () {
      expect(
        _followUps(
          bookings: [
            _visit('a', 50),
            _visit('b', 78),
            _visit('c', 107),
            _visit('d', 134),
          ],
        ).single.usualDays,
        28,
      );
      expect(
        _followUps(
          bookings: [
            _visit('a', 50),
            _visit('b', 57),
            _visit('c', 64),
            _visit('d', 200),
          ],
        ),
        isEmpty,
      );
    });
    test(
      'inactive clients, recent contact edits and existing follow-up tasks are suppressed',
      () {
        expect(_followUps(client: _client(status: 'inactive')), isEmpty);
        expect(
          _followUps(
            client: _client(activity: _now.subtract(const Duration(days: 6))),
          ),
          isEmpty,
        );
        expect(
          _followUps(
            tasks: const [
              SlateTask(
                id: 't',
                workspaceId: 'workspace',
                title: 'Call client',
                contactId: 'client',
              ),
            ],
          ),
          isEmpty,
        );
        expect(
          _followUps(
            tasks: const [
              SlateTask(
                id: 't',
                workspaceId: 'workspace',
                title: 'Call client',
                contactId: 'client',
                status: 'done',
              ),
            ],
          ),
          hasLength(1),
        );
      },
    );
    test(
      'future/current bookings suppress but cancelled or past records do not',
      () {
        expect(
          _followUps(
            bookings: [
              ..._regular(),
              _visit('future', -1, status: 'scheduled'),
            ],
          ),
          isEmpty,
        );
        expect(
          _followUps(
            bookings: [
              ..._regular(),
              _visit('today', 0, status: 'scheduled'),
            ],
          ),
          isEmpty,
        );
        expect(
          _followUps(
            bookings: [
              ..._regular(),
              _visit('cancelled', -1, status: 'cancelled'),
            ],
          ),
          hasLength(1),
        );
      },
    );
    for (final status in ['pending', 'contacted']) {
      test(
        '$status requests suppress by exact normalized phone or email, never just a name',
        () {
          BookingRequest request({String phone = '', String email = ''}) =>
              BookingRequest(
                id: 'r',
                workspaceId: 'workspace',
                name: 'Sample customer',
                phone: phone,
                email: email,
                status: status,
              );
          expect(
            _followUps(requests: [request(phone: '+44 7700 900123')]),
            isEmpty,
          );
          expect(
            _followUps(requests: [request(email: ' SAMPLE@EXAMPLE.TEST ')]),
            isEmpty,
          );
          expect(_followUps(requests: [request()]), hasLength(1));
        },
      );
    }
    test(
      'cross-workspace history and request/task context cannot suppress or create a nudge',
      () {
        expect(
          _followUps(
            bookings: [
              for (var i = 0; i < 3; i++)
                _visit('$i', 42 + i * 28, workspace: 'other'),
            ],
          ),
          isEmpty,
        );
        expect(
          _followUps(
            requests: const [
              BookingRequest(
                id: 'r',
                workspaceId: 'other',
                name: 'Sample',
                phone: '07700900123',
              ),
            ],
            tasks: const [
              SlateTask(
                id: 't',
                workspaceId: 'other',
                title: 'Call',
                contactId: 'client',
              ),
            ],
          ),
          hasLength(1),
        );
      },
    );
    test(
      'snooze expires precisely and no real customer activity is fabricated',
      () {
        final until = _now.add(const Duration(days: 7));
        expect(_followUps(snoozes: {'client': until}), isEmpty);
        expect(
          _followUps(snoozes: {'client': until}, now: until),
          hasLength(1),
        );
        expect(_client().lastActivityAt, isNull);
      },
    );
    test(
      'lead follow-ups retain the 7-day rule without requiring bookings',
      () {
        expect(
          _followUps(
            bookings: [],
            client: _client(
              status: 'lead',
              activity: _now.subtract(const Duration(days: 7)),
            ),
          ).single.usualDays,
          isNull,
        );
        expect(
          _followUps(
            bookings: [],
            client: _client(
              status: 'lead',
              activity: _now.subtract(const Duration(days: 6)),
            ),
          ),
          isEmpty,
        );
      },
    );
  });

  group('local snooze storage', () {
    test(
      'production adapter persists across store instances without crossing accounts',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
        const scope = (userId: 'owner', workspaceId: 'business');
        await snoozeClientFollowUp(
          store: LocalClientFollowUpSnoozeStore(),
          scope: scope,
          clientId: 'client',
          now: _now,
        );
        final reopened = LocalClientFollowUpSnoozeStore();
        expect(
          (await reopened.read(scope))['client'],
          _now.add(const Duration(days: 7)),
        );
        expect(
          await reopened.read((userId: 'other', workspaceId: 'business')),
          isEmpty,
        );
      },
    );
    test(
      'survives a new read and is isolated by both user and workspace',
      () async {
        final store = _Store();
        const scope = (userId: 'owner', workspaceId: 'business');
        await snoozeClientFollowUp(
          store: store,
          scope: scope,
          clientId: 'client',
          now: _now,
        );
        expect(
          (await store.read(scope))['client'],
          _now.add(const Duration(days: 7)),
        );
        expect(
          await store.read((userId: 'another', workspaceId: 'business')),
          isEmpty,
        );
        expect(
          await store.read((userId: 'owner', workspaceId: 'another')),
          isEmpty,
        );
      },
    );
    test(
      'failed writes preserve the saved value; expired entries are pruned on success',
      () async {
        final store = _Store();
        const scope = (userId: 'owner', workspaceId: 'business');
        store.values[scope] = {'old': _now.subtract(const Duration(days: 1))};
        store.fail = true;
        await expectLater(
          snoozeClientFollowUp(
            store: store,
            scope: scope,
            clientId: 'client',
            now: _now,
          ),
          throwsStateError,
        );
        expect(store.values[scope]!.keys, ['old']);
        store.fail = false;
        await snoozeClientFollowUp(
          store: store,
          scope: scope,
          clientId: 'client',
          now: _now,
        );
        expect(store.values[scope]!.keys, ['client']);
      },
    );
  });

  group('tomorrow business-day brief', () {
    Appointment appointment(
      String id,
      String start, {
      String status = 'scheduled',
      int minutes = 60,
    }) => Appointment(
      id: id,
      workspaceId: 'workspace',
      startTime: DateTime.parse(start),
      endTime: DateTime.parse(start).add(Duration(minutes: minutes)),
      status: status,
    );
    test(
      'uses workspace tomorrow rather than device tomorrow across the date line',
      () {
        final brief = buildTomorrowBrief(
          now: DateTime.utc(2026, 9, 6, 13),
          timezone: 'Pacific/Auckland',
          appointments: [
            appointment('today-in-nz', '2026-09-06T22:00:00Z'),
            appointment('tomorrow-in-nz', '2026-09-07T22:00:00Z', minutes: 90),
            appointment('day-after', '2026-09-08T22:00:00Z'),
          ],
        );
        expect(brief.bookings.map((a) => a.id), ['tomorrow-in-nz']);
        expect(brief.bookedMinutes, 90);
      },
    );
    test(
      'includes both repeated-hour instants and adds actual elapsed duration',
      () {
        final brief = buildTomorrowBrief(
          now: DateTime.utc(2026, 10, 24, 12),
          timezone: 'Europe/London',
          appointments: [
            appointment('second', '2026-10-25T01:30:00Z', minutes: 30),
            appointment('first', '2026-10-25T00:30:00Z', minutes: 90),
            appointment(
              'cancelled',
              '2026-10-25T12:00:00Z',
              status: 'cancelled',
            ),
            appointment(
              'completed',
              '2026-10-25T14:00:00Z',
              status: 'completed',
            ),
          ],
        );
        expect(brief.bookings.map((a) => a.id), ['first', 'second']);
        expect(brief.bookedMinutes, 120);
      },
    );
    test(
      'spring clock change uses calendar tomorrow rather than adding 24 hours',
      () {
        final brief = buildTomorrowBrief(
          now: DateTime.utc(2026, 3, 28, 23, 30),
          timezone: 'Europe/London',
          appointments: [
            appointment('late-tomorrow', '2026-03-29T22:30:00Z'),
            appointment('monday', '2026-03-29T23:30:00Z'),
          ],
        );
        expect(brief.bookings.map((a) => a.id), ['late-tomorrow']);
      },
    );
    test(
      'invalid zone is unavailable rather than an invented empty schedule',
      () {
        expect(
          () => buildTomorrowBrief(
            now: _now,
            timezone: 'Unknown/Place',
            appointments: [],
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
