import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/slate_ui.dart';

class ObWelcome extends StatelessWidget {
  final VoidCallback onNext;
  const ObWelcome({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = SlateTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 700;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                AppSpacing.sm,
                AppSpacing.pageX,
                AppSpacing.md,
              ),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const WorkloopWordmark(),
                        if (!compact) const Spacer(),
                        SizedBox(
                          height: compact ? AppSpacing.xl : AppSpacing.xxl,
                        ),
                        Semantics(
                          header: true,
                          child: Text(
                            'Your business,\nin good order.',
                            style: textTheme.displayMedium,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Bookings, clients and money, connected in one place. '
                          'Built for people who work for themselves.',
                          style: textTheme.bodyLarge?.copyWith(
                            color: tokens.textSecondary,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const _BusinessOrganiser(),
                        if (!compact) const Spacer(flex: 2),
                        const SizedBox(height: AppSpacing.xl),
                        Center(
                          child: Text(
                            'Let’s make Workloop yours.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SlateButton(
                          key: const ValueKey('onboarding-get-started'),
                          label: 'Get started',
                          icon: LucideIcons.arrowRight,
                          onPressed: onNext,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// An illustrated introduction to the real workspace, without sample records
/// or progress states that could be mistaken for the owner's business data.
class _BusinessOrganiser extends StatelessWidget {
  const _BusinessOrganiser();

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopPaperPanel(
      title: 'A clearer working day',
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const _WorkspaceRow(
            illustration: WorkloopIllustrationKind.calendar,
            title: 'Know what’s next',
            description: 'Your bookings and tasks, together.',
          ),
          Divider(
            height: 1,
            color: tokens.divider,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
          ),
          const _WorkspaceRow(
            illustration: WorkloopIllustrationKind.clients,
            title: 'Every client, remembered',
            description: 'Their details and history, ready.',
          ),
          Divider(
            height: 1,
            color: tokens.divider,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
          ),
          const _WorkspaceRow(
            illustration: WorkloopIllustrationKind.receipt,
            title: 'Money in view',
            description: 'Quotes, invoices and payments.',
          ),
        ],
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  final WorkloopIllustrationKind illustration;
  final String title;
  final String description;

  const _WorkspaceRow({
    required this.illustration,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = SlateTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkloopIllustration(kind: illustration, size: 48),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
