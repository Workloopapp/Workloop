import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:workloop/features/subscription/store_trial_offer.dart';
import 'package:workloop/features/subscription/subscription_access.dart';

import 'support/store_trial_fakes.dart';
import 'support/subscription_fakes.dart';

void main() {
  test(
    'only exact StoreKit offer plus positive eligibility promises a trial',
    () async {
      final checked = <String>[];
      final offer = await loadAppleTrialOffer(
        appleTrialProduct(),
        checkEligibility: (id) async {
          checked.add(id);
          return true;
        },
      );
      expect(checked, [WorkloopPlans.monthlyId]);
      expect(offer.status, StoreTrialEligibility.eligible);
      expect(offer.isEligible, isTrue);
      expect(offer.isConfigured, isTrue);
    },
  );

  test(
    'previous introductory use retains configured but ineligible status',
    () async {
      final offer = await loadAppleTrialOffer(
        appleTrialProduct(),
        checkEligibility: (_) async => false,
      );
      expect(offer.status, StoreTrialEligibility.ineligible);
      expect(offer.isEligible, isFalse);
      expect(offer.isConfigured, isTrue);
    },
  );

  test(
    'failed Apple eligibility is unknown and never advertised as free',
    () async {
      final offer = await loadAppleTrialOffer(
        appleTrialProduct(),
        checkEligibility: (_) async => throw StateError('store unavailable'),
      );
      expect(offer.status, StoreTrialEligibility.unknown);
      expect(offer.isEligible, isFalse);
    },
  );

  test('missing platform metadata cannot prove a configured offer', () async {
    final offer = await loadAppleTrialOffer(
      subscriptionProduct(),
      checkEligibility: (_) async => throw StateError('must not query'),
    );
    expect(offer.status, StoreTrialEligibility.unknown);
  });

  final mismatched = {
    'no introductory offer': appleTrialProduct(configured: false),
    'promotional discount': appleTrialProduct(
      offerType: SK2SubscriptionOfferType.promotional,
    ),
    'win-back discount': appleTrialProduct(
      offerType: SK2SubscriptionOfferType.winBack,
    ),
    'paid introduction': appleTrialProduct(introductoryPrice: 1),
    'upfront offer': appleTrialProduct(
      mode: SK2SubscriptionOfferPaymentMode.payUpFront,
    ),
    'thirty days': appleTrialProduct(
      trialUnit: SK2SubscriptionPeriodUnit.day,
      trialUnits: 30,
    ),
    'one week': appleTrialProduct(trialUnit: SK2SubscriptionPeriodUnit.week),
    'two months': appleTrialProduct(trialUnits: 2),
    'repeated monthly periods': appleTrialProduct(trialPeriods: 2),
    'annual renewal': appleTrialProduct(
      renewalUnit: SK2SubscriptionPeriodUnit.year,
    ),
    'three-month renewal': appleTrialProduct(renewalCount: 3),
    'annual product ID': appleTrialProduct(id: WorkloopPlans.yearlyId),
    'non-consumable': appleTrialProduct(type: SK2ProductType.nonConsumable),
  };
  for (final entry in mismatched.entries) {
    test('${entry.key} never becomes a one-month trial promise', () async {
      var checked = false;
      final offer = await loadAppleTrialOffer(
        entry.value,
        checkEligibility: (_) async {
          checked = true;
          return true;
        },
      );
      expect(checked, isFalse);
      expect(offer.status, StoreTrialEligibility.notConfigured);
      expect(offer.isEligible, isFalse);
    });
  }
}
