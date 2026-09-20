import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'subscription_access.dart';

enum StoreTrialEligibility { eligible, ineligible, notConfigured, unknown }

/// Offer merchandising only. The signed transaction and server own access.
///
/// An eligible status means StoreKit returned both the exact one-month free
/// introduction on our monthly subscription and this customer's eligibility.
class StoreTrialOffer {
  const StoreTrialOffer({this.status = StoreTrialEligibility.unknown});

  final StoreTrialEligibility status;

  bool get isEligible => status == StoreTrialEligibility.eligible;
  bool get isConfigured =>
      status == StoreTrialEligibility.eligible ||
      status == StoreTrialEligibility.ineligible;
}

Future<StoreTrialOffer> loadAppleTrialOffer(
  ProductDetails product, {
  required Future<bool> Function(String productId) checkEligibility,
}) async {
  // StoreKit 1 and platform-neutral products do not prove an offer. Unknown
  // metadata must never become a free-trial promise on the purchase screen.
  if (product is! AppStoreProduct2Details) return const StoreTrialOffer();
  final native = product.sk2Product;
  final subscription = native.subscription;
  if (product.id != WorkloopPlans.monthlyId ||
      native.id != product.id ||
      native.type != SK2ProductType.autoRenewable ||
      subscription == null ||
      subscription.subscriptionPeriod.unit != SK2SubscriptionPeriodUnit.month ||
      subscription.subscriptionPeriod.value != 1) {
    return const StoreTrialOffer(status: StoreTrialEligibility.notConfigured);
  }

  // The plugin's native translator puts the introductory offer into this list
  // alongside promotional offers. Eligibility alone can be true even when no
  // introductory offer exists, so validate its type, price and exact duration.
  final hasOneMonthFree = subscription.promotionalOffers.any(
    (offer) =>
        offer.type == SK2SubscriptionOfferType.introductory &&
        offer.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial &&
        offer.price == 0 &&
        offer.period.unit == SK2SubscriptionPeriodUnit.month &&
        offer.period.value == 1 &&
        offer.periodCount == 1,
  );
  if (!hasOneMonthFree) {
    return const StoreTrialOffer(status: StoreTrialEligibility.notConfigured);
  }
  try {
    final eligible = await checkEligibility(
      product.id,
    ).timeout(const Duration(seconds: 10));
    return StoreTrialOffer(
      status: eligible
          ? StoreTrialEligibility.eligible
          : StoreTrialEligibility.ineligible,
    );
  } catch (_) {
    return const StoreTrialOffer();
  }
}
