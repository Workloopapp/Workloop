import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/repositories/supabase_client_provider.dart';
import '../../shared/widgets/slate_ui.dart';
import '../settings/legal_document_screen.dart';
import '../settings/support_screen.dart';
import '../settings/widgets/settings_account_tab.dart';
import 'store_purchase_service.dart';
import 'subscription_access.dart';
import 'subscription_plan_widgets.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key, this.canClose = true});
  final bool canClose;
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen>
    with WidgetsBindingObserver {
  String? _loadedForUserId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    // Refresh access and offer eligibility after an Apple account/settings change.
    _loadedForUserId = null;
    ref.invalidate(subscriptionAccessProvider(userId));
  }

  Future<void> _openUrl(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep account and restore controls available if the store cannot open.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open that page. Please try again.'),
        ),
      );
    }
  }

  void _open(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(supabaseClientProvider).auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    final access = ref.watch(subscriptionAccessProvider(user.id));
    final service = ref.watch(storePurchaseServiceProvider(user.id));
    final value = access.value;
    final apple = defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;
    final android = defaultTargetPlatform == TargetPlatform.android && !kIsWeb;
    final salesEnabled =
        value != null &&
        !access.hasError &&
        !access.isLoading &&
        !value.isLifetime &&
        value.state != 'beta' &&
        (apple ? value.appleSalesEnabled : android && value.googleSalesEnabled);
    if (salesEnabled && _loadedForUserId != user.id) {
      _loadedForUserId = user.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(supabaseClientProvider).auth.currentUser?.id == user.id) {
          service.load();
        }
      });
    }
    final showOffer =
        value != null &&
        !value.isLifetime &&
        !value.hasStoreSubscription &&
        value.state != 'beta';
    return Scaffold(
      backgroundColor: SlateTheme.of(context).surface,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                AppSpacing.screenTop,
                AppSpacing.pageX,
                AppSpacing.xxl,
              ),
              children: [
                if (widget.canClose)
                  const WorkloopRouteHeader(title: 'Your Workloop plan')
                else
                  const WorkloopWordmark(),
                const SizedBox(height: AppSpacing.lg),
                if (access.isLoading && value == null)
                  const Center(child: CircularProgressIndicator())
                else if (access.hasError) ...[
                  Text(
                    'Let’s check your plan',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'We could not check your plan. Please check your connection.',
                  ),
                  WorkloopTextButton(
                    label: 'Try again',
                    onPressed: () =>
                        ref.invalidate(subscriptionAccessProvider(user.id)),
                  ),
                ] else if (value != null) ...[
                  if (showOffer) ...[
                    Text(
                      widget.canClose
                          ? 'Make room for your work.'
                          : 'Your business,\nin good order.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'For people who work for themselves, by themselves.\nOne place for your clients, work and money.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SubscriptionValuePreview(),
                    if (value.state == 'trial') ...[
                      const SizedBox(height: AppSpacing.md),
                      SubscriptionStatusCard(access: value),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    ValueListenableBuilder<StorePurchaseState>(
                      valueListenable: service.state,
                      builder: (context, purchase, _) {
                        final product = purchase.products
                            .where((p) => p.id == WorkloopPlans.monthlyId)
                            .firstOrNull;
                        final freeTrial =
                            apple &&
                            product != null &&
                            purchase.oneMonthTrialEligible(product.id);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (salesEnabled &&
                                purchase.available &&
                                product != null)
                              SubscriptionOfferCard(
                                product: product,
                                freeTrial: freeTrial,
                                busy:
                                    purchase.busy ||
                                    purchase.awaitingApproval ||
                                    purchase.awaitingVerification,
                                onContinue: () => service.buy(product),
                              )
                            else if (!salesEnabled)
                              const WorkloopPaperPanel(
                                title: 'Monthly membership',
                                child: Text(
                                  'We’re preparing subscriptions for launch. Planned UK price: £14.99 per month, with 1 month free for eligible new Apple subscribers. Purchasing is not available yet.',
                                  style: TextStyle(height: 1.5),
                                ),
                              )
                            else if (!purchase.busy)
                              WorkloopPrimaryButton(
                                label: 'Load monthly plan',
                                onPressed: service.load,
                              ),
                            if (freeTrial) ...[
                              const SizedBox(height: AppSpacing.lg),
                              SubscriptionTrialTimeline(
                                emailReminders: value.billingRemindersEnabled,
                              ),
                            ],
                            if (salesEnabled) ...[
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'Cancel in your store subscription settings. Deleting Workloop or your account does not cancel a subscription. Payment collection fees for your own customers are separate.',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(height: 1.5),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ] else
                    ValueListenableBuilder<StorePurchaseState>(
                      valueListenable: service.state,
                      builder: (context, purchase, _) => SubscriptionStatusCard(
                        access: value,
                        email: user.email,
                        product: apple
                            ? purchase.products
                                  .where((p) => p.id == value.productId)
                                  .firstOrNull
                            : null,
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.lg),
                ValueListenableBuilder<StorePurchaseState>(
                  valueListenable: service.state,
                  builder: (context, purchase, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (purchase.busy)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (purchase.message != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            purchase.message!,
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                      WorkloopTextButton(
                        label: 'Restore purchases',
                        onPressed: purchase.busy ? null : service.restore,
                      ),
                    ],
                  ),
                ),
                if (value?.isLifetime != true && value?.state != 'beta')
                  WorkloopTextButton(
                    label: 'Manage store subscription',
                    onPressed: () => _openUrl(
                      (value?.platform == 'apple' ||
                              (value?.platform == null && apple))
                          ? 'https://apps.apple.com/account/subscriptions'
                          : 'https://play.google.com/store/account/subscriptions',
                    ),
                  ),
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    WorkloopTextButton(
                      label: 'Terms of use',
                      onPressed: () => _open(
                        const LegalDocumentScreen(
                          document: WorkloopLegalDocument.terms,
                          backSemanticLabel: 'Back to your plan',
                        ),
                      ),
                    ),
                    WorkloopTextButton(
                      label: 'Privacy policy',
                      onPressed: () => _open(
                        const LegalDocumentScreen(
                          document: WorkloopLegalDocument.privacy,
                          backSemanticLabel: 'Back to your plan',
                        ),
                      ),
                    ),
                  ],
                ),
                if (!widget.canClose) ...[
                  WorkloopTextButton(
                    label: 'Export data or delete account',
                    onPressed: () => _open(
                      Scaffold(
                        appBar: AppBar(title: const Text('Privacy & data')),
                        body: const SettingsAccountTab(showDataOnly: true),
                      ),
                    ),
                  ),
                  WorkloopTextButton(
                    label: 'Manage account or sign out',
                    onPressed: () => _open(
                      Scaffold(
                        appBar: AppBar(title: const Text('Your account')),
                        body: const SettingsAccountTab(),
                      ),
                    ),
                  ),
                ],
                WorkloopTextButton(
                  label: 'Help & support',
                  onPressed: () => _open(const SupportScreen()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
