import 'package:flutter/services.dart';

import '../../core/workloop_capabilities.dart';

typedef ConnectionTokenLoader = Future<String> Function();

class TapToPayAvailability {
  final bool supported;
  final String? reason;

  const TapToPayAvailability({required this.supported, this.reason});

  factory TapToPayAvailability.fromMap(Map<Object?, Object?> map) {
    return TapToPayAvailability(
      supported: map['supported'] == true,
      reason: map['reason'] as String?,
    );
  }
}

class TapToPayResult {
  final String paymentIntentId;
  final String status;

  const TapToPayResult({required this.paymentIntentId, required this.status});
}

class TapToPayService {
  static const MethodChannel _channel = MethodChannel(
    'com.ismaeel.workloop/payments',
  );

  ConnectionTokenLoader? _tokenLoader;

  TapToPayService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'fetchConnectionToken' || _tokenLoader == null) {
        throw PlatformException(
          code: 'token_unavailable',
          message: 'The payment reader session is no longer active.',
        );
      }
      return _tokenLoader!();
    });
  }

  Future<TapToPayAvailability> availability() async {
    if (!WorkloopCapabilities.paymentCollectionEnabled ||
        !WorkloopCapabilities.tapToPayEnabled) {
      return const TapToPayAvailability(
        supported: false,
        reason:
            'Use a secure payment link. Contactless is not enabled for this build.',
      );
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'availability',
      );
      return TapToPayAvailability.fromMap(result ?? const {});
    } on MissingPluginException {
      return const TapToPayAvailability(
        supported: false,
        reason: 'Tap to Pay is not available on this device.',
      );
    }
  }

  Future<TapToPayResult> collect({
    required String clientSecret,
    required String locationId,
    required ConnectionTokenLoader connectionTokenLoader,
  }) async {
    if (!WorkloopCapabilities.paymentCollectionEnabled ||
        !WorkloopCapabilities.tapToPayEnabled) {
      throw PlatformException(
        code: 'tap_to_pay_disabled',
        message:
            'Use a secure payment link. Contactless is not enabled for this build.',
      );
    }
    _tokenLoader = connectionTokenLoader;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'collectPayment',
        {'clientSecret': clientSecret, 'locationId': locationId},
      );
      final intentId = result?['paymentIntentId'] as String? ?? '';
      final status = result?['status'] as String? ?? '';
      if (!intentId.startsWith('pi_') || status.isEmpty) {
        throw const FormatException(
          'The reader returned an incomplete result.',
        );
      }
      return TapToPayResult(paymentIntentId: intentId, status: status);
    } finally {
      _tokenLoader = null;
    }
  }
}

final tapToPayService = TapToPayService();
