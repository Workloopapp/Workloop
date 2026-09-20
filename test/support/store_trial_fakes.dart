import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:workloop/features/subscription/subscription_access.dart';

AppStoreProduct2Details appleTrialProduct({
  String id = WorkloopPlans.monthlyId,
  SK2ProductType type = SK2ProductType.autoRenewable,
  SK2SubscriptionPeriodUnit renewalUnit = SK2SubscriptionPeriodUnit.month,
  int renewalCount = 1,
  bool configured = true,
  SK2SubscriptionOfferType offerType = SK2SubscriptionOfferType.introductory,
  SK2SubscriptionOfferPaymentMode mode =
      SK2SubscriptionOfferPaymentMode.freeTrial,
  SK2SubscriptionPeriodUnit trialUnit = SK2SubscriptionPeriodUnit.month,
  int trialUnits = 1,
  int trialPeriods = 1,
  double introductoryPrice = 0,
}) => AppStoreProduct2Details.fromSK2Product(
  SK2Product(
    id: id,
    displayName: 'Workloop Monthly',
    displayPrice: '£14.99',
    description: 'Your business, together.',
    price: 14.99,
    type: type,
    priceLocale: SK2PriceLocale(currencyCode: 'GBP', currencySymbol: '£'),
    subscription: SK2SubscriptionInfo(
      subscriptionGroupID: '22364660',
      subscriptionPeriod: SK2SubscriptionPeriod(
        value: renewalCount,
        unit: renewalUnit,
      ),
      promotionalOffers: [
        if (configured)
          SK2SubscriptionOffer(
            price: introductoryPrice,
            type: offerType,
            period: SK2SubscriptionPeriod(value: trialUnits, unit: trialUnit),
            periodCount: trialPeriods,
            paymentMode: mode,
          ),
      ],
    ),
  ),
);
