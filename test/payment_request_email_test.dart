import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/payment_collection_sheet.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/stripe_payments_repository.dart';

void main() {
  test(
    'payment email errors explain the corrective action without database details',
    () {
      expect(
        friendlyPaymentError(
          const PostgrestException(
            message: 'Add a valid customer email first',
            code: 'P0001',
          ),
        ),
        'Add a valid customer email first',
      );
      expect(
        friendlyPaymentError(
          const PostgrestException(
            message: 'private relation missing',
            code: '42P01',
          ),
        ),
        'Payments are temporarily unavailable. Please try again.',
      );
    },
  );
  for (final approve in [false, true]) {
    testWidgets(
      'payment email reviews recipient and sends only after approval: $approve',
      (tester) async {
        final repository = _Repository();
        final payment = Payment(
          id: 'invoice-1',
          workspaceId: 'workspace-1',
          number: 'PAY-001',
          status: 'sent',
          issueDate: DateTime(2026, 9, 4),
          total: 45,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              stripePaymentsRepositoryProvider.overrideWithValue(repository),
              paymentCollectionEnabledProvider.overrideWithValue(true),
              workspaceIdProvider.overrideWith((_) async => 'workspace-1'),
              invoicesProvider.overrideWith((_) async => [payment]),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showPaymentCollectionSheet(
                      context: context,
                      payment: payment,
                    ),
                    child: const Text('Collect'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Collect'));
        await tester.pumpAndSettle();
        final button = find.text('Email payment request');
        await tester.scrollUntilVisible(
          button,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('£45 to customer@example.test'),
          findsOneWidget,
        );
        expect(repository.sends, 0);
        await tester.tap(find.text(approve ? 'Send email' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(repository.sends, approve ? 1 : 0);
        expect(
          repository.expectedEmail,
          approve ? 'customer@example.test' : null,
        );
        expect(tester.takeException(), isNull);
      },
      skip: !WorkloopCapabilities.paymentCollectionEnabled,
    );
  }
}

class _Repository implements StripePaymentsRepository {
  int sends = 0;
  String? expectedEmail;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<StripeAccountStatus> accountStatus(String workspaceId) async =>
      const StripeAccountStatus(
        connected: true,
        detailsSubmitted: true,
        chargesEnabled: true,
        payoutsEnabled: true,
        onboardingStatus: 'ready',
        mode: 'test',
      );
  @override
  Future<List<Map<String, dynamic>>> transactionsForInvoice(
    String workspaceId,
    String invoiceId,
  ) async => [];
  @override
  Future<PaymentLinkResult> createPaymentLink({
    required String workspaceId,
    required String invoiceId,
    int? amountMinor,
    required String idempotencyKey,
  }) async => PaymentLinkResult(
    transactionId: 'transaction-1',
    url: Uri.parse('https://checkout.stripe.com/c/pay/example'),
  );
  @override
  Future<Map<String, dynamic>> paymentRequestEmail(
    String transactionId, {
    required bool send,
    String? expectedEmail,
  }) async {
    if (send) {
      sends++;
      this.expectedEmail = expectedEmail;
    }
    return {
      'email': 'customer@example.test',
      'amount_minor': 4500,
      'status': send ? 'pending' : 'preview',
    };
  }
}
