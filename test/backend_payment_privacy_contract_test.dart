import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/repositories/privacy_repository.dart';
import 'package:workloop/shared/repositories/stripe_payments_repository.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260812120000_enforce_privileged_mfa_and_stripe_retention.sql';

  test('payment readiness requires details, charges, and payouts', () {
    StripeAccountStatus status({
      bool details = true,
      bool charges = true,
      bool payouts = true,
      String onboarding = 'ready',
    }) => StripeAccountStatus(
      connected: true,
      detailsSubmitted: details,
      chargesEnabled: charges,
      payoutsEnabled: payouts,
      onboardingStatus: onboarding,
      mode: 'test',
    );

    expect(status().ready, isTrue);
    expect(status(details: false).ready, isFalse);
    expect(status(charges: false).ready, isFalse);
    expect(status(payouts: false).ready, isFalse);
    expect(status(onboarding: 'pending').ready, isFalse);
  });

  test('workspace privacy export includes the provider payment ledger', () {
    expect(
      workspacePrivacyExportTables,
      containsAll(const {
        'workspace_payment_accounts',
        'payment_transactions',
        'payment_refunds',
      }),
    );

    final source = File(
      'lib/shared/repositories/privacy_repository.dart',
    ).readAsStringSync();
    expect(
      source,
      contains("'workspace_payment_account': await _maybeSingle("),
    );
    expect(source, contains("'payment_transactions': await _list("));
    expect(source, contains("'payment_refunds': await _list("));
  });

  test('privileged RPCs use the opt-in MFA policy at their boundary', () {
    final migration = File(migrationPath).readAsStringSync().toLowerCase();
    for (final function in const [
      'complete_onboarding',
      'create_task_workflow',
      'create_booking_workflow',
      'complete_booking_workflow',
    ]) {
      final start = migration.indexOf(
        'create or replace function public.$function(',
      );
      expect(
        start,
        greaterThanOrEqualTo(0),
        reason: '$function wrapper missing',
      );
      final bodyEnd = migration.indexOf(r'$$;', start);
      expect(
        migration.substring(start, bodyEnd),
        contains('app_private.current_user_meets_mfa_policy()'),
        reason: '$function must reject a verified-MFA AAL1 request',
      );
    }

    expect(
      migration,
      contains(
        'revoke execute on function app_private.create_task_workflow(jsonb)',
      ),
    );
  });

  test('authenticated service-role edges check the same MFA RPC', () {
    for (final path in const [
      'supabase/functions/stripe-payments/index.ts',
      'supabase/functions/request-account-deletion/index.ts',
    ]) {
      final source = File(path).readAsStringSync();
      final mfaCall = RegExp(
        r'const\s+\{\s*data:\s*(\w+),\s*error:\s*(\w+)\s*\}\s*'
        r'=\s*await\s+userClient\.rpc\(\s*"current_user_meets_mfa_policy"',
      ).firstMatch(source);
      expect(mfaCall, isNotNull, reason: '$path must check the caller MFA RPC');
      final result = mfaCall!.group(1)!;
      final error = mfaCall.group(2)!;
      expect(source, contains('if ($error)'));
      expect(source, contains('if ($result !== true)'));
      expect(source, contains('code: "mfa_required"'));
    }
  });

  test('Stripe actions are protected by a default-off server beta gate', () {
    final function = File(
      'supabase/functions/stripe-payments/index.ts',
    ).readAsStringSync();
    final gate = File(
      'supabase/functions/_shared/payments_beta_gate.ts',
    ).readAsStringSync();
    final environment = File(
      'supabase/functions/.env.example',
    ).readAsStringSync();

    expect(function, contains('if (!paymentsBetaEnabled())'));
    expect(function, contains('code: "payments_beta_disabled"'));
    expect(gate, contains('=== "true"'));
    expect(environment, contains('WORKLOOP_PAYMENTS_BETA_ENABLED=false'));
  });

  test('webhook PII has expiry, unknown-account, and deletion scrubbing', () {
    final migration = File(migrationPath).readAsStringSync().toLowerCase();
    expect(migration, contains("interval '30 days'"));
    expect(migration, contains('payload_expires_at'));
    expect(migration, contains('sanitized_at'));
    expect(migration, contains('scrub_expired_stripe_webhook_payloads'));
    expect(migration, contains('workloop-scrub-stripe-webhook-payloads'));
    expect(migration, contains("'17 * * * *'"));
    expect(
      migration,
      contains('scrub_stripe_webhooks_before_workspace_delete'),
    );
    expect(
      migration,
      contains(
        "case when v_workspace_id is null then '{}'::jsonb else p_payload end",
      ),
    );
  });

  test('account deletion closes Accounts v2 before local deletion', () {
    final completion = File(
      'supabase/functions/complete-account-deletion/index.ts',
    ).readAsStringSync();
    final offboarding = File(
      'supabase/functions/_shared/stripe_account_offboarding.ts',
    ).readAsStringSync();

    expect(completion, contains('await closeWorkloopStripeAccount('));
    expect(
      completion.indexOf('await closeWorkloopStripeAccount('),
      lessThan(completion.indexOf('.from("workspaces")')),
    );
    expect(offboarding, contains('/v2/core/accounts/'));
    expect(offboarding, contains('/close`'));
    expect(offboarding, contains('applied_configurations'));
    expect(offboarding, contains('account.closed === true'));
  });
}
