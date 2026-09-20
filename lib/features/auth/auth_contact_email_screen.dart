import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'auth_validation.dart';

/// Shown by AuthGate before workspace access for a verified phone identity
/// without a verified email. Verification belongs to Supabase, never a local
/// checkbox or metadata flag.
class AuthContactEmailScreen extends ConsumerStatefulWidget {
  final VoidCallback onVerified;

  const AuthContactEmailScreen({super.key, required this.onVerified});

  @override
  ConsumerState<AuthContactEmailScreen> createState() =>
      _AuthContactEmailScreenState();
}

class _AuthContactEmailScreenState
    extends ConsumerState<AuthContactEmailScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (!isValidAuthEmail(_email.text)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    await _run(() async {
      await ref
          .read(authRepositoryProvider)
          .requestContactEmailVerification(_email.text);
      if (mounted) setState(() => _sent = true);
    });
  }

  Future<void> _check() => _run(() async {
    final verified = await ref
        .read(authRepositoryProvider)
        .refreshContactEmailVerification();
    if (!mounted) return;
    if (verified) {
      widget.onVerified();
    } else {
      setState(
        () => _error =
            'Open the verification link in your email first, then try again.',
      );
    }
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthErrorMessage(error.message));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'We could not connect. Your account is safe; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).bg,
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pageX),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WorkloopWordmark(size: 26),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Add your account email',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Use an email you can access for account recovery, receipts and important Workloop updates. Verify it before setting up your business.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const ValueKey('auth-contact-email'),
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                label: WorkloopFieldLabel('Email address', isRequired: true),
              ),
              onChanged: (_) {
                if (_sent) setState(() => _sent = false);
              },
              onSubmitted: (_) => _send(),
            ),
            if (_sent) ...[
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Check your inbox and spam folder. Open the verification link, then return here.',
                style: TextStyle(height: 1.5),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              SlateErrorState(message: _error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            SlateButton(
              label: _busy
                  ? 'One moment'
                  : _sent
                  ? 'I have verified my email'
                  : 'Send verification email',
              onPressed: _busy
                  ? null
                  : _sent
                  ? _check
                  : _send,
            ),
            if (_sent)
              TextButton(
                onPressed: _busy ? null : _send,
                child: const Text('Send another verification email'),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => ref.read(authRepositoryProvider).signOutLocal(),
                    ),
              child: const Text('Use a different account'),
            ),
          ],
        ),
      ),
    ),
  );
}
