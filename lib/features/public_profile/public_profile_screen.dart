import '../../shared/widgets/business_logo_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/workloop_app_info.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/public_booking_availability.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/currency_format.dart';
import '../../shared/utils/duration_format.dart';
import '../../shared/utils/workflow_idempotency.dart';
import '../../shared/utils/working_hours.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import '../../shared/widgets/additional_services_picker.dart';
import 'booking_request_time.dart';
import 'public_booking_availability_provider.dart';

final publicProfileProvider = FutureProvider.family<PublicProfile?, String>((
  ref,
  handle,
) {
  return ref.watch(profileRepositoryProvider).getPublicProfile(handle);
});

class PublicProfileScreen extends ConsumerStatefulWidget {
  final String handle;
  final PublicProfile? previewProfile;

  const PublicProfileScreen({
    super.key,
    required this.handle,
    this.previewProfile,
  });

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  String? _selectedServiceId;
  List<String> _selectedServiceIds = [];
  final Set<String> _selectedAddOnIds = {};
  DateTime? _requestedForUtc;
  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _requestedForError;
  String? _submitError;
  bool _sending = false;
  bool _sent = false;
  final String _requestToken = createPublicRequestToken();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest(PublicProfile profile) async {
    if (_sending || _sent) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final nameError = name.isEmpty ? 'Add your name' : null;
    final phoneError = phone.isEmpty
        ? 'Add a phone number'
        : phoneDigits.length < 7
        ? 'Add a valid phone number'
        : null;
    final emailError = email.isEmpty
        ? 'Add your email address'
        : !isValidBookingRequestEmail(email)
        ? 'Add a valid email address'
        : null;
    final requestedForError = _requestedForUtc == null
        ? 'Choose the date and time you would prefer'
        : null;
    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
      _emailError = emailError;
      _requestedForError = requestedForError;
      _submitError = null;
    });
    if (nameError != null ||
        phoneError != null ||
        emailError != null ||
        requestedForError != null) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .createBookingRequest(
            handle: profile.profile.handle,
            name: name,
            phone: phone,
            email: email,
            requestToken: _requestToken,
            serviceId: _selectedServiceId,
            serviceIds: _selectedServiceIds,
            addOnIds: _selectedAddOnIds.toList(growable: false),
            requestedFor: _requestedForUtc,
            requestedTimezone: profile.timezone,
            preferredTimeText: _requestedForLabel(
              context,
              requestedForUtc: _requestedForUtc!,
              timezone: profile.timezone,
            ),
            message: _messageController.text.trim().isEmpty
                ? null
                : _messageController.text.trim(),
          );
      if (mounted) {
        setState(() {
          _sent = true;
          _sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _submitError =
              'Your request was not sent. Check your connection and try again.';
        });
      }
    }
  }

  void _clearNameError(String _) {
    if (_nameError != null) setState(() => _nameError = null);
  }

  void _clearPhoneError(String _) {
    if (_phoneError != null) setState(() => _phoneError = null);
  }

  void _clearEmailError(String _) {
    if (_emailError != null) setState(() => _emailError = null);
  }

  Future<void> _pickRequestedFor(PublicProfile profile) async {
    final now = DateTime.now();
    final currentWallClock = _requestedForUtc == null
        ? now.add(const Duration(days: 1))
        : bookingRequestWallClock(
            requestedForUtc: _requestedForUtc!,
            timezone: profile.timezone,
          );
    final date = await showWorkloopDatePicker(
      context: context,
      initialDate: currentWallClock,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (date == null || !mounted) return;
    final time = await showWorkloopTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentWallClock),
    );
    if (time == null || !mounted) return;
    try {
      final requestedForUtc = bookingRequestUtcFromWallClock(
        date: date,
        hour: time.hour,
        minute: time.minute,
        timezone: profile.timezone,
      );
      setState(() {
        _requestedForUtc = requestedForUtc;
        _requestedForError = null;
      });
    } on ArgumentError {
      setState(() {
        _requestedForError =
            'That time is skipped by the clock change. Choose another time.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PublicProfile?> profile = widget.previewProfile == null
        ? ref.watch(publicProfileProvider(widget.handle))
        : AsyncValue.data(widget.previewProfile);
    final canGoBack = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          Positioned.fill(
            child: profile.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: AppColors.of(context).green,
                ),
              ),
              error: (_, _) => _ProfileMessage(
                title: 'Could not load profile',
                body: 'Check the link and try again.',
                onRetry: () =>
                    ref.invalidate(publicProfileProvider(widget.handle)),
              ),
              data: (data) {
                if (data == null) {
                  return const _ProfileMessage(
                    title: 'Profile not found',
                    body: 'This Workloop profile is not available.',
                  );
                }
                final availability = _selectedServiceId == null
                    ? null
                    : ref.watch(
                        publicBookingAvailabilityProvider((
                          handle: data.profile.handle,
                          serviceId: _selectedServiceId!,
                          serviceIdsKey: _selectedServiceIds.join(','),
                          addOnIdsKey: (_selectedAddOnIds.toList()..sort())
                              .join(','),
                        )),
                      );
                return _ProfileContent(
                  profile: data,
                  availability: availability,
                  selectedServiceId: _selectedServiceId,
                  selectedServiceIds: _selectedServiceIds,
                  selectedAddOnIds: _selectedAddOnIds,
                  nameController: _nameController,
                  phoneController: _phoneController,
                  emailController: _emailController,
                  requestedForUtc: _requestedForUtc,
                  messageController: _messageController,
                  sending: _sending,
                  sent: _sent,
                  nameError: _nameError,
                  phoneError: _phoneError,
                  emailError: _emailError,
                  requestedForError: _requestedForError,
                  submitError: _submitError,
                  topInset: canGoBack ? 84 : 28,
                  onNameChanged: _clearNameError,
                  onPhoneChanged: _clearPhoneError,
                  onEmailChanged: _clearEmailError,
                  onServiceChanged: (id) => setState(() {
                    _selectedServiceId = id;
                    _selectedServiceIds = id == null ? [] : [id];
                    _selectedAddOnIds.clear();
                    _requestedForUtc = null;
                    _requestedForError = null;
                  }),
                  onServicesChanged: (ids) => setState(() {
                    _selectedServiceIds = List.of(ids);
                    _selectedServiceId = ids.firstOrNull;
                    final validExtras = data.services
                        .where((service) => ids.contains(service.id))
                        .expand((service) => service.addOns)
                        .map((extra) => extra.id)
                        .toSet();
                    _selectedAddOnIds.removeWhere(
                      (id) => !validExtras.contains(id),
                    );
                    _requestedForUtc = null;
                    _requestedForError = null;
                  }),
                  onAddOnChanged: (id, selected) => setState(() {
                    if (selected) {
                      if (_selectedAddOnIds.length < 8) {
                        _selectedAddOnIds.add(id);
                      }
                    } else {
                      _selectedAddOnIds.remove(id);
                    }
                    _requestedForUtc = null;
                    _requestedForError = null;
                  }),
                  onRequestedForTap: () => _pickRequestedFor(data),
                  onSuggestedTimeSelected: (requestedForUtc) => setState(() {
                    _requestedForUtc = requestedForUtc;
                    _requestedForError = null;
                  }),
                  onSubmit: () => _sendRequest(data),
                );
              },
            ),
          ),
          if (canGoBack)
            Positioned(
              left: 0,
              top: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.pageX,
                    top: AppSpacing.sm,
                  ),
                  child: WorkloopIconButton(
                    icon: LucideIcons.chevronLeft,
                    semanticLabel: 'Back to profile',
                    backgroundColor: AppColors.of(
                      context,
                    ).bgCard.withValues(alpha: 0.94),
                    onTap: () => workloopGoBack(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  final PublicProfile profile;
  final AsyncValue<PublicBookingAvailability>? availability;
  final String? selectedServiceId;
  final List<String> selectedServiceIds;
  final Set<String> selectedAddOnIds;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final DateTime? requestedForUtc;
  final TextEditingController messageController;
  final bool sending;
  final bool sent;
  final String? nameError;
  final String? phoneError;
  final String? emailError;
  final String? requestedForError;
  final String? submitError;
  final double topInset;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String?> onServiceChanged;
  final ValueChanged<List<String>> onServicesChanged;
  final void Function(String id, bool selected) onAddOnChanged;
  final VoidCallback onRequestedForTap;
  final ValueChanged<DateTime> onSuggestedTimeSelected;
  final VoidCallback onSubmit;

  const _ProfileContent({
    required this.profile,
    required this.availability,
    required this.selectedServiceId,
    required this.selectedServiceIds,
    required this.selectedAddOnIds,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.requestedForUtc,
    required this.messageController,
    required this.sending,
    required this.sent,
    required this.nameError,
    required this.phoneError,
    required this.emailError,
    required this.requestedForError,
    required this.submitError,
    required this.topInset,
    required this.onNameChanged,
    required this.onPhoneChanged,
    required this.onEmailChanged,
    required this.onServiceChanged,
    required this.onServicesChanged,
    required this.onAddOnChanged,
    required this.onRequestedForTap,
    required this.onSuggestedTimeSelected,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final bookingClosed = profile.profile.bookingMode != 'manual';
    final bookingSectionKey = GlobalKey();
    final selectedServices = selectedServiceIds
        .map(
          (id) =>
              profile.services.where((service) => service.id == id).firstOrNull,
        )
        .whereType<Service>()
        .toList();
    final selectedService = selectedServices.firstOrNull;
    final distinctSelectedServices = <String, Service>{};
    for (final service in selectedServices) {
      distinctSelectedServices.putIfAbsent(service.id, () => service);
    }
    final selectedAddOnsById = <String, ServiceAddOn>{};
    for (final extra in distinctSelectedServices.values.expand(
      (service) => service.addOns,
    )) {
      if (selectedAddOnIds.contains(extra.id)) {
        selectedAddOnsById.putIfAbsent(extra.id, () => extra);
      }
    }
    final selectedAddOns = selectedAddOnsById.values.toList(growable: false);
    final totalDurationMinutes = selectedService == null
        ? null
        : selectedServices.fold<int>(
                0,
                (total, service) => total + service.durationMins,
              ) +
              selectedAddOns.fold<int>(
                0,
                (total, extra) => total + extra.durationMins,
              );
    final totalPrice =
        selectedServices.fold<double>(
          0,
          (total, service) => total + service.price,
        ) +
        selectedAddOns.fold<double>(0, (total, extra) => total + extra.price);

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pageX,
          topInset,
          AppSpacing.pageX,
          40,
        ),
        children: [
          _Hero(profile: profile),
          if (!bookingClosed && !sent) ...[
            const SizedBox(height: AppSpacing.lg),
            WorkloopPrimaryButton(
              label: 'Request a booking',
              icon: LucideIcons.calendarPlus,
              onPressed: () {
                final target = bookingSectionKey.currentContext;
                if (target == null) return;
                Scrollable.ensureVisible(
                  target,
                  duration: AppMotion.responsive(context, AppMotion.standard),
                  curve: AppMotion.curve,
                  alignment: 0.06,
                );
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Send a preferred time. The business will contact you before anything is confirmed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (profile.profile.isNoticeActive()) ...[
            _Notice(text: profile.profile.noticeText!),
            const SizedBox(height: 16),
          ],
          _Section(
            title: 'Services',
            child: profile.services.isEmpty
                ? Text(
                    'No services are currently listed.',
                    style: TextStyle(color: AppColors.of(context).t3),
                  )
                : Column(
                    children: profile.services
                        .map(
                          (service) => _ServiceRow(
                            name: service.name,
                            duration: service.durationMins,
                            price: service.price,
                            description: service.description,
                            selected: selectedServiceIds.contains(service.id),
                            onTap: bookingClosed
                                ? null
                                : () {
                                    onServiceChanged(service.id);
                                    final target =
                                        bookingSectionKey.currentContext;
                                    if (target == null) return;
                                    Scrollable.ensureVisible(
                                      target,
                                      duration: AppMotion.responsive(
                                        context,
                                        AppMotion.standard,
                                      ),
                                      curve: AppMotion.curve,
                                      alignment: 0.06,
                                    );
                                  },
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Working hours',
            child: _PublishedHours(workingHours: profile.workingHours),
          ),
          const SizedBox(height: 16),
          Container(
            key: bookingSectionKey,
            child: _Section(
              title: 'Request a booking',
              child: bookingClosed
                  ? const _ClosedBookingState()
                  : sent
                  ? _SentState(
                      businessName: profile.businessName,
                      email: emailController.text.trim(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This is a request, not a confirmed appointment. The business will contact you to agree the details.',
                          style: TextStyle(
                            color: AppColors.of(context).t3,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ProfileField(
                          controller: nameController,
                          label: 'Name',
                          isRequired: true,
                          hint: 'Your name',
                          errorText: nameError,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          onChanged: onNameChanged,
                          maxLength: 80,
                        ),
                        const SizedBox(height: 10),
                        _ProfileField(
                          controller: phoneController,
                          label: 'Phone',
                          isRequired: true,
                          hint: 'Phone number',
                          errorText: phoneError,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          textInputAction: TextInputAction.next,
                          onChanged: onPhoneChanged,
                          keyboardType: TextInputType.phone,
                          maxLength: 32,
                        ),
                        const SizedBox(height: 10),
                        _ProfileField(
                          controller: emailController,
                          label: 'Email',
                          isRequired: true,
                          hint: 'Email address',
                          errorText: emailError,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          onChanged: onEmailChanged,
                          keyboardType: TextInputType.emailAddress,
                          maxLength: 254,
                        ),
                        const SizedBox(height: 10),
                        const WorkloopFieldLabel('Service', isRequired: false),
                        const SizedBox(height: AppSpacing.xs),
                        WorkloopPickerField<String?>(
                          value: selectedServiceId,
                          title: 'Choose a service',
                          hint: 'Service',
                          searchHint: 'Search services',
                          options: [
                            const WorkloopPickerOption<String?>(
                              value: null,
                              label: 'Not sure yet',
                            ),
                            ...profile.services.map(
                              (service) => WorkloopPickerOption<String?>(
                                value: service.id,
                                label:
                                    '${service.name} · ${formatFriendlyDuration(service.durationMins)}',
                              ),
                            ),
                          ],
                          onChanged: onServiceChanged,
                        ),
                        const SizedBox(height: 10),
                        AdditionalServicesPicker(
                          services: profile.services,
                          selectedIds: selectedServiceIds,
                          onChanged: onServicesChanged,
                        ),
                        for (final service in distinctSelectedServices.values)
                          if (service.addOns.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _OptionalExtras(
                              service: service,
                              selectedIds: selectedAddOnIds,
                              onChanged: onAddOnChanged,
                            ),
                          ],
                        if (selectedServices.length > 1) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Combined total · ${formatFriendlyDuration(totalDurationMinutes!)} · ${formatPounds(totalPrice)}',
                          ),
                        ],
                        const SizedBox(height: 10),
                        _SuggestedTimes(
                          availability: availability,
                          selectedServiceId: selectedServiceId,
                          requestedForUtc: requestedForUtc,
                          onSelected: onSuggestedTimeSelected,
                          onRequestAnotherTime: onRequestedForTap,
                        ),
                        const SizedBox(height: 10),
                        _RequestedForField(
                          requestedForUtc: requestedForUtc,
                          timezone: profile.timezone,
                          workingHours: profile.workingHours,
                          durationMinutes: totalDurationMinutes,
                          errorText: requestedForError,
                          onTap: onRequestedForTap,
                        ),
                        const SizedBox(height: 10),
                        _ProfileField(
                          controller: messageController,
                          label: 'Message',
                          hint: 'Anything we should know?',
                          maxLines: 3,
                          maxLength: 1000,
                        ),
                        if (submitError != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Semantics(
                            liveRegion: true,
                            container: true,
                            label: submitError,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  LucideIcons.circleAlert,
                                  color: AppColors.of(context).error,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    submitError!,
                                    style: TextStyle(
                                      color: AppColors.of(context).error,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: sending ? null : onSubmit,
                            child: sending
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: AppColors.of(
                                        context,
                                      ).onBrandAccent,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Send request'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const _BookingPrivacyNotice(),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionalExtras extends StatelessWidget {
  final Service service;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onChanged;

  const _OptionalExtras({
    required this.service,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = service.addOns
        .where((addOn) => selectedIds.contains(addOn.id))
        .toList(growable: false);
    final duration =
        service.durationMins +
        selected.fold<int>(0, (total, addOn) => total + addOn.durationMins);
    final price =
        service.price +
        selected.fold<double>(0, (total, addOn) => total + addOn.price);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgInteract,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optional extras · ${service.name}',
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose any extras you would like included in your request.',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final addOn in service.addOns)
              Semantics(
                checked: selectedIds.contains(addOn.id),
                child: CheckboxListTile(
                  value: selectedIds.contains(addOn.id),
                  onChanged: (value) => onChanged(addOn.id, value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    addOn.name,
                    style: TextStyle(
                      color: AppColors.of(context).t1,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (addOn.durationMins > 0)
                        '+${formatFriendlyDuration(addOn.durationMins)}',
                      if (addOn.price > 0) '+${formatPounds(addOn.price)}',
                      if (addOn.description?.isNotEmpty == true)
                        addOn.description!,
                    ].join(' · '),
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            Divider(color: AppColors.of(context).border),
            Text(
              'Total · ${formatFriendlyDuration(duration)} · ${formatPounds(price)}',
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestedTimes extends StatelessWidget {
  final AsyncValue<PublicBookingAvailability>? availability;
  final String? selectedServiceId;
  final DateTime? requestedForUtc;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onRequestAnotherTime;

  const _SuggestedTimes({
    required this.availability,
    required this.selectedServiceId,
    required this.requestedForUtc,
    required this.onSelected,
    required this.onRequestAnotherTime,
  });

  @override
  Widget build(BuildContext context) {
    final content = selectedServiceId == null
        ? Text(
            'Choose a service to see suggested times.',
            style: TextStyle(color: AppColors.of(context).t3, fontSize: 13),
          )
        : availability!.when(
            loading: () => Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Checking suggested times…',
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            error: (_, _) => Text(
              'Suggested times are unavailable right now. You can still request another time.',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            data: (data) => data.days.isEmpty
                ? Text(
                    'No suggested times are showing right now. You can still request another time.',
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final day in data.days) ...[
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(day.date),
                          style: TextStyle(
                            color: AppColors.of(context).t2,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final slotUtc in day.slotsUtc)
                              _SuggestedTimeChip(
                                slotUtc: slotUtc,
                                timezone: data.timezone,
                                selected:
                                    requestedForUtc?.toUtc() == slotUtc.toUtc(),
                                onSelected: () => onSelected(slotUtc),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgInteract,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested times',
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Looks open right now. These times are not held or confirmed until the business accepts your request.',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          content,
          const SizedBox(height: AppSpacing.xs),
          WorkloopTextButton(
            label: 'Request another time',
            onPressed: onRequestAnotherTime,
          ),
        ],
      ),
    );
  }
}

class _SuggestedTimeChip extends StatelessWidget {
  final DateTime slotUtc;
  final String timezone;
  final bool selected;
  final VoidCallback onSelected;

  const _SuggestedTimeChip({
    required this.slotUtc,
    required this.timezone,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final wallClock = bookingRequestWallClock(
      requestedForUtc: slotUtc,
      timezone: timezone,
    );
    final label = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(wallClock));
    return Semantics(
      button: true,
      selected: selected,
      label: 'Suggested time $label',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onSelected(),
        ),
      ),
    );
  }
}

class _BookingPrivacyNotice extends StatelessWidget {
  const _BookingPrivacyNotice();

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(WorkloopAppInfo.privacyUrl),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The privacy policy could not be opened')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Column(
        children: [
          Text(
            'Workloop sends these details to this business so they can respond. Your email is also used to send a confirmation if they accept the request.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          WorkloopTextButton(
            label: 'Privacy policy',
            onPressed: () => _openPrivacyPolicy(context),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final PublicProfile profile;
  const _Hero({required this.profile});

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final coverUrl = profile.profile.coverPhotoUrl;
    return WorkloopSurface(
      color: tokens.inkSurface,
      borderColor: tokens.divider,
      radius: AppRadius.xl,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverUrl?.isNotEmpty == true) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.of(context).bgCard,
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.imageOff,
                      color: AppColors.of(context).t3,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ] else if (profile.logoUrl?.isNotEmpty != true) ...[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.divider),
              ),
              child: Center(
                child: Text(
                  profile.businessName.isEmpty
                      ? 'S'
                      : profile.businessName[0].toUpperCase(),
                  style: TextStyle(
                    color: tokens.accentInk,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (profile.logoUrl?.isNotEmpty == true) ...[
            BusinessLogo(logoUrl: profile.logoUrl, size: 72),
            const SizedBox(height: 18),
          ],
          Text(
            profile.businessName,
            style: TextStyle(
              color: tokens.onInk,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            profile.profile.bio?.isNotEmpty == true
                ? profile.profile.bio!
                : profile.industry ?? 'Independent service business',
            style: TextStyle(
              color: tokens.onInkMuted,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.link, color: tokens.accentInk, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Powered by Workloop',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.onInkMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.of(context).greenDim,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).green),
      ),
      child: Text(
        text,
        style: TextStyle(color: AppColors.of(context).t1, fontSize: 13),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        child,
        const SizedBox(height: AppSpacing.lg),
        Divider(height: 1, thickness: 1, color: AppColors.of(context).border),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final String name;
  final int duration;
  final double price;
  final String? description;
  final bool selected;
  final VoidCallback? onTap;
  const _ServiceRow({
    required this.name,
    required this.duration,
    required this.price,
    this.description,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$name, ${formatFriendlyDuration(duration)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.of(context).modBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppColors.of(context).accentInk
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: AppColors.of(context).t1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatFriendlyDuration(duration),
                      style: TextStyle(
                        color: AppColors.of(context).t3,
                        fontSize: 12,
                      ),
                    ),
                    if (description?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        description!,
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                formatPounds(price),
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  selected ? LucideIcons.circleCheck : LucideIcons.chevronRight,
                  color: selected
                      ? AppColors.of(context).accentInk
                      : AppColors.of(context).t3,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PublishedHours extends StatelessWidget {
  final Map<String, dynamic> workingHours;

  const _PublishedHours({required this.workingHours});

  @override
  Widget build(BuildContext context) {
    final openDays = <({String day, Map<String, dynamic> hours})>[];
    for (final day in workingHourDays) {
      final shortDay = shortToLongDay.entries
          .firstWhere((entry) => entry.value == day)
          .key;
      final value = workingHours[day] ?? workingHours[shortDay];
      final hours = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      if (hours['enabled'] == true) openDays.add((day: day, hours: hours));
    }
    if (openDays.isEmpty) {
      return Text(
        'Hours not published yet.',
        style: TextStyle(color: AppColors.of(context).t3),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in openDays)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.day,
                    style: TextStyle(color: AppColors.of(context).t2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    formatFriendlyWorkingHourValue(entry.hours),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: AppColors.of(context).t1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (openDays.length < workingHourDays.length) ...[
          const SizedBox(height: 2),
          Text(
            'Closed on other days',
            style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isRequired;
  final String hint;
  final String? errorText;
  final int maxLines;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final int? maxLength;

  const _ProfileField({
    required this.controller,
    required this.label,
    this.isRequired = false,
    required this.hint,
    this.errorText,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopFormField(
      label: label,
      isRequired: isRequired,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        buildCounter: maxLength == null
            ? null
            : (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onChanged: onChanged,
        style: TextStyle(color: AppColors.of(context).t1),
        decoration: _fieldDecoration(context, hint, errorText: errorText),
      ),
    );
  }
}

class _RequestedForField extends StatelessWidget {
  final DateTime? requestedForUtc;
  final String timezone;
  final Map<String, dynamic> workingHours;
  final int? durationMinutes;
  final String? errorText;
  final VoidCallback onTap;

  const _RequestedForField({
    required this.requestedForUtc,
    required this.timezone,
    required this.workingHours,
    required this.durationMinutes,
    required this.errorText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPublishedHours = workingHours.values.any(
      (value) => workingHourBlocks(value).isNotEmpty,
    );
    final hoursFit = requestedForUtc == null
        ? null
        : bookingRequestHoursFit(
            requestedForUtc: requestedForUtc!,
            timezone: timezone,
            workingHours: workingHours,
            durationMinutes: durationMinutes ?? 1,
          );
    final guidance = switch (hoursFit) {
      BookingRequestHoursFit.withinPublishedHours =>
        'This time is within the published hours. It is still a request until the business confirms it.',
      BookingRequestHoursFit.outsidePublishedHours =>
        'This time is outside the published hours. You can still request it and the business will let you know if it works.',
      BookingRequestHoursFit.noPublishedHours =>
        'Hours are not published for this day. You can still request it and the business will let you know if it works.',
      null when hasPublishedHours =>
        'Published hours are a guide. You can request any time; nothing is confirmed until the business contacts you.',
      null =>
        'Choose any preferred time. Nothing is confirmed until the business contacts you.',
    };
    final guidanceColor =
        hoursFit == BookingRequestHoursFit.withinPublishedHours
        ? AppColors.of(context).t3
        : hoursFit == null
        ? AppColors.of(context).t3
        : AppColors.of(context).warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Preferred date and time',
          value: requestedForUtc == null
              ? 'Not chosen'
              : _requestedForLabel(
                  context,
                  requestedForUtc: requestedForUtc!,
                  timezone: timezone,
                ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.of(context).bgInteract,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: errorText == null
                      ? AppColors.of(context).border
                      : AppColors.of(context).error,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.calendarClock,
                    color: AppColors.of(context).t3,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WorkloopFieldLabel(
                          'Preferred date and time',
                          isRequired: true,
                          style: TextStyle(
                            color: AppColors.of(context).t3,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          requestedForUtc == null
                              ? 'Choose a date and time'
                              : _requestedForLabel(
                                  context,
                                  requestedForUtc: requestedForUtc!,
                                  timezone: timezone,
                                ),
                          style: TextStyle(
                            color: AppColors.of(context).t1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    color: AppColors.of(context).t3,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: TextStyle(color: AppColors.of(context).error, fontSize: 12),
          ),
        ],
        const SizedBox(height: 6),
        Semantics(
          liveRegion: requestedForUtc != null,
          child: Text(
            guidance,
            style: TextStyle(color: guidanceColor, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}

String _requestedForLabel(
  BuildContext context, {
  required DateTime requestedForUtc,
  required String timezone,
}) {
  final wallClock = bookingRequestWallClock(
    requestedForUtc: requestedForUtc,
    timezone: timezone,
  );
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(wallClock)} at '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(wallClock))}';
}

InputDecoration _fieldDecoration(
  BuildContext context,
  String hint, {
  String? errorText,
}) {
  return InputDecoration(
    hintText: hint,
    errorText: errorText,
    hintStyle: TextStyle(color: AppColors.of(context).t3),
    filled: true,
    fillColor: AppColors.of(context).bgInteract,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.of(context).border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.of(context).border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppColors.of(context).accentInk,
        width: 1.5,
      ),
    ),
  );
}

class _SentState extends StatelessWidget {
  final String businessName;
  final String email;

  const _SentState({required this.businessName, required this.email});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label:
          'Request sent. Nothing is booked yet. If $businessName accepts, confirmation will be emailed to $email.',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Icon(
              LucideIcons.checkCircle2,
              color: AppColors.of(context).success,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              'Request sent',
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$businessName will contact you to agree the details. Nothing is booked yet. If they accept, confirmation will be emailed to $email.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedBookingState extends StatelessWidget {
  const _ClosedBookingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgInteract,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.lock, color: AppColors.of(context).t3, size: 22),
          SizedBox(height: 12),
          Text(
            'Booking requests are closed',
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'This business is not accepting new booking requests right now.',
            style: TextStyle(color: AppColors.of(context).t3, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback? onRetry;

  const _ProfileMessage({
    required this.title,
    required this.body,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.of(context).t3),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              WorkloopPrimaryButton(
                label: 'Try again',
                icon: LucideIcons.refreshCw,
                secondary: true,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
