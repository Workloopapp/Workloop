import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/booking_requests_provider.dart';
import '../../shared/providers/dashboard_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/notifications_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import '../../shared/widgets/record_link_unavailable.dart';
import '../appointments/booking_schedule_warning_sheet.dart';
import 'booking_request_time.dart';

export '../../shared/providers/booking_requests_provider.dart'
    show bookingRequestsProvider;

enum _RequestView { active, pending, closed }

String bookingRequestEditablePrice(num price) {
  if (!price.isFinite || price < 0) return '0';
  return price.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

class BookingRequestsScreen extends ConsumerStatefulWidget {
  final String? initialRequestId;

  const BookingRequestsScreen({super.key, this.initialRequestId});

  @override
  ConsumerState<BookingRequestsScreen> createState() =>
      _BookingRequestsScreenState();
}

class _BookingRequestsScreenState extends ConsumerState<BookingRequestsScreen> {
  _RequestView _view = _RequestView.active;
  bool _didHandleInitialRequest = false;
  String? _scheduledInitialId;
  bool _initialRecordMissing = false;

  Future<void> _refreshRequests() async {
    ref.invalidate(bookingRequestsProvider);
    try {
      await ref.read(bookingRequestsProvider.future);
    } catch (_) {
      // The request list displays a visible error and retry action.
    }
  }

  Widget _refreshableEmpty(Widget child) => RefreshIndicator(
    color: AppColors.of(context).green,
    onRefresh: _refreshRequests,
    child: child,
  );

  @override
  void didUpdateWidget(covariant BookingRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRequestId != oldWidget.initialRequestId) {
      _didHandleInitialRequest = false;
      _scheduledInitialId = null;
      _initialRecordMissing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialRequestId != null) ref.watch(workspaceIdProvider);
    final requests = ref.watch(bookingRequestsProvider);
    if (_initialRecordMissing) {
      return WorkloopRecordLinkUnavailable(
        recordName: 'Booking request',
        onRetry: () {
          setState(() {
            _didHandleInitialRequest = false;
            _initialRecordMissing = false;
          });
          ref.invalidate(bookingRequestsProvider);
        },
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    AppSpacing.screenTop,
                    AppSpacing.pageX,
                    AppSpacing.md,
                  ),
                  child: WorkloopRouteHeader(
                    title: 'Booking requests',
                    backSemanticLabel: 'Back to bookings',
                  ),
                ),
                requests.maybeWhen(
                  data: (items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    final pending = items
                        .where((item) => item.status == 'pending')
                        .length;
                    final active = items
                        .where((item) => item.needsDecision)
                        .length;
                    final closed = items
                        .where(
                          (item) =>
                              item.status == 'confirmed' ||
                              item.status == 'declined',
                        )
                        .length;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageX,
                        0,
                        AppSpacing.pageX,
                        AppSpacing.md,
                      ),
                      child: WorkloopNavigationControl<_RequestView>(
                        selected: _view,
                        emphasized: false,
                        onChanged: (view) => setState(() => _view = view),
                        segments: [
                          WorkloopSegment(
                            value: _RequestView.active,
                            label: 'Active',
                            badge: active > 0 ? '$active' : null,
                          ),
                          WorkloopSegment(
                            value: _RequestView.pending,
                            label: 'New',
                            badge: pending > 0 ? '$pending' : null,
                          ),
                          WorkloopSegment(
                            value: _RequestView.closed,
                            label: 'Closed',
                            badge: closed > 0 ? '$closed' : null,
                          ),
                        ],
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
                Expanded(
                  child: requests.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: AppColors.of(context).green,
                      ),
                    ),
                    error: (_, _) => _refreshableEmpty(
                      _EmptyRequests(
                        title: 'Could not load requests',
                        subtitle: 'Check your connection, then try again.',
                        onRetry: _refreshRequests,
                      ),
                    ),
                    data: (items) {
                      _openInitialRequest(items);
                      if (items.isEmpty) {
                        return _refreshableEmpty(
                          const _EmptyRequests(
                            title: 'No booking requests',
                            subtitle:
                                'Requests from your public profile will appear here.',
                          ),
                        );
                      }
                      final filtered = _filterRequests(items);
                      if (filtered.isEmpty) {
                        return _refreshableEmpty(
                          _EmptyRequests(
                            title: switch (_view) {
                              _RequestView.pending => 'No new requests',
                              _RequestView.closed => 'No closed requests',
                              _RequestView.active => 'No active requests',
                            },
                            subtitle:
                                'Switch filters to review other requests.',
                          ),
                        );
                      }
                      return RefreshIndicator(
                        color: AppColors.of(context).green,
                        onRefresh: _refreshRequests,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.pageX,
                            0,
                            AppSpacing.pageX,
                            40,
                          ),
                          itemBuilder: (context, index) => _RequestRow(
                            request: filtered[index],
                            onTap: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                settings: RouteSettings(
                                  name:
                                      '/booking-requests/${filtered[index].id}',
                                ),
                                builder: (_) => BookingRequestDetailScreen(
                                  request: filtered[index],
                                ),
                              ),
                            ),
                          ),
                          separatorBuilder: (_, _) =>
                              const WorkloopDivider(margin: EdgeInsets.zero),
                          itemCount: filtered.length,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<BookingRequest> _filterRequests(List<BookingRequest> items) {
    final filtered = items.where((item) {
      return switch (_view) {
        _RequestView.active => item.needsDecision,
        _RequestView.pending => item.status == 'pending',
        _RequestView.closed =>
          item.status == 'confirmed' || item.status == 'declined',
      };
    }).toList();

    const statusOrder = {
      'pending': 0,
      'contacted': 1,
      'confirmed': 2,
      'declined': 3,
    };
    filtered.sort((a, b) {
      final statusCompare = (statusOrder[a.status] ?? 9).compareTo(
        statusOrder[b.status] ?? 9,
      );
      if (statusCompare != 0) return statusCompare;
      final aCreated = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bCreated = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bCreated.compareTo(aCreated);
    });
    return filtered;
  }

  void _openInitialRequest(List<BookingRequest> records) {
    final id = widget.initialRequestId?.trim();
    final snapshot = ref.read(bookingRequestsProvider);
    final workspace = ref.read(workspaceIdProvider);
    if (_didHandleInitialRequest ||
        id == null ||
        id.isEmpty ||
        _scheduledInitialId == id ||
        snapshot.isLoading ||
        snapshot.hasError ||
        !snapshot.hasValue ||
        workspace.isLoading ||
        workspace.hasError ||
        workspace.value == null) {
      return;
    }
    final workspaceId = workspace.value;
    _scheduledInitialId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _scheduledInitialId != id ||
          widget.initialRequestId?.trim() != id) {
        return;
      }
      _scheduledInitialId = null;
      final current = ref.read(bookingRequestsProvider);
      final currentWorkspace = ref.read(workspaceIdProvider);
      if (current.isLoading ||
          current.hasError ||
          !current.hasValue ||
          currentWorkspace.isLoading ||
          currentWorkspace.hasError ||
          currentWorkspace.value != workspaceId) {
        return;
      }
      BookingRequest? match;
      for (final record in current.value ?? <BookingRequest>[]) {
        if (record.id == id) {
          match = record;
          break;
        }
      }
      _didHandleInitialRequest = true;
      if (match == null) {
        setState(() => _initialRecordMissing = true);
      } else {
        Navigator.push<void>(
          context,
          MaterialPageRoute(
            settings: RouteSettings(name: '/booking-requests/${match.id}'),
            builder: (_) => BookingRequestDetailScreen(request: match!),
          ),
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

class _RequestRow extends StatelessWidget {
  final BookingRequest request;
  final VoidCallback onTap;

  const _RequestRow({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final requestedTimeLabel = bookingRequestRequestedTimeLabel(
      context,
      request,
    );
    final contextLine = [
      if (request.serviceName?.trim().isNotEmpty == true)
        request.serviceName!.trim(),
      ?requestedTimeLabel,
    ].join(' · ');
    final initial = request.name.trim().isEmpty
        ? '?'
        : request.name.trim()[0].toUpperCase();
    return WorkloopListRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      showDivider: false,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.of(context).modBg,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        request.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        contextLine.isEmpty ? request.phone : contextLine,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(status: request.status),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            LucideIcons.chevronRight,
            color: AppColors.of(context).t3,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class BookingRequestDetailScreen extends StatelessWidget {
  final BookingRequest request;

  const BookingRequestDetailScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    AppSpacing.md,
                  ),
                  child: const WorkloopRouteHeader(
                    title: 'Booking request',
                    backSemanticLabel: 'Back to booking requests',
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
                    child: _RequestCard(
                      request: request,
                      detailMode: true,
                      closeAfterAction: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  final BookingRequest request;
  final bool detailMode;
  final bool closeAfterAction;

  const _RequestCard({
    required this.request,
    this.detailMode = false,
    this.closeAfterAction = false,
  });

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _saving = false;
  bool _openingBooking = false;

  Future<void> _setStatus(String status) async {
    if (_saving || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateBookingRequestStatus(
            requestId: widget.request.id,
            workspaceId: widget.request.workspaceId,
            status: status,
          );
      if (!mounted) return;
      SlateHaptics.success();
      ref.invalidate(bookingRequestsProvider);
      if (widget.closeAfterAction) Navigator.pop(context);
    } on BookingRequestStateException catch (error) {
      if (mounted) {
        ref.invalidate(bookingRequestsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.of(context).error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The request could not be updated. Check your connection and try again.',
            ),
            backgroundColor: AppColors.of(context).error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _declineRequest() async {
    final confirmed = await showWorkloopBottomSheet<bool>(
      context: context,
      builder: (context) => SlateSheetFrame(
        scrollable: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Decline request?',
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.request.name} will move to closed requests. You can still find it later.',
              style: TextStyle(color: AppColors.of(context).t3, height: 1.35),
            ),
            const SizedBox(height: 18),
            SlateButton(
              label: 'Decline Request',
              icon: LucideIcons.xCircle,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            SlateButton(
              label: 'Keep Request',
              secondary: true,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await _setStatus('declined');
    }
  }

  Future<void> _confirmAsBooking() async {
    if (_saving || _openingBooking) return;
    final request = widget.request;
    setState(() => _openingBooking = true);
    final isServiceBundle = request.serviceItems.any(
      (item) => item.itemKind == 'service',
    );
    final now = DateTime.now();
    late final String bookingTimezone;
    try {
      bookingTimezone = request.requestedTimezone?.trim().isNotEmpty == true
          ? request.requestedTimezone!.trim()
          : await ref
                .read(profileRepositoryProvider)
                .bookingRequestTimezone(request)
                .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (!identical(widget.request, request) ||
          ModalRoute.of(context)?.isCurrent == false) {
        setState(() => _openingBooking = false);
        return;
      }
      bookingRequestLocation(bookingTimezone);
    } on ArgumentError {
      if (!mounted) return;
      setState(() => _openingBooking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This request’s time zone could not be read. Refresh the request before confirming it.',
          ),
        ),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _openingBooking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load the business time zone. Check your connection and try again.',
          ),
        ),
      );
      return;
    }
    final businessNow = bookingRequestWallClock(
      requestedForUtc: now.toUtc(),
      timezone: bookingTimezone,
    );
    final requestedTime = resolveBookingRequestTime(
      timezone: bookingTimezone,
      requestedFor: request.requestedFor,
      preferredTimeText: request.preferredTimeText,
    );
    DateTime? selectedDate = requestedTime.date;
    TimeOfDay? selectedTime = requestedTime.hour == null
        ? null
        : TimeOfDay(hour: requestedTime.hour!, minute: requestedTime.minute!);
    final initialDate = selectedDate;
    final initialTime = selectedTime;
    DateTime? selectedInstant = requestedTime.instantUtc;
    List<DateTime> possibleInstants() =>
        selectedDate == null || selectedTime == null
        ? const []
        : bookingRequestPossibleInstants(
            date: selectedDate!,
            hour: selectedTime!.hour,
            minute: selectedTime!.minute,
            timezone: bookingTimezone,
          );
    void updateSelectedInstant() {
      final possibilities = possibleInstants();
      final original = requestedTime.instantUtc;
      final sameAsRequested =
          selectedDate == initialDate && selectedTime == initialTime;
      selectedInstant = sameAsRequested && original != null
          ? original
          : possibilities.length == 1
          ? possibilities.single
          : null;
    }

    final clientNameController = TextEditingController(text: request.name);
    final phoneController = TextEditingController(text: request.phone);
    final emailController = TextEditingController(text: request.email);
    final canEditEmail = !isValidBookingRequestEmail(request.email);
    final serviceController = TextEditingController(
      text: request.serviceName?.trim().isNotEmpty == true
          ? request.serviceName!.trim()
          : 'Booking request',
    );
    final durationController = TextEditingController(
      text: (request.serviceDurationMins ?? 60).toString(),
    );
    final priceController = TextEditingController(
      text: bookingRequestEditablePrice(request.servicePrice ?? 0),
    );
    final locationController = TextEditingController();
    final notesController = TextEditingController();
    var createPaymentDue = (request.servicePrice ?? 0) > 0;
    final requestedAddOns = request.serviceItems
        .where((item) => item.isAddOn)
        .toList(growable: false);
    var submitting = false;
    var askingToClose = false;
    String? submissionError;
    final initialValues = [
      clientNameController.text,
      phoneController.text,
      emailController.text,
      serviceController.text,
      durationController.text,
      priceController.text,
      locationController.text,
      notesController.text,
    ];
    bool hasChanges() {
      final values = [
        clientNameController.text,
        phoneController.text,
        emailController.text,
        serviceController.text,
        durationController.text,
        priceController.text,
        locationController.text,
        notesController.text,
      ];
      return values.indexed.any(
            (entry) => entry.$2 != initialValues[entry.$1],
          ) ||
          selectedDate != initialDate ||
          selectedTime != initialTime ||
          selectedInstant != requestedTime.instantUtc ||
          createPaymentDue != ((request.servicePrice ?? 0) > 0);
    }

    final sheetCloseDuration = AppMotion.responsive(
      context,
      AppMotion.deliberate,
    );

    setState(() => _openingBooking = true);
    final confirmation = await showWorkloopBottomSheet<BookingRequestConfirmationOutcome>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final requestedTimeLabel = bookingRequestRequestedTimeLabel(
              context,
              request,
              timezone: bookingTimezone,
            );
            bool canSubmit() {
              final duration =
                  int.tryParse(durationController.text.trim()) ?? 0;
              final price = double.tryParse(priceController.text.trim()) ?? -1;
              return selectedInstant != null &&
                  clientNameController.text.trim().isNotEmpty &&
                  phoneController.text.trim().isNotEmpty &&
                  serviceController.text.trim().isNotEmpty &&
                  duration >= 5 &&
                  duration <= 1440 &&
                  price.isFinite &&
                  price >= 0 &&
                  (emailController.text.trim().isEmpty ||
                      isValidBookingRequestEmail(emailController.text));
            }

            void refreshForm() => setSheetState(() {});

            Future<void> pickDate() async {
              final picked = await showWorkloopDatePicker(
                context: context,
                initialDate:
                    selectedDate ??
                    DateTime(
                      businessNow.year,
                      businessNow.month,
                      businessNow.day,
                    ),
                firstDate: DateTime(
                  businessNow.year,
                  businessNow.month,
                  businessNow.day,
                ),
                lastDate: DateTime(
                  businessNow.year,
                  businessNow.month,
                  businessNow.day + 366,
                ),
              );
              if (picked != null) {
                setSheetState(() {
                  selectedDate = DateTime.utc(
                    picked.year,
                    picked.month,
                    picked.day,
                  );
                  updateSelectedInstant();
                });
              }
            }

            Future<void> pickTime() async {
              final picked = await showWorkloopTimePicker(
                context: context,
                initialTime:
                    selectedTime ?? TimeOfDay.fromDateTime(businessNow),
              );
              if (picked != null) {
                setSheetState(() {
                  selectedTime = picked;
                  updateSelectedInstant();
                });
              }
            }

            Future<void> submit() async {
              if (submitting || !canSubmit()) return;
              setSheetState(() {
                submitting = true;
                submissionError = null;
              });
              FocusScope.of(context).unfocus();
              final draft = (
                name: clientNameController.text.trim(),
                phone: phoneController.text.trim(),
                email: emailController.text.trim(),
                service: serviceController.text.trim(),
                location: locationController.text.trim(),
                notes: notesController.text.trim(),
                createPaymentDue: createPaymentDue,
              );
              final duration =
                  int.tryParse(durationController.text.trim()) ?? 60;
              final price = double.tryParse(priceController.text.trim()) ?? 0;
              late final DateTime startTime;
              try {
                startTime = bookingRequestUtcFromWallClock(
                  date: selectedDate!,
                  hour: selectedTime!.hour,
                  minute: selectedTime!.minute,
                  timezone: bookingTimezone,
                  preferredInstantUtc: selectedInstant,
                );
              } on ArgumentError {
                setSheetState(() {
                  submitting = false;
                  submissionError =
                      'This date, time or time zone could not be used. Choose another time.';
                });
                return;
              }

              Future<BookingRequestConfirmationOutcome> confirm({
                required bool allowOverlap,
              }) {
                return ref
                    .read(profileRepositoryProvider)
                    .confirmBookingRequest(
                      request: request,
                      startTime: startTime,
                      durationMins: duration,
                      price: price,
                      clientName: draft.name,
                      clientPhone: draft.phone,
                      clientEmail: isValidBookingRequestEmail(draft.email)
                          ? draft.email
                          : null,
                      serviceTitle: draft.service,
                      location: draft.location,
                      extraNotes: draft.notes,
                      createPaymentDue: draft.createPaymentDue,
                      enforceWorkingHours: false,
                      allowOverlap: allowOverlap,
                    );
              }

              try {
                final scheduleReview = await ref
                    .read(profileRepositoryProvider)
                    .reviewBookingRequestSchedule(
                      request: request,
                      startTime: startTime.toUtc(),
                      endTime: startTime
                          .add(Duration(minutes: duration))
                          .toUtc(),
                    );
                if (!context.mounted) return;
                final proceed = await showBookingScheduleWarning(
                  context,
                  scheduleReview,
                );
                if (!proceed) {
                  if (context.mounted) {
                    setSheetState(() => submitting = false);
                  }
                  return;
                }
                final outcome = await confirm(
                  allowOverlap: scheduleReview.conflictCount > 0,
                );
                if (context.mounted) {
                  SlateHaptics.success();
                  Navigator.pop(context, outcome);
                }
              } on AppointmentScheduleException catch (error) {
                if (context.mounted) {
                  setSheetState(() {
                    submitting = false;
                    submissionError = error.message;
                  });
                }
              } on BookingRequestStateException catch (error) {
                ref.invalidate(bookingRequestsProvider);
                if (context.mounted) {
                  setSheetState(() {
                    submitting = false;
                    submissionError = error.message;
                  });
                }
              } catch (_) {
                if (context.mounted) {
                  setSheetState(() {
                    submitting = false;
                    submissionError =
                        'The booking was not created. Check your connection and try again.';
                  });
                }
              }
            }

            final price = double.tryParse(priceController.text.trim()) ?? 0;
            final valid = canSubmit();
            final choices = possibleInstants();
            final formNote = selectedInstant == null
                ? choices.length > 1
                      ? 'The clocks change at this time. Choose which occurrence you agreed with the customer.'
                      : selectedDate != null && selectedTime != null
                      ? 'This clock time does not exist on the selected date. Choose another time.'
                      : 'Choose the date and time agreed with the customer before creating the booking.'
                : !valid
                ? 'Add a client, phone, service, valid duration and price. Check the email address if provided.'
                : createPaymentDue && price > 0
                ? 'This will create the booking and an unpaid Money item.'
                : 'This will create the booking and close the request.';

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop || submitting || askingToClose) return;
                if (!hasChanges()) {
                  Navigator.pop(context);
                  return;
                }
                askingToClose = true;
                final decision = await showWorkloopDraftConfirmation(
                  context,
                  title: 'Keep this booking draft?',
                  message:
                      'Your changes have not been saved. Create the booking, keep editing, or discard the draft.',
                  saveLabel: 'Create booking',
                  canSave: canSubmit(),
                );
                askingToClose = false;
                if (!context.mounted) return;
                if (decision == WorkloopDraftDecision.save) {
                  await submit();
                } else if (decision == WorkloopDraftDecision.discard) {
                  Navigator.pop(context);
                }
              },
              child: SlateSheetFrame(
                scrollable: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WorkloopSheetHeader(
                      title: 'Confirm booking',
                      subtitle:
                          'Check the details, then add it to your calendar.',
                      canClose: !submitting,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Column(
                        children: [
                          if (requestedTimeLabel != null)
                            _SheetSummaryRow(
                              icon: LucideIcons.messageSquare,
                              label: 'Asked for',
                              value: requestedTimeLabel,
                            ),
                          if (request.message?.isNotEmpty == true) ...[
                            if (requestedTimeLabel != null)
                              const SizedBox(height: 10),
                            _SheetSummaryRow(
                              icon: LucideIcons.messageCircle,
                              label: 'Message',
                              value: request.message!,
                            ),
                          ],
                          if (requestedAddOns.isNotEmpty) ...[
                            if (requestedTimeLabel != null ||
                                request.message?.isNotEmpty == true)
                              const SizedBox(height: 10),
                            _SheetSummaryRow(
                              icon: LucideIcons.plus,
                              label: 'Add-ons',
                              value: requestedAddOns
                                  .map((item) => item.name)
                                  .join(', '),
                            ),
                          ],
                          if (requestedTimeLabel == null &&
                              request.message?.isEmpty != false &&
                              requestedAddOns.isEmpty)
                            Text(
                              'No extra message was included with this request.',
                              style: TextStyle(
                                color: AppColors.of(context).t3,
                                fontSize: 12,
                                height: 1.32,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SheetField(
                      enabled: !submitting,
                      controller: clientNameController,
                      label: 'Client name',
                      isRequired: true,
                      icon: LucideIcons.user,
                      keyboardType: TextInputType.name,
                      onChanged: (_) => refreshForm(),
                    ),
                    const SizedBox(height: 10),
                    _SheetField(
                      enabled: !submitting,
                      controller: phoneController,
                      label: 'Phone',
                      isRequired: true,
                      icon: LucideIcons.phone,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => refreshForm(),
                    ),
                    const SizedBox(height: 10),
                    _SheetField(
                      enabled: !submitting,
                      controller: emailController,
                      label: 'Customer email',
                      icon: LucideIcons.mail,
                      keyboardType: TextInputType.emailAddress,
                      readOnly: !canEditEmail,
                      onChanged: (_) => refreshForm(),
                    ),
                    const SizedBox(height: 10),
                    _SheetField(
                      enabled: !submitting,
                      controller: serviceController,
                      label: 'Service',
                      isRequired: true,
                      keyboardType: TextInputType.text,
                      readOnly: isServiceBundle,
                      onChanged: (_) => refreshForm(),
                    ),
                    const SizedBox(height: 14),
                    const WorkloopFieldLabel('Date and time', isRequired: true),
                    const SizedBox(height: AppSpacing.xs),
                    _ResponsiveSheetPair(
                      first: _SheetPickerButton(
                        icon: LucideIcons.calendar,
                        label: selectedDate == null
                            ? 'Choose date'
                            : _formatSheetDate(selectedDate!),
                        onTap: submitting ? null : pickDate,
                      ),
                      second: _SheetPickerButton(
                        icon: LucideIcons.clock3,
                        label: selectedTime?.format(context) ?? 'Choose time',
                        onTap: submitting ? null : pickTime,
                      ),
                    ),
                    if (requestedTime.issue != null &&
                        selectedInstant == null) ...[
                      const SizedBox(height: 8),
                      Text(
                        requestedTime.issue == BookingRequestTimeIssue.invalid
                            ? 'The requested date or time could not be used. Confirm another time with the customer.'
                            : requestedTime.issue ==
                                  BookingRequestTimeIssue.repeatedHour
                            ? 'This requested time occurs twice because the clocks change.'
                            : 'The customer has not specified an exact date and time. Choose the details agreed with them.',
                        style: TextStyle(color: AppColors.of(context).t3),
                      ),
                    ],
                    if (choices.length > 1) ...[
                      const SizedBox(height: 8),
                      const WorkloopFieldLabel(
                        'Time occurrence',
                        isRequired: true,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      WorkloopPickerField<DateTime>(
                        title: 'Which occurrence?',
                        hint: 'Choose the agreed time',
                        value: selectedInstant == null
                            ? null
                            : choices
                                  .where(
                                    (choice) =>
                                        choice.millisecondsSinceEpoch ~/
                                            60000 ==
                                        selectedInstant!
                                                .millisecondsSinceEpoch ~/
                                            60000,
                                  )
                                  .firstOrNull,
                        options: choices.indexed
                            .map(
                              (entry) => WorkloopPickerOption(
                                value: entry.$2,
                                label:
                                    '${entry.$1 == 0 ? 'First' : 'Second'} ${selectedTime!.format(context)} · ${bookingRequestOccurrenceLabel(entry.$2, bookingTimezone)}',
                              ),
                            )
                            .toList(),
                        enabled: !submitting,
                        onChanged: (value) =>
                            setSheetState(() => selectedInstant = value),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _ResponsiveSheetPair(
                      first: _SheetField(
                        enabled: !submitting,
                        controller: durationController,
                        label: 'Duration mins',
                        isRequired: true,
                        readOnly: isServiceBundle,
                        icon: LucideIcons.timer,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => refreshForm(),
                      ),
                      second: _SheetField(
                        enabled: !submitting,
                        controller: priceController,
                        label: 'Price',
                        isRequired: true,
                        readOnly: isServiceBundle,
                        icon: LucideIcons.banknote,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => refreshForm(),
                      ),
                    ),
                    if (isServiceBundle) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Service names, duration and price are saved from the customer’s request.',
                        style: TextStyle(color: AppColors.of(context).t3),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _SheetField(
                      enabled: !submitting,
                      controller: locationController,
                      label: 'Location',
                      icon: LucideIcons.mapPin,
                      keyboardType: TextInputType.text,
                      onChanged: (_) => refreshForm(),
                    ),
                    const SizedBox(height: 10),
                    _SheetField(
                      enabled: !submitting,
                      controller: notesController,
                      label: 'Private booking note',
                      icon: LucideIcons.fileText,
                      keyboardType: TextInputType.multiline,
                      maxLines: 2,
                      onChanged: (_) => refreshForm(),
                    ),
                    if (price > 0) ...[
                      const SizedBox(height: 12),
                      _SheetSwitchRow(
                        title: 'Add a payment to collect',
                        subtitle: 'Links an unpaid Money item to the booking.',
                        value: createPaymentDue,
                        onChanged: submitting
                            ? null
                            : (value) =>
                                  setSheetState(() => createPaymentDue = value),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _SheetEmptyHint(text: formNote),
                    if (submissionError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Semantics(
                        liveRegion: true,
                        container: true,
                        label: submissionError,
                        child: _SheetSubmissionError(message: submissionError!),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SlateButton(
                      label: submitting
                          ? 'Creating booking…'
                          : 'Create booking',
                      icon: submitting ? null : LucideIcons.calendarCheck,
                      onPressed: valid && !submitting ? submit : null,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // The modal future completes when pop begins; keep controllers alive for
    // the closing transition so its text fields cannot rebuild after disposal.
    Future<void>.delayed(sheetCloseDuration, () {
      clientNameController.dispose();
      phoneController.dispose();
      emailController.dispose();
      serviceController.dispose();
      durationController.dispose();
      priceController.dispose();
      locationController.dispose();
      notesController.dispose();
    });
    if (!mounted) return;
    setState(() => _openingBooking = false);
    if (confirmation == null) return;

    ref.invalidate(bookingRequestsProvider);
    ref.invalidate(appointmentsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(dashboardRevenueProvider);
    ref.invalidate(dashboardFocusProvider);
    ref.invalidate(todayAppointmentsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
    if (mounted) {
      final successMessage = bookingRequestConfirmationMessage(
        confirmation.confirmationEmailStatus,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor:
              confirmation.confirmationEmailStatus ==
                  BookingRequestConfirmationEmailStatus.failed
              ? AppColors.of(context).warning
              : AppColors.of(context).success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (widget.closeAfterAction) Navigator.pop(context);
    }
  }

  Future<void> _call() async {
    final phone = widget.request.phone.replaceAll(' ', '');
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _email() async {
    await launchUrl(Uri(scheme: 'mailto', path: widget.request.email));
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final requestedTimeLabel = bookingRequestRequestedTimeLabel(
      context,
      request,
    );
    final pending = request.status == 'pending';
    final contacted = request.status == 'contacted';
    final requestedAddOns = request.serviceItems
        .where((item) => item.isAddOn)
        .toList(growable: false);
    return Container(
      padding: widget.detailMode
          ? EdgeInsets.zero
          : const EdgeInsets.all(AppSpacing.md),
      decoration: widget.detailMode
          ? null
          : BoxDecoration(
              color: AppColors.of(context).bgCard,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.of(context).border),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.name,
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusBadge(status: request.status),
            ],
          ),
          if (isValidBookingRequestEmail(request.email)) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.of(context).t2),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Email ${request.name}',
                  onTap: _email,
                  child: ExcludeSemantics(
                    child: OutlinedButton.icon(
                      onPressed: _email,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.of(context).t2,
                        minimumSize: const Size(0, AppSpacing.minTouch),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: BorderSide(color: AppColors.of(context).border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      icon: const Icon(LucideIcons.mail, size: 14),
                      label: const Text(
                        'Email',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  request.phone,
                  style: TextStyle(color: AppColors.of(context).t2),
                ),
              ),
              Semantics(
                button: true,
                label: 'Call ${request.name}',
                onTap: _call,
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    onPressed: _call,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.of(context).t2,
                      minimumSize: const Size(0, AppSpacing.minTouch),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: AppColors.of(context).border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    icon: const Icon(LucideIcons.phone, size: 14),
                    label: const Text(
                      'Call',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (request.serviceName?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.lg),
            _SheetSummaryRow(
              icon: LucideIcons.briefcase,
              label: 'Service',
              value: request.serviceName!,
            ),
          ],
          if (requestedTimeLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _SheetSummaryRow(
              icon: LucideIcons.clock3,
              label: 'Requested time',
              value: requestedTimeLabel,
            ),
          ],
          if (requestedAddOns.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _SheetSummaryRow(
              icon: LucideIcons.plus,
              label: 'Add-ons',
              value: requestedAddOns.map((item) => item.name).join(', '),
            ),
          ],
          if (request.message?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              request.message!,
              style: TextStyle(color: AppColors.of(context).t3, height: 1.35),
            ),
          ],
          if (pending || contacted) ...[
            const SizedBox(height: AppSpacing.lg),
            _ActionButton(
              label: 'Book',
              variant: _RequestActionVariant.primary,
              loading: _saving || _openingBooking,
              onTap: _confirmAsBooking,
            ),
            const SizedBox(height: AppSpacing.xs),
            _ResponsiveSheetPair(
              first: pending
                  ? _ActionButton(
                      label: 'Mark contacted',
                      variant: _RequestActionVariant.secondary,
                      loading: _saving || _openingBooking,
                      onTap: () => _setStatus('contacted'),
                    )
                  : const SizedBox.shrink(),
              second: _ActionButton(
                label: 'Decline',
                variant: _RequestActionVariant.destructiveQuiet,
                loading: _saving || _openingBooking,
                onTap: _declineRequest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String bookingRequestConfirmationMessage(
  BookingRequestConfirmationEmailStatus status,
) => switch (status) {
  BookingRequestConfirmationEmailStatus.sent =>
    'Booking confirmed and confirmation email sent.',
  BookingRequestConfirmationEmailStatus.pending =>
    'Booking confirmed. The confirmation email is queued.',
  BookingRequestConfirmationEmailStatus.failed =>
    'Booking confirmed, but the email could not be sent. Contact the customer directly.',
  BookingRequestConfirmationEmailStatus.notApplicable =>
    'Booking confirmed. No email was available for confirmation.',
};

String? bookingRequestRequestedTimeLabel(
  BuildContext context,
  BookingRequest request, {
  String? timezone,
}) {
  if (request.requestedFor != null) {
    final effectiveTimezone = timezone ?? request.requestedTimezone?.trim();
    if (effectiveTimezone == null || effectiveTimezone.isEmpty) {
      return 'Requested time needs checking';
    }
    late final DateTime wallClock;
    try {
      wallClock = bookingRequestWallClock(
        requestedForUtc: request.requestedFor!,
        timezone: effectiveTimezone,
      );
    } on ArgumentError {
      return 'Requested time unavailable';
    }
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(wallClock)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(wallClock))}';
  }
  final legacy = request.preferredTimeText?.trim();
  return legacy?.isNotEmpty == true ? legacy : null;
}

String _formatSheetDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

class _SheetPickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SheetPickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap == null
          ? null
          : () {
              SlateHaptics.selection();
              onTap!();
            },
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null
              ? null
              : () {
                  SlateHaptics.selection();
                  onTap!();
                },
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.of(context).bgInteract,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.of(context).border),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.of(context).t3, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppColors.of(context).t1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponsiveSheetPair extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _ResponsiveSheetPair({required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBody = MediaQuery.textScalerOf(context).scale(14);
        final stacked = constraints.maxWidth < 360 || scaledBody > 18;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 10), second],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isRequired;
  final IconData? icon;
  final TextInputType keyboardType;
  final int maxLines;
  final bool readOnly;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const _SheetField({
    required this.controller,
    required this.label,
    this.isRequired = false,
    this.icon,
    required this.keyboardType,
    this.maxLines = 1,
    this.readOnly = false,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopFormField(
      label: label,
      isRequired: isRequired,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: readOnly,
        onChanged: onChanged,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelStyle: TextStyle(color: AppColors.of(context).t3),
          prefixIcon: icon == null
              ? null
              : Icon(icon, color: AppColors.of(context).t3, size: 17),
        ),
      ),
    );
  }
}

class _SheetSubmissionError extends StatelessWidget {
  final String message;

  const _SheetSubmissionError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.of(context).error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.of(context).error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.circleAlert,
            color: AppColors.of(context).error,
            size: 17,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.of(context).error,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetEmptyHint extends StatelessWidget {
  final String text;
  const _SheetEmptyHint({required this.text});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: AppColors.of(context).t3,
      fontSize: 13,
      height: 1.4,
    ),
  );
}

class _SheetSummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SheetSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, color: AppColors.of(context).t3, size: 18),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              value,
              style: TextStyle(
                color: AppColors.of(context).t1,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SheetSwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SheetSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(
        color: AppColors.of(context).t3,
        fontSize: 13,
        height: 1.4,
      ),
    ),
    value: value,
    onChanged: onChanged == null
        ? null
        : (value) {
            SlateHaptics.selection();
            onChanged!(value);
          },
  );
}

enum _RequestActionVariant { primary, secondary, destructiveQuiet }

class _ActionButton extends StatelessWidget {
  final String label;
  final _RequestActionVariant variant;
  final bool loading;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.variant,
    required this.loading,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    if (variant == _RequestActionVariant.destructiveQuiet) {
      return WorkloopTextButton(
        label: label,
        destructive: true,
        onPressed: loading ? null : onTap,
      );
    }
    return SlateButton(
      label: label,
      secondary: variant == _RequestActionVariant.secondary,
      onPressed: loading ? null : onTap,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'confirmed' => AppColors.of(context).success,
      'declined' => AppColors.of(context).error,
      'contacted' => AppColors.of(context).t2,
      _ => AppColors.of(context).warning,
    };
    final label = switch (status) {
      'confirmed' => 'Booked',
      'declined' => 'Declined',
      'contacted' => 'Contacted',
      _ => 'New',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  const _EmptyRequests({
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.inbox,
                    color: AppColors.of(context).t3,
                    size: 38,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.of(context).t1,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.of(context).t3),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    WorkloopTextButton(label: 'Try again', onPressed: onRetry),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
