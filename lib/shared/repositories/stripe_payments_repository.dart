import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';

final stripePaymentsRepositoryProvider = Provider<StripePaymentsRepository>((
  ref,
) {
  return StripePaymentsRepository(ref.watch(supabaseClientProvider));
});

class StripeAccountStatus {
  final bool connected;
  final bool detailsSubmitted;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final String onboardingStatus;
  final String mode;
  final String? terminalLocationId;
  final List<String> requirementsDue;

  const StripeAccountStatus({
    required this.connected,
    required this.detailsSubmitted,
    required this.chargesEnabled,
    required this.payoutsEnabled,
    required this.onboardingStatus,
    required this.mode,
    this.terminalLocationId,
    this.requirementsDue = const [],
  });

  bool get ready =>
      connected &&
      detailsSubmitted &&
      chargesEnabled &&
      payoutsEnabled &&
      onboardingStatus == 'ready';

  factory StripeAccountStatus.fromMap(Map<String, dynamic> map) {
    return StripeAccountStatus(
      connected: map['connected'] == true,
      detailsSubmitted: map['detailsSubmitted'] == true,
      chargesEnabled: map['chargesEnabled'] == true,
      payoutsEnabled: map['payoutsEnabled'] == true,
      onboardingStatus: map['onboardingStatus'] as String? ?? 'pending',
      mode: map['mode'] as String? ?? 'test',
      terminalLocationId: map['terminalLocationId'] as String?,
      requirementsDue:
          (map['requirementsDue'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
    );
  }
}

class TerminalPaymentRequest {
  final String transactionId;
  final String clientSecret;
  final String locationId;

  const TerminalPaymentRequest({
    required this.transactionId,
    required this.clientSecret,
    required this.locationId,
  });
}

class PaymentLinkResult {
  final String transactionId;
  final Uri url;

  const PaymentLinkResult({required this.transactionId, required this.url});
}

class StripePaymentsRepository {
  final SupabaseClient _client;
  const StripePaymentsRepository(this._client);

  Future<StripeAccountStatus> accountStatus(String workspaceId) async {
    final data = await _invoke('accountStatus', workspaceId);
    return StripeAccountStatus.fromMap(data);
  }

  Future<Uri> createOnboardingLink(String workspaceId) async {
    final data = await _invoke('createOnboardingLink', workspaceId);
    return _requiredUri(data['url']);
  }

  Future<Uri> createDashboardLink(String workspaceId) async {
    final data = await _invoke('createDashboardLink', workspaceId);
    return _requiredUri(data['url']);
  }

  Future<String> createConnectionToken(String workspaceId) async {
    final data = await _invoke('createConnectionToken', workspaceId);
    final secret = data['secret'] as String? ?? '';
    if (!secret.startsWith('pst_')) {
      throw const FormatException('Payment reader token was missing.');
    }
    return secret;
  }

  Future<TerminalPaymentRequest> createTerminalPayment({
    required String workspaceId,
    required String invoiceId,
    required String idempotencyKey,
    String? receiptEmail,
    int? amountMinor,
  }) async {
    final data = await _invoke(
      'createTerminalPaymentIntent',
      workspaceId,
      body: {
        'invoiceId': invoiceId,
        'amountMinor': ?amountMinor,
        'receiptEmail': ?receiptEmail,
        'idempotencyKey': idempotencyKey,
      },
    );
    final transaction = _map(data['transaction']);
    final transactionId = transaction['id'] as String? ?? '';
    final secret = data['clientSecret'] as String? ?? '';
    final locationId = data['locationId'] as String? ?? '';
    if (transactionId.isEmpty ||
        secret.isEmpty ||
        !locationId.startsWith('tml_')) {
      throw const FormatException('Payment reader response was incomplete.');
    }
    return TerminalPaymentRequest(
      transactionId: transactionId,
      clientSecret: secret,
      locationId: locationId,
    );
  }

  Future<PaymentLinkResult> createPaymentLink({
    required String workspaceId,
    required String invoiceId,
    required String idempotencyKey,
    int? amountMinor,
  }) async {
    final data = await _invoke(
      'createPaymentLink',
      workspaceId,
      body: {
        'invoiceId': invoiceId,
        'amountMinor': ?amountMinor,
        'idempotencyKey': idempotencyKey,
      },
    );
    final transaction = _map(data['transaction']);
    return PaymentLinkResult(
      transactionId: transaction['id'] as String? ?? '',
      url: _requiredUri(data['url']),
    );
  }

  Future<Map<String, dynamic>> paymentRequestEmail(
    String transactionId, {
    required bool send,
    String? expectedEmail,
  }) async {
    return _map(
      await _client.rpc(
        'queue_payment_request_email',
        params: {
          'p_transaction_id': transactionId,
          'p_send': send,
          'p_expected_email': expectedEmail,
        },
      ),
    );
  }

  Future<void> refund({
    required String workspaceId,
    required String transactionId,
    required int amountMinor,
    required String idempotencyKey,
  }) async {
    await _invoke(
      'refund',
      workspaceId,
      body: {
        'transactionId': transactionId,
        'amountMinor': amountMinor,
        'idempotencyKey': idempotencyKey,
      },
    );
  }

  Future<List<Map<String, dynamic>>> transactionsForInvoice(
    String workspaceId,
    String invoiceId,
  ) async {
    final rows = await _client
        .from('payment_transactions')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('invoice_id', invoiceId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> _invoke(
    String action,
    String workspaceId, {
    Map<String, dynamic> body = const {},
  }) async {
    final response = await _client.functions.invoke(
      'stripe-payments',
      body: {'action': action, 'workspaceId': workspaceId, ...body},
    );
    return _map(response.data);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Unexpected payment service response.');
  }

  Uri _requiredUri(dynamic value) {
    final uri = Uri.tryParse(value as String? ?? '');
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException('Payment link was invalid.');
    }
    return uri;
  }
}
