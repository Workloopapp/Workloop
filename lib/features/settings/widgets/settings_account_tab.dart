import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/auth_validation.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/repositories/slate_repositories.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import 'settings_helpers.dart' show saveBtn;

class SettingsAccountTab extends ConsumerStatefulWidget {
  const SettingsAccountTab({super.key, this.showDataOnly = false});

  final bool showDataOnly;

  @override
  ConsumerState<SettingsAccountTab> createState() => _SettingsAccountTabState();
}

class _SettingsAccountTabState extends ConsumerState<SettingsAccountTab> {
  bool _changingPassword = false;
  bool _savingPassword = false;
  bool _exporting = false;
  bool _sheetOpen = false;
  String? _passwordError;
  late final String? _accountId;
  StreamSubscription<Object?>? _authSubscription;
  ModalRoute<dynamic>? _sheetRoute;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authRepositoryProvider);
    _accountId = auth.currentUserId;
    _authSubscription = auth.authChanges.listen((_) {
      if (!mounted || _isCurrentAccount) return;
      // A sheet is a separate route. Remove only the one this screen owns,
      // rather than leaving the old owner's personal details above a new login.
      final route = _sheetRoute;
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
      _clearPasswords();
      setState(() {});
    });
  }

  bool get _isCurrentAccount =>
      mounted &&
      _accountId != null &&
      ref.read(authRepositoryProvider).currentUserId == _accountId;

  bool get _isCurrentPage =>
      _isCurrentAccount && ModalRoute.of(context)?.isCurrent != false;

  void _clearPasswords() {
    _newPasswordCtrl.clear();
    _confirmPasswordCtrl.clear();
    _reauthCodeCtrl.clear();
  }

  Future<void> _showAccountSheet(WidgetBuilder builder) async {
    if (!_isCurrentPage || _sheetOpen || _savingPassword || _exporting) return;
    _sheetOpen = true;
    try {
      await showWorkloopBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) {
          _sheetRoute = ModalRoute.of(ctx);
          return builder(ctx);
        },
      );
    } finally {
      _sheetOpen = false;
      _sheetRoute = null;
    }
  }

  bool _sheetIsCurrent(BuildContext ctx) =>
      _isCurrentAccount && ctx.mounted && ModalRoute.of(ctx)?.isCurrent == true;
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _reauthCodeCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _deleteConfirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _authSubscription?.cancel();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _reauthCodeCtrl.dispose();
    _firstNameCtrl.dispose();
    _deleteConfirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (_savingPassword || !_isCurrentPage) return;
    final password = _newPasswordCtrl.text;
    final code = _reauthCodeCtrl.text.trim();
    final error = !RegExp(r'^\d{6}$').hasMatch(code)
        ? 'Enter the 6-digit security code from your email.'
        : validateNewPasswordPair(password, _confirmPasswordCtrl.text);
    if (error != null) {
      setState(() => _passwordError = error);
      return;
    }
    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .updatePassword(password, nonce: code);
      if (!mounted || !_isCurrentAccount) return;
      _clearPasswords();
      setState(() => _changingPassword = false);
      if (_isCurrentPage) {
        _snack('Password updated', AppColors.of(context).green);
      }
    } catch (_) {
      if (_isCurrentAccount) {
        setState(
          () => _passwordError =
              'Your password could not be updated. Check the code or request a new one.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _startPasswordChange() async {
    if (_savingPassword || !_isCurrentPage) return;
    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPasswordReauthentication();
      if (!mounted || !_isCurrentPage) return;
      _reauthCodeCtrl.clear();
      setState(() => _changingPassword = true);
      _snack('Security code sent to your email', AppColors.of(context).green);
    } catch (_) {
      if (_isCurrentAccount) {
        setState(
          () => _passwordError =
              'A security code could not be sent. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _showNameSheet() async {
    if (!_isCurrentPage || _sheetOpen) return;
    _firstNameCtrl.text =
        ref.read(authRepositoryProvider).currentFirstName ?? '';
    var saving = false;
    String? error;
    await _showAccountSheet(
      (ctx) => StatefulBuilder(
        builder: (ctx, updateSheet) {
          Future<void> save() async {
            if (saving || !_sheetIsCurrent(ctx)) return;
            final value = _firstNameCtrl.text.trim();
            if (value.isEmpty) {
              updateSheet(() => error = 'Enter your first name.');
              return;
            }
            updateSheet(() {
              saving = true;
              error = null;
            });
            try {
              await ref.read(authRepositoryProvider).updateFirstName(value);
              if (!mounted || !ctx.mounted || !_sheetIsCurrent(ctx)) return;
              Navigator.pop(ctx);
              setState(() {});
              _snack('Name updated', AppColors.of(context).green);
            } catch (_) {
              if (ctx.mounted && _sheetIsCurrent(ctx)) {
                updateSheet(
                  () => error =
                      'Your name could not be saved. Check your connection and try again.',
                );
              }
            } finally {
              if (ctx.mounted) updateSheet(() => saving = false);
            }
          }

          return _AccountSheet(
            busy: saving,
            title: 'Your name',
            description: 'The first name Workloop uses when greeting you.',
            children: [
              TextField(
                controller: _firstNameCtrl,
                enabled: !saving,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.givenName],
                maxLength: 80,
                decoration: InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  label: const WorkloopFieldLabel(
                    'First name',
                    isRequired: true,
                  ),
                  errorText: error,
                  errorMaxLines: 3,
                  counterText: '',
                ),
                onSubmitted: (_) => save(),
              ),
              const SizedBox(height: AppSpacing.lg),
              saveBtn(ctx, label: 'Save name', onTap: save, loading: saving),
              _cancelButton(ctx, busy: saving),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSignOutSheet() async {
    var signingOut = false;
    String? error;
    await _showAccountSheet(
      (ctx) => StatefulBuilder(
        builder: (ctx, updateSheet) => _AccountSheet(
          busy: signingOut,
          title: 'Sign out?',
          description:
              'Sign out of Workloop on this device. Your saved business data stays in your account.',
          children: [
            if (error != null) _AccountError(error!),
            saveBtn(
              ctx,
              label: 'Sign out',
              loading: signingOut,
              onTap: () async {
                if (signingOut || !_sheetIsCurrent(ctx)) return;
                final auth = ref.read(authRepositoryProvider);
                updateSheet(() {
                  signingOut = true;
                  error = null;
                });
                try {
                  await auth.signOutLocal(expectedUserId: _accountId);
                  // Auth may already have removed this route. Never redirect a
                  // different account that signed in while cleanup was pending.
                  if (!mounted || auth.currentUserId != null) return;
                  if (ctx.mounted && ModalRoute.of(ctx)?.isCurrent == true) {
                    Navigator.pop(ctx);
                  }
                  ref.invalidate(sessionIntegrityProvider);
                  ref.invalidate(workspaceProvider);
                  if (mounted) context.go('/auth');
                } catch (_) {
                  if (ctx.mounted && _sheetIsCurrent(ctx)) {
                    updateSheet(
                      () =>
                          error = 'We couldn’t sign you out. Please try again.',
                    );
                  }
                } finally {
                  if (ctx.mounted) updateSheet(() => signingOut = false);
                }
              },
            ),
            _cancelButton(ctx, busy: signingOut),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData() async {
    if (_exporting || !_isCurrentPage || _sheetOpen) return;
    setState(() => _exporting = true);
    try {
      final workspaceId = await ref
          .read(workspaceIdProvider.future)
          .timeout(const Duration(seconds: 10));
      if (!_isCurrentPage) return;
      if (workspaceId == null) {
        throw StateError('No active workspace');
      }
      final json = await ref
          .read(privacyRepositoryProvider)
          .exportWorkspaceData(workspaceId);
      if (!_isCurrentPage ||
          await ref.read(workspaceIdProvider.future) != workspaceId ||
          !_isCurrentPage) {
        return;
      }
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save Workloop data export',
        fileName: 'workloop-data-export-$date.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (mounted && _isCurrentPage && savedPath != null) {
        _snack('Data export saved', AppColors.of(context).green);
      }
    } on ReceiptExportTooLargeException {
      if (mounted && _isCurrentPage) {
        _snack(
          'Receipt files exceed the 20 MB mobile export limit. Export originals from each expense, or contact support for a full archive. No partial file was saved.',
          AppColors.of(context).error,
        );
      }
    } on PrivacyExportIncompleteException {
      if (mounted && _isCurrentPage) {
        _snack(
          'The export was incomplete, so no file was saved. Please try again.',
          AppColors.of(context).error,
        );
      }
    } catch (_) {
      if (mounted) {
        if (_isCurrentPage) {
          _snack(
            'Your data export could not be prepared. Please try again.',
            AppColors.of(context).error,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showDeleteAccountSheet() async {
    if (!_isCurrentPage || _sheetOpen) return;
    final router = GoRouter.of(context);
    _deleteConfirmCtrl.clear();
    var requesting = false;
    var appleUnavailable = false;
    AccountDeletionResult? acceptedResult;
    String? error;
    await _showAccountSheet(
      (ctx) => StatefulBuilder(
        builder: (ctx, updateSheet) {
          Future<void> submit({bool withoutApple = false}) async {
            if (requesting ||
                !_sheetIsCurrent(ctx) ||
                _deleteConfirmCtrl.text.trim().toUpperCase() != 'DELETE') {
              return;
            }
            updateSheet(() {
              requesting = true;
              error = null;
            });
            final auth = ref.read(authRepositoryProvider);
            try {
              if (acceptedResult == null) {
                String? appleCode;
                if (auth.hasAppleIdentity && !withoutApple) {
                  try {
                    appleCode = await auth.requestAppleDeletionAuthorization();
                  } on AppleDeletionAuthorizationException catch (failure) {
                    if (ctx.mounted && _sheetIsCurrent(ctx)) {
                      updateSheet(() {
                        appleUnavailable = true;
                        error = failure.cancelled
                            ? 'Apple confirmation was cancelled. Your account has not been deleted. Try again, or continue deletion and disconnect Apple yourself.'
                            : 'Apple confirmation is unavailable. Try again, or continue deletion and disconnect Apple yourself.';
                      });
                    }
                    return;
                  }
                }
                if (!ctx.mounted || !_sheetIsCurrent(ctx)) return;
                // A pre-onboarding account has no workspace. The server resolves
                // any existing membership and checks ownership itself.
                String? workspaceId;
                try {
                  workspaceId = await ref
                      .read(workspaceIdProvider.future)
                      .timeout(const Duration(seconds: 10));
                } catch (_) {
                  // Account deletion also works when workspace lookup fails.
                }
                if (!ctx.mounted || !_sheetIsCurrent(ctx)) return;
                acceptedResult = await ref
                    .read(privacyRepositoryProvider)
                    .requestAccountDeletion(
                      workspaceId: workspaceId,
                      appleAuthorizationCode: appleCode,
                    );
              }
              if (!_isCurrentAccount) return;
              try {
                await ref.read(onboardingProvider.notifier).clearDraft();
              } catch (_) {
                /* Optional cleanup cannot undo accepted deletion. */
              }
              await auth.signOutLocal(expectedUserId: _accountId);
              if (auth.currentUserId != null) return;
              // Use the captured router: successful sign-out may already have
              // disposed the account screen. Keep Apple unlink guidance visible.
              router.go('/account-deletion-requested', extra: acceptedResult);
            } catch (failure) {
              if (ctx.mounted && _sheetIsCurrent(ctx)) {
                updateSheet(() {
                  final mismatch =
                      failure is AccountDeletionException &&
                      failure.appleIdentityMismatch;
                  if (mismatch) appleUnavailable = true;
                  error = acceptedResult != null
                      ? 'Your deletion request was accepted. Try again to finish signing out.'
                      : mismatch
                      ? 'That Apple Account is not linked to this Workloop account. Try the linked Apple Account, or continue deletion and disconnect Apple yourself.'
                      : 'Your deletion request could not be confirmed. Please try again or contact support.';
                });
              }
              if (acceptedResult != null && _isCurrentAccount) {
                ref.invalidate(sessionIntegrityProvider);
                ref.invalidate(workspaceProvider);
              }
            } finally {
              if (ctx.mounted) updateSheet(() => requesting = false);
            }
          }

          return _AccountSheet(
            busy: requesting,
            title: 'Request account deletion',
            description:
                'When your request is accepted, you’ll be signed out and lose access to this account. Your workspace, clients, bookings and other business records will then be permanently deleted.',
            children: [
              Text(
                'Export any records you need before continuing. Deleting your Workloop account does not cancel an Apple or Google subscription; cancel it in your store subscription settings first if you have one. Deletion is queued immediately and pending requests are checked every minute. Provider issues may delay completion. We’ll email you when deletion is complete. Some records may need to be kept for legal or security reasons.',
                style: TextStyle(color: AppColors.of(ctx).t2, height: 1.5),
              ),
              if (ref.read(authRepositoryProvider).hasAppleIdentity) ...[
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Apple will ask you to confirm your linked Apple Account so we can disconnect Sign in with Apple.',
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _deleteConfirmCtrl,
                enabled: !requesting,
                onChanged: (_) => updateSheet(() {}),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: const InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  label: WorkloopFieldLabel(
                    'Type DELETE to confirm',
                    isRequired: true,
                  ),
                ),
              ),
              if (error != null) _AccountError(error!),
              const SizedBox(height: AppSpacing.lg),
              saveBtn(
                ctx,
                label: acceptedResult != null
                    ? 'Finish signing out'
                    : 'Request deletion',
                color: AppColors.of(ctx).error,
                loading: requesting,
                disabled:
                    _deleteConfirmCtrl.text.trim().toUpperCase() != 'DELETE',
                onTap: submit,
              ),
              if (appleUnavailable && acceptedResult == null)
                WorkloopTextButton(
                  label: 'Continue deletion without Apple',
                  onPressed:
                      requesting ||
                          _deleteConfirmCtrl.text.trim().toUpperCase() !=
                              'DELETE'
                      ? null
                      : () => submit(withoutApple: true),
                ),
              _cancelButton(ctx, busy: requesting),
            ],
          );
        },
      ),
    );
  }

  Widget _cancelButton(BuildContext context, {required bool busy}) =>
      WorkloopTextButton(
        label: 'Cancel',
        onPressed: busy ? null : () => Navigator.pop(context),
      );

  @override
  Widget build(BuildContext context) {
    final authRepository = ref.watch(authRepositoryProvider);
    final email = authRepository.currentEmail;
    final firstName = authRepository.currentFirstName;

    if (!_isCurrentAccount) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.pageX),
        child: Text('Your account has changed. Reopen Settings to continue.'),
      );
    }
    final hasEmail = isValidAuthEmail(email);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        0,
        AppSpacing.pageX,
        AppSpacing.xxl,
      ),
      children: [
        if (!widget.showDataOnly) ...[
          const WorkloopSectionHeader(label: 'Personal details'),
          _AccountActionRow(
            icon: LucideIcons.user,
            label: 'Your name',
            subtitle: firstName ?? 'Add your first name',
            onTap: _showNameSheet,
          ),
          const WorkloopDivider(margin: EdgeInsets.zero),
          _AccountActionRow(
            icon: LucideIcons.mail,
            label: 'Email address',
            subtitle: email,
            selectable: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          const WorkloopSectionHeader(label: 'Security'),
          if (_changingPassword) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the security code sent to $email, then choose your password.',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _reauthCodeCtrl,
                    enabled: !_savingPassword,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      label: WorkloopFieldLabel(
                        'Email security code',
                        isRequired: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _passwordField(
                    label: 'New password',
                    controller: _newPasswordCtrl,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Use at least 12 characters, with uppercase and lowercase letters, a number and a symbol.',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _passwordField(
                    label: 'Confirm password',
                    controller: _confirmPasswordCtrl,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  if (_passwordError != null) _AccountError(_passwordError!),
                  const SizedBox(height: AppSpacing.md),
                  WorkloopPrimaryButton(
                    label: _savingPassword ? 'Please wait…' : 'Save password',
                    icon: LucideIcons.lock,
                    onPressed: _savingPassword ? null : _changePassword,
                  ),
                  WorkloopTextButton(
                    label: 'Send a new code',
                    onPressed: _savingPassword ? null : _startPasswordChange,
                  ),
                  WorkloopTextButton(
                    label: 'Cancel',
                    onPressed: _savingPassword
                        ? null
                        : () {
                            _clearPasswords();
                            setState(() {
                              _changingPassword = false;
                              _passwordError = null;
                            });
                          },
                  ),
                ],
              ),
            ),
          ] else ...[
            _AccountActionRow(
              icon: LucideIcons.lock,
              label: 'Set or change password',
              subtitle: _savingPassword
                  ? 'Sending your security code…'
                  : hasEmail
                  ? 'We’ll email you a code before you make changes.'
                  : 'A verified email address is needed to set a password.',
              loading: _savingPassword,
              onTap: _savingPassword || !hasEmail ? null : _startPasswordChange,
            ),
            if (_passwordError != null) _AccountError(_passwordError!),
          ],
          const WorkloopDivider(margin: EdgeInsets.zero),
          _AccountActionRow(
            icon: LucideIcons.shieldCheck,
            label: 'Two-step verification',
            subtitle: 'Add extra protection with an authenticator app.',
            onTap: _savingPassword ? null : () => context.push('/security/2fa'),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (widget.showDataOnly) ...[
          Text(
            'Your business records belong to you. Save a copy or manage the deletion of your account.',
            style: TextStyle(color: AppColors.of(context).t2, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          const WorkloopSectionHeader(label: 'Your data'),
          _AccountActionRow(
            icon: LucideIcons.download,
            label: 'Export your data',
            subtitle: _exporting
                ? 'Preparing your file…'
                : 'Save your clients, bookings and business records as a JSON file.',
            loading: _exporting,
            onTap: _exporting || _savingPassword ? null : _exportData,
          ),
          const WorkloopDivider(margin: EdgeInsets.zero),
          _AccountActionRow(
            icon: LucideIcons.trash2,
            label: 'Delete account',
            subtitle:
                'Request permanent deletion of your account and workspace.',
            destructive: true,
            onTap: _exporting || _savingPassword
                ? null
                : _showDeleteAccountSheet,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (!widget.showDataOnly)
          _AccountActionRow(
            icon: LucideIcons.logOut,
            label: 'Sign out',
            subtitle:
                'Sign out on this device. Your saved data stays in your account.',
            onTap: _exporting || _savingPassword ? null : _showSignOutSheet,
          ),
      ],
    );
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      enabled: !_savingPassword,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.newPassword],
      textInputAction: controller == _confirmPasswordCtrl
          ? TextInputAction.done
          : TextInputAction.next,
      onSubmitted: controller == _confirmPasswordCtrl
          ? (_) => _changePassword()
          : null,
      decoration: InputDecoration(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        label: WorkloopFieldLabel(label, isRequired: true),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show password' : 'Hide password',
          onPressed: _savingPassword ? null : onToggle,
          icon: Icon(obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 20),
        ),
      ),
    );
  }
}

class _AccountActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;
  final bool destructive;
  final bool selectable;

  const _AccountActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
    this.loading = false,
    this.destructive = false,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.of(context).error
        : AppColors.of(context).t1;
    final subtitleStyle = TextStyle(
      color: AppColors.of(context).t2,
      fontSize: 13,
      height: 1.5,
    );
    return WorkloopListRow(
      flat: true,
      onTap: onTap,
      showDivider: false,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: selectable
          ? SelectableText(subtitle, style: subtitleStyle)
          : Text(subtitle, style: subtitleStyle),
      trailing: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : onTap == null
          ? null
          : Icon(
              LucideIcons.chevronRight,
              color: AppColors.of(context).t3,
              size: 18,
            ),
    );
  }
}

class _AccountSheet extends StatelessWidget {
  final bool busy;
  final String title;
  final String description;
  final List<Widget> children;

  const _AccountSheet({
    required this.busy,
    required this.title,
    required this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AnimatedPadding(
      duration: AppMotion.responsive(context, AppMotion.fast),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SlateSheetFrame(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: TextStyle(color: AppColors.of(context).t2, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

class _AccountError extends StatelessWidget {
  final String message;
  const _AccountError(this.message);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: AppColors.of(context).error, height: 1.5),
      ),
    ),
  );
}
