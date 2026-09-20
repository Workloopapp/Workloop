import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/workloop_app_info.dart';
import '../../shared/widgets/slate_ui.dart';
import 'legal_document_screen.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                const WorkloopRouteHeader(
                  title: 'Help & support',
                  backSemanticLabel: 'Back to settings',
                ),
                const SizedBox(height: AppSpacing.md),
                const WorkloopSectionHeader(label: 'Get help'),
                const SizedBox(height: AppSpacing.xs),
                _SupportRow(
                  icon: LucideIcons.mail,
                  title: 'Contact support',
                  subtitle: WorkloopAppInfo.supportEmail,
                  onTap: () => _contactSupport(context),
                ),
                _SupportRow(
                  icon: LucideIcons.copy,
                  title: 'Copy app information',
                  subtitle:
                      'Share your app version and phone type with support. No client data is included.',
                  onTap: () => _copyDiagnostics(context),
                  showDivider: false,
                ),
                const SizedBox(height: AppSpacing.xxl),
                const WorkloopSectionHeader(label: 'About Workloop'),
                const SizedBox(height: AppSpacing.xs),
                _SupportRow(
                  icon: LucideIcons.shieldCheck,
                  title: 'Privacy policy',
                  subtitle: 'Read how Workloop handles and protects data.',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        document: WorkloopLegalDocument.privacy,
                        backSemanticLabel: 'Back to help and support',
                      ),
                    ),
                  ),
                ),
                _SupportRow(
                  icon: LucideIcons.fileText,
                  title: 'Terms of use',
                  subtitle: 'Read the agreement for using Workloop.',
                  showDivider: false,
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        document: WorkloopLegalDocument.terms,
                        backSemanticLabel: 'Back to help and support',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const WorkloopSectionHeader(label: 'Service operator'),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  WorkloopAppInfo.operatorDetails,
                  key: ValueKey('workloop-operator-details'),
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Center(
                  child: Text(
                    'Workloop ${WorkloopAppInfo.versionLabel}',
                    style: TextStyle(
                      color: AppColors.of(context).t4,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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

  Future<void> _contactSupport(BuildContext context) async {
    SlateHaptics.action();
    final uri = Uri(
      scheme: 'mailto',
      path: WorkloopAppInfo.supportEmail,
      queryParameters: {
        'subject': 'Workloop support',
        'body': '${_diagnostics()}\n\nPlease describe what happened:\n',
      },
    );
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {
      // A missing mail app can throw instead of returning false.
    }
    try {
      await Clipboard.setData(
        const ClipboardData(text: WorkloopAppInfo.supportEmail),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email support@workloop.uk for help.')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Support email copied')));
  }

  Future<void> _copyDiagnostics(BuildContext context) async {
    SlateHaptics.action();
    try {
      await Clipboard.setData(ClipboardData(text: _diagnostics()));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not copy app information. Please try again.'),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App information copied')));
  }

  String _diagnostics() {
    return 'Workloop ${WorkloopAppInfo.versionLabel}\nPlatform: ${defaultTargetPlatform.name}\nMode: ${kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug'}';
  }
}

class _SupportRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _SupportRow({
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
      padding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.md,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.surfaceSubtle,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: tokens.textSecondary, size: 18),
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
          height: 1.35,
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
