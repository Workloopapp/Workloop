import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import 'subscription_access.dart';

String subscriptionDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatFullDate(date.toLocal());

class SubscriptionValuePreview extends StatelessWidget {
  const SubscriptionValuePreview({super.key});
  @override
  Widget build(BuildContext context) => WorkloopPaperPanel(
    title: 'One plan. Everything included.',
    child: Column(
      children: [
        for (final (kind, title, detail) in const [
          (
            WorkloopIllustrationKind.clients,
            'Every client, remembered',
            'Details and work history, ready when you need them.',
          ),
          (
            WorkloopIllustrationKind.calendar,
            'A clearer working day',
            'Bookings and the work that needs your attention.',
          ),
          (
            WorkloopIllustrationKind.receipt,
            'From job to payment',
            'Quotes, invoices and money, connected.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkloopIllustration(kind: kind, size: 38),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SlateTheme.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class SubscriptionOfferCard extends StatelessWidget {
  const SubscriptionOfferCard({
    super.key,
    required this.product,
    required this.freeTrial,
    required this.busy,
    required this.onContinue,
  });
  final ProductDetails product;
  final bool freeTrial, busy;
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => WorkloopPaperPanel(
    title: freeTrial ? 'Your first month is on us' : 'Workloop monthly',
    tone: WorkloopPaperTone.warm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${product.price} / month',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          freeTrial
              ? '1 month free, then billed monthly. Automatically renews unless cancelled.'
              : 'Billed monthly. Automatically renews unless cancelled.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        const SizedBox(height: AppSpacing.md),
        WorkloopPrimaryButton(
          label: freeTrial
              ? 'Start my 1-month free trial'
              : 'Continue with monthly plan',
          onPressed: busy ? null : onContinue,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          freeTrial
              ? 'Nothing to pay today. Apple confirms your trial and billing terms before you start.'
              : 'Review the price and any available offer in the store before confirming.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
        ),
      ],
    ),
  );
}

class SubscriptionTrialTimeline extends StatelessWidget {
  const SubscriptionTrialTimeline({super.key, required this.emailReminders});
  final bool emailReminders;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'How your trial works',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.sm),
      const _TimelineStep(
        number: '1',
        title: 'Start with Apple',
        body:
            'Confirm your free trial, then set up your business at your own pace.',
      ),
      if (emailReminders)
        const _TimelineStep(
          number: '2',
          title: 'A reminder before you pay',
          body:
              'We’ll email your account address 7 and 3 days before the first charge.',
        ),
      _TimelineStep(
        number: emailReminders ? '3' : '2',
        title: 'Keep going, or cancel',
        body:
            'Your monthly plan starts when the trial ends. To avoid a charge, cancel in Apple subscriptions at least 24 hours before the trial ends.',
      ),
    ],
  );
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.number,
    required this.title,
    required this.body,
  });
  final String number, title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SlateTheme.of(context).surfaceSubtle,
            shape: BoxShape.circle,
          ),
          child: Text(number, style: Theme.of(context).textTheme.labelMedium),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: SlateTheme.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SubscriptionStatusCard extends StatelessWidget {
  const SubscriptionStatusCard({
    super.key,
    required this.access,
    this.email,
    this.product,
  });
  final SubscriptionAccess access;
  final String? email;
  final ProductDetails? product;
  @override
  Widget build(BuildContext context) {
    final end = access.accessEndsAt;
    final date = end == null ? null : subscriptionDate(context, end);
    final trialDate = access.trialEndsAt == null
        ? null
        : subscriptionDate(context, access.trialEndsAt!);
    final renewalDate = access.renewsAt == null
        ? null
        : subscriptionDate(context, access.renewsAt!);
    final message = access.isSandboxSubscription
        ? 'No real payment was taken.${date == null ? '' : ' Test access ends on $date.'} ${access.autoRenews == false ? 'Test renewal is off.' : 'Manage test renewals in your Sandbox Apple Account settings.'}'
        : switch (access.state) {
            'beta_lifetime' =>
              'Thank you for helping shape Workloop. Your beta account has free lifetime access. There is nothing to pay and no subscription to cancel.',
            'beta' =>
              'You can keep using Workloop during the beta. No payment is needed.',
            'trial' =>
              'Your existing free access${trialDate == null ? '' : ' ends on $trialDate'}. This earlier trial does not charge automatically. Choose a subscription when you’re ready.',
            'store_trial' =>
              access.autoRenews == false
                  ? 'Renewal is off. Your free trial${trialDate == null ? '' : ' ends on $trialDate'}. Apple will not renew this subscription unless you turn renewal back on.'
                  : 'All of Workloop is yours to try${trialDate == null ? '' : ' until $trialDate'}. ${access.autoRenews == true ? 'Your monthly subscription renews automatically after the trial.' : 'Check your renewal and cancellation status in Apple subscriptions.'}',
            'subscribed' =>
              access.inBillingRetry
                  ? 'Apple needs help with your payment. Update your billing details in Apple subscriptions.${date == null ? '' : ' Your current access ends on $date.'}'
                  : access.autoRenews == false
                  ? 'Renewal is off.${date == null ? '' : ' You can keep using Workloop until $date.'} You can restart renewal in your store subscription settings.'
                  : 'Your plan keeps your business connected.${renewalDate == null ? '' : ' Next renewal: $renewalDate.'} Manage billing and cancellation in your store subscription settings.',
            _ =>
              'Choose a plan to keep your business connected. Existing records are safe, and export and account controls remain available.',
          };
    return WorkloopPaperPanel(
      title: access.isSandboxSubscription
          ? 'Test subscription'
          : access.isStoreTrial
          ? 'Your free month'
          : 'Your access',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            access.isSandboxSubscription
                ? 'Apple Sandbox purchase'
                : access.label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: const TextStyle(height: 1.5)),
          if (access.hasStoreSubscription &&
              !access.isSandboxSubscription &&
              product != null &&
              product!.id == WorkloopPlans.monthlyId &&
              product!.id == access.productId) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Current monthly price: ${product!.price}. Apple confirms your renewal amount in subscription settings.',
              style: const TextStyle(height: 1.45),
            ),
          ],
          if (access.isStoreTrial &&
              !access.isSandboxSubscription &&
              access.autoRenews != false) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'To avoid a charge, cancel at least 24 hours before your trial ends.',
              style: TextStyle(height: 1.45),
            ),
            if (access.billingRemindersEnabled &&
                access.autoRenews == true) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Trial reminders go to ${email ?? 'your account email'} 7 and 3 days before renewal.',
                style: const TextStyle(height: 1.45),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
