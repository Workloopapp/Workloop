import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/working_hours.dart';
import '../../shared/widgets/slate_ui.dart';
import '../settings/providers/settings_providers.dart';
import '../settings/business_document_settings_screen.dart';
import '../settings/widgets/settings_business_tab.dart';
import 'profile_editor_screen.dart';

String profileWorkingHoursSummary(Map<String, dynamic> workingHours) {
  final normalized = {
    for (final entry in workingHours.entries)
      entry.key.toLowerCase(): entry.value,
  };
  final enabled = workingHourDays.where((day) {
    final lower = day.toLowerCase();
    final value = normalized[lower] ?? normalized[lower.substring(0, 3)];
    return workingHourBlocks(value).isNotEmpty;
  }).toList();
  if (enabled.isEmpty) return 'Working hours not set';
  if (enabled.length == 7) return 'Open every day';
  return '${enabled.length} working ${enabled.length == 1 ? 'day' : 'days'}';
}

String profileServicesSummary(int count) {
  if (count == 0) return 'No services added';
  return '$count ${count == 1 ? 'service' : 'services'} available';
}

String profileRequestSummary(int count) {
  if (count == 0) return 'No requests waiting';
  return '$count ${count == 1 ? 'request' : 'requests'} waiting';
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final settings = ref.watch(settingsWorkspaceSettingsProvider);
    final services = ref.watch(settingsServicesProvider);
    final auth = ref.watch(authRepositoryProvider);

    final profileDataReady =
        workspace.hasValue && settings.hasValue && services.hasValue;
    final profileHasFailure =
        workspace.hasError || settings.hasError || services.hasError;
    if (!profileDataReady) {
      return _ProfileInitialState(
        failed: profileHasFailure,
        onRetry: () => _refresh(ref),
      );
    }

    final workspaceData = workspace.value;
    final settingsData = settings.value;
    final servicesData = services.value ?? const <Map<String, dynamic>>[];
    final businessName = workspaceData?['name']?.toString().trim();
    final displayName = businessName?.isNotEmpty == true
        ? businessName!
        : 'Your business';
    final industry = workspaceData?['industry']?.toString().trim();
    final ownerName = auth.currentFirstName?.trim();
    final workingHours = settingsData?['working_hours'] is Map
        ? Map<String, dynamic>.from(settingsData!['working_hours'] as Map)
        : <String, dynamic>{};

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
                  _ProfileHeader(
                    onEdit: () => _openProfileEditor(
                      context,
                      ref,
                      SettingsBusinessSection.business,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ProfileIdentity(
                    businessName: displayName,
                    industry: industry?.isNotEmpty == true
                        ? industry!
                        : 'Add your industry',
                    ownerName: ownerName,
                    onBusinessTap: () => _openProfileEditor(
                      context,
                      ref,
                      SettingsBusinessSection.business,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const WorkloopSectionHeader(label: 'Business'),
                  const SizedBox(height: AppSpacing.xs),
                  _ProfileRow(
                    icon: LucideIcons.briefcase,
                    title: 'Business details',
                    subtitle: industry?.isNotEmpty == true
                        ? '$displayName · $industry'
                        : 'Name, industry, and public description',
                    onTap: () => _openProfileEditor(
                      context,
                      ref,
                      SettingsBusinessSection.business,
                    ),
                  ),
                  _ProfileRow(
                    icon: LucideIcons.fileText,
                    title: 'Invoice setup',
                    subtitle:
                        'Legal details, contact information and payment terms',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BusinessDocumentSettingsScreen(),
                      ),
                    ),
                  ),
                  _ProfileRow(
                    icon: LucideIcons.slidersHorizontal,
                    title: 'Services',
                    subtitle: profileServicesSummary(servicesData.length),
                    onTap: () => _openProfileEditor(
                      context,
                      ref,
                      SettingsBusinessSection.services,
                    ),
                  ),
                  _ProfileRow(
                    icon: LucideIcons.clock3,
                    title: 'Working hours',
                    subtitle: profileWorkingHoursSummary(workingHours),
                    onTap: () => _openProfileEditor(
                      context,
                      ref,
                      SettingsBusinessSection.workingHours,
                    ),
                    showDivider: false,
                  ),
                  if (profileHasFailure) ...[
                    const SizedBox(height: AppSpacing.xl),
                    SlateErrorState(
                      message:
                          'Some profile details could not be refreshed. Existing details are still shown.',
                      onRetry: () => _refresh(ref).ignore(),
                    ),
                  ],
                  if (workspace.isLoading ||
                      settings.isLoading ||
                      services.isLoading) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.of(context).accentPrimary,
                        ),
                      ),
                    ),
                  ],
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
    ref.invalidate(settingsWorkspaceSettingsProvider);
    ref.invalidate(settingsServicesProvider);
    try {
      await Future.wait([
        ref.read(workspaceProvider.future),
        ref.read(settingsWorkspaceSettingsProvider.future),
        ref.read(settingsServicesProvider.future),
      ]);
    } catch (_) {
      // Provider error states remain visible and can be retried.
    }
  }

  Future<void> _openProfileEditor(
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
    ref.invalidate(settingsWorkspaceSettingsProvider);
    ref.invalidate(settingsServicesProvider);
  }
}

class _ProfileInitialState extends StatelessWidget {
  final bool failed;
  final Future<void> Function() onRetry;

  const _ProfileInitialState({required this.failed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: RefreshIndicator(
              color: AppColors.of(context).accentPrimary,
              onRefresh: onRetry,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  AppSpacing.screenTop,
                  AppSpacing.pageX,
                  AppSpacing.xxl,
                ),
                children: [
                  const _ProfileHeader(onEdit: null),
                  const SizedBox(height: AppSpacing.md),
                  if (failed)
                    SlateErrorState(
                      message:
                          'Could not load your profile. Check your connection.',
                      onRetry: () => onRetry().ignore(),
                    )
                  else ...[
                    const SlateLoadingBlock(height: 92, radius: AppRadius.lg),
                    const SizedBox(height: AppSpacing.md),
                    const SlateLoadingBlock(height: 86, radius: AppRadius.lg),
                    const SizedBox(height: AppSpacing.xl),
                    const SlateLoadingBlock(height: 210, radius: AppRadius.lg),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final VoidCallback? onEdit;

  const _ProfileHeader({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return WorkloopRouteHeader(
      title: 'Business profile',
      backSemanticLabel: 'Back to Business',
      trailing: WorkloopTextButton(label: 'Edit', onPressed: onEdit),
    );
  }
}

class _ProfileIdentity extends StatelessWidget {
  final String businessName;
  final String industry;
  final String? ownerName;
  final VoidCallback onBusinessTap;

  const _ProfileIdentity({
    required this.businessName,
    required this.industry,
    required this.ownerName,
    required this.onBusinessTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = businessName.trim().isEmpty
        ? 'W'
        : businessName.trim()[0].toUpperCase();
    return Column(
      children: [
        InkWell(
          onTap: onBusinessTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.of(context).accentPrimaryStrong,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: AppColors.of(context).onBrandAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontSize: 20,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        industry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ownerName?.isNotEmpty == true
                            ? ownerName!
                            : 'Add your name in Business details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).t3,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 17,
                  color: AppColors.of(context).t3,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopListRow(
      flat: true,
      onTap: onTap,
      showDivider: showDivider,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.of(context).modBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: AppColors.of(context).t2),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t3,
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w400,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: AppColors.of(context).t3,
          ),
        ],
      ),
    );
  }
}
