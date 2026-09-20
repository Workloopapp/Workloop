import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/workloop_app_info.dart';
import '../../shared/providers/theme_mode_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/widgets/slate_ui.dart';
import '../getting_started/getting_started_guide.dart';
import '../finance/finance_screen.dart';
import '../finance/payment_collection_sheet.dart';
import '../notifications/notifications_screen.dart';
import '../imports/import_data_screen.dart';
import 'support_screen.dart';
import '../profile/profile_editor_screen.dart';
import 'widgets/settings_business_tab.dart';
import '../subscription/subscription_access.dart';
import '../subscription/subscription_screen.dart';
import 'customer_reminders_screen.dart';
import 'widgets/email_settings_section.dart';
import 'widgets/settings_account_tab.dart';
import 'widgets/settings_appearance_view.dart';
import 'widgets/settings_app_tab.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final auth = ref.watch(authRepositoryProvider);
    final name = auth.currentFirstName?.trim();
    final email = auth.currentEmail.trim() == '—'
        ? ''
        : auth.currentEmail.trim();
    final appearance =
        ref.watch(workloopAppearanceProvider).value ??
        WorkloopAppearance.system;
    final effectiveAppearance = Theme.of(context).brightness == Brightness.dark
        ? 'Dark'
        : 'Light';
    final appearanceSubtitle = appearance == WorkloopAppearance.system
        ? 'System · currently $effectiveAppearance'
        : '${appearance.label} appearance';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                AppSpacing.screenTop,
                AppSpacing.pageX,
                AppSpacing.xxl,
              ),
              children: [
                WorkloopRouteHeader(
                  title: 'Settings',
                  backSemanticLabel: 'Back to Business',
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: AppSpacing.md),
                _AccountIdentity(
                  name: name,
                  email: email,
                  onTap: () => _open(
                    context,
                    ref,
                    title: 'Account',
                    child: const SettingsAccountTab(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (ref.watch(subscriptionsEnabledProvider)) ...[
                  _SettingsGroup(
                    title: 'Your plan',
                    children: [
                      _SettingsRow(
                        icon: LucideIcons.badgeCheck,
                        title: 'Workloop access',
                        subtitle:
                            'Your trial, subscription or lifetime beta access',
                        showDivider: false,
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _SettingsGroup(
                  title: 'For you',
                  children: [
                    _SettingsRow(
                      icon: LucideIcons.bell,
                      title: 'Your alerts',
                      subtitle: 'In-app updates and alerts on your phone',
                      onTap: () => _open(
                        context,
                        ref,
                        title: 'Your alerts',
                        child: const NotificationSettingsView(),
                      ),
                    ),
                    _SettingsRow(
                      icon: LucideIcons.mail,
                      title: 'Emails to you',
                      subtitle: 'Workloop tips, updates and account messages',
                      showDivider: false,
                      onTap: () => _open(
                        context,
                        ref,
                        title: 'Emails to you',
                        child: const SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.pageX,
                            0,
                            AppSpacing.pageX,
                            AppSpacing.xxl,
                          ),
                          child: EmailSettingsSection(
                            showCustomerEmails: false,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _SettingsGroup(
                  title: 'For your customers',
                  tone: WorkloopPaperTone.warm,
                  children: [
                    _SettingsRow(
                      icon: LucideIcons.store,
                      title: 'Business details',
                      subtitle: 'Your business name, logo and industry',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileEditorScreen(
                            section: SettingsBusinessSection.business,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: LucideIcons.creditCard,
                      title: 'Card & contactless payments',
                      subtitle: 'Payment links, Tap to Pay and Stripe setup',
                      onTap: _openPaymentSettings,
                    ),
                    _SettingsRow(
                      icon: LucideIcons.calendarClock,
                      title: 'Booking reminders',
                      subtitle: 'Automatic email · Manual WhatsApp',
                      showDivider: false,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomerRemindersScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SettingsGroup(
                  title: 'Make it yours',
                  tone: WorkloopPaperTone.plain,
                  children: [
                    _SettingsRow(
                      icon: LucideIcons.sunMoon,
                      title: 'App appearance',
                      subtitle: appearanceSubtitle,
                      onTap: () => _open(
                        context,
                        ref,
                        title: 'App appearance',
                        child: const SettingsAppearanceView(),
                      ),
                    ),
                    _SettingsRow(
                      icon: LucideIcons.slidersHorizontal,
                      title: 'Maps & calendar',
                      subtitle: 'Choose your maps app and export bookings',
                      showDivider: false,
                      onTap: () => _open(
                        context,
                        ref,
                        title: 'Maps & calendar',
                        child: const SettingsAppTab(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _SettingsGroup(
                  title: 'Support',
                  tone: WorkloopPaperTone.plain,
                  children: [
                    const _GettingStartedRow(),
                    _SettingsRow(
                      icon: LucideIcons.lifeBuoy,
                      title: 'Help & support',
                      subtitle:
                          'Get help, read policies and find app information',
                      showDivider: false,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SupportScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _SettingsGroup(
                  title: 'Your data',
                  tone: WorkloopPaperTone.plain,
                  children: [
                    _SettingsRow(
                      icon: LucideIcons.import,
                      title: 'Import data',
                      subtitle: 'Contacts, calendar events and selected files',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ImportDataScreen(),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: LucideIcons.shieldCheck,
                      title: 'Privacy & data',
                      subtitle: 'Export your data or delete your account',
                      showDivider: false,
                      onTap: () => _open(
                        context,
                        ref,
                        title: 'Privacy & data',
                        child: const SettingsAccountTab(showDataOnly: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Workloop ${WorkloopAppInfo.version}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textDisabled,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentSettings() async {
    final workspaceId = ref.read(workspaceIdProvider).value;
    if (workspaceId == null) return;
    final action = await showPaymentSetupSheet(
      context: context,
      workspaceId: workspaceId,
    );
    if (!mounted || action != PaymentSetupAction.viewOwed) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const FinanceScreen(
          initialFocus: FinanceInitialFocus.followUps,
          showBackButton: true,
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required Widget child,
  }) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsDestinationScreen(title: title, child: child),
      ),
    );
    if (!context.mounted) return;
    // The repository is shared with authentication and notification services.
    // Rebuilding this view must not recreate those dependencies after a visit.
    setState(() {});
  }
}

class _SettingsDestinationScreen extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsDestinationScreen({required this.title, required this.child});

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
                  child: WorkloopRouteHeader(
                    title: title,
                    backSemanticLabel: 'Back to settings',
                    onBack: () => Navigator.pop(context),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GettingStartedRow extends ConsumerStatefulWidget {
  const _GettingStartedRow();

  @override
  ConsumerState<_GettingStartedRow> createState() => _GettingStartedRowState();
}

class _GettingStartedRowState extends ConsumerState<_GettingStartedRow> {
  bool _opening = false;

  Future<void> _openGuide() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (!mounted) return;
      if (userId == null ||
          workspaceId == null ||
          ref.read(supabaseClientProvider).auth.currentUser?.id != userId) {
        throw StateError('A verified workspace is required');
      }
      await showWorkloopGettingStartedGuide(
        context,
        userId: userId,
        workspaceId: workspaceId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the guide. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsRow(
    icon: LucideIcons.bookOpen,
    title: 'Getting started',
    subtitle: _opening
        ? 'Opening your guide…'
        : 'A short guide to your everyday Workloop',
    onTap: _opening ? null : _openGuide,
  );
}

class _AccountIdentity extends StatelessWidget {
  final String? name;
  final String email;
  final VoidCallback onTap;

  const _AccountIdentity({
    required this.name,
    required this.email,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final label = name?.isNotEmpty == true ? name! : 'Your account';
    final initial = label.characters.first.toUpperCase();
    return WorkloopListRow(
      flat: true,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      leading: Container(
        key: const ValueKey('settings-account-avatar'),
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        email.isEmpty
            ? 'Your name and sign-in security'
            : '$email\nYour name and sign-in security',
        style: TextStyle(
          color: tokens.textTertiary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: tokens.textTertiary,
        size: 18,
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showDivider;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      flat: true,
      onTap: onTap,
      showDivider: showDivider,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      leading: Container(
        key: ValueKey('settings-row-icon-${icon.codePoint}'),
        width: 24,
        height: 24,
        alignment: Alignment.center,
        child: Icon(icon, color: tokens.accentInk, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: tokens.textTertiary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: tokens.textTertiary,
        size: 16,
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final WorkloopPaperTone tone;
  final List<Widget> children;

  const _SettingsGroup({
    required this.title,
    this.tone = WorkloopPaperTone.blue,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => WorkloopPaperPanel(
    title: title,
    tone: tone,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Column(children: children),
  );
}
