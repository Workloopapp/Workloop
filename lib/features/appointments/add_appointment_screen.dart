import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/notifications_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/providers/workspace_settings_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/currency_format.dart';
import '../../shared/utils/appointment_recurrence.dart';
import '../../shared/utils/duration_format.dart';
import '../../shared/utils/workflow_idempotency.dart';
import '../../shared/utils/working_hours.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import '../../shared/widgets/additional_services_picker.dart';
import '../clients/widgets/client_form.dart';
import 'booking_schedule_warning_sheet.dart';
import 'recurring_booking_fields.dart';

part 'add_appointment_logic.dart';
part 'add_appointment_widgets.dart';

class AddAppointmentScreen extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  final String? initialClientId;

  const AddAppointmentScreen({
    super.key,
    this.initialDate,
    this.initialClientId,
  });

  @override
  ConsumerState<AddAppointmentScreen> createState() =>
      _AddAppointmentScreenState();
}

class _AddAppointmentScreenState extends ConsumerState<AddAppointmentScreen> {
  static const _customServiceId = '__custom_service__';

  String? _selectedClientId;
  String? _selectedServiceId;
  List<String> _selectedServiceIds = [];
  int _serviceSelectionRevision = 0;
  String? _selectedServiceName;
  List<ServiceAddOn> _availableServiceAddOns = const [];
  final Set<String> _selectedAddOnIds = {};
  bool _loadingServiceAddOns = false;
  double _selectedServiceBasePrice = 0;
  int _selectedServiceBaseDuration = 60;
  bool _creatingClient = false;
  bool _customService = false;
  DateTime _selectedDate = DateTime.now();
  int _selectedHour = 9;
  int _selectedMinute = 0;
  int _selectedDuration = 60;
  bool _customDuration = false;
  String _locationMode = 'business';
  bool _createPaymentDue = false;
  int _repeatIntervalWeeks = 0;
  int _repeatOccurrences = 4;
  final _newClientNameController = TextEditingController();
  final _newClientPhoneController = TextEditingController();
  final _newClientEmailController = TextEditingController();
  final _newClientAddressController = TextEditingController();
  final _customServiceController = TextEditingController();
  final _priceController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final List<TextEditingController> _taskControllers = [];
  bool _saving = false;
  Map<String, dynamic>? _pendingWorkflowPayload;
  String? _submissionUserId;
  bool _allowPop = false;
  final String _workflowIdempotencyKey = createWorkflowIdempotencyKey();
  late DateTime _initialDate;
  late String? _initialClientId;

  @override
  void initState() {
    super.initState();
    _selectedClientId = widget.initialClientId;
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
    }
    _initialDate = _selectedDate;
    _initialClientId = _selectedClientId;
    for (final controller in [
      _newClientNameController,
      _newClientPhoneController,
      _newClientEmailController,
      _newClientAddressController,
      _customServiceController,
      _priceController,
      _durationController,
      _locationController,
      _notesController,
    ]) {
      controller.addListener(_handleDraftChanged);
    }
  }

  void _handleDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _newClientNameController.dispose();
    _newClientPhoneController.dispose();
    _newClientEmailController.dispose();
    _newClientAddressController.dispose();
    _customServiceController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    for (final controller in _taskControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showWorkloopDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await _showAppointmentTimePicker(
      context: context,
      initialHour: _selectedHour,
      initialMinute: _selectedMinute,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedHour = picked.hour;
      _selectedMinute = picked.minute;
    });
  }

  bool get _hasDraftChanges {
    final dateChanged =
        _selectedDate.year != _initialDate.year ||
        _selectedDate.month != _initialDate.month ||
        _selectedDate.day != _initialDate.day;
    return _selectedClientId != _initialClientId ||
        _creatingClient ||
        _newClientNameController.text.trim().isNotEmpty ||
        _newClientPhoneController.text.trim().isNotEmpty ||
        _newClientEmailController.text.trim().isNotEmpty ||
        _newClientAddressController.text.trim().isNotEmpty ||
        _selectedServiceId != null ||
        _selectedAddOnIds.isNotEmpty ||
        _customService ||
        _customServiceController.text.trim().isNotEmpty ||
        _priceController.text.trim().isNotEmpty ||
        _durationController.text.trim() != '60' ||
        dateChanged ||
        _selectedHour != 9 ||
        _selectedMinute != 0 ||
        _locationMode != 'business' ||
        _locationController.text.trim().isNotEmpty ||
        _notesController.text.trim().isNotEmpty ||
        _taskControllers.any(
          (controller) => controller.text.trim().isNotEmpty,
        ) ||
        _createPaymentDue ||
        _repeatIntervalWeeks != 0;
  }

  Future<void> _handleBack() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_hasDraftChanges) {
      await _leaveScreen();
      return;
    }
    final decision = await showWorkloopDraftConfirmation(
      context,
      title: _pendingWorkflowPayload == null
          ? 'Save this booking?'
          : 'Confirm this save?',
      message: _pendingWorkflowPayload == null
          ? 'Your booking details have not been saved yet.'
          : 'The last save could not be confirmed. Retry the same details to check it safely. If you leave, check Bookings before adding it again.',
      saveLabel: _pendingWorkflowPayload == null
          ? 'Save booking'
          : 'Retry save',
      canSave: (_canSave || _pendingWorkflowPayload != null) && !_saving,
    );
    if (!mounted) return;
    switch (decision) {
      case WorkloopDraftDecision.save:
        await _save();
        return;
      case WorkloopDraftDecision.discard:
        await _leaveScreen();
        return;
      case WorkloopDraftDecision.stay:
        return;
    }
  }

  Future<void> _leaveScreen() async {
    if (!_allowPop && mounted) setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) workloopGoBack(context, fallbackLocation: '/work');
  }

  Future<void> _save() async {
    if ((!_canSave && _pendingWorkflowPayload == null) || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final retrying = _pendingWorkflowPayload != null;
    setState(() => _saving = true);
    try {
      if (retrying) {
        await _submitPendingWorkflow();
        return;
      }
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (!mounted) return;
      if (workspaceId == null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your workspace is unavailable. Reload Workloop and try again.',
            ),
            backgroundColor: AppColors.of(context).error,
          ),
        );
        return;
      }

      final userId = ref.read(authRepositoryProvider).currentUserId;
      final settings = await ref.read(workspaceSettingsProvider.future);
      if (!mounted) return;
      final recurrenceTimezone = _repeatIntervalWeeks == 0
          ? null
          : settings?['timezone'] as String?;
      if (_repeatIntervalWeeks > 0 &&
          (recurrenceTimezone == null || recurrenceTimezone.trim().isEmpty)) {
        throw const RecurringBookingTimeException(
          'Set a business timezone in Settings before repeating bookings.',
        );
      }
      final selectedWallClock = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedHour,
        _selectedMinute,
      );
      final startTime = recurrenceTimezone == null
          ? DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _selectedHour,
              _selectedMinute,
            ).toUtc()
          : recurringBookingInstant(selectedWallClock, recurrenceTimezone);
      final duration =
          int.tryParse(_durationController.text.trim()) ?? _selectedDuration;
      final price = double.tryParse(_priceController.text.trim()) ?? 0;
      final endTime = startTime.add(Duration(minutes: duration));
      final recurrenceRule = _repeatIntervalWeeks == 0
          ? null
          : 'FREQ=WEEKLY;INTERVAL=$_repeatIntervalWeeks';
      final repeatOccurrences = _repeatIntervalWeeks == 0
          ? 1
          : _repeatOccurrences;
      final serviceName = _customService
          ? _customServiceController.text.trim()
          : _selectedServiceName;
      final serviceLabel = serviceName?.isNotEmpty == true
          ? serviceName!
          : 'Booking';
      final workingHours = settings?['working_hours'] is Map
          ? Map<String, dynamic>.from(settings!['working_hours'] as Map)
          : <String, dynamic>{};
      final location = _locationTextWithDefault(
        settings?['business_address'] as String?,
        newClientAddress: _creatingClient
            ? _newClientAddressController.text
            : null,
      );

      final repository = ref.read(appointmentsRepositoryProvider);
      final scheduleReview = await repository.reviewSchedule(
        workspaceId: workspaceId,
        startTime: startTime,
        endTime: endTime,
        workingHours: workingHours,
        workingHoursTimezone: settings?['timezone'] as String?,
        recurrenceRule: recurrenceRule,
        repeatOccurrences: repeatOccurrences,
      );
      if (!mounted) return;
      final proceed = await showBookingScheduleWarning(context, scheduleReview);
      if (!proceed) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      final taskTitles = _taskControllers
          .map((controller) => controller.text.trim())
          .where((title) => title.isNotEmpty)
          .toList();
      final payload = buildBookingWorkflowPayload(
        workspaceId: workspaceId,
        idempotencyKey: _workflowIdempotencyKey,
        contactId: _creatingClient ? null : _selectedClientId,
        newContactName: _creatingClient ? _newClientNameController.text : null,
        newContactPhone: _creatingClient
            ? _newClientPhoneController.text
            : null,
        newContactEmail: _creatingClient
            ? _newClientEmailController.text
            : null,
        newContactAddress: _creatingClient
            ? _newClientAddressController.text
            : null,
        serviceId: _customService ? null : _selectedServiceId,
        addOnIds: _selectedAddOnIds.toList(growable: false),
        serviceIds: List<String>.of(_selectedServiceIds),
        title: serviceName,
        startTime: startTime,
        endTime: endTime,
        price: price,
        notes: _notesController.text,
        location: location,
        recurrenceRule: recurrenceRule,
        recurrenceTimezone: recurrenceTimezone,
        repeatOccurrences: repeatOccurrences,
        taskTitles: taskTitles,
        taskDueDate: _selectedDate,
        createPaymentDue: _createPaymentDue && price > 0,
        paymentNote: 'Payment due for $serviceLabel',
        notificationTitle: repeatOccurrences > 1
            ? 'Repeating booking created'
            : 'New booking created',
        notificationBody: repeatOccurrences > 1
            ? 'Created $repeatOccurrences bookings for $serviceLabel.'
            : '$serviceLabel booked for ${_formatAppointmentDate(_selectedDate)}.',
        allowOverlap: scheduleReview.conflictCount > 0,
      );

      if (!mounted) return;
      if (ref.read(workspaceIdProvider).value != workspaceId ||
          ref.read(authRepositoryProvider).currentUserId != userId) {
        throw StateError('The account changed before saving.');
      }
      _submissionUserId = userId;
      _pendingWorkflowPayload = payload;
      await _submitPendingWorkflow();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (!retrying && bookingWorkflowDefinitelyRejected(error)) {
          _pendingWorkflowPayload = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is RecurringBookingTimeException
                ? error.message
                : error is AppointmentScheduleException
                ? error.message
                : _pendingWorkflowPayload != null
                ? 'Save not confirmed. Retry save to safely check the same booking details.'
                : 'The booking could not be saved. Please try again.',
          ),
          backgroundColor: AppColors.of(context).error,
        ),
      );
    }
  }

  Future<void> _submitPendingWorkflow() async {
    final payload = _pendingWorkflowPayload!;
    if (ref.read(workspaceIdProvider).value != payload['workspace_id'] ||
        ref.read(authRepositoryProvider).currentUserId != _submissionUserId) {
      throw StateError('Return to the original workspace to retry this save.');
    }
    await ref
        .read(appointmentsRepositoryProvider)
        .createBookingWorkflowFromPayload(payload);
    if (!mounted) return;
    _pendingWorkflowPayload = null;
    ref.invalidate(appointmentsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(allTasksProvider);
    ref.invalidate(clientsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
    await _leaveScreen();
  }

  bool get _canSave {
    final hasClient =
        _selectedClientId != null ||
        (_creatingClient && _newClientNameController.text.trim().isNotEmpty);
    final hasService =
        (_selectedServiceId != null && !_customService) ||
        (_customService && _customServiceController.text.trim().isNotEmpty);
    final price = double.tryParse(_priceController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    return hasClient &&
        hasService &&
        !_loadingServiceAddOns &&
        price != null &&
        price >= 0 &&
        duration != null &&
        duration > 0 &&
        (_selectedServiceIds.length < 2 ||
            (duration <= 1440 && price <= 1000000));
  }

  int get _selectedDurationValue =>
      int.tryParse(_durationController.text.trim()) ?? _selectedDuration;

  void _setDuration(int minutes) {
    setState(() {
      _selectedDuration = minutes;
      _durationController.text = '$minutes';
      _customDuration = false;
    });
  }

  void _showCustomDuration() {
    setState(() {
      _customDuration = true;
    });
  }

  Future<void> _selectService(
    String? value,
    List<Map<String, dynamic>> services,
  ) async {
    if (value == _customServiceId) {
      _serviceSelectionRevision++;
      setState(() {
        _selectedServiceId = value;
        _selectedServiceIds = [];
        _customService = true;
        _selectedServiceName = null;
        _availableServiceAddOns = const [];
        _selectedAddOnIds.clear();
        _loadingServiceAddOns = false;
        _selectedServiceBasePrice = 0;
        _selectedServiceBaseDuration = 60;
        _priceController.clear();
        _durationController.text = '60';
        _selectedDuration = 60;
        _customDuration = false;
      });
      return;
    }
    await _updateSelectedServices(value == null ? [] : [value], services);
  }

  Future<void> _updateSelectedServices(
    List<String> ids,
    List<Map<String, dynamic>> services,
  ) async {
    final revision = ++_serviceSelectionRevision;
    final selected = ids
        .map((id) => services.firstWhere((service) => service['id'] == id))
        .toList();
    final price = selected.fold<double>(
      0,
      (total, service) => total + (service['price'] as num).toDouble(),
    );
    final duration = selected.fold<int>(
      0,
      (total, service) => total + (service['duration_mins'] as num).toInt(),
    );
    setState(() {
      _selectedServiceIds = List.of(ids);
      _selectedServiceId = ids.firstOrNull;
      _customService = false;
      _selectedServiceName = selected
          .map((service) => service['name'])
          .join(' + ');
      _selectedServiceBasePrice = price;
      _selectedServiceBaseDuration = duration;
      _availableServiceAddOns = const [];
      _selectedAddOnIds.clear();
      _loadingServiceAddOns = ids.isNotEmpty;
      _selectedDuration = duration;
      _customDuration = ![30, 45, 60, 90, 120].contains(duration);
      _priceController.text = currencyInputValue(price);
      _durationController.text = '$duration';
    });
    if (ids.isEmpty) return;
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null) throw StateError('Workspace unavailable');
      final groups = await Future.wait(
        ids.toSet().map(
          (id) => ref
              .read(servicesRepositoryProvider)
              .listAddOns(
                workspaceId: workspaceId,
                serviceId: id,
                includeInactive: false,
              ),
        ),
      );
      if (!mounted || revision != _serviceSelectionRevision) return;
      final addOnsById = <String, ServiceAddOn>{};
      for (final addOn in groups.expand((group) => group)) {
        addOnsById.putIfAbsent(addOn.id, () => addOn);
      }
      setState(() {
        _availableServiceAddOns = addOnsById.values.toList(growable: false);
        _loadingServiceAddOns = false;
      });
    } catch (_) {
      if (!mounted || revision != _serviceSelectionRevision) return;
      setState(() {
        _availableServiceAddOns = const [];
        _loadingServiceAddOns = false;
      });
    }
  }

  void _setAddOnSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedAddOnIds.length >= 8) return;
        _selectedAddOnIds.add(id);
      } else {
        _selectedAddOnIds.remove(id);
      }
      final composition = appointmentComposition(
        baseDurationMins: _selectedServiceBaseDuration,
        basePrice: _selectedServiceBasePrice,
        addOns: _availableServiceAddOns,
        selectedAddOnIds: _selectedAddOnIds,
      );
      _selectedDuration = composition.durationMins;
      _customDuration = ![
        30,
        45,
        60,
        90,
        120,
      ].contains(composition.durationMins);
      _durationController.text = '${composition.durationMins}';
      _priceController.text = currencyInputValue(composition.price);
    });
  }

  void _selectClient(String? clientId, List<Client> clients) {
    setState(() {
      _selectedClientId = clientId;
      if (_locationMode != 'client' || clientId == null) return;
      for (final client in clients) {
        final address = client.address?.trim() ?? '';
        if (client.id == clientId && address.isNotEmpty) {
          _locationController.text = address;
          break;
        }
      }
    });
  }

  void _setLocationMode(String mode, List<Client> clients) {
    setState(() {
      _locationMode = mode;
      if (mode != 'client' || _selectedClientId == null) return;
      for (final client in clients) {
        final address = client.address?.trim() ?? '';
        if (client.id == _selectedClientId && address.isNotEmpty) {
          _locationController.text = address;
          break;
        }
      }
    });
  }

  String? _locationTextWithDefault(
    String? businessAddress, {
    String? newClientAddress,
  }) {
    final custom = _locationController.text.trim();
    if (_locationMode == 'business') {
      if (custom.isNotEmpty) return custom;
      final address = businessAddress?.trim();
      return address?.isNotEmpty == true ? address : 'Business location';
    }
    if (_locationMode == 'client') {
      final inlineAddress = newClientAddress?.trim();
      if (custom.isEmpty && inlineAddress?.isNotEmpty == true) {
        return inlineAddress;
      }
      return custom.isEmpty ? 'Client location' : custom;
    }
    if (_locationMode == 'online') {
      return custom.isEmpty ? 'Online / phone' : custom;
    }
    return custom.isEmpty ? null : custom;
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    final services = ref.watch(servicesProvider);
    final workspaceSettings = ref.watch(workspaceSettingsProvider);
    final existingAppointments = ref.watch(appointmentsProvider);

    final appointmentStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedHour,
      _selectedMinute,
    );
    final endTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedHour,
      _selectedMinute,
    ).add(Duration(minutes: _selectedDurationValue));
    final endStr =
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    final workingHours = workspaceSettings.value?['working_hours'] is Map
        ? Map<String, dynamic>.from(
            workspaceSettings.value!['working_hours'] as Map,
          )
        : <String, dynamic>{};
    final insideWorkingHours =
        workingHours.isEmpty ||
        isWithinWorkingHours(
          hours: workingHours,
          start: appointmentStart,
          end: endTime,
        );
    final dayHoursLabel = workingHours.isEmpty
        ? null
        : formatWorkingHourValue(
            workingHoursValueForDate(workingHours, appointmentStart),
          );
    final conflicts = (existingAppointments.value ?? const []).where((
      appointment,
    ) {
      if (appointment['status'] == 'cancelled') return false;
      final start = DateTime.tryParse(
        appointment['start_time']?.toString() ?? '',
      )?.toLocal();
      final end = DateTime.tryParse(
        appointment['end_time']?.toString() ?? '',
      )?.toLocal();
      if (start == null || end == null) return false;
      return start.isBefore(endTime) && end.isAfter(appointmentStart);
    }).toList();

    return PopScope(
      canPop: _allowPop || !_hasDraftChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const Positioned.fill(child: WorkloopTexturedBackdrop()),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageX,
                      AppSpacing.screenTop,
                      AppSpacing.pageX,
                      0,
                    ),
                    child: WorkloopRouteHeader(
                      title: 'New booking',
                      backSemanticLabel: 'Back to bookings',
                      onBack: _handleBack,
                      trailing: _BookingSaveAction(
                        label: _pendingWorkflowPayload != null
                            ? 'Retry save'
                            : _repeatIntervalWeeks == 0
                            ? 'Add'
                            : 'Add $_repeatOccurrences',
                        loading: _saving,
                        enabled: _canSave || _pendingWorkflowPayload != null,
                        onTap: _save,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_pendingWorkflowPayload != null && !_saving)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageX,
                        0,
                        AppSpacing.pageX,
                        AppSpacing.md,
                      ),
                      child: Text(
                        ref.watch(workspaceIdProvider).value !=
                                    _pendingWorkflowPayload!['workspace_id'] ||
                                ref
                                        .watch(authRepositoryProvider)
                                        .currentUserId !=
                                    _submissionUserId
                            ? 'Return to the original workspace to confirm this save.'
                            : 'Save not confirmed. Your details are kept unchanged. Retry save to check safely without creating duplicates.',
                        style: TextStyle(color: AppColors.of(context).t2),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageX,
                        0,
                        AppSpacing.pageX,
                        AppSpacing.xxl,
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ExcludeFocus(
                        excluding: _saving || _pendingWorkflowPayload != null,
                        child: AbsorbPointer(
                          absorbing: _saving || _pendingWorkflowPayload != null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Client ──────────────────────────────────────
                              const _AppointmentSectionLabel(
                                'CLIENT',
                                isRequired: true,
                                subtitle: 'Choose who this booking is for.',
                              ),
                              const SizedBox(height: 8),
                              clients.when(
                                loading: () =>
                                    const _AppointmentSkeleton(height: 54),
                                error: (_, _) => _AppointmentErrorBox(
                                  'Could not load clients',
                                  onRetry: () =>
                                      ref.invalidate(clientsProvider),
                                ),
                                data: (data) => Column(
                                  children: [
                                    if (!_creatingClient)
                                      WorkloopPickerField<String>(
                                        value: _selectedClientId,
                                        title: 'Choose a client',
                                        hint: 'Select client',
                                        searchHint: 'Search clients',
                                        searchable: true,
                                        leadingIcon: LucideIcons.users,
                                        options: data
                                            .map(
                                              (client) => WorkloopPickerOption(
                                                value: client.id,
                                                label: client.name,
                                                subtitle:
                                                    client.address
                                                            ?.trim()
                                                            .isNotEmpty ==
                                                        true
                                                    ? client.address!.trim()
                                                    : null,
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (value) =>
                                            _selectClient(value, data),
                                      ),
                                    if (_creatingClient) ...[
                                      _AppointmentTextInput(
                                        controller: _newClientNameController,
                                        label: 'Client name',
                                        isRequired: true,
                                        hint: 'Client name',
                                        icon: LucideIcons.user,
                                        onChanged: (_) => setState(() {}),
                                      ),
                                      const SizedBox(height: 10),
                                      _ResponsiveBookingPair(
                                        first: _AppointmentTextInput(
                                          controller: _newClientPhoneController,
                                          label: 'Phone number',
                                          hint: 'Phone',
                                          icon: LucideIcons.phone,
                                          keyboardType: TextInputType.phone,
                                        ),
                                        second: _AppointmentTextInput(
                                          controller: _newClientEmailController,
                                          label: 'Email address',
                                          hint: 'Email',
                                          icon: LucideIcons.mail,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      BookingAddressField(
                                        controller: _newClientAddressController,
                                        onChanged: () => setState(() {}),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _creatingClient = !_creatingClient;
                                            if (_creatingClient) {
                                              _selectedClientId = null;
                                            }
                                          });
                                        },
                                        icon: Icon(
                                          _creatingClient
                                              ? Icons.person_search_rounded
                                              : Icons.person_add_alt_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          _creatingClient
                                              ? 'Choose existing client'
                                              : 'Add new client',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Service ──────────────────────────────────────
                              const _AppointmentSectionLabel(
                                'SERVICE',
                                isRequired: true,
                                subtitle:
                                    'What you are doing and what it costs.',
                              ),
                              const SizedBox(height: 8),
                              services.when(
                                loading: () =>
                                    const _AppointmentSkeleton(height: 54),
                                error: (_, _) => _AppointmentErrorBox(
                                  'Could not load services',
                                  onRetry: () =>
                                      ref.invalidate(servicesProvider),
                                ),
                                data: (data) => Column(
                                  children: [
                                    WorkloopPickerField<String>(
                                      value: _selectedServiceId,
                                      title: 'Choose a service',
                                      hint: 'Select service',
                                      searchHint: 'Search services',
                                      options: [
                                        ...data.map(
                                          (service) => WorkloopPickerOption(
                                            value: service['id'] as String,
                                            label: service['name'] as String,
                                            subtitle:
                                                '${formatPounds(service['price'] as num)} · ${formatFriendlyDuration((service['duration_mins'] as num?)?.toInt() ?? 60)}',
                                          ),
                                        ),
                                        const WorkloopPickerOption(
                                          value: _customServiceId,
                                          label: 'Custom service',
                                          subtitle: 'Enter a one-off service',
                                        ),
                                      ],
                                      onChanged: (value) =>
                                          _selectService(value, data),
                                    ),
                                    if (!_customService &&
                                        _selectedServiceIds.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      AdditionalServicesPicker(
                                        services: data
                                            .map(Service.fromMap)
                                            .toList(),
                                        selectedIds: _selectedServiceIds,
                                        onChanged: (ids) =>
                                            _updateSelectedServices(ids, data),
                                      ),
                                    ],
                                    if (_loadingServiceAddOns) ...[
                                      const SizedBox(height: 10),
                                      const _AppointmentSkeleton(height: 58),
                                    ] else if (_availableServiceAddOns
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      _AppointmentAddOnSelector(
                                        addOns: _availableServiceAddOns,
                                        selectedIds: _selectedAddOnIds,
                                        onChanged: _setAddOnSelected,
                                      ),
                                    ],
                                    if (_customService) ...[
                                      const SizedBox(height: 10),
                                      _AppointmentTextInput(
                                        controller: _customServiceController,
                                        label: 'Service name',
                                        isRequired: true,
                                        hint: 'Service name',
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    if (_selectedServiceIds.length > 1)
                                      Text(
                                        'Combined price · ${formatPounds(double.tryParse(_priceController.text) ?? 0)}',
                                      )
                                    else
                                      _AppointmentTextInput(
                                        controller: _priceController,
                                        label: 'Price',
                                        isRequired: true,
                                        hint: 'Price',
                                        prefix: '£',
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    const SizedBox(height: 12),
                                    _PaymentDueToggle(
                                      value: _createPaymentDue,
                                      onChanged: (value) => setState(
                                        () => _createPaymentDue = value,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Date ─────────────────────────────────────────
                              const _AppointmentSectionLabel(
                                'DATE',
                                isRequired: true,
                                subtitle: 'When the work takes place.',
                              ),
                              const SizedBox(height: 8),
                              Semantics(
                                button: true,
                                label: 'Booking date',
                                value: _formatAppointmentDate(_selectedDate),
                                onTap: _pickDate,
                                child: ExcludeSemantics(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _pickDate,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.of(context).bgCard,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.md,
                                        ),
                                        border: Border.all(
                                          color: AppColors.of(context).border,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today_rounded,
                                            color: AppColors.of(context).t3,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              _formatAppointmentDate(
                                                _selectedDate,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.of(context).t1,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppColors.of(context).t3,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Time ─────────────────────────────────────────
                              const _AppointmentSectionLabel(
                                'TIME & DURATION',
                                isRequired: true,
                                subtitle:
                                    'Set a clear start time and expected length.',
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.of(context).bgCard,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(
                                    color: AppColors.of(context).border,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Semantics(
                                      button: true,
                                      label: 'Booking start time',
                                      value:
                                          '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}',
                                      onTap: _pickTime,
                                      child: ExcludeSemantics(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _pickTime,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minHeight: AppSpacing.minTouch,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.access_time_rounded,
                                                  color: AppColors.of(
                                                    context,
                                                  ).t3,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.of(
                                                      context,
                                                    ).t1,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'to $endStr',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: AppColors.of(
                                                        context,
                                                      ).t3,
                                                    ),
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  color: AppColors.of(
                                                    context,
                                                  ).t3,
                                                  size: 18,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    if (_selectedServiceIds.length > 1)
                                      Text(
                                        _selectedDurationValue > 1440
                                            ? 'Choose services totalling no more than 24 hours.'
                                            : 'Combined duration · ${formatFriendlyDuration(_selectedDurationValue)}',
                                      )
                                    else
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          ...[30, 45, 60, 90, 120].map((
                                            minutes,
                                          ) {
                                            final selected =
                                                !_customDuration &&
                                                _selectedDurationValue ==
                                                    minutes;
                                            return WorkloopFilterChip(
                                              label: '${minutes}m',
                                              selected: selected,
                                              onTap: () =>
                                                  _setDuration(minutes),
                                            );
                                          }),
                                          WorkloopFilterChip(
                                            label: 'Custom',
                                            selected: _customDuration,
                                            onTap: _showCustomDuration,
                                          ),
                                        ],
                                      ),
                                    if (_customDuration &&
                                        _selectedServiceIds.length < 2) ...[
                                      const SizedBox(height: 10),
                                      _AppointmentTextInput(
                                        controller: _durationController,
                                        label: 'Custom duration',
                                        isRequired: true,
                                        hint: 'Custom duration',
                                        suffix: 'min',
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              RecurringBookingFields(
                                intervalWeeks: _repeatIntervalWeeks,
                                occurrences: _repeatOccurrences,
                                firstWallClock: DateTime.utc(
                                  _selectedDate.year,
                                  _selectedDate.month,
                                  _selectedDate.day,
                                  _selectedHour,
                                  _selectedMinute,
                                ),
                                timezoneName:
                                    workspaceSettings.value?['timezone']
                                        as String?,
                                onIntervalChanged: (value) => setState(
                                  () => _repeatIntervalWeeks = value,
                                ),
                                onOccurrencesChanged: (value) =>
                                    setState(() => _repeatOccurrences = value),
                              ),
                              const SizedBox(height: 20),

                              // ── Location ─────────────────────────────────────
                              const _AppointmentSectionLabel(
                                'LOCATION',
                                subtitle: 'Where this booking takes place.',
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    const [
                                      _LocationChoice(
                                        value: 'business',
                                        label: 'Business',
                                      ),
                                      _LocationChoice(
                                        value: 'client',
                                        label: 'Client',
                                      ),
                                      _LocationChoice(
                                        value: 'online',
                                        label: 'Online',
                                      ),
                                    ].map((choice) {
                                      final selected =
                                          _locationMode == choice.value;
                                      return WorkloopFilterChip(
                                        label: choice.label,
                                        selected: selected,
                                        onTap: () => _setLocationMode(
                                          choice.value,
                                          clients.value ?? const <Client>[],
                                        ),
                                      );
                                    }).toList(),
                              ),
                              const SizedBox(height: 10),
                              if (_locationMode == 'online')
                                _AppointmentTextInput(
                                  controller: _locationController,
                                  label: 'Call link or phone note',
                                  hint: 'Call link or phone note',
                                  onChanged: (_) => setState(() {}),
                                )
                              else
                                BookingAddressField(
                                  controller: _locationController,
                                  onChanged: () => setState(() {}),
                                ),
                              const SizedBox(height: 20),

                              if (_repeatIntervalWeeks == 0 &&
                                  !insideWorkingHours &&
                                  dayHoursLabel != null) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.of(context).warningDim,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    border: Border.all(
                                      color: AppColors.of(
                                        context,
                                      ).warning.withValues(alpha: 0.24),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: AppColors.of(context).warning,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${weekdayName(appointmentStart)} hours are $dayHoursLabel. This booking falls outside your working blocks.',
                                          style: TextStyle(
                                            color: AppColors.of(context).t2,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              if (_repeatIntervalWeeks == 0 &&
                                  conflicts.isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.of(context).errorDim,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    border: Border.all(
                                      color: AppColors.of(
                                        context,
                                      ).error.withValues(alpha: 0.24),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.event_busy_rounded,
                                        color: AppColors.of(context).error,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'This overlaps ${conflicts.length} existing booking${conflicts.length == 1 ? '' : 's'}. You can still save it if this is intentional.',
                                          style: TextStyle(
                                            color: AppColors.of(context).t2,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              // ── Tasks ───────────────────────────────────────
                              _AppointmentSectionLabel(
                                'BOOKING TASKS',
                                subtitle: _repeatIntervalWeeks == 0
                                    ? 'Prep or follow-up linked to this booking.'
                                    : 'Prep or follow-up for the first booking only.',
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.of(context).bgCard,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(
                                    color: AppColors.of(context).border,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    if (_taskControllers.isEmpty)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Add prep or follow-up tasks for this booking.',
                                          style: TextStyle(
                                            color: AppColors.of(context).t3,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ..._taskControllers.asMap().entries.map((
                                      entry,
                                    ) {
                                      final index = entry.key;
                                      final controller = entry.value;
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          bottom:
                                              index ==
                                                  _taskControllers.length - 1
                                              ? 0
                                              : 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: _AppointmentTextInput(
                                                controller: controller,
                                                label: 'Task title',
                                                hint: 'Task title',
                                              ),
                                            ),
                                            IconButton(
                                              tooltip:
                                                  'Remove linked task ${index + 1}',
                                              onPressed: () {
                                                setState(() {
                                                  _taskControllers.removeAt(
                                                    index,
                                                  );
                                                });
                                                controller.dispose();
                                              },
                                              icon: Icon(
                                                Icons.close_rounded,
                                                color: AppColors.of(context).t3,
                                                size: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _taskControllers.add(
                                              TextEditingController(),
                                            );
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 17,
                                        ),
                                        label: const Text('Add task'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Notes ─────────────────────────────────────────
                              const _AppointmentSectionLabel(
                                'BOOKING NOTES',
                                subtitle: 'Useful context for this visit.',
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _notesController,
                                maxLines: 3,
                                style: TextStyle(
                                  color: AppColors.of(context).t1,
                                  fontSize: 15,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Add any notes...',
                                  hintStyle: TextStyle(
                                    color: AppColors.of(context).t3,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.of(context).bgCard,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    borderSide: BorderSide(
                                      color: AppColors.of(context).border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    borderSide: BorderSide(
                                      color: AppColors.of(context).border,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    borderSide: BorderSide(
                                      color: AppColors.of(context).green,
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
