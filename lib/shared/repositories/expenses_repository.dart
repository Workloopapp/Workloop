import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/slate_models.dart';
import 'repository_pagination.dart';
import 'supabase_client_provider.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(ref.watch(supabaseClientProvider));
});

class ExpensesRepository {
  final SupabaseClient _client;
  const ExpensesRepository(this._client);

  Future<List<Expense>> list(String workspaceId) async {
    try {
      final rows = await fetchAllRepositoryPages<Map<String, dynamic>>(
        loadPage: (from, to) async {
          final page = await _client
              .from('expenses')
              .select()
              .eq('workspace_id', workspaceId)
              .order('expense_date', ascending: false)
              .order('created_at', ascending: false)
              .order('id', ascending: true)
              .range(from, to);
          return List<Map<String, dynamic>>.from(page);
        },
      );
      return rows.map<Expense>(Expense.fromMap).toList();
    } on PostgrestException catch (error) {
      if (_tableMissing(error)) return [];
      rethrow;
    }
  }

  Future<List<Expense>> listForBusinessFeed(
    String workspaceId, {
    required DateTime from,
    int limit = 12,
  }) async {
    try {
      final rows = await _client
          .from('expenses')
          .select()
          .eq('workspace_id', workspaceId)
          .gte('expense_date', from.toIso8601String().split('T').first)
          .order('expense_date', ascending: false)
          .order('created_at', ascending: false)
          .order('id', ascending: true)
          .limit(limit);
      return rows
          .map<Expense>(
            (row) => Expense.fromMap(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on PostgrestException catch (error) {
      if (_tableMissing(error)) return [];
      rethrow;
    }
  }

  Future<void> create({
    required String workspaceId,
    required double amount,
    required String category,
    required DateTime date,
    String? notes,
    String? expenseId,
  }) async {
    final values = {
      'id': ?expenseId,
      'workspace_id': workspaceId,
      'amount': amount,
      'category': category,
      'expense_date': date.toIso8601String().split('T').first,
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
    };
    if (expenseId == null) {
      await _client.from('expenses').insert(values);
    } else {
      // Match receipt-backed creation: retries retain this expense identity,
      // including any corrections the owner made while the form stayed open.
      await _client.from('expenses').upsert(values);
      await _client
          .from('expenses')
          .select('id')
          .eq('id', expenseId)
          .eq('workspace_id', workspaceId)
          .single();
    }
  }

  /// Used when a receipt needs the new expense id before upload.
  Future<String> createReturningId({
    required String expenseId,
    required String workspaceId,
    required double amount,
    required String category,
    required DateTime date,
    String? notes,
  }) async {
    final row = await _client
        .from('expenses')
        .upsert({
          'id': expenseId,
          'workspace_id': workspaceId,
          'amount': amount,
          'category': category,
          'expense_date': date.toIso8601String().split('T').first,
          'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> update({
    required String expenseId,
    required double amount,
    required String category,
    required DateTime date,
    String? notes,
  }) async {
    await _client
        .from('expenses')
        .update({
          'amount': amount,
          'category': category,
          'expense_date': date.toIso8601String().split('T').first,
          'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', expenseId)
        .select('id')
        .single();
  }

  Future<void> delete(String expenseId) async {
    // Delete object bytes before cascading their metadata. Failure blocks the
    // expense deletion so receipts remain discoverable and the user can retry.
    final receipts = await fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async => List<Map<String, dynamic>>.from(
        await _client
            .from('expense_receipts')
            .select('id,object_path')
            .eq('expense_id', expenseId)
            .order('id')
            .range(from, to),
      ),
    );
    for (var offset = 0; offset < receipts.length; offset += 100) {
      final page = receipts.skip(offset).take(100).toList();
      await _client.storage
          .from('expense-receipts')
          .remove(page.map((row) => row['object_path'] as String).toList());
      await _client
          .from('expense_receipts')
          .delete()
          .inFilter('id', page.map((row) => row['id'] as String).toList());
    }
    await _client
        .from('expenses')
        .delete()
        .eq('id', expenseId)
        .select('id')
        .single();
  }

  bool _tableMissing(PostgrestException error) {
    return (error.code == '42P01' &&
            error.message == 'relation "public.expenses" does not exist') ||
        (error.code == 'PGRST205' &&
            error.message ==
                "Could not find the table 'public.expenses' in the schema cache");
  }
}
