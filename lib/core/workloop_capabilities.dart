import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class WorkloopCapabilities {
  // Native acceptance requires separate entitlement and real-device approval.
  static const tapToPayEnabled = bool.fromEnvironment(
    'TAP_TO_PAY_ENABLED',
    defaultValue: false,
  );

  // Hosted card links are part of the app; Stripe still enforces merchant
  // readiness and the server payment gate. Releases can explicitly disable it.
  static const paymentCollectionEnabled = bool.fromEnvironment(
    'PAYMENT_COLLECTION_ENABLED',
    defaultValue: true,
  );
}

final paymentCollectionEnabledProvider = Provider<bool>(
  (ref) => WorkloopCapabilities.paymentCollectionEnabled,
);
