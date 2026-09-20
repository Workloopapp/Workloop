import 'package:device_calendar/device_calendar.dart' as device;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as contacts;
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_settings_provider.dart';
import '../../shared/repositories/appointments_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'import_models.dart';

typedef CalendarImportStep = Future<void> Function();

Future<void> executeCalendarImportBooking({
  required CalendarImportStep validateSchedule,
  required CalendarImportStep createBookingWorkflow,
}) async {
  try {
    await validateSchedule();
  } on AppointmentScheduleException catch (error) {
    if (error.issue != AppointmentScheduleIssue.conflict) rethrow;
    // Let the atomic workflow arbitrate this conflict. A retry can see the
    // booking committed by its previous response and recover by idempotency.
  }
  await createBookingWorkflow();
}

String calendarImportFailureMessage(Object error) {
  if (error is AppointmentScheduleException) {
    return switch (error.issue) {
      AppointmentScheduleIssue.workingHours =>
        '${error.message} Create it manually if you want to confirm an exception.',
      AppointmentScheduleIssue.conflict =>
        '${error.message} Deselect it or change the source event time, then reload.',
      AppointmentScheduleIssue.other =>
        '${error.message} Review the event and try again.',
    };
  }
  return 'Could not create this booking. Check your connection and try again.';
}

class CalendarImportScreen extends ConsumerStatefulWidget {
  const CalendarImportScreen({super.key});

  @override
  ConsumerState<CalendarImportScreen> createState() =>
      _CalendarImportScreenState();
}

class _CalendarImportScreenState extends ConsumerState<CalendarImportScreen> {
  final device.DeviceCalendarPlugin _calendar = device.DeviceCalendarPlugin();
  List<device.Calendar> _calendars = const [];
  List<device.Event> _events = const [];
  final Set<String> _selected = {};
  final Map<String, String> _eventFailures = {};
  String? _calendarId;
  String? _clientId;
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now().add(const Duration(days: 90));
  bool _loading = false;
  bool _importing = false;
  bool _permissionDenied = false;
  String? _message;

  Future<void> _loadCalendars() async {
    if (_loading || _importing) return;
    setState(() {
      _loading = true;
      _permissionDenied = false;
      _message = null;
    });
    try {
      var permission = await _calendar.hasPermissions();
      if (permission.data != true) {
        permission = await _calendar.requestPermissions();
      }
      if (permission.data != true) {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _message =
                'Calendar access is off. Enable it in system settings to choose events.';
          });
        }
        return;
      }
      final result = await _calendar.retrieveCalendars();
      final calendars = result.data?.toList() ?? const <device.Calendar>[];
      if (!mounted) return;
      setState(() {
        _permissionDenied = false;
        _calendars = calendars;
        _calendarId =
            calendars
                .where((calendar) => calendar.isDefault == true)
                .map((calendar) => calendar.id)
                .firstOrNull ??
            calendars.map((calendar) => calendar.id).firstOrNull;
        _message = calendars.isEmpty
            ? 'No readable calendars were found.'
            : null;
      });
      if (_calendarId != null) await _loadEvents();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Calendars could not be loaded. Check permission and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSettings() async {
    try {
      await contacts.FlutterContacts.permissions.openSettings();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System settings could not be opened')),
      );
    }
  }

  Future<void> _loadEvents() async {
    if (_calendarId == null || _importing) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final result = await _calendar.retrieveEvents(
        _calendarId,
        device.RetrieveEventsParams(startDate: _from, endDate: _to),
      );
      final events =
          (result.data?.toList() ?? const <device.Event>[])
              .where((event) => event.start != null)
              .where((event) => event.status != device.EventStatus.Canceled)
              .toList()
            ..sort((a, b) => a.start!.compareTo(b.start!));
      if (!mounted) return;
      setState(() {
        _events = events;
        _selected.clear();
        _eventFailures.clear();
        _message = events.isEmpty
            ? 'No events were found in this calendar and date range.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Events could not be read. Try another calendar or date range.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    if (_loading || _importing) return;
    final from = await showWorkloopDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      title: 'Import from',
    );
    if (from == null || !mounted) return;
    final to = await showWorkloopDatePicker(
      context: context,
      initialDate: _to.isBefore(from)
          ? from.add(const Duration(days: 30))
          : _to,
      firstDate: from,
      lastDate: from.add(const Duration(days: 730)),
      title: 'Import until',
    );
    if (to == null || !mounted) return;
    setState(() {
      _from = from;
      _to = to.add(const Duration(hours: 23, minutes: 59));
    });
    await _loadEvents();
  }

  Future<void> _import() async {
    if (_importing || _selected.isEmpty || _clientId == null) return;
    final selectedIds = Set<String>.of(_selected);
    final chosen = _events
        .where((event) => selectedIds.contains(_id(event)))
        .toList();
    if (chosen.isEmpty) return;
    setState(() {
      _importing = true;
      _message = null;
      _eventFailures.removeWhere((id, _) => selectedIds.contains(id));
    });
    var imported = 0;
    final completedIds = <String>{};
    final failures = <({String eventId, String title, String reason})>[];
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null) throw StateError('Workspace unavailable');
      final settings = await ref.read(workspaceSettingsProvider.future);
      final workingHours = settings?['working_hours'] is Map
          ? Map<String, dynamic>.from(settings!['working_hours'] as Map)
          : <String, dynamic>{};
      final repository = ref.read(appointmentsRepositoryProvider);
      for (final event in chosen) {
        final eventId = _id(event);
        final start = event.start!.toLocal();
        final candidateEnd =
            event.end?.toLocal() ?? start.add(const Duration(hours: 1));
        final end = candidateEnd.isAfter(start)
            ? candidateEnd
            : start.add(const Duration(hours: 1));
        final title = event.title?.trim().isNotEmpty == true
            ? event.title!.trim()
            : 'Imported booking';
        final notes = [
          event.description?.trim(),
          'Imported once from device calendar.',
          if (event.allDay == true) 'Originally an all-day event.',
        ].whereType<String>().where((value) => value.isNotEmpty).join('\n\n');
        final idempotencyKey = calendarImportIdempotencyKey(
          calendarId: event.calendarId ?? _calendarId!,
          eventId: event.eventId,
          startTime: start,
          endTime: end,
          title: title,
          location: event.location,
        );
        try {
          await executeCalendarImportBooking(
            validateSchedule: () => repository.ensureScheduleAvailable(
              workspaceId: workspaceId,
              startTime: start,
              endTime: end,
              workingHours: workingHours,
            ),
            createBookingWorkflow: () async {
              await repository.createBookingWorkflow(
                workspaceId: workspaceId,
                idempotencyKey: idempotencyKey,
                contactId: _clientId!,
                startTime: start,
                endTime: end,
                price: 0,
                title: title,
                notes: notes,
                location: event.location,
                notificationTitle: 'Calendar event imported',
                notificationBody: '$title was added to your schedule.',
              );
            },
          );
          imported++;
          completedIds.add(eventId);
        } catch (error) {
          failures.add((
            eventId: eventId,
            title: event.title?.trim().isNotEmpty == true
                ? event.title!.trim()
                : 'Untitled event',
            reason: calendarImportFailureMessage(error),
          ));
        }
      }
      final result = reconcileImportAttempt(
        attempted: chosen.map(_id),
        completed: completedIds,
      );
      final summary = failures.isEmpty
          ? '$imported ${imported == 1 ? 'booking was' : 'bookings were'} created.'
          : '$imported ${imported == 1 ? 'booking was' : 'bookings were'} created. '
                '${result.retryable.length} ${result.retryable.length == 1 ? 'event remains' : 'events remain'} selected to retry.';
      if (mounted) {
        setState(() {
          _events = _events
              .where((event) => !result.completed.contains(_id(event)))
              .toList();
          _selected
            ..removeAll(result.completed)
            ..addAll(result.retryable);
          _eventFailures
            ..removeWhere((id, _) => result.completed.contains(id))
            ..addEntries(
              failures.map(
                (failure) => MapEntry(failure.eventId, failure.reason),
              ),
            );
          _message = summary;
        });
      }
      ref.invalidate(appointmentsProvider);
      if (!mounted) return;
      if (imported > 0) {
        SlateHaptics.success();
      } else {
        SlateHaptics.warning();
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Calendar import complete'),
          content: Text(
            failures.isEmpty
                ? summary
                : [
                    summary,
                    ...failures
                        .take(3)
                        .map(
                          (failure) => '${failure.title}: ${failure.reason}',
                        ),
                    if (failures.length > 3)
                      '${failures.length - 3} more failed events remain selected.',
                  ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted && failures.isEmpty) Navigator.pop(context, imported);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The selected events could not be imported. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _id(device.Event event) {
    return event.eventId ??
        '${event.calendarId}-${event.title}-${event.start?.millisecondsSinceEpoch}';
  }

  String _date(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _time(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider).value ?? const <Client>[];
    return WorkloopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkloopRouteHeader(title: 'Import calendar'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Review a one-time snapshot before creating any bookings. Your source calendar is never changed.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_calendars.isEmpty) ...[
            WorkloopPrimaryButton(
              label: _loading ? 'Loading calendars…' : 'Choose a calendar',
              icon: LucideIcons.calendarDays,
              onPressed: _loading ? null : _loadCalendars,
            ),
            if (_permissionDenied) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: WorkloopTextButton(
                  label: 'Open system settings',
                  onPressed: _openSettings,
                ),
              ),
            ],
          ] else ...[
            WorkloopFieldLabel(
              'Calendar',
              isRequired: true,
              style: TextStyle(
                color: AppColors.of(context).t2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            WorkloopPickerField<String>(
              value: _calendarId,
              title: 'Choose calendar',
              hint: 'Choose calendar',
              leadingIcon: LucideIcons.calendarDays,
              options: _calendars
                  .where((calendar) => calendar.id != null)
                  .map(
                    (calendar) => WorkloopPickerOption(
                      value: calendar.id!,
                      label: calendar.name ?? 'Calendar',
                      subtitle: calendar.accountName,
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (_importing) return;
                setState(() => _calendarId = value);
                await _loadEvents();
              },
              enabled: !_importing,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Date range',
              style: TextStyle(
                color: AppColors.of(context).t2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            WorkloopSurface(
              onTap: _importing ? null : _pickRange,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.calendarRange,
                    color: AppColors.of(context).t3,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${_date(_from)} — ${_date(_to)}',
                      style: TextStyle(
                        color: AppColors.of(context).t1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    color: AppColors.of(context).t3,
                  ),
                ],
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              container: true,
              liveRegion: true,
              label: _message!,
              child: ExcludeSemantics(
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: AppSpacing.lg),
            const Center(child: CircularProgressIndicator()),
          ] else if (_events.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                const Expanded(child: WorkloopSectionHeader(label: 'Events')),
                WorkloopTextButton(
                  label: _selected.length == _events.length
                      ? 'Clear'
                      : 'Select all',
                  onPressed: _importing
                      ? null
                      : () => setState(() {
                          if (_selected.length == _events.length) {
                            _selected.clear();
                          } else {
                            _selected.addAll(_events.map(_id));
                          }
                        }),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            WorkloopSurface(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    final id = _id(event);
                    final start = event.start!.toLocal();
                    final failure = _eventFailures[id];
                    return WorkloopListRow(
                      flat: true,
                      onTap: _importing
                          ? null
                          : () => setState(() {
                              if (!_selected.add(id)) _selected.remove(id);
                            }),
                      showDivider: index != _events.length - 1,
                      leading: Checkbox.adaptive(
                        value: _selected.contains(id),
                        onChanged: _importing
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  _selected.add(id);
                                } else {
                                  _selected.remove(id);
                                }
                              }),
                      ),
                      title: Text(
                        event.title?.trim().isNotEmpty == true
                            ? event.title!.trim()
                            : 'Untitled event',
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.allDay == true
                                ? '${_date(start)} · All day'
                                : '${_date(start)} · ${_time(start)}${event.end == null ? '' : '–${_time(event.end!.toLocal())}'}',
                            style: TextStyle(color: AppColors.of(context).t3),
                          ),
                          if (failure != null) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              failure,
                              style: TextStyle(
                                color: AppColors.of(context).error,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            WorkloopFieldLabel(
              'Client for selected events',
              isRequired: true,
              style: TextStyle(
                color: AppColors.of(context).t2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            WorkloopPickerField<String>(
              value: _clientId,
              title: 'Choose client',
              hint: 'Choose a client',
              searchHint: 'Search clients',
              searchable: true,
              leadingIcon: LucideIcons.user,
              options: clients
                  .map(
                    (client) => WorkloopPickerOption(
                      value: client.id,
                      label: client.name,
                      subtitle: client.address,
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _clientId = value),
              enabled: !_importing,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Imported bookings start at £0 so you can confirm the service and price safely afterward.',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            WorkloopPrimaryButton(
              label: _importing ? 'Importing…' : 'Import selected events',
              icon: LucideIcons.download,
              onPressed: _importing || _selected.isEmpty || _clientId == null
                  ? null
                  : _import,
            ),
          ],
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
