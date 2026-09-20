import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/finance_screen.dart';
import 'package:workloop/features/finance/widgets/payment_cards.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/business_documents_provider.dart';
import 'package:workloop/shared/providers/business_document_defaults_provider.dart';
import 'package:workloop/shared/models/business_document_defaults.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';

final _now = DateTime(2026, 9, 16, 12);

Future<void> _showMoney(
  WidgetTester tester, {
  List<Payment> payments = const [],
  List<Expense> expenses = const [],
  bool collectionEnabled = true,
  Future<Map<String, dynamic>?> Function()? settings,
  String? initialPaymentId,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessNowProvider.overrideWithValue(_now),
        workspaceIdProvider.overrideWith((ref) async => 'workspace-one'),
        invoicesProvider.overrideWith((ref) async => payments),
        expensesProvider.overrideWith((ref) async => expenses),
        clientsProvider.overrideWith((ref) async => const []),
        businessDocumentsProvider.overrideWith((ref) async => const []),
        businessDocumentDefaultsProvider.overrideWith(
          (ref) async => const BusinessDocumentDefaults(
            business: {'name': 'Test business'},
          ),
        ),
        paymentCollectionEnabledProvider.overrideWithValue(collectionEnabled),
        workspaceSettingsProvider.overrideWith(
          (ref) =>
              settings?.call() ??
              Future.value(const {
                'workspace_id': 'workspace-one',
                'revenue_target': 4345,
              }),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FinanceScreen(
          referenceDate: _now,
          initialPaymentId: initialPaymentId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final history = find.byKey(const ValueKey('money-history-toggle'));
  await tester.ensureVisible(history);
  await tester.pumpAndSettle();
  await tester.tap(history);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Money renders deposit and balance rows without duplicate keys', (
    tester,
  ) async {
    await _showMoney(
      tester,
      collectionEnabled: false,
      payments: [
        Payment(
          id: 'invoice-one',
          workspaceId: 'workspace-one',
          number: 'INV-0001',
          status: 'paid',
          issueDate: _now,
          sourceDocumentId: 'document-one',
          total: 100,
          amountPaid: 100,
          depositAmount: 25,
          receipts: [
            PaymentReceipt(
              id: 'deposit',
              amount: 25,
              receivedAt: _now.subtract(const Duration(hours: 2)),
            ),
            PaymentReceipt(
              id: 'balance',
              amount: 75,
              receivedAt: _now.subtract(const Duration(hours: 1)),
            ),
          ],
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('income-receipt:deposit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('income-receipt:balance')),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<PaymentCard>(find.byType(PaymentCard))
          .map((card) => card.receivedEntryAmount),
      containsAll([25.0, 75.0]),
    );
  });
}
