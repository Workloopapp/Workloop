import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/repositories/privacy_repository.dart';
import '../../shared/widgets/slate_ui.dart';

/// This route contains no account identifiers and remains visible after logout.
class AccountDeletionConfirmationScreen extends StatelessWidget {
  const AccountDeletionConfirmationScreen({super.key, required this.result});
  final AccountDeletionResult result;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Account deletion'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pageX),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your request is recorded',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Account access is closed and deletion is queued. Pending requests are checked every minute. Provider issues may delay completion. We’ll email you when deletion is complete.',
            ),
            if (result.needsAppleUnlink) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Finish disconnecting Apple',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Your Workloop deletion request is accepted. We couldn’t automatically disconnect Sign in with Apple. Open your Apple Account, choose Sign in with Apple, select Workloop, then Stop Using Sign in with Apple.',
              ),
              const SizedBox(height: AppSpacing.md),
              WorkloopPrimaryButton(
                label: 'Open Apple Account',
                onPressed: () async {
                  var opened = false;
                  try {
                    opened = await launchUrl(
                      Uri.parse('https://account.apple.com/'),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {
                    /* Keep the manual instructions available. */
                  }
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Open account.apple.com in your browser to continue.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Deleting Workloop does not cancel an Apple or Google subscription. Cancel any subscription in your store subscription settings.',
            ),
            const SizedBox(height: AppSpacing.lg),
            WorkloopTextButton(
              label: 'Back to sign in',
              onPressed: () => context.go('/auth'),
            ),
          ],
        ),
      ),
    ),
  );
}
