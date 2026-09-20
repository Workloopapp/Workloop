import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/finance/add_payment_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/business_clock_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/payments_repository.dart';

class _Payments implements PaymentsRepository {
  final ids = <String?>[];
  @override
  Future<String> create({
    required String workspaceId,
    required double amount,
    required String status,
    required DateTime date,
    DateTime? dueDate,
    String? contactId,
    String? appointmentId,
    String? notes,
    String? paymentId,
  }) async {
    ids.add(paymentId);
    throw StateError('Lost response');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('retrying income save uses the same editor-held identity', (
    tester,
  ) async {
    final repo = _Payments();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentsRepositoryProvider.overrideWithValue(repo),
          clientsProvider.overrideWith((ref) async => []),
          workspaceIdProvider.overrideWith((ref) async => 'workspace'),
        ],
        child: const MaterialApp(home: AddPaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pump();
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    expect(repo.ids, hasLength(2));
    expect(repo.ids.first, isNotNull);
    expect(repo.ids.last, repo.ids.first);
  });

  testWidgets('future received date stays editable and cannot save', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 12);
    final repo = _Payments();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessNowProvider.overrideWithValue(now),
          paymentsRepositoryProvider.overrideWithValue(repo),
          clientsProvider.overrideWith((ref) async => []),
          workspaceIdProvider.overrideWith((ref) async => 'workspace'),
        ],
        child: MaterialApp(
          home: AddPaymentScreen(
            payment: Payment(
              id: 'future',
              workspaceId: 'workspace',
              number: 'PAY-1',
              status: 'paid',
              issueDate: DateTime(2026, 9, 13),
              total: 100,
              amountPaid: 100,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Received income must be dated today or earlier. Use To collect for expected income.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AddPaymentScreen), findsOneWidget);
    expect(repo.ids, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
