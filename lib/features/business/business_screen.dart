import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/utils/public_booking_url.dart';
import '../../shared/utils/working_hours.dart';
import '../../shared/widgets/slate_ui.dart';
import '../finance/tax_estimate_screen.dart';
import '../profile/booking_page_screen.dart';
import '../profile/profile_editor_screen.dart';
import '../profile/profile_screen.dart';
import '../public_profile/booking_requests_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/providers/settings_providers.dart';
import '../settings/customer_reminders_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/widgets/settings_business_tab.dart';

class BusinessScreen extends ConsumerWidget {
  const BusinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SlateTheme.of(context);
    final workspace = ref.watch(workspaceProvider);
    final profile = ref.watch(settingsBusinessProfileProvider);
    final settings = ref.watch(settingsWorkspaceSettingsProvider);
    final services = ref.watch(settingsServicesProvider);
    final requests = ref.watch(bookingRequestsProvider);

    final businessName = workspace.value?['name']?.toString().trim() ?? '';
    final handle = profile.value?.handle.trim() ?? '';
    final acceptingRequests = profile.value?.bookingMode == 'manual';
    final publicServices =
        services.value
            ?.where(
              (service) =>
                  service['active'] != false &&
                  service['show_on_profile'] != false,
            )
            .length ??
        0;
    final workingHours = settings.value?['working_hours'] is Map
        ? Map<String, dynamic>.from(settings.value!['working_hours'] as Map)
        : <String, dynamic>{};
    final hasWorkingHours = workingHours.values.any(
      (value) => workingHourBlocks(value).isNotEmpty,
    );
    final waitingRequests =
        requests.value?.where((request) => request.needsDecision).length ?? 0;
    final coreLoading =
        workspace.isLoading ||
        profile.isLoading ||
        settings.isLoading ||
        services.isLoading;
    final coreFailure =
        workspace.hasError ||
        profile.hasError ||
        settings.hasError ||
        services.hasError;
    final status = _bookingPageStatus(
      handle: handle,
      businessName: businessName,
      serviceCount: publicServices,
      hasWorkingHours: hasWorkingHours,
      acceptingRequests: acceptingRequests,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: tokens.accent,
              onRefresh: () => _refresh(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  AppSpacing.screenTop,
                  AppSpacing.pageX,
                  AppSpacing.shellBottomClearance(context),
                ),
                children: [
                  WorkloopPageHeader(
                    title: 'Business',
                    subtitle: 'Shape how customers find and book you.',
                    color: tokens.accentInk,
                    trailing: WorkloopIconButton(
                      icon: LucideIcons.settings,
                      semanticLabel: 'Settings',
                      color: tokens.textSecondary,
                      backgroundColor: tokens.surfaceRaised,
                      borderColor: tokens.divider,
                      size: AppSpacing.minTouch,
                      onTap: () => _open(context, const SettingsScreen()),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  WorkloopPaperPanel(
                    title: 'Customer bookings',
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        WorkloopModuleRow(
                          key: const ValueKey('business-booking-requests'),
                          icon: LucideIcons.inbox,
                          title: 'Booking requests',
                          subtitle: requests.hasError
                              ? 'Could not load requests. Open to retry.'
                              : requests.isLoading && !requests.hasValue
                              ? 'Checking requests…'
                              : waitingRequests == 0
                              ? 'No requests waiting'
                              : '$waitingRequests ${waitingRequests == 1 ? 'request' : 'requests'} waiting',
                          color: tokens.accent,
                          onTap: () =>
                              _open(context, const BookingRequestsScreen()),
                        ),
                        _BookingPageFeature(
                          status: status,
                          handle: handle,
                          loading: coreLoading,
                          failed: coreFailure,
                          onOpen: () =>
                              _open(context, const BookingPageScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const WorkloopSectionHeader(label: 'Run your business'),
                  const SizedBox(height: AppSpacing.xs),
                  WorkloopModuleRow(
                    key: const ValueKey('business-reports'),
                    icon: LucideIcons.chartNoAxesCombined,
                    title: 'Reports',
                    subtitle: 'Understand your money and plan ahead',
                    color: tokens.accent,
                    onTap: () => _open(context, const ReportsScreen()),
                  ),
                  WorkloopModuleRow(
                    key: const ValueKey('business-tax-planning'),
                    icon: LucideIcons.calculator,
                    title: 'Tax planning',
                    subtitle: 'Estimate tax and what to put aside',
                    color: tokens.accent,
                    onTap: () => _open(context, const TaxEstimateScreen()),
                  ),
                  WorkloopModuleRow(
                    key: const ValueKey('business-services'),
                    icon: LucideIcons.briefcaseBusiness,
                    title: 'Services',
                    subtitle: services.isLoading
                        ? 'Checking services…'
                        : services.hasError
                        ? 'Could not load services'
                        : publicServices == 0
                        ? 'Add what customers can book'
                        : '$publicServices ${publicServices == 1 ? 'service' : 'services'} visible',
                    color: tokens.accent,
                    onTap: () =>
                        _openEditor(context, SettingsBusinessSection.services),
                  ),
                  WorkloopModuleRow(
                    key: const ValueKey('business-hours'),
                    icon: LucideIcons.clock3,
                    title: 'Working hours',
                    subtitle: settings.isLoading
                        ? 'Checking working hours…'
                        : settings.hasError
                        ? 'Could not load working hours'
                        : hasWorkingHours
                        ? profileWorkingHoursSummary(workingHours)
                        : 'Set when you usually work',
                    color: tokens.accent,
                    onTap: () => _openEditor(
                      context,
                      SettingsBusinessSection.workingHours,
                    ),
                  ),
                  WorkloopModuleRow(
                    key: const ValueKey('business-profile'),
                    icon: LucideIcons.store,
                    title: 'Business profile',
                    subtitle: workspace.isLoading
                        ? 'Checking business details…'
                        : workspace.hasError
                        ? 'Could not load business details'
                        : businessName.isEmpty
                        ? 'Add your business identity'
                        : businessName,
                    color: tokens.accent,
                    onTap: () => _open(context, const ProfileScreen()),
                  ),
                  WorkloopModuleRow(
                    key: const ValueKey('business-customer-reminders'),
                    icon: LucideIcons.calendarClock,
                    title: 'Booking reminders',
                    subtitle: 'Automatic email · Manual WhatsApp',
                    color: tokens.accent,
                    showDivider: false,
                    onTap: () =>
                        _open(context, const CustomerRemindersScreen()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(workspaceProvider);
    ref.invalidate(settingsBusinessProfileProvider);
    ref.invalidate(settingsWorkspaceSettingsProvider);
    ref.invalidate(settingsServicesProvider);
    ref.invalidate(bookingRequestsProvider);
    try {
      await Future.wait([
        ref.read(workspaceProvider.future),
        ref.read(settingsBusinessProfileProvider.future),
        ref.read(settingsWorkspaceSettingsProvider.future),
        ref.read(settingsServicesProvider.future),
        ref.read(bookingRequestsProvider.future),
      ]);
    } catch (_) {
      // Each provider exposes its own visible retry state on this screen.
    }
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _openEditor(BuildContext context, SettingsBusinessSection section) {
    _open(context, ProfileEditorScreen(section: section));
  }
}

enum _BookingPageStatus { live, needsAttention, paused }

_BookingPageStatus _bookingPageStatus({
  required String handle,
  required String businessName,
  required int serviceCount,
  required bool hasWorkingHours,
  required bool acceptingRequests,
}) {
  if (handle.isEmpty ||
      businessName.isEmpty ||
      serviceCount == 0 ||
      !hasWorkingHours) {
    return _BookingPageStatus.needsAttention;
  }
  if (!acceptingRequests) return _BookingPageStatus.paused;
  return _BookingPageStatus.live;
}

class _BookingPageFeature extends StatelessWidget {
  final _BookingPageStatus status;
  final String handle;
  final bool loading;
  final bool failed;
  final VoidCallback onOpen;

  const _BookingPageFeature({
    required this.status,
    required this.handle,
    required this.loading,
    required this.failed,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final statusColor = switch (status) {
      _BookingPageStatus.live => tokens.success,
      _BookingPageStatus.needsAttention => tokens.warning,
      _BookingPageStatus.paused => tokens.textTertiary,
    };
    final statusLabel = failed
        ? 'Unavailable'
        : loading
        ? 'Checking…'
        : switch (status) {
            _BookingPageStatus.live => 'Live',
            _BookingPageStatus.needsAttention => 'Needs attention',
            _BookingPageStatus.paused => 'Requests paused',
          };
    return WorkloopListRow(
      key: const ValueKey('business-booking-page'),
      flat: true,
      showDivider: false,
      onTap: onOpen,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      leading: const WorkloopIllustration(
        kind: WorkloopIllustrationKind.storefront,
        size: 40,
      ),
      title: Text(
        'Your booking page',
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLabel,
            style: TextStyle(
              color: failed || loading ? tokens.textSecondary : statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            failed
                ? 'Could not check your booking page. Open to retry.'
                : loading
                ? 'Checking your saved page details…'
                : handle.isEmpty
                ? 'Choose your public booking address'
                : publicBookingPageDisplayUrl(handle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: tokens.textTertiary,
        size: 17,
      ),
    );
  }
}
