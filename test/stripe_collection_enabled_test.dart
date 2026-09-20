import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/payment_collection_sheet.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/stripe_payments_repository.dart';

void main() {
  testWidgets(
    'contactless availability is visible before Stripe setup',
    (tester) async {
      final repository = _Repository(false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stripePaymentsRepositoryProvider.overrideWithValue(repository),
            workspaceIdProvider.overrideWith((_) async => 'workspace-1'),
            invoicesProvider.overrideWith((_) async => []),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => PaymentSetupCard(
                  onTap: () => showPaymentSetupSheet(
                    context: context,
                    workspaceId: 'workspace-1',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Card & contactless payments'));
      await tester.pumpAndSettle();
      expect(find.text('Contactless payments'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Continue Stripe setup'), findsOneWidget);
      expect(find.text('Take contactless payment'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip:
        !WorkloopCapabilities.paymentCollectionEnabled ||
        WorkloopCapabilities.tapToPayEnabled,
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final chargesEnabled in [true, false]) {
      testWidgets(
        'part-paid receipts and refunds stay accessible (charges: $chargesEnabled, platform: $platform)',
        (tester) async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('com.ismaeel.workloop/payments'),
            (call) async => {'supported': true},
          );
          final repository = _Repository(chargesEnabled);
          final payment = Payment(
            id: 'invoice-1',
            workspaceId: 'workspace-1',
            number: 'PAY-001',
            status: 'sent',
            issueDate: DateTime(2026, 9, 4),
            total: 100,
            amountPaid: 30,
            stripeAmountPaid: 30,
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                stripePaymentsRepositoryProvider.overrideWithValue(repository),
                workspaceIdProvider.overrideWith((_) async => 'workspace-1'),
                invoicesProvider.overrideWith((_) async => [payment]),
              ],
              child: MaterialApp(
                theme: AppTheme.light.copyWith(platform: platform),
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
          final refund = find.text('Refund card payment');
          await tester.scrollUntilVisible(
            refund,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(refund, findsOneWidget);
          expect(find.text('Take contactless payment'), findsNothing);
          expect(find.text('View Stripe receipt'), findsOneWidget);
          if (chargesEnabled) {
            expect(find.text('Send payment link'), findsOneWidget);
          } else {
            expect(find.text('Send payment link'), findsNothing);
          }
          await tester.tap(refund);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'NaN');
          await tester.tap(find.text('Refund'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
        skip: !WorkloopCapabilities.paymentCollectionEnabled,
      );
    }
  }
}

class _Repository implements StripePaymentsRepository {
  final bool enabled;
  _Repository(this.enabled);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<StripeAccountStatus> accountStatus(String workspaceId) async =>
      StripeAccountStatus(
        connected: true,
        detailsSubmitted: true,
        chargesEnabled: enabled,
        payoutsEnabled: enabled,
        onboardingStatus: enabled ? 'ready' : 'restricted',
        mode: 'test',
      );
  @override
  Future<List<Map<String, dynamic>>> transactionsForInvoice(
    String workspaceId,
    String invoiceId,
  ) async => [
    {
      'id': 'transaction-1',
      'status': 'succeeded',
      'amount_minor': 3000,
      'amount_refunded_minor': 0,
      'receipt_url': 'https://pay.stripe.com/receipts/example',
    },
  ];
}
