import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';

class MfaChallengeScreen extends ConsumerStatefulWidget {
  final VoidCallback onVerified;

  const MfaChallengeScreen({super.key, required this.onVerified});

  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final _codeController = TextEditingController();
  bool _loading = true;
  bool _verifying = false;
  Factor? _factor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await ref
          .read(authRepositoryProvider)
          .getMfaSecurityState();
      if (!mounted) return;
      if (!state.needsChallenge) {
        widget.onVerified();
        return;
      }
      setState(() {
        _factor = state.factors.isEmpty ? null : state.factors.first;
        _loading = false;
        _error = _factor == null
            ? 'Your security factor could not be loaded. Sign in again.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Your security check could not be opened. Try again.';
      });
    }
  }

  Future<void> _verify() async {
    final factor = _factor;
    final code = _codeController.text.trim();
    if (factor == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(
        () => _error = 'Enter the 6-digit code from your authenticator app.',
      );
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyTotp(factorId: factor.id, code: code);
      if (!mounted) return;
      SlateHaptics.success();
      widget.onVerified();
    } on AuthException {
      if (!mounted) return;
      SlateHaptics.warning();
      setState(
        () => _error = 'That code was not accepted. Check it and try again.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'The security check failed. Try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const WorkloopPage(
        scrollable: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return WorkloopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Icon(
            LucideIcons.shieldCheck,
            color: AppColors.of(context).accentPrimary,
            size: 36,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Confirm it is you.',
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 28,
              height: 1.08,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Enter the current code from the authenticator app linked to Workloop.',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            key: const ValueKey('mfa-challenge-code'),
            controller: _codeController,
            enabled: _factor != null && !_verifying,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              floatingLabelBehavior: FloatingLabelBehavior.always,
              label: WorkloopFieldLabel('6-digit code', isRequired: true),
            ),
            onSubmitted: (_) => _verify(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SlateErrorState(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          WorkloopPrimaryButton(
            label: _verifying ? 'Checking' : 'Continue',
            icon: LucideIcons.arrowRight,
            onPressed: _factor == null || _verifying ? null : _verify,
          ),
          Center(
            child: WorkloopTextButton(label: 'Sign out', onPressed: _signOut),
          ),
        ],
      ),
    );
  }
}

class MfaSetupScreen extends ConsumerStatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  ConsumerState<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen> {
  final _codeController = TextEditingController();
  MfaSecurityState? _state;
  AuthMFAEnrollResponse? _enrollment;
  bool _loading = true;
  bool _working = false;
  bool _showSecret = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await ref
          .read(authRepositoryProvider)
          .getMfaSecurityState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Two-factor security could not be loaded.';
      });
    }
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final enrollment = await ref.read(authRepositoryProvider).enrollTotp();
      if (!mounted) return;
      setState(() => _enrollment = enrollment);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyMfaError(error.message));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmEnrollment() async {
    final enrollment = _enrollment;
    final code = _codeController.text.trim();
    if (enrollment == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(
        () => _error = 'Enter the 6-digit code from your authenticator app.',
      );
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyTotp(factorId: enrollment.id, code: code);
      if (!mounted) return;
      SlateHaptics.success();
      setState(() {
        _enrollment = null;
        _codeController.clear();
      });
      await _reload();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyMfaError(error.message));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancelEnrollment() async {
    final enrollment = _enrollment;
    setState(() {
      _enrollment = null;
      _codeController.clear();
      _error = null;
    });
    if (enrollment == null) return;
    try {
      await ref.read(authRepositoryProvider).removeMfaFactor(enrollment.id);
    } catch (_) {
      // An unverified factor is inert; a later enrollment replaces the setup.
    }
  }

  Future<void> _removeFactor(Factor factor) async {
    final confirmed = await showWorkloopBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SlateSheetFrame(
        scrollable: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Turn off two-factor security?',
              style: TextStyle(
                color: AppColors.of(sheetContext).t1,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your account will return to password or social sign-in only. You can set up an authenticator again at any time.',
              style: TextStyle(
                color: AppColors.of(sheetContext).t3,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SlateButton(
              label: 'Turn off two-factor security',
              destructive: true,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
            const SizedBox(height: AppSpacing.sm),
            SlateButton(
              label: 'Keep protection on',
              secondary: true,
              onPressed: () => Navigator.pop(sheetContext, false),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).removeMfaFactor(factor.id);
      if (!mounted) return;
      SlateHaptics.success();
      await _reload();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyMfaError(error.message));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyMfaError(String raw) {
    final message = raw.toLowerCase();
    if (message.contains('already exists')) {
      return 'An authenticator is already being set up. Reopen this screen and try again.';
    }
    if (message.contains('invalid') || message.contains('code')) {
      return 'That code was not accepted. Wait for a new code and try again.';
    }
    return 'The security change could not be completed. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return WorkloopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkloopRouteHeader(title: 'Two-factor security'),
          const SizedBox(height: AppSpacing.xl),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_enrollment != null)
            _buildEnrollment(_enrollment!)
          else
            _buildStatus(),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            SlateErrorState(message: _error!),
          ],
        ],
      ),
    );
  }

  Widget _buildStatus() {
    final state = _state;
    if (state == null) {
      return WorkloopEmptyState(
        icon: LucideIcons.shieldAlert,
        title: 'Security status unavailable',
        subtitle: 'Check your connection and try again.',
        action: WorkloopPrimaryButton(label: 'Try again', onPressed: _reload),
      );
    }
    if (!state.isEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protect your business data even if your password or social account is compromised.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          WorkloopSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.smartphone,
                  color: AppColors.of(context).accentPrimary,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Use any standards-based authenticator app. Workloop never sends the setup secret to another service.',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          WorkloopPrimaryButton(
            key: const ValueKey('mfa-start-setup'),
            label: _working ? 'Preparing' : 'Set up authenticator',
            icon: LucideIcons.shieldPlus,
            onPressed: _working ? null : _startEnrollment,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopSurface(
          child: Row(
            children: [
              Icon(LucideIcons.shieldCheck, color: AppColors.of(context).green),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Two-factor security is on.',
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const WorkloopSectionHeader(label: 'Authenticator'),
        const SizedBox(height: AppSpacing.xs),
        for (final factor in state.factors)
          WorkloopListRow(
            showDivider: false,
            leading: Icon(
              LucideIcons.smartphone,
              color: AppColors.of(context).t2,
            ),
            title: Text(factor.friendlyName ?? 'Authenticator app'),
            subtitle: Text('Added ${_formatDate(factor.createdAt)}'),
            trailing: TextButton(
              onPressed: _working ? null : () => _removeFactor(factor),
              child: const Text('Remove'),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Removing your only authenticator turns off two-factor protection for this account.',
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildEnrollment(AuthMFAEnrollResponse enrollment) {
    final totp = enrollment.totp;
    if (totp == null) {
      return const SlateErrorState(
        message: 'The authenticator setup details were not returned.',
      );
    }
    final tokens = SlateTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scan this code.',
          style: TextStyle(
            color: AppColors.of(context).t1,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'In your authenticator app, add an account and scan the QR code.',
          style: TextStyle(color: AppColors.of(context).t3, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Semantics(
            label: 'Authenticator setup QR code',
            image: true,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: QrImageView(
                data: totp.uri,
                size: 220,
                eyeStyle: const QrEyeStyle(color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        WorkloopSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manual setup key',
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _showSecret ? totp.secret : '•••• •••• •••• ••••',
                      key: const ValueKey('mfa-manual-secret'),
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontFamily: _showSecret ? 'monospace' : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _showSecret ? 'Hide setup key' : 'Show setup key',
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                    icon: Icon(
                      _showSecret ? LucideIcons.eyeOff : LucideIcons.eye,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy setup key',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: totp.secret));
                      if (mounted) SlateHaptics.success();
                    },
                    icon: const Icon(LucideIcons.copy),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const ValueKey('mfa-enrollment-code'),
          controller: _codeController,
          enabled: !_working,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            floatingLabelBehavior: FloatingLabelBehavior.always,
            label: WorkloopFieldLabel('6-digit code', isRequired: true),
          ),
          onSubmitted: (_) => _confirmEnrollment(),
        ),
        const SizedBox(height: AppSpacing.md),
        WorkloopPrimaryButton(
          label: _working ? 'Checking' : 'Turn on two-factor security',
          icon: LucideIcons.shieldCheck,
          onPressed: _working ? null : _confirmEnrollment,
        ),
        Center(
          child: WorkloopTextButton(
            label: 'Cancel setup',
            onPressed: _working ? null : _cancelEnrollment,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
