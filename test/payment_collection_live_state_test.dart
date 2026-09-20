import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/payment_collection_sheet.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/stripe_payments_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

Payment _payment(double paid) => Payment(
  id: 'invoice',
  workspaceId: 'workspace',
  number: 'INV-1',
  status: 'sent',
  issueDate: DateTime(2026, 9, 8),
  total: 100,
  amountPaid: paid,
  depositAmount: 30,
  sourceDocumentId: 'document',
  clientName: 'Sam',
);

class _Stripe implements StripePaymentsRepository {
  final requests = <({String workspace, int? amount, String key})>[];
  bool loseFirstResponse = false;
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
  }) async {
    requests.add((
      workspace: workspaceId,
      amount: amountMinor,
      key: idempotencyKey,
    ));
    if (loseFirstResponse && requests.length == 1) {
      throw StateError('Response lost after creating the link');
    }
    return PaymentLinkResult(
      transactionId: 'transaction',
      url: Uri.parse('https://example.invalid/payment'),
    );
  }

  @override
  Future<Map<String, dynamic>> paymentRequestEmail(
    String transactionId, {
    required bool send,
    String? expectedEmail,
  }) async {
    if (send) throw StateError('This test must never send email');
    return {
      'email': 'fictional@example.invalid',
      'amount_minor': requests.last.amount ?? 10000,
      'status': 'preview',
    };
  }
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  _Stripe repository, {
  required Future<List<Payment>> Function() payments,
  required Future<String> Function() workspace,
}) async {
  final container = ProviderContainer(
    overrides: [
      stripePaymentsRepositoryProvider.overrideWithValue(repository),
      workspaceIdProvider.overrideWith((_) => workspace()),
      invoicesProvider.overrideWith((_) => payments()),
      paymentCollectionEnabledProvider.overrideWithValue(true),
    ],
  );
  addTearDown(container.dispose);
  await container.read(workspaceIdProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPaymentCollectionSheet(
                context: context,
                payment: _payment(0),
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
  expect(find.text('Get paid'), findsOneWidget);
  return container;
}

Future<void> _emailPreview(WidgetTester tester) async {
  final button = find.widgetWithText(
    WorkloopTextButton,
    'Email payment request',
  );
  await tester.scrollUntilVisible(
    button,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'changed balance needs a fresh review before creating a request',
    (tester) async {
      final repository = _Stripe();
      var reads = 0;
      await _show(
        tester,
        repository,
        payments: () async => [_payment(reads++ == 0 ? 0 : 30)],
        workspace: () async => 'workspace',
      );
      await _emailPreview(tester);
      expect(repository.requests, isEmpty);
      expect(
        find.text(
          'The balance changed. Check the updated amount, then try again.',
        ),
        findsOneWidget,
      );
      await _emailPreview(tester);
      expect(repository.requests.single.amount, 7000);
      expect(
        find.textContaining('£70 to fictional@example.invalid'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: !WorkloopCapabilities.paymentCollectionEnabled,
  );

  testWidgets(
    'new collection refreshes a deposit already paid on another device',
    (tester) async {
      final repository = _Stripe();
      var reads = 0;
      await _show(
        tester,
        repository,
        payments: () async {
          reads++;
          return [_payment(30)];
        },
        workspace: () async => 'workspace',
      );
      await _emailPreview(tester);
      expect(reads, greaterThanOrEqualTo(2));
      expect(repository.requests.single.amount, 7000);
      expect(
        find.textContaining('£70 to fictional@example.invalid'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: !WorkloopCapabilities.paymentCollectionEnabled,
  );

  testWidgets(
    'lost link response freezes amount and key when live balance changes',
    (tester) async {
      final repository = _Stripe()..loseFirstResponse = true;
      var current = _payment(0);
      final container = await _show(
        tester,
        repository,
        payments: () async => [current],
        workspace: () async => 'workspace',
      );
      await _emailPreview(tester);
      expect(repository.requests.single.amount, 3000);
      current = _payment(50);
      container.invalidate(invoicesProvider);
      await tester.pumpAndSettle();
      await _emailPreview(tester);
      expect(repository.requests.length, 2);
      expect(repository.requests.last, repository.requests.first);
      expect(
        find.textContaining('£30 to fictional@example.invalid'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: !WorkloopCapabilities.paymentCollectionEnabled,
  );

  testWidgets(
    'workspace switch hides old payment and blocks a retained action callback',
    (tester) async {
      final repository = _Stripe();
      var currentWorkspace = 'workspace';
      final container = await _show(
        tester,
        repository,
        payments: () async => [_payment(0)],
        workspace: () async => currentWorkspace,
      );
      final button = find.widgetWithText(
        WorkloopTextButton,
        'Email payment request',
      );
      await tester.scrollUntilVisible(
        button,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final oldAction = tester.widget<WorkloopTextButton>(button).onPressed!;
      currentWorkspace = 'other';
      container.invalidate(workspaceIdProvider);
      await tester.pumpAndSettle();
      expect(find.text('Email payment request'), findsNothing);
      oldAction();
      await tester.pumpAndSettle();
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
    skip: !WorkloopCapabilities.paymentCollectionEnabled,
  );
}
