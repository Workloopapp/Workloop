import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';

/// A temporarily locked Keychain must not become an empty sign-in session.
class SecureSessionRecoveryScreen extends StatefulWidget {
  const SecureSessionRecoveryScreen({super.key, required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  State<SecureSessionRecoveryScreen> createState() =>
      _SecureSessionRecoveryScreenState();
}

class _SecureSessionRecoveryScreenState
    extends State<SecureSessionRecoveryScreen> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pageX),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Your sign-in couldn’t be loaded',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Workloop couldn’t open secure sign-in storage. Unlock your device and try again. Your saved sign-in has not been removed.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  WorkloopPrimaryButton(
                    label: _busy ? 'Please wait…' : 'Try again',
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await widget.onRetry();
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
