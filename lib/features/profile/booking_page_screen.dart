import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/public_booking_url.dart';
import '../../shared/utils/working_hours.dart';
import '../../shared/widgets/slate_ui.dart';
import '../public_profile/booking_requests_screen.dart';
import '../public_profile/public_profile_screen.dart';
import '../settings/providers/settings_providers.dart';
import '../settings/widgets/settings_business_tab.dart';
import 'profile_editor_screen.dart';

class BookingPageScreen extends ConsumerWidget {
  const BookingPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final profile = ref.watch(settingsBusinessProfileProvider);
    final settings = ref.watch(settingsWorkspaceSettingsProvider);
    final services = ref.watch(settingsServicesProvider);
    final requests = ref.watch(bookingRequestsProvider);
    final coreReady =
        workspace.hasValue &&
        profile.hasValue &&
        settings.hasValue &&
        services.hasValue;
    final coreFailed =
        workspace.hasError ||
        profile.hasError ||
        settings.hasError ||
        services.hasError;

    if (!coreReady) {
      return _BookingPageInitialState(
        failed: coreFailed,
        onRetry: () => _refresh(ref),
      );
    }

    final workspaceData = workspace.value;
    final profileData = profile.value;
    final settingsData = settings.value;
    final servicesData = services.value ?? const <Map<String, dynamic>>[];
    final businessName = workspaceData?['name']?.toString().trim() ?? '';
    final industry = workspaceData?['industry']?.toString().trim();
    final handle = profileData?.handle.trim() ?? '';
    final workingHours = settingsData?['working_hours'] is Map
        ? Map<String, dynamic>.from(settingsData!['working_hours'] as Map)
        : <String, dynamic>{};
    final publicServices = servicesData
        .where(
          (service) =>
              service['active'] != false && service['show_on_profile'] != false,
        )
        .map(Service.fromMap)
        .toList();
    final hasHours = workingHours.values.any(
      (value) => workingHourBlocks(value).isNotEmpty,
    );
    final acceptingRequests = profileData?.bookingMode == 'manual';
    final setupComplete =
        handle.isNotEmpty &&
        businessName.isNotEmpty &&
        publicServices.isNotEmpty &&
        hasHours;
    final status = handle.isEmpty
        ? _BookingPageStatus.needsSetup
        : !acceptingRequests
        ? _BookingPageStatus.paused
        : setupComplete
        ? _BookingPageStatus.accepting
        : _BookingPageStatus.needsAttention;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: RefreshIndicator(
              color: AppColors.of(context).accentPrimary,
              onRefresh: () => _refresh(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  AppSpacing.screenTop,
                  AppSpacing.pageX,
                  AppSpacing.xxl,
                ),
                children: [
                  WorkloopRouteHeader(
                    title: 'Booking page',
                    backSemanticLabel: 'Back to Business',
                    trailing: WorkloopTextButton(
                      label: 'Edit',
                      onPressed: () => _openEditor(
                        context,
                        ref,
                        SettingsBusinessSection.publicProfile,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _BookingPageHero(
                    status: status,
                    handle: handle,
                    businessName: businessName,
                    onPreview: handle.isEmpty
                        ? null
                        : () => _openPreview(
                            context,
                            handle: handle,
                            businessName: businessName,
                            industry: industry,
                            profile: profileData!,
                            workingHours: workingHours,
                            services: publicServices,
                            timezone:
                                settingsData?['timezone']?.toString() ??
                                'Europe/London',
                          ),
                    onCopy: handle.isEmpty
                        ? null
                        : () => _copyLink(context, handle),
                    onShare: handle.isEmpty
                        ? null
                        : () => _shareLink(context, businessName, handle),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const WorkloopSectionHeader(label: 'Requests'),
                  const SizedBox(height: AppSpacing.xs),
                  requests.when(
                    loading: () => const SlateLoadingBlock(
                      height: 76,
                      radius: AppRadius.lg,
                    ),
                    error: (_, _) => WorkloopListRow(
                      flat: true,
                      showDivider: false,
                      onTap: () => ref.invalidate(bookingRequestsProvider),
                      leading: const _RowIcon(icon: LucideIcons.refreshCw),
                      title: const Text('Could not load requests'),
                      subtitle: const Text('Tap to try again'),
                      trailing: Icon(
                        LucideIcons.chevronRight,
                        color: AppColors.of(context).t3,
                        size: 16,
                      ),
                    ),
                    data: (items) {
                      final waiting = items
                          .where(
                            (item) =>
                                item.status == 'pending' ||
                                item.status == 'contacted',
                          )
                          .length;
                      return WorkloopListRow(
                        flat: true,
                        showDivider: false,
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BookingRequestsScreen(),
                          ),
                        ),
                        leading: const _RowIcon(icon: LucideIcons.inbox),
                        title: const Text(
                          'Booking requests',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          waiting == 0
                              ? 'No requests waiting'
                              : '$waiting ${waiting == 1 ? 'request' : 'requests'} waiting for a response',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (waiting > 0) ...[
                              Text(
                                '$waiting',
                                style: TextStyle(
                                  color: AppColors.of(context).accentPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            Icon(
                              LucideIcons.chevronRight,
                              color: AppColors.of(context).t3,
                              size: 16,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const WorkloopSectionHeader(label: 'Page readiness'),
                  const SizedBox(height: AppSpacing.xs),
                  _ReadinessRow(
                    title: 'Business details',
                    subtitle: businessName.isEmpty
                        ? 'Add the name clients should see'
                        : businessName,
                    complete: businessName.isNotEmpty,
                    onTap: () => _openEditor(
                      context,
                      ref,
                      SettingsBusinessSection.business,
                    ),
                  ),
                  _ReadinessRow(
                    title: 'Visible services',
                    subtitle: publicServices.isEmpty
                        ? 'Choose at least one service to show'
                        : '${publicServices.length} ${publicServices.length == 1 ? 'service' : 'services'} shown',
                    complete: publicServices.isNotEmpty,
                    onTap: () => _openEditor(
                      context,
                      ref,
                      SettingsBusinessSection.services,
                    ),
                  ),
                  _ReadinessRow(
                    title: 'Working hours',
                    subtitle: hasHours
                        ? 'Clients can see when you usually work'
                        : 'Add the days and times you usually work',
                    complete: hasHours,
                    onTap: () => _openEditor(
                      context,
                      ref,
                      SettingsBusinessSection.workingHours,
                    ),
                  ),
                  _ReadinessRow(
                    title: 'Booking link',
                    subtitle: handle.isEmpty
                        ? 'Choose your public booking address'
                        : publicBookingPageDisplayUrl(handle),
                    complete: handle.isNotEmpty,
                    showDivider: false,
                    onTap: () => _openEditor(
                      context,
                      ref,
                      SettingsBusinessSection.publicProfile,
                    ),
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
      // Provider error states remain visible and can be retried.
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    SettingsBusinessSection section,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ProfileEditorScreen(section: section)),
    );
    if (!context.mounted) return;
    ref.invalidate(workspaceProvider);
    ref.invalidate(settingsBusinessProfileProvider);
    ref.invalidate(settingsWorkspaceSettingsProvider);
    ref.invalidate(settingsServicesProvider);
  }

  Future<void> _copyLink(BuildContext context, String handle) async {
    await Clipboard.setData(
      ClipboardData(text: publicBookingPageUri(handle).toString()),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Booking link copied')));
  }

  Future<void> _shareLink(
    BuildContext context,
    String businessName,
    String handle,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Request a booking with ${businessName.isEmpty ? 'my business' : businessName}: ${publicBookingPageUri(handle)}',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _openPreview(
    BuildContext context, {
    required String handle,
    required String businessName,
    required String? industry,
    required BusinessProfile profile,
    required Map<String, dynamic> workingHours,
    required List<Service> services,
    required String timezone,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          handle: handle,
          previewProfile: PublicProfile(
            profile: profile,
            businessName: businessName,
            industry: industry,
            workingHours: workingHours,
            services: services,
            timezone: timezone,
          ),
        ),
      ),
    );
  }
}

enum _BookingPageStatus { accepting, paused, needsSetup, needsAttention }

extension on _BookingPageStatus {
  String get label => switch (this) {
    _BookingPageStatus.accepting => 'Accepting requests',
    _BookingPageStatus.paused => 'Requests paused',
    _BookingPageStatus.needsSetup => 'Needs setup',
    _BookingPageStatus.needsAttention => 'Needs attention',
  };

  String get message => switch (this) {
    _BookingPageStatus.accepting =>
      'Your page is ready to share with customers.',
    _BookingPageStatus.paused =>
      'Customers can view the page but cannot send new requests.',
    _BookingPageStatus.needsSetup =>
      'Choose a booking link before sharing your page.',
    _BookingPageStatus.needsAttention =>
      'Complete the items below so customers have enough information.',
  };

  Color color(WorkloopThemeTokens tokens) => switch (this) {
    _BookingPageStatus.accepting => tokens.success,
    _BookingPageStatus.paused => tokens.textTertiary,
    _BookingPageStatus.needsSetup ||
    _BookingPageStatus.needsAttention => tokens.warning,
  };
}

class _BookingPageHero extends StatelessWidget {
  final _BookingPageStatus status;
  final String handle;
  final String businessName;
  final VoidCallback? onPreview;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  const _BookingPageHero({
    required this.status,
    required this.handle,
    required this.businessName,
    required this.onPreview,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final statusColor = status.color(tokens);
    return WorkloopSurface(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.calendarCheck2,
                  color: tokens.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            status.label,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      handle.isEmpty
                          ? 'Your booking page'
                          : publicBookingPageDisplayUrl(handle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).t1,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            status.message,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _HeroAction(
                  icon: LucideIcons.eye,
                  label: 'Preview',
                  onTap: onPreview,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _HeroAction(
                  icon: LucideIcons.copy,
                  label: 'Copy',
                  onTap: onCopy,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _HeroAction(
                  icon: LucideIcons.share2,
                  label: 'Share',
                  onTap: onShare,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _HeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled
            ? tokens.surfaceSubtle
            : tokens.surfaceSubtle.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: enabled ? tokens.accent : tokens.textDisabled,
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? tokens.textPrimary : tokens.textDisabled,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _ReadinessRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool complete;
  final VoidCallback onTap;
  final bool showDivider;

  const _ReadinessRow({
    required this.title,
    required this.subtitle,
    required this.complete,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      flat: true,
      showDivider: showDivider,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: (complete ? tokens.success : tokens.warning).withValues(
            alpha: 0.12,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          complete ? LucideIcons.check : LucideIcons.circleAlert,
          size: 17,
          color: complete ? tokens.success : tokens.warning,
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: AppColors.of(context).t3,
        size: 16,
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  final IconData icon;
  const _RowIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.of(context).modBg,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.of(context).t2, size: 18),
    );
  }
}

class _BookingPageInitialState extends StatelessWidget {
  final bool failed;
  final Future<void> Function() onRetry;

  const _BookingPageInitialState({required this.failed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                AppSpacing.screenTop,
                AppSpacing.pageX,
                AppSpacing.xxl,
              ),
              children: [
                const WorkloopRouteHeader(
                  title: 'Booking page',
                  backSemanticLabel: 'Back to Business',
                ),
                const SizedBox(height: AppSpacing.md),
                if (failed)
                  SlateErrorState(
                    message: 'Could not load your booking page.',
                    onRetry: () => onRetry().ignore(),
                  )
                else ...[
                  const SlateLoadingBlock(height: 220, radius: AppRadius.xl),
                  const SizedBox(height: AppSpacing.md),
                  const SlateLoadingBlock(height: 260, radius: AppRadius.lg),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
