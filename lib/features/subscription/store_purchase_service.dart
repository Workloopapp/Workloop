import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/repositories/supabase_client_provider.dart';
import 'subscription_access.dart';
import 'store_trial_offer.dart';

export 'store_trial_offer.dart';

class StorePurchaseState {
  const StorePurchaseState({
    this.busy = false,
    this.products = const [],
    this.message,
    this.available = false,
    this.awaitingApproval = false,
    this.awaitingVerification = false,
    this.trialOffers = const {},
  });
  final bool busy, available;
  final bool awaitingApproval;
  final bool awaitingVerification;
  final List<ProductDetails> products;
  final String? message;
  final Map<String, StoreTrialOffer> trialOffers;

  bool oneMonthTrialEligible(String productId) =>
      trialOffers[productId]?.isEligible == true;
}

final storePurchaseServiceProvider = Provider.autoDispose
    .family<StorePurchaseService, String>((ref, userId) {
      final service = StorePurchaseService(
        ref.watch(supabaseClientProvider),
        userId,
        onVerified: () => ref.invalidate(subscriptionAccessProvider(userId)),
      );
      ref.onDispose(service.dispose);
      return service;
    });

/// The store owns charges. Supabase verifies the signed transaction and owns
/// access. A local purchase callback alone never unlocks a subscription.
class StorePurchaseService {
  StorePurchaseService(
    this.client,
    this.userId, {
    required this.onVerified,
    InAppPurchase? store,
    Future<bool> Function(String productId)? introductoryOfferEligibility,
  }) : store = store ?? InAppPurchase.instance,
       _introductoryOfferEligibility =
           introductoryOfferEligibility ??
           SK2Product.isIntroductoryOfferEligible {
    if (_supported) {
      _subscription = this.store.purchaseStream.listen(
        (purchases) {
          _pending = _pending
              .then((_) async {
                for (final purchase in purchases) {
                  await _handle(purchase);
                }
              })
              .catchError((Object _) {
                _show(
                  'Could not confirm the purchase. Please restore purchases.',
                  awaitingApproval: state.value.awaitingApproval,
                );
              });
        },
        onError: (Object _) {
          _show(
            'The store could not connect. Please try again.',
            awaitingApproval: state.value.awaitingApproval,
          );
        },
      );
    }
  }
  final SupabaseClient client;
  final String userId;
  final VoidCallback onVerified;
  final InAppPurchase store;
  final Future<bool> Function(String productId) _introductoryOfferEligibility;
  final state = ValueNotifier(const StorePurchaseState());
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _pending = Future.value();
  final _verifiedTransactions = <String, bool>{};
  final _completedTransactions = <String>{};
  final _unconfirmedPurchases = <String>{};
  bool _disposed = false;
  int _activity = 0;
  bool get _supported =>
      !kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.android,
      }.contains(defaultTargetPlatform);
  bool get _current => !_disposed && client.auth.currentUser?.id == userId;

  void _show(
    String? message, {
    bool busy = false,
    bool awaitingApproval = false,
    bool? awaitingVerification,
    bool? available,
    List<ProductDetails>? products,
    Map<String, StoreTrialOffer>? trialOffers,
  }) {
    if (!_current) return;
    state.value = StorePurchaseState(
      message: message,
      busy: busy,
      awaitingApproval: awaitingApproval,
      awaitingVerification:
          awaitingVerification ?? state.value.awaitingVerification,
      available: available ?? state.value.available,
      products: products ?? state.value.products,
      trialOffers: trialOffers ?? state.value.trialOffers,
    );
  }

  Future<void> load() async {
    if (!_current ||
        state.value.busy ||
        state.value.awaitingApproval ||
        state.value.awaitingVerification) {
      return;
    }
    final activity = _activity;
    _show(null, busy: true);
    try {
      if (!_supported ||
          !await store.isAvailable().timeout(const Duration(seconds: 12))) {
        if (!_current || activity != _activity) return;
        _show(
          'The app store is unavailable. Please try again later.',
          available: false,
          products: const [],
          trialOffers: const {},
        );
        return;
      }
      final response = await store
          .queryProductDetails({WorkloopPlans.monthlyId})
          .timeout(const Duration(seconds: 20));
      if (!_current || activity != _activity) return;
      if (response.error != null || response.productDetails.isEmpty) {
        _show(
          'Plans are not available in the store yet. Your existing access is unchanged.',
          available: false,
          products: const [],
          trialOffers: const {},
        );
        return;
      }
      final products = response.productDetails
          .where((p) => p.id == WorkloopPlans.monthlyId)
          .toList();
      final trialOffers = <String, StoreTrialOffer>{};
      for (final product in products) {
        trialOffers[product.id] = await _loadTrialOffer(product);
      }
      if (!_current || activity != _activity) return;
      _show(
        products.isEmpty
            ? 'No Workloop plans were returned by the store.'
            : null,
        available: products.isNotEmpty,
        products: products,
        trialOffers: Map.unmodifiable(trialOffers),
      );
    } catch (_) {
      if (!_current || activity != _activity) return;
      _show(
        'Could not load plans. Check your connection and try again.',
        available: false,
        products: const [],
        trialOffers: const {},
      );
    }
  }

  Future<void> buy(ProductDetails product) async {
    if (!_current ||
        state.value.busy ||
        state.value.awaitingApproval ||
        state.value.awaitingVerification ||
        !state.value.available ||
        !state.value.products.any((p) => identical(p, product))) {
      return;
    }
    final activity = ++_activity;
    final expectedFreeTrial = state.value.oneMonthTrialEligible(product.id);
    _show('Waiting for the app store…', busy: true);
    try {
      final refreshedOffer = await _loadTrialOffer(product);
      if (!_current || activity != _activity) return;
      final offers = Map<String, StoreTrialOffer>.unmodifiable({
        ...state.value.trialOffers,
        product.id: refreshedOffer,
      });
      if (expectedFreeTrial && !refreshedOffer.isEligible) {
        _show(
          'Your free trial availability could not be confirmed. Review the plan details before continuing.',
          trialOffers: offers,
        );
        return;
      }
      _show('Waiting for the app store…', busy: true, trialOffers: offers);
      // UUID associates Apple's signed transaction with this Workloop account.
      final started = await store
          .buyNonConsumable(
            purchaseParam: PurchaseParam(
              productDetails: product,
              applicationUserName: userId,
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (!started && activity == _activity) {
        _show('The purchase did not start. Please try again.');
      }
    } catch (_) {
      if (activity != _activity) return;
      _show('No purchase was confirmed. Please try again.');
    }
  }

  Future<StoreTrialOffer> _loadTrialOffer(ProductDetails product) =>
      defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb
      ? loadAppleTrialOffer(
          product,
          checkEligibility: _introductoryOfferEligibility,
        )
      : Future.value(const StoreTrialOffer());

  Future<void> restore() async {
    if (!_current || state.value.busy) return;
    if (!_supported) {
      _show('Restore purchases in Workloop on your iPhone or Android device.');
      return;
    }
    final activity = ++_activity;
    // An explicit restore asks the server again: a previously seen receipt can
    // now be expired or revoked. Ordinary duplicate stream events stay deduped.
    _verifiedTransactions.clear();
    // Restoring is safe while approval is pending, but an empty result or a
    // connection failure cannot cancel that purchase. Only a terminal store
    // event clears the approval state.
    _show(
      'Checking your purchases…',
      busy: true,
      awaitingApproval: state.value.awaitingApproval,
    );
    try {
      await store
          .restorePurchases(applicationUserName: userId)
          .timeout(const Duration(seconds: 25));
      await _pending;
      if (_current) {
        if (state.value.busy) {
          _show(
            state.value.awaitingVerification
                ? 'Your purchase still needs confirmation. Do not buy again; try Restore purchases again or contact support.'
                : state.value.awaitingApproval
                ? 'No additional purchases were found. Your payment is still awaiting approval.'
                : 'No additional purchases were found. Your access is unchanged.',
            awaitingApproval: state.value.awaitingApproval,
          );
        }
      }
    } catch (_) {
      if (activity != _activity) return;
      _show(
        state.value.awaitingVerification
            ? 'Could not restore purchases. Your purchase still needs confirmation; do not buy again. Try restoring again later.'
            : state.value.awaitingApproval
            ? 'Could not restore purchases. Your payment is still awaiting approval; try restoring again later.'
            : 'Could not restore purchases. Please try again.',
        awaitingApproval: state.value.awaitingApproval,
      );
    }
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    if (!_current || !WorkloopPlans.productIds.contains(purchase.productID)) {
      return;
    }
    _activity++;
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _show(
          'Waiting for payment approval. Your access is unchanged.',
          awaitingApproval: true,
        );
        return;
      case PurchaseStatus.canceled:
        _show('Purchase cancelled. Your access is unchanged.');
        return;
      case PurchaseStatus.error:
        _show('The store could not complete the purchase. Please try again.');
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final signedTransaction =
            purchase.verificationData.serverVerificationData;
        final unconfirmedKey =
            '${purchase.productID}:${purchase.purchaseID ?? purchase.transactionDate ?? signedTransaction}';
        _unconfirmedPurchases.add(unconfirmedKey);
        // A store callback is not evidence of entitlement. Empty verification
        // data must remain unfinished so the store can redeliver it later.
        if (signedTransaction.trim().isEmpty) {
          _show(
            'The store did not return a receipt. Use Restore purchases to retry.',
            awaitingVerification: true,
          );
          return;
        }
        final key =
            '${purchase.productID}:${purchase.purchaseID ?? ''}:$signedTransaction';
        // A completed trial may have consumed this Apple account's only
        // introduction. A fresh StoreKit lookup is required before promising
        // it again, including when the signed purchase still needs verifying.
        _show(
          'Confirming your purchase…',
          busy: true,
          awaitingVerification: true,
          trialOffers: const {},
        );
        try {
          if (!_verifiedTransactions.containsKey(key)) {
            final accessToken = client.auth.currentSession?.accessToken;
            if (accessToken == null) throw StateError('Signed out');
            final response = await client.functions
                .invoke(
                  'workloop-subscription',
                  headers: {'Authorization': 'Bearer $accessToken'},
                  body: {
                    'platform': defaultTargetPlatform == TargetPlatform.iOS
                        ? 'apple'
                        : 'google',
                    'signedTransaction': signedTransaction,
                  },
                )
                .timeout(const Duration(seconds: 25));
            if (!_current) return;
            if (response.status != 200 ||
                response.data is! Map ||
                response.data['verified'] != true) {
              throw StateError('Not verified');
            }
            _verifiedTransactions[key] =
                response.data['environment'] == 'Sandbox';
            onVerified();
          }
          if (!_current) return;
          if (purchase.pendingCompletePurchase &&
              !_completedTransactions.contains(key)) {
            try {
              await store
                  .completePurchase(purchase)
                  .timeout(const Duration(seconds: 12));
              if (!_current) return;
              _completedTransactions.add(key);
            } catch (_) {
              _show(
                'Your purchase was verified, but the store could not finish confirming it. Do not buy again; use Restore purchases to retry.',
              );
              return;
            }
          }
          if (!_current) return;
          _unconfirmedPurchases.remove(unconfirmedKey);
          _show(
            _unconfirmedPurchases.isNotEmpty
                ? 'One purchase was verified. Another still needs confirmation; use Restore purchases before buying again.'
                : _verifiedTransactions[key] == true
                ? 'Test purchase verified. No real payment was taken.'
                : 'Purchase verified. Your current plan details are shown here.',
            awaitingVerification: _unconfirmedPurchases.isNotEmpty,
          );
        } catch (_) {
          _show(
            'Your purchase is awaiting verification. Do not buy again; use Restore purchases to retry.',
          );
        }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    state.dispose();
  }
}
