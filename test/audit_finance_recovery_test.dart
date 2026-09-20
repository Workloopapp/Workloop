import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/repositories/expenses_repository.dart';
import 'package:workloop/shared/repositories/payments_repository.dart';

void main() {
  for (final code in ['42501', 'XX000', '42P01']) {
    test('expense $code failure remains an error in list and feed', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'fake',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': code,
              'message': 'permission denied for table expenses',
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      final repo = ExpensesRepository(client);
      await expectLater(
        repo.list('workspace-one'),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        repo.listForBusinessFeed('workspace-one', from: DateTime(2026)),
        throwsA(isA<PostgrestException>()),
      );
    });
  }
  for (final code in ['42P01', 'PGRST205']) {
    test(
      'only exact missing expense schema uses legacy empty fallback $code',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'fake',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'code': code,
                'message': code == '42P01'
                    ? 'relation "public.expenses" does not exist'
                    : "Could not find the table 'public.expenses' in the schema cache",
              }),
              404,
              request: request,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        addTearDown(client.dispose);
        expect(await ExpensesRepository(client).list('workspace-one'), isEmpty);
      },
    );
  }
  for (final income in [false, true]) {
    test(
      '${income ? "income" : "expense"} retry saves corrections under the same committed identity',
      () async {
        final stored = <String, Map<String, dynamic>>{};
        var writes = 0;
        final client = SupabaseClient(
          'https://example.supabase.co',
          'fake',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            if (request.method == 'POST') {
              writes++;
              final row = jsonDecode(request.body) as Map<String, dynamic>;
              expect(
                request.headers['Prefer'],
                contains('resolution=merge-duplicates'),
              );
              stored[row['id'] as String] = row;
              if (writes == 1) {
                throw http.ClientException('Response lost after server commit');
              }
              return http.Response('', 201, request: request);
            }
            return http.Response(
              jsonEncode({'id': stored.keys.single}),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        Future<void> save(double amount, String id) async {
          if (income) {
            await PaymentsRepository(client).create(
              workspaceId: 'workspace-one',
              paymentId: id,
              amount: amount,
              status: 'paid',
              date: DateTime(2026, 9, 12),
            );
          } else {
            await ExpensesRepository(client).create(
              workspaceId: 'workspace-one',
              expenseId: id,
              amount: amount,
              category: 'Materials',
              date: DateTime(2026, 9, 12),
            );
          }
        }

        await expectLater(
          save(100, 'stable-id'),
          throwsA(isA<http.ClientException>()),
        );
        await save(200, 'stable-id');
        expect(writes, 2);
        expect(stored, hasLength(1));
        expect(stored.values.single[income ? 'total' : 'amount'], 200);
      },
    );
  }
  test('cash totals exclude future income and refunds but include today', () {
    final now = DateTime(2026, 9, 12, 12);
    final payments = [
      Payment(
        id: 'future',
        workspaceId: 'workspace-one',
        number: 'PAY-1',
        status: 'paid',
        issueDate: DateTime(2026, 9, 13),
        incomeRecordedAt: DateTime(2026, 9, 13),
        total: 500,
        amountPaid: 500,
      ),
      Payment(
        id: 'document',
        workspaceId: 'workspace-one',
        number: 'INV-1',
        status: 'paid',
        sourceDocumentId: 'doc',
        issueDate: now,
        total: 100,
        amountPaid: 100,
        receipts: [
          PaymentReceipt(
            id: 'received',
            amount: 100,
            receivedAt: DateTime(2026, 9, 12, 18),
          ),
          PaymentReceipt(
            id: 'future-refund',
            amount: -20,
            receivedAt: DateTime(2026, 9, 13),
          ),
        ],
      ),
    ];
    final summary = FinanceSummary.from(
      payments: payments,
      expenses: [],
      monthlyTarget: 1000,
      now: now,
    );
    expect(summary.thisWeekPaid, 100);
    expect(summary.thisMonthPaid, 100);
    expect(summary.thisWeekSummary.paid, 100);
    expect(receivedIncomeForMonth(payments, now, now: now), 100);
    expect(
      displayReceivedDate(payments.first, now: now),
      DateTime(2026, 9, 13),
    );
  });
}
