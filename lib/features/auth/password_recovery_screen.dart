import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'auth_validation.dart';

String? validateRecoveryPassword(String password, String confirmation) {
  return validateNewPasswordPair(password, confirmation);
}

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = validateRecoveryPassword(
      _passwordController.text,
      _confirmationController.text,
    );
    if (error != null) {
      SlateHaptics.warning();
      setState(() => _error = error);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .updatePassword(_passwordController.text);
      if (!mounted) return;
      SlateHaptics.success();
      context.go('/');
    } catch (_) {
      if (!mounted) return;
      SlateHaptics.warning();
      setState(() {
        _error =
            'This reset link may have expired. Request a new link and try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.pageX),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (AppSpacing.pageX * 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.keyRound,
                          color: AppColors.of(context).accentPrimary,
                          size: 34,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Choose a new password.',
                          style: TextStyle(
                            color: AppColors.of(context).t1,
                            fontSize: 27,
                            fontWeight: FontWeight.w600,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Use $minimumWorkloopPasswordLength+ characters with uppercase, lowercase, a number, and a symbol you have not used elsewhere.',
                          style: TextStyle(
                            color: AppColors.of(context).t3,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            label: const WorkloopFieldLabel(
                              'New password',
                              isRequired: true,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () {
                                SlateHaptics.selection();
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? LucideIcons.eye
                                    : LucideIcons.eyeOff,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _confirmationController,
                          obscureText: _obscureConfirmation,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saving ? null : _save(),
                          decoration: InputDecoration(
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            label: const WorkloopFieldLabel(
                              'Confirm password',
                              isRequired: true,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirmation
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () {
                                SlateHaptics.selection();
                                setState(
                                  () => _obscureConfirmation =
                                      !_obscureConfirmation,
                                );
                              },
                              icon: Icon(
                                _obscureConfirmation
                                    ? LucideIcons.eye
                                    : LucideIcons.eyeOff,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          SlateErrorState(message: _error!),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        WorkloopPrimaryButton(
                          label: _saving
                              ? 'Updating password'
                              : 'Save password',
                          icon: LucideIcons.lock,
                          onPressed: _saving ? null : _save,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        WorkloopTextButton(
                          label: 'Request another link',
                          onPressed: _saving ? null : () => context.go('/auth'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
