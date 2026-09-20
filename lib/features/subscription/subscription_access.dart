import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/repositories/supabase_client_provider.dart';

abstract final class WorkloopPlans {
  static const monthlyId = 'workloop_monthly';
  static const yearlyId = 'workloop_yearly';
  static const monthlyPrice = '£14.99';
  static const yearlyPrice = '£149.99';
  static const trialDays = 30;
  static const productIds = {monthlyId, yearlyId};
}

final subscriptionsEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment(
    'WORKLOOP_SUBSCRIPTIONS_ENABLED',
    defaultValue: false,
  ),
);

class SubscriptionAccess {
  const SubscriptionAccess({
    required this.state,
    required this.hasAccess,
    required this.serverNow,
    this.trialEndsAt,
    this.paidUntil,
    this.appleSalesEnabled = false,
    this.googleSalesEnabled = false,
    this.productId,
    this.platform,
    this.renewsAt,
    this.autoRenews,
    this.inBillingRetry = false,
    this.graceEndsAt,
    this.billingRemindersEnabled = false,
    this.isSandboxTester = false,
    this.sandboxTestExpiresAt,
    this.storeEnvironment,
    Stopwatch? elapsedSinceCheck,
  }) : _elapsedSinceCheck = elapsedSinceCheck;
  final String state;
  final bool hasAccess;
  final DateTime serverNow;
  final DateTime? trialEndsAt, paidUntil;
  final bool appleSalesEnabled, googleSalesEnabled;
  final String? productId, platform;
  final DateTime? renewsAt, graceEndsAt;
  final bool? autoRenews;
  final bool inBillingRetry, billingRemindersEnabled;
  final bool isSandboxTester;
  final DateTime? sandboxTestExpiresAt;
  final String? storeEnvironment;
  final Stopwatch? _elapsedSinceCheck;
  DateTime get estimatedServerNow =>
      serverNow.add(_elapsedSinceCheck?.elapsed ?? Duration.zero);
  bool get isLifetime => state == 'beta_lifetime';
  bool get isStoreTrial => state == 'store_trial';
  bool get hasStoreSubscription => isStoreTrial || state == 'subscribed';
  // The testing permission does not determine which environment Apple uses.
  // Only the verified period selected by the server can label a test purchase.
  bool get isSandboxSubscription =>
      hasStoreSubscription && storeEnvironment == 'Sandbox';
  DateTime? get accessEndsAt => switch (state) {
    'trial' => trialEndsAt,
    'store_trial' || 'subscribed' => paidUntil ?? trialEndsAt,
    _ => null,
  };
  int get trialDaysRemaining => trialEndsAt == null
      ? 0
      : ((trialEndsAt!.difference(estimatedServerNow).inSeconds / 86400).ceil())
            .clamp(0, 31);
  String get label => switch (state) {
    'beta_lifetime' => 'Lifetime beta access',
    'subscribed' =>
      productId == WorkloopPlans.yearlyId ? 'Yearly plan' : 'Monthly plan',
    'trial' || 'store_trial' =>
      '$trialDaysRemaining ${trialDaysRemaining == 1 ? 'day' : 'days'} left in your trial',
    'beta' => 'Free beta access',
    'trial_available' => 'Make Workloop yours',
    _ => 'Choose your plan',
  };
  factory SubscriptionAccess.fromJson(
    Map<String, dynamic> json, {
    Stopwatch? elapsedSinceCheck,
  }) {
    final state = json['state'];
    if (!{
          'beta_lifetime',
          'beta',
          'trial',
          'trial_available',
          'store_trial',
          'subscribed',
          'expired',
        }.contains(state) ||
        json['has_access'] is! bool) {
      throw const FormatException('Could not confirm Workloop access');
    }
    DateTime? date(String key) {
      final raw = json[key];
      if (raw == null) return null;
      final parsed = raw is String ? DateTime.tryParse(raw) : null;
      if (parsed == null) {
        throw const FormatException('Could not confirm Workloop access dates');
      }
      return parsed.toUtc();
    }

    final serverNow = date('server_now');
    if (serverNow == null) {
      throw const FormatException('Could not confirm Workloop server time');
    }
    final environment = json['store_environment'];
    if (environment != null &&
        environment != 'Production' &&
        environment != 'Sandbox') {
      throw const FormatException('Could not confirm the subscription store');
    }
    return SubscriptionAccess(
      state: state as String,
      hasAccess: json['has_access'] as bool,
      serverNow: serverNow,
      trialEndsAt: date('trial_ends_at'),
      paidUntil: date('paid_until'),
      appleSalesEnabled: json['apple_sales_enabled'] == true,
      googleSalesEnabled: json['google_sales_enabled'] == true,
      productId: json['product_id'] as String?,
      platform: json['platform'] as String?,
      renewsAt: date('renews_at'),
      autoRenews: json['auto_renews'] is bool
          ? json['auto_renews'] as bool
          : null,
      inBillingRetry: json['in_billing_retry'] == true,
      graceEndsAt: date('grace_ends_at'),
      billingRemindersEnabled: json['billing_reminders_enabled'] == true,
      isSandboxTester: json['is_sandbox_tester'] == true,
      sandboxTestExpiresAt: date('sandbox_test_expires_at'),
      storeEnvironment: environment as String?,
      elapsedSinceCheck: elapsedSinceCheck ?? (Stopwatch()..start()),
    );
  }
}

final subscriptionAccessProvider = FutureProvider.autoDispose
    .family<SubscriptionAccess, String>((ref, userId) async {
      final client = ref.watch(supabaseClientProvider);
      if (client.auth.currentUser?.id != userId) {
        throw StateError('Sign in again');
      }
      final elapsedSinceCheck = Stopwatch()..start();
      final result = await client
          .rpc('get_workloop_access')
          .timeout(const Duration(seconds: 15));
      if (client.auth.currentUser?.id != userId) {
        throw StateError('Account changed');
      }
      return SubscriptionAccess.fromJson(
        Map<String, dynamic>.from(result as Map),
        elapsedSinceCheck: elapsedSinceCheck,
      );
    });
