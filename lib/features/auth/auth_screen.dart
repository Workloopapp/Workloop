import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import '../settings/legal_document_screen.dart';
import 'auth_validation.dart';
import 'auth_methods.dart';
import '../../shared/email/email_preferences_repository.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _scrollController = ScrollController();
  _AuthMode _mode = _AuthMode.login;
  bool _isLoading = false;
  bool _emailUpdates = true;
  String? _socialProvider;
  String? _error;
  String? _success;
  bool _createPasswordlessAccount = false;
  String? _sentPhone;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  bool _reviewingNotice = false;
  StreamSubscription<AuthState>? _externalSignIn;

  bool get _busy => _isLoading || _socialProvider != null || _reviewingNotice;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _resendTimer?.cancel();
    _externalSignIn?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _reviewEmailNotice() async {
    if (_busy) return false;
    setState(() => _reviewingNotice = true);
    try {
      final result = await showWorkloopBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, updateSheet) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.pageX),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Workloop emails',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'For new accounts: $accountEmailNotice',
                    style: TextStyle(fontSize: 16, height: 1.5),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('signup-email-opt-out'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Do not send me tips and marketing emails',
                    ),
                    value: !_emailUpdates,
                    onChanged: (value) =>
                        updateSheet(() => _emailUpdates = !(value ?? false)),
                  ),
                  Text(
                    'Essential account emails still arrive. If you already have an account, your existing email preference applies.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.of(context).t3,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SlateButton(
                    label: 'Continue',
                    onPressed: () => Navigator.pop(sheetContext, true),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return result == true;
    } finally {
      if (mounted) setState(() => _reviewingNotice = false);
    }
  }

  Future<void> _signInWithSocial(String provider) async {
    if (_busy) return;
    if (!await _reviewEmailNotice() || !mounted) return;
    setState(() {
      _socialProvider = provider;
      _error = null;
      _success = null;
    });
    try {
      await ref
          .read(emailPreferencesRepositoryProvider)
          .saveSocialSignupChoice(_emailUpdates);
      if (provider == 'apple') {
        await ref.read(authRepositoryProvider).signInWithApple();
        if (mounted) context.go('/');
      } else {
        final repository = ref.read(authRepositoryProvider);
        _watchExternalSignIn();
        final opened = await (provider == 'apple-oauth'
            ? repository.signInWithAppleOAuth()
            : repository.signInWithGoogle());
        final name = provider == 'apple-oauth' ? 'Apple' : 'Google';
        if (!opened) {
          throw AuthException('Could not open $name sign in.');
        }
        if (mounted) {
          setState(() {
            _success = 'Finish signing in with $name, then return to Workloop.';
          });
        }
      }
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code != AuthorizationErrorCode.canceled && mounted) {
        setState(
          () => _error = 'Apple sign in could not be completed. Try again.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthErrorMessage(error.message));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sign in could not be completed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _socialProvider = null);
    }
  }

  void _watchExternalSignIn() {
    _externalSignIn ??= ref
        .read(authRepositoryProvider)
        .authChanges
        .listen(
          (state) {
            if (mounted &&
                state.event == AuthChangeEvent.signedIn &&
                state.session != null) {
              context.go('/');
            }
          },
          onError: (Object _) {
            if (mounted) {
              setState(
                () => _error =
                    'That sign-in link could not be used. Request a new link and try again.',
              );
            }
          },
        );
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_mode == _AuthMode.emailLink || _mode == _AuthMode.phone) {
      await _submitPasswordless();
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final validationError = validateAuthForm(
      email: email,
      password: password,
      intent: switch (_mode) {
        _AuthMode.login => AuthFormIntent.signIn,
        _AuthMode.signup => AuthFormIntent.signUp,
        _AuthMode.reset => AuthFormIntent.resetPassword,
        _AuthMode.emailLink || _AuthMode.phone => AuthFormIntent.resetPassword,
      },
    );
    if (validationError != null) {
      SlateHaptics.warning();
      setState(() {
        _error = validationError;
        _success = null;
      });
      return;
    }

    if (_mode == _AuthMode.signup &&
        (!await _reviewEmailNotice() || !mounted)) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      if (_mode == _AuthMode.login) {
        await ref
            .read(authRepositoryProvider)
            .signIn(email: email, password: password);
        if (mounted) context.go('/');
      } else if (_mode == _AuthMode.signup) {
        // This route can be opened directly, outside AuthGate. A later email
        // confirmation must enter the app when Supabase establishes a session.
        _watchExternalSignIn();
        final response = await ref
            .read(authRepositoryProvider)
            .signUp(
              email: email,
              password: password,
              emailUpdates: _emailUpdates,
            );
        if (response.session != null) {
          if (mounted) context.go('/');
        } else if (mounted) {
          setState(() {
            _mode = _AuthMode.login;
            _passwordController.clear();
            _success =
                'If a new account was created, check your inbox and spam for its confirmation link. Already registered? Sign in instead. If you requested account deletion, wait for the completion email before creating a new account.';
          });
        }
      } else {
        await ref.read(authRepositoryProvider).sendPasswordReset(email);
        if (mounted) {
          setState(() {
            _success = 'Password reset email sent. Check your inbox.';
          });
        }
      }
      TextInput.finishAutofillContext();
      SlateHaptics.success();
    } on AuthException catch (e) {
      SlateHaptics.warning();
      if (!mounted) return;
      setState(() {
        _error = friendlyAuthErrorMessage(e.message);
      });
    } catch (_) {
      SlateHaptics.warning();
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setMode(_AuthMode mode) {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _mode = mode;
      _error = null;
      _success = null;
      _sentPhone = null;
      _codeController.clear();
      if (mode == _AuthMode.reset) _passwordController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendSeconds--);
      if (_resendSeconds <= 0) timer.cancel();
    });
  }

  Future<void> _submitPasswordless({bool resend = false}) async {
    if (_busy) return;
    final isPhone = _mode == _AuthMode.phone;
    final verifying = isPhone && _sentPhone != null && !resend;
    if (!verifying && _resendSeconds > 0) return;
    final phone = _sentPhone ?? normalizedAuthPhone(_phoneController.text);
    String? error;
    if (isPhone && phone == null) {
      error =
          'Enter your number with its country code, for example +44 7700 900123.';
    } else if (!isPhone && !isValidAuthEmail(_emailController.text)) {
      error = 'Enter a valid email address.';
    } else if (verifying &&
        !RegExp(r'^\d{6,10}$').hasMatch(_codeController.text.trim())) {
      error = 'Enter the verification code from your text message.';
    }
    if (error != null) {
      setState(() {
        _error = error;
        _success = null;
      });
      return;
    }
    if (!verifying &&
        !resend &&
        _createPasswordlessAccount &&
        (!await _reviewEmailNotice() || !mounted)) {
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      if (verifying) {
        await repository.verifyPhoneSignInCode(
          phone: phone!,
          code: _codeController.text,
        );
        if (mounted) context.go('/');
      } else {
        // Recheck on send: a provider may have been disabled since the menu
        // opened. Never replace a failed settings read with assumed support.
        final methods = await ref.refresh(authMethodsProvider.future);
        if ((isPhone && !methods.phone) ||
            (!isPhone && !methods.email) ||
            (_createPasswordlessAccount && !methods.signup)) {
          throw const AuthException(
            'This sign-in method is currently unavailable.',
          );
        }
        if (isPhone) {
          await repository.sendPhoneSignInCode(
            phone: phone!,
            createAccount: _createPasswordlessAccount,
            emailUpdates: _emailUpdates,
          );
          if (mounted) {
            setState(() {
              _sentPhone = phone;
              _success = 'Enter the code sent to $phone.';
            });
          }
        } else {
          _watchExternalSignIn();
          await repository.sendEmailSignInLink(
            email: _emailController.text,
            createAccount: _createPasswordlessAccount,
            emailUpdates: _emailUpdates,
          );
          if (mounted) {
            setState(
              () => _success =
                  'Check your inbox and spam folder. Open the Workloop link on this device to continue.',
            );
          }
        }
        if (mounted) _startResendCooldown();
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthErrorMessage(error.message));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We could not connect. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _moreMethods() async {
    if (_busy) return;
    final creating = _mode == _AuthMode.signup;
    final choice = await showWorkloopBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MoreAuthMethods(creating: creating),
    );
    if (!mounted || choice == null) return;
    if (choice == 'apple-oauth') {
      await _signInWithSocial(choice);
    } else {
      _createPasswordlessAccount = creating;
      _setMode(choice == 'phone' ? _AuthMode.phone : _AuthMode.emailLink);
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
                // Persistent field labels need extra room on standard phones.
                // Compact gaps preserve the controls; larger windows share
                // spare height above the form and footer.
                final compactHeight = constraints.maxHeight < 800;
                final verticalInset = compactHeight
                    ? AppSpacing.xs
                    : AppSpacing.sm;
                return SingleChildScrollView(
                  key: const ValueKey('auth-scroll'),
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageX,
                    vertical: verticalInset,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 440,
                        minHeight: constraints.maxHeight - (verticalInset * 2),
                      ),
                      child: IntrinsicHeight(
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _AuthBrandHeader(),
                              if (!compactHeight) const Spacer(),
                              SizedBox(
                                height: compactHeight
                                    ? AppSpacing.xs
                                    : AppSpacing.md,
                              ),
                              AnimatedSwitcher(
                                duration: AppMotion.responsive(
                                  context,
                                  AppMotion.standard,
                                ),
                                child: Text(
                                  _mode.title,
                                  key: ValueKey(_mode),
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.of(context).t1,
                                    letterSpacing: 0,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                _mode.subtitle,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: AppColors.of(context).t2,
                                  height: 1.4,
                                ),
                              ),
                              SizedBox(
                                height: compactHeight
                                    ? AppSpacing.sm
                                    : AppSpacing.xl,
                              ),
                              _SlateTextField(
                                controller: _mode == _AuthMode.phone
                                    ? _phoneController
                                    : _emailController,
                                label: _mode == _AuthMode.phone
                                    ? 'Phone number'
                                    : 'Email address',
                                hint: _mode == _AuthMode.phone
                                    ? 'Phone number, including +country code'
                                    : 'Email address',
                                keyboardType: _mode == _AuthMode.phone
                                    ? TextInputType.phone
                                    : TextInputType.emailAddress,
                                autofillHints: _mode == _AuthMode.phone
                                    ? const [AutofillHints.telephoneNumber]
                                    : const [AutofillHints.email],
                                enabled: !_busy && _sentPhone == null,
                                textInputAction: !_mode.usesPassword
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                onSubmitted: !_mode.usesPassword
                                    ? (_) => _submit()
                                    : null,
                              ),
                              if (_mode == _AuthMode.phone &&
                                  _sentPhone != null) ...[
                                const SizedBox(height: 12),
                                _SlateTextField(
                                  controller: _codeController,
                                  label: 'Verification code',
                                  hint: 'Verification code',
                                  keyboardType: TextInputType.number,
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode,
                                  ],
                                  enabled: !_busy,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                ),
                                Wrap(
                                  children: [
                                    TextButton(
                                      onPressed: _busy || _resendSeconds > 0
                                          ? null
                                          : () => _submitPasswordless(
                                              resend: true,
                                            ),
                                      child: Text(
                                        _resendSeconds > 0
                                            ? 'Send again in ${_resendSeconds}s'
                                            : 'Send a new code',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(() {
                                              _sentPhone = null;
                                              _codeController.clear();
                                              _error = null;
                                              _success = null;
                                            }),
                                      child: const Text('Change number'),
                                    ),
                                  ],
                                ),
                              ],
                              if (_mode.usesPassword) ...[
                                SizedBox(height: compactHeight ? 8 : 12),
                                _SlateTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  hint: 'Password',
                                  obscure: true,
                                  enabled: !_busy,
                                  autofillHints: [
                                    _mode == _AuthMode.signup
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                ),
                                if (_mode == _AuthMode.login)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton(
                                            key: const ValueKey(
                                              'auth-more-methods',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : _moreMethods,
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(44, 44),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.xs,
                                                  ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: const Text('More options'),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () =>
                                                _setMode(_AuthMode.reset),
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(44, 44),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.xs,
                                                  ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: const Text(
                                              'Forgot password?',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (_mode == _AuthMode.signup) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Use $minimumWorkloopPasswordLength+ characters with uppercase, lowercase, a number, and a symbol.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.of(context).t3,
                                    ),
                                  ),
                                ],
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                SlateErrorState(message: _error!),
                              ],
                              if (_success != null) ...[
                                const SizedBox(height: 12),
                                _AuthSuccessState(message: _success!),
                              ],
                              const SizedBox(height: AppSpacing.xs),
                              SlateButton(
                                key: const ValueKey('auth-primary-action'),
                                label: _isLoading
                                    ? 'One moment'
                                    : _mode == _AuthMode.phone &&
                                          _sentPhone != null
                                    ? 'Verify and continue'
                                    : (_mode == _AuthMode.emailLink ||
                                              _mode == _AuthMode.phone) &&
                                          _resendSeconds > 0
                                    ? 'Send again in ${_resendSeconds}s'
                                    : _mode.actionLabel,
                                icon: _isLoading
                                    ? null
                                    : LucideIcons.arrowRight,
                                onPressed:
                                    _busy ||
                                        ((_mode == _AuthMode.emailLink ||
                                                (_mode == _AuthMode.phone &&
                                                    _sentPhone == null)) &&
                                            _resendSeconds > 0)
                                    ? null
                                    : _submit,
                              ),
                              if (_mode == _AuthMode.login) ...[
                                SizedBox(
                                  height: compactHeight
                                      ? AppSpacing.xxs
                                      : AppSpacing.sm,
                                ),
                                Center(
                                  child: KeyedSubtree(
                                    key: const ValueKey('auth-first-run-cta'),
                                    child: TextButton(
                                      key: const ValueKey('auth-mode-toggle'),
                                      onPressed: () =>
                                          _setMode(_AuthMode.signup),
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(44, 44),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'New to Workloop? Create account',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (_mode.usesPassword) ...[
                                SizedBox(
                                  height: compactHeight
                                      ? AppSpacing.xs
                                      : AppSpacing.md,
                                ),
                                const _AuthDivider(),
                                SizedBox(
                                  height: compactHeight
                                      ? AppSpacing.sm
                                      : AppSpacing.md,
                                ),
                                if (!kIsWeb &&
                                    defaultTargetPlatform ==
                                        TargetPlatform.iOS) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: SignInWithAppleButton(
                                      key: const ValueKey('auth-apple'),
                                      onPressed: !_busy
                                          ? () => _signInWithSocial('apple')
                                          : () {},
                                      style: SignInWithAppleButtonStyle.white,
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(AppRadius.md),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                ],
                                WorkloopPrimaryButton(
                                  key: const ValueKey('auth-google'),
                                  label: _socialProvider == 'google'
                                      ? 'Opening Google'
                                      : 'Continue with Google',
                                  secondary: true,
                                  onPressed: !_busy
                                      ? () => _signInWithSocial('google')
                                      : null,
                                ),
                                if (_mode == _AuthMode.signup)
                                  Center(
                                    child: TextButton(
                                      key: const ValueKey('auth-more-methods'),
                                      onPressed: _busy ? null : _moreMethods,
                                      child: const Text('More sign-in options'),
                                    ),
                                  ),
                              ],
                              if (_mode != _AuthMode.login) ...[
                                SizedBox(height: compactHeight ? 8 : 16),
                                Center(
                                  child: TextButton(
                                    key: const ValueKey(
                                      'auth-return-mode-toggle',
                                    ),
                                    onPressed: () => _setMode(_mode.toggleMode),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(44, 44),
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: AppMotion.responsive(
                                        context,
                                        AppMotion.standard,
                                      ),
                                      child: RichText(
                                        key: ValueKey('auth-toggle-$_mode'),
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontFamily: 'Manrope',
                                            fontSize: 14,
                                            color: AppColors.of(context).t3,
                                          ),
                                          children: [
                                            TextSpan(text: _mode.togglePrompt),
                                            TextSpan(
                                              text: _mode.toggleAction,
                                              style: TextStyle(
                                                color: AppColors.of(
                                                  context,
                                                ).green,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (!compactHeight) const Spacer(flex: 2),
                              if (_mode.usesPassword) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Center(
                                  child: _AuthLegalNotice(
                                    compact: true,
                                    onOpen: (document) => Navigator.push<void>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LegalDocumentScreen(
                                          document: document,
                                          backSemanticLabel:
                                              'Back to account access',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
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

class _MoreAuthMethods extends ConsumerWidget {
  final bool creating;
  const _MoreAuthMethods({required this.creating});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(authMethodsProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pageX),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              creating ? 'Create your account' : 'More ways to sign in',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            methods.when(
              skipLoadingOnRefresh: false,
              skipError: false,
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => SlateErrorState(
                message:
                    'Could not load sign-in options. Check your connection and try again.',
                onRetry: () => ref.invalidate(authMethodsProvider),
              ),
              data: (available) {
                if (creating && !available.signup) {
                  return const Text(
                    'New accounts are temporarily unavailable. You can still sign in to an existing account.',
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (available.email)
                      ListTile(
                        key: const ValueKey('auth-email-link'),
                        leading: const Icon(LucideIcons.mail),
                        title: const Text('Email me a sign-in link'),
                        subtitle: const Text('Continue without a password'),
                        onTap: () => Navigator.pop(context, 'email-link'),
                      ),
                    if (available.phone)
                      ListTile(
                        key: const ValueKey('auth-phone'),
                        leading: const Icon(LucideIcons.smartphone),
                        title: const Text('Continue with phone'),
                        subtitle: const Text('Receive a code by text message'),
                        onTap: () => Navigator.pop(context, 'phone'),
                      ),
                    if (available.appleOAuth &&
                        (kIsWeb ||
                            (defaultTargetPlatform != TargetPlatform.iOS &&
                                defaultTargetPlatform != TargetPlatform.macOS)))
                      ListTile(
                        key: const ValueKey('auth-apple-oauth'),
                        leading: const Icon(Icons.apple),
                        title: const Text('Continue with Apple'),
                        onTap: () => Navigator.pop(context, 'apple-oauth'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.of(context).border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            'OR',
            style: TextStyle(
              color: AppColors.of(context).t3,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.of(context).border)),
      ],
    );
  }
}

class _AuthLegalNotice extends StatelessWidget {
  final ValueChanged<WorkloopLegalDocument> onOpen;
  final bool compact;

  const _AuthLegalNotice({required this.onOpen, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    return Semantics(
      container: true,
      child: Column(
        children: [
          if (!compact)
            Text(
              'By continuing, you agree to our terms and privacy policy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xxs,
            children: [
              TextButton(
                key: const ValueKey('auth-terms-link'),
                onPressed: () => onOpen(WorkloopLegalDocument.terms),
                style: linkStyle,
                child: const Text('Terms of use'),
              ),
              Text('and', style: TextStyle(color: AppColors.of(context).t3)),
              TextButton(
                key: const ValueKey('auth-privacy-link'),
                onPressed: () => onOpen(WorkloopLegalDocument.privacy),
                style: linkStyle,
                child: const Text('Privacy policy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthBrandHeader extends StatelessWidget {
  const _AuthBrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      key: ValueKey('auth-brand-panel'),
      children: [
        Expanded(child: WorkloopWordmark(size: 22)),
        SizedBox(width: AppSpacing.md),
        WorkloopIllustration(
          key: ValueKey('auth-brand-icon'),
          kind: WorkloopIllustrationKind.storefront,
          size: 40,
        ),
      ],
    );
  }
}

enum _AuthMode {
  login,
  signup,
  reset,
  emailLink,
  phone;

  bool get usesPassword => this == login || this == signup;

  String get title => switch (this) {
    _AuthMode.login => 'Welcome back.',
    _AuthMode.signup => 'Create your account.',
    _AuthMode.reset => 'Reset password.',
    _AuthMode.emailLink => 'Continue with email.',
    _AuthMode.phone => 'Continue with your phone.',
  };

  String get subtitle => switch (this) {
    _AuthMode.login => 'Sign in to your workspace.',
    _AuthMode.signup => 'Start running your business from one app.',
    _AuthMode.reset => 'Enter your email and we will send a reset link.',
    _AuthMode.emailLink => 'We will email you a secure, one-use sign-in link.',
    _AuthMode.phone =>
      'We will text you a verification code. A verified account email is also required.',
  };

  String get actionLabel => switch (this) {
    _AuthMode.login => 'Sign in',
    _AuthMode.signup => 'Create account',
    _AuthMode.reset => 'Send reset email',
    _AuthMode.emailLink => 'Email me a sign-in link',
    _AuthMode.phone => 'Send verification code',
  };

  _AuthMode get toggleMode => switch (this) {
    _AuthMode.login => _AuthMode.signup,
    _AuthMode.signup => _AuthMode.login,
    _AuthMode.reset ||
    _AuthMode.emailLink ||
    _AuthMode.phone => _AuthMode.login,
  };

  String get togglePrompt => switch (this) {
    _AuthMode.login => "Don't have an account? ",
    _AuthMode.signup => 'Already have an account? ',
    _AuthMode.reset => 'Remembered it? ',
    _AuthMode.emailLink || _AuthMode.phone => 'Prefer another way? ',
  };

  String get toggleAction => switch (this) {
    _AuthMode.login => 'Sign up',
    _AuthMode.signup => 'Sign in',
    _AuthMode.reset || _AuthMode.emailLink || _AuthMode.phone => 'Sign in',
  };
}

class _AuthSuccessState extends StatelessWidget {
  final String message;

  const _AuthSuccessState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.of(context).green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.of(context).green.withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: AppColors.of(context).green,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlateTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String label;
  final bool obscure;
  final TextInputType keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const _SlateTextField({
    required this.controller,
    required this.hint,
    required this.label,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  State<_SlateTextField> createState() => _SlateTextFieldState();
}

class _SlateTextFieldState extends State<_SlateTextField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return WorkloopFormField(
      label: widget.label,
      isRequired: true,
      child: TextField(
        enabled: widget.enabled,
        controller: widget.controller,
        obscureText: _obscured,
        keyboardType: widget.keyboardType,
        autofillHints: widget.autofillHints,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        autocorrect: !widget.obscure,
        enableSuggestions: !widget.obscure,
        style: TextStyle(color: AppColors.of(context).t1, fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _obscured ? 'Show password' : 'Hide password',
                  onPressed: () {
                    SlateHaptics.selection();
                    setState(() => _obscured = !_obscured);
                  },
                  icon: Icon(
                    _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
                    color: AppColors.of(context).t3,
                    size: 19,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
