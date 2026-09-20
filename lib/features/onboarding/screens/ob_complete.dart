import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/repositories/slate_repositories.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/public_booking_url.dart';
import '../../getting_started/getting_started_store.dart';

class ObComplete extends ConsumerStatefulWidget {
  final VoidCallback? onReviewSetup;

  const ObComplete({super.key, this.onReviewSetup});

  @override
  ConsumerState<ObComplete> createState() => _ObCompleteState();
}

class _ObCompleteState extends ConsumerState<ObComplete>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;
  bool _saving = false;
  bool _saved = false;
  String? _savedWorkspaceId;
  bool _reminderPreferencesFailed = false;
  bool _logoFailed = false;
  bool _animationStarted = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideUp = Tween<double>(
      begin: 30,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _saveWorkspace();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationStarted) return;
    _animationStarted = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveWorkspace() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final onboarding = ref.read(onboardingProvider);
      final workspaceId = await ref
          .read(onboardingRepositoryProvider)
          .complete(
            firstName: onboarding.firstName,
            businessName: onboarding.businessName,
            industry: onboarding.industry,
            handle: onboarding.handle,
            services: onboarding.services,
            workingHours: onboarding.workingHours,
            revenueTarget: onboarding.revenueTarget,
            firstBooking: onboarding.firstBooking,
          );
      if (!mounted) return;
      if (workspaceId == null) {
        throw StateError('Workspace was not created');
      }
      // The workspace and any first booking have already committed. An
      // optional reminder preference failure must never invite another create.
      var logoFailed = false;
      if (onboarding.logoUrl.isNotEmpty) {
        try {
          await ref
              .read(workspaceRepositoryProvider)
              .update(workspaceId, {'logo_url': onboarding.logoUrl})
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          logoFailed = true;
        }
      }
      if (!mounted) return;
      var reminderPreferencesFailed = false;
      try {
        await ref
            .read(notificationsRepositoryProvider)
            .upsertPreferences(workspaceId, onboarding.notificationPreferences)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        reminderPreferencesFailed = true;
      }
      if (!mounted) return;
      setState(() {
        _saved = true;
        _savedWorkspaceId = workspaceId;
        _reminderPreferencesFailed = reminderPreferencesFailed;
        _logoFailed = logoFailed;
      });
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('Error saving workspace: $e');
        debugPrint('Stack: $stack');
      }
      if (!mounted) return;
      setState(() {
        _saved = false;
        _saveError =
            'We could not finish setting up your workspace. Try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _goToDashboard() async {
    if (!_saved || _savedWorkspaceId == null || _saving) return;
    setState(() => _saving = true);
    final importAfterSetup = ref.read(onboardingProvider).importAfterSetup;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId != null) {
      await ref.read(gettingStartedStoreProvider).prepareIntroduction((
        userId: userId,
        workspaceId: _savedWorkspaceId!,
      ));
    }
    if (!mounted) return;
    await ref.read(onboardingProvider.notifier).clearDraft();
    if (!mounted) return;
    ref.invalidate(workspaceProvider);
    context.go(importAfterSetup ? '/import-data' : '/');
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            constraints.hasBoundedHeight && constraints.maxHeight > 48
            ? constraints.maxHeight - 48
            : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pageX),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: reduceMotion ? 1 : _fadeIn.value,
                  child: Transform.translate(
                    offset: Offset(0, reduceMotion ? 0 : _slideUp.value),
                    child: child,
                  ),
                );
              },
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Icon(
                      _saveError == null
                          ? Icons.celebration_rounded
                          : Icons.error_outline_rounded,
                      size: 48,
                      color: _saveError == null
                          ? AppColors.of(context).green
                          : AppColors.of(context).error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _saveError != null
                          ? 'Setup needs\none more try.'
                          : _saved
                          ? 'Your workspace\nis ready.'
                          : 'Preparing your\nworkspace…',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: _saveError == null
                            ? AppColors.of(context).t1
                            : AppColors.of(context).error,
                        letterSpacing: 0,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SummaryRow(
                      icon: Icons.business_rounded,
                      label: onboarding.businessName,
                    ),
                    const SizedBox(height: 10),
                    _SummaryRow(
                      icon: Icons.link_rounded,
                      label: publicBookingPageDisplayUrl(onboarding.handle),
                      color: AppColors.of(context).green,
                    ),
                    const SizedBox(height: 10),
                    _SummaryRow(
                      icon: Icons.design_services_rounded,
                      label:
                          '${onboarding.services.length} services configured',
                    ),
                    if (onboarding.revenueTarget > 0) ...[
                      const SizedBox(height: 10),
                      _SummaryRow(
                        icon: Icons.track_changes_rounded,
                        label:
                            '${formatPounds(onboarding.revenueTarget)} monthly target set',
                        color: AppColors.of(context).green,
                      ),
                    ],
                    if (_saveError != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _saveError!,
                          style: TextStyle(
                            color: AppColors.of(context).t2,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    if (_logoFailed) ...[
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'Your business is saved. Your logo could not be added; please add it in Settings → Business details.',
                      ),
                    ],
                    if (_reminderPreferencesFailed) ...[
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          'Your workspace is saved. Reminder preferences could not be saved; you can choose them in Settings.',
                          style: TextStyle(
                            color: AppColors.of(context).t2,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _saving
                            ? null
                            : _saveError != null
                            ? _saveWorkspace
                            : _saved
                            ? _goToDashboard
                            : null,
                        child: _saving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: AppColors.of(context).onBrandAccent,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _saveError != null
                                    ? 'Try again'
                                    : _saved
                                    ? onboarding.importAfterSetup
                                          ? 'Import existing data'
                                          : 'Go to my dashboard'
                                    : 'Setting up workspace…',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    if (_saveError != null && widget.onReviewSetup != null)
                      TextButton(
                        onPressed: _saving ? null : widget.onReviewSetup,
                        child: const Text('Review setup'),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _SummaryRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? AppColors.of(context).t2, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color ?? AppColors.of(context).t1,
              ),
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: AppColors.of(context).success,
            size: 18,
          ),
        ],
      ),
    );
  }
}
