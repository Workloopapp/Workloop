import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/payment_collection_sheet.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/repositories/payments_repository.dart';

void main() {
  test('payment collection follows the requested build gate', () {
    expect(
      WorkloopCapabilities.paymentCollectionEnabled,
      const bool.fromEnvironment(
        'PAYMENT_COLLECTION_ENABLED',
        defaultValue: true,
      ),
    );

    final financeSource = File(
      'lib/features/finance/finance_screen.dart',
    ).readAsStringSync();
    final bookingSource = File(
      'lib/features/appointments/appointment_detail_screen.dart',
    ).readAsStringSync();
    expect(
      financeSource,
      contains('ref.read(paymentCollectionEnabledProvider)'),
    );
    final collectionSource = File(
      'lib/features/finance/payment_collection_sheet.dart',
    ).readAsStringSync();
    expect(
      collectionSource,
      contains('if (!WorkloopCapabilities.paymentCollectionEnabled)'),
    );
    expect(
      RegExp(
        r"if \(paymentCollectionEnabled\) \.\.\.\[\s+SlateButton\(\s+label: 'Take Card Payment'",
      ).allMatches(bookingSource),
      hasLength(2),
    );
  });

  group('Stripe payment security contract', () {
    final migration = File(
      'supabase/migrations/20260804090000_stripe_connect_payments.sql',
    ).readAsStringSync().toLowerCase();
    final retryMigration = File(
      'supabase/migrations/20260805210418_harden_stripe_retries_and_private_rls.sql',
    ).readAsStringSync().toLowerCase();

    test('provider tables are RLS protected and client read-only', () {
      for (final table in const [
        'workspace_payment_accounts',
        'payment_transactions',
        'payment_refunds',
      ]) {
        expect(
          migration,
          contains('alter table public.$table enable row level security'),
        );
      }
      expect(
        migration,
        contains('revoke all on table public.workspace_payment_accounts'),
      );
      expect(migration, contains('to authenticated;'));
      expect(migration, contains('to service_role;'));
    });

    test(
      'webhooks are idempotent and provider income is trigger reconciled',
      () {
        expect(migration, contains('app_private.stripe_webhook_events'));
        expect(migration, contains('stripe_event_id text primary key'));
        expect(migration, contains('sync_invoice_stripe_amount'));
        expect(migration, contains('amount_paid - invoice.stripe_amount_paid'));
        expect(migration, contains('on delete restrict'));
      },
    );

    test('failed webhooks are reclaimable but completed events stay final', () {
      expect(retryMigration, contains("status = 'failed'"));
      expect(retryMigration, contains("interval '5 minutes'"));
      expect(retryMigration, contains('attempt_count'));
      expect(retryMigration, contains("and status = 'processing'"));
      expect(
        retryMigration,
        contains(
          'alter table app_private.stripe_webhook_events enable row level security',
        ),
      );
    });

    test(
      'payment retry persistence requires a supplied key and unique refund identity',
      () {
        final repository = File(
          'lib/shared/repositories/stripe_payments_repository.dart',
        ).readAsStringSync();
        final sheet = File(
          'lib/features/finance/payment_collection_sheet.dart',
        ).readAsStringSync();
        expect(repository, contains('required String idempotencyKey'));
        // Stable link/terminal command behavior is covered by the live-state
        // widget tests, including changed balances and lost responses.
        expect(sheet, contains('_refundIdempotencyKeys.putIfAbsent'));
        expect(retryMigration, contains('idempotency_key text'));
        expect(
          retryMigration,
          contains('payment_refunds_workspace_idempotency_idx'),
        );
      },
    );

    test('contactless payments offer a Stripe email receipt', () {
      final repository = File(
        'lib/shared/repositories/stripe_payments_repository.dart',
      ).readAsStringSync();
      final sheet = File(
        'lib/features/finance/payment_collection_sheet.dart',
      ).readAsStringSync();
      final function = File(
        'supabase/functions/stripe-payments/index.ts',
      ).readAsStringSync();

      expect(repository, contains("'receiptEmail': ?receiptEmail"));
      expect(sheet, contains("'Email receipt'"));
      expect(sheet, contains("label: 'Send payment link'"));
      expect(function, contains('["receipt_email", receiptEmail]'));
      expect(function, contains('metadata: receiptEmail'));
    });

    test('beta payments, platform fee, and live mode default off', () {
      final environment = File(
        'supabase/functions/.env.example',
      ).readAsStringSync();
      expect(environment, contains('WORKLOOP_PAYMENTS_BETA_ENABLED=false'));
      expect(environment, contains('WORKLOOP_PLATFORM_FEE_BPS=0'));
      expect(environment, contains('WORKLOOP_PLATFORM_FEE_ENABLED=false'));
      expect(environment, contains('STRIPE_LIVE_MODE_ALLOWED=false'));
    });

    test('connected accounts use the configured Stripe v2 merchant model', () {
      final function = File(
        'supabase/functions/stripe-payments/index.ts',
      ).readAsStringSync();

      expect(function, contains('"/v2/core/accounts"'));
      expect(function, contains('dashboard: "full"'));
      expect(function, contains('merchant: {'));
      expect(function, contains('fees_collector: "stripe"'));
      expect(function, contains('losses_collector: "stripe"'));
      expect(function, contains('"/v2/core/account_links"'));
      expect(function, contains('configurations: ["merchant"]'));
      expect(function, isNot(contains('["type", "express"]')));
      expect(function, isNot(contains('capabilities[transfers][requested]')));
    });
  });

  test('provider-collected income survives a manual unpaid edit', () {
    final payment = Payment.fromMap({
      'id': 'payment-1',
      'workspace_id': 'workspace-1',
      'status': 'paid',
      'issue_date': '2026-08-04',
      'total': 100,
      'amount_paid': 40,
      'stripe_amount_paid': 40,
    });

    final update = resolvePaymentUpdateState(
      existingPayment: payment,
      amount: 100,
      selectedStatus: 'sent',
      selectedDate: DateTime(2026, 8, 4),
      paymentStateChanged: true,
    );

    expect(payment.stripeAmountPaid, 40);
    expect(update.status, 'sent');
    expect(update.amountPaid, 40);
    expect(update.incomeRecordedAt, isNotNull);
  });

  test('payment total cannot be edited below provider-collected amount', () {
    final payment = Payment(
      id: 'payment-1',
      workspaceId: 'workspace-1',
      number: 'PAY-001',
      status: 'paid',
      issueDate: DateTime(2026, 8, 4),
      total: 100,
      amountPaid: 75,
      stripeAmountPaid: 75,
    );

    expect(
      () => resolvePaymentUpdateState(
        existingPayment: payment,
        amount: 50,
        selectedStatus: 'paid',
        selectedDate: DateTime(2026, 8, 4),
        paymentStateChanged: false,
      ),
      throwsArgumentError,
    );
  });

  test('payment errors never expose Dart StateError prefixes', () {
    expect(
      friendlyPaymentError(
        StateError(
          'Tap to Pay is not enabled for this Workloop build yet. '
          'You can still copy a secure payment link.',
        ),
      ),
      'Tap to Pay is not enabled for this Workloop build yet. '
      'You can still copy a secure payment link.',
    );
  });

  test('payment function failures never expose backend exception details', () {
    expect(
      friendlyPaymentError(
        const FunctionException(
          status: 503,
          details: {
            'error': 'Payment setup is being finalised.',
            'code': 'platform_configuration_required',
          },
        ),
      ),
      'Payment setup is being finalised. Please try again shortly.',
    );
    expect(
      friendlyPaymentError(
        const FunctionException(
          status: 400,
          details: {
            'error':
                'Please review responsibilities at '
                'https://dashboard.stripe.com/settings/connect/platform-profile',
          },
          reasonPhrase: 'Bad Request',
        ),
      ),
      'Payments are temporarily unavailable. Please try again.',
    );
  });

  test('contactless availability explains the real platform gate', () {
    expect(
      contactlessUnavailableMessage(TargetPlatform.iOS),
      WorkloopCapabilities.tapToPayEnabled
          ? 'Contactless payments are not available on this phone. Use a card payment link.'
          : 'Tap to Pay is not enabled in this version of Workloop. Use a card payment link.',
    );
    expect(
      contactlessUnavailableMessage(TargetPlatform.android),
      WorkloopCapabilities.tapToPayEnabled
          ? 'Contactless payments are not available on this phone. Use a card payment link.'
          : 'Tap to Pay is not enabled in this version of Workloop. Use a card payment link.',
    );
  });

  test(
    'receipt email validation permits decline and rejects malformed input',
    () {
      expect(isValidReceiptEmail(''), isTrue);
      expect(isValidReceiptEmail('client@example.com'), isTrue);
      expect(isValidReceiptEmail('client@'), isFalse);
      expect(isValidReceiptEmail('client example.com'), isFalse);
    },
  );

  testWidgets('payment setup entry sets honest expectations', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PaymentSetupCard(onTap: () {})),
      ),
    );

    expect(find.text('Card & contactless payments'), findsOneWidget);
    expect(
      find.text(
        'Take card payments by link, check Tap to Pay, and manage payouts.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Tap to Pay'), findsOneWidget);
  });

  testWidgets(
    'disabled payment setup explains availability without a repository',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.tap(find.text('Card & contactless payments'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Card payment collection is not enabled'),
        findsOneWidget,
      );
      expect(find.text('Set up secure payments'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: WorkloopCapabilities.paymentCollectionEnabled,
  );

  test('ready flow leads users to money they can collect', () {
    final source = File(
      'lib/features/finance/payment_collection_sheet.dart',
    ).readAsStringSync();

    expect(source, contains("label: 'View payments to collect'"));
    expect(source, contains("label: 'Send payment link'"));
    expect(source, contains('Copy payment link'));
    expect(source, contains("status: 'Unavailable'"));
    expect(source, contains('Test mode — no real money will move.'));
    expect(source, contains('SlateErrorState(message: _error!)'));
  });
}
