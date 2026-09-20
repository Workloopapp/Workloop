import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository_pagination.dart';
import 'supabase_client_provider.dart';

const privacyExportPageSize = 1000;
const receiptExportMaxBytes = 20 * 1024 * 1024;

class ReceiptExportTooLargeException implements Exception {
  const ReceiptExportTooLargeException();
}

const workspacePrivacyExportTables = <String>{
  'workspaces',
  'workspace_members',
  'workspace_settings',
  'business_profiles',
  'contacts',
  'services',
  'service_add_ons',
  'appointments',
  'appointment_items',
  'invoices',
  'invoice_line_items',
  'business_documents',
  'business_document_receipts',
  'expenses',
  'expense_receipts',
  'record_attachments',
  'mileage_entries',
  'workspace_tax_estimates',
  'tasks',
  'task_checklist_items',
  'notes',
  'booking_requests',
  'booking_request_items',
  'notification_preferences',
  'notifications',
  'push_tokens',
  'calendar_sync_accounts',
  'workspace_payment_accounts',
  'payment_transactions',
  'payment_refunds',
  'account_deletion_requests',
};

class PrivacyExportIncompleteException implements Exception {
  final List<String> warnings;
  const PrivacyExportIncompleteException(this.warnings);

  @override
  String toString() => 'Workspace export was incomplete: ${warnings.join(' ')}';
}

enum AppleAccountRevocation { revoked, manualActionRequired, notApplicable }

class AccountDeletionResult {
  const AccountDeletionResult({
    this.appleRevocation = AppleAccountRevocation.notApplicable,
  });
  final AppleAccountRevocation appleRevocation;
  bool get needsAppleUnlink =>
      appleRevocation == AppleAccountRevocation.manualActionRequired;
}

class AccountDeletionException implements Exception {
  const AccountDeletionException({this.appleIdentityMismatch = false});
  final bool appleIdentityMismatch;
}

final privacyRepositoryProvider = Provider<PrivacyRepository>((ref) {
  return PrivacyRepository(ref.watch(supabaseClientProvider));
});

class PrivacyRepository {
  final SupabaseClient _client;
  const PrivacyRepository(this._client);

  Future<String> exportWorkspaceData(String workspaceId) async {
    final warnings = <String>[];
    final user = _client.auth.currentUser;
    final data = <String, dynamic>{
      'format': 'workloop_workspace_export',
      'format_version': 4,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'workspace_id': workspaceId,
      'account': user == null
          ? null
          : {
              'id': user.id,
              'email': user.email,
              'user_metadata': user.userMetadata,
            },
      'workspace': await _maybeSingle(
        'workspaces',
        'id',
        workspaceId,
        warnings,
      ),
      'workspace_settings': await _maybeSingle(
        'workspace_settings',
        'workspace_id',
        workspaceId,
        warnings,
      ),
      'business_profile': await _maybeSingle(
        'business_profiles',
        'workspace_id',
        workspaceId,
        warnings,
      ),
      'workspace_members': await _list(
        'workspace_members',
        workspaceId,
        warnings,
      ),
      'contacts': await _list('contacts', workspaceId, warnings),
      'services': await _list('services', workspaceId, warnings),
      'service_add_ons': await _list('service_add_ons', workspaceId, warnings),
      'appointments': await _list('appointments', workspaceId, warnings),
      'appointment_items': await _list(
        'appointment_items',
        workspaceId,
        warnings,
      ),
      'payments': await _list('invoices', workspaceId, warnings),
      'payment_line_items': await _list(
        'invoice_line_items',
        workspaceId,
        warnings,
      ),
      'expenses': await _list('expenses', workspaceId, warnings),
      'business_documents': await _list(
        'business_documents',
        workspaceId,
        warnings,
      ),
      'business_document_receipts': await _list(
        'business_document_receipts',
        workspaceId,
        warnings,
      ),
      'expense_receipts': await _list(
        'expense_receipts',
        workspaceId,
        warnings,
      ),
      'receipt_files': await _receiptFiles(workspaceId, warnings),
      'record_attachments': await _list(
        'record_attachments',
        workspaceId,
        warnings,
      ),
      'attachment_files': await _receiptFiles(
        workspaceId,
        warnings,
        table: 'record_attachments',
        bucket: 'record-attachments',
      ),
      'mileage_entries': await _list('mileage_entries', workspaceId, warnings),
      'tax_estimate_inputs': await _list(
        'workspace_tax_estimates',
        workspaceId,
        warnings,
      ),
      'tasks': await _list('tasks', workspaceId, warnings),
      'task_checklist_items': await _list(
        'task_checklist_items',
        workspaceId,
        warnings,
      ),
      'notes': await _list('notes', workspaceId, warnings),
      'booking_requests': await _list(
        'booking_requests',
        workspaceId,
        warnings,
      ),
      'booking_request_items': await _list(
        'booking_request_items',
        workspaceId,
        warnings,
      ),
      'notification_preferences': await _maybeSingle(
        'notification_preferences',
        'workspace_id',
        workspaceId,
        warnings,
      ),
      'notifications': await _list('notifications', workspaceId, warnings),
      'push_tokens': await _list('push_tokens', workspaceId, warnings),
      'calendar_sync_accounts': await _list(
        'calendar_sync_accounts',
        workspaceId,
        warnings,
      ),
      'workspace_payment_account': await _maybeSingle(
        'workspace_payment_accounts',
        'workspace_id',
        workspaceId,
        warnings,
      ),
      'payment_transactions': await _list(
        'payment_transactions',
        workspaceId,
        warnings,
      ),
      'payment_refunds': await _list('payment_refunds', workspaceId, warnings),
      'account_deletion_requests': await _list(
        'account_deletion_requests',
        workspaceId,
        warnings,
      ),
    };
    if (warnings.isNotEmpty) {
      throw PrivacyExportIncompleteException(List.unmodifiable(warnings));
    }

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<AccountDeletionResult> requestAccountDeletion({
    String? workspaceId,
    String? appleAuthorizationCode,
  }) async {
    final accountId = _client.auth.currentUser?.id;
    if (accountId == null) throw const AccountDeletionException();
    try {
      final response = await _client.functions.invoke(
        'request-account-deletion',
        body: {
          'workspaceId': ?workspaceId,
          'appleAuthorizationCode': ?appleAuthorizationCode,
        },
      );
      final data = response.data;
      if (_client.auth.currentUser?.id != accountId ||
          data is! Map ||
          data['ok'] != true ||
          data['accessLocked'] != true) {
        throw const AccountDeletionException();
      }
      return AccountDeletionResult(
        appleRevocation: switch (data['appleRevocation']) {
          'revoked' => AppleAccountRevocation.revoked,
          'not_applicable' => AppleAccountRevocation.notApplicable,
          _ => AppleAccountRevocation.manualActionRequired,
        },
      );
    } on FunctionException catch (error) {
      final details = error.details;
      throw AccountDeletionException(
        appleIdentityMismatch:
            details is Map &&
            (details['error'] == 'apple_identity_mismatch' ||
                details['code'] == 'apple_identity_mismatch'),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _receiptFiles(
    String workspaceId,
    List<String> warnings, {
    String table = 'expense_receipts',
    String bucket = 'expense-receipts',
  }) async {
    final receipts = await _list(table, workspaceId, warnings);
    if (receipts.fold<int>(
          0,
          (sum, row) => sum + ((row['size_bytes'] as num?)?.toInt() ?? 0),
        ) >
        receiptExportMaxBytes) {
      throw const ReceiptExportTooLargeException();
    }
    final files = <Map<String, dynamic>>[];
    var downloadedBytes = 0;
    for (final receipt in receipts) {
      try {
        final path = receipt['object_path'] as String;
        final bytes = await _client.storage.from(bucket).download(path);
        downloadedBytes += bytes.length;
        if (downloadedBytes > receiptExportMaxBytes) {
          throw const ReceiptExportTooLargeException();
        }
        files.add({
          'file_name': receipt['file_name'],
          'mime_type': receipt['mime_type'],
          'object_path': path,
          'encoding': 'base64',
          'data': base64Encode(bytes),
        });
      } on ReceiptExportTooLargeException {
        rethrow;
      } catch (_) {
        warnings.add('A private file could not be included in this export.');
      }
    }
    return files;
  }

  Future<Map<String, dynamic>?> _maybeSingle(
    String table,
    String column,
    String value,
    List<String> warnings,
  ) async {
    try {
      final row = await _client
          .from(table)
          .select()
          .eq(column, value)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      warnings.add('$table could not be included in this export.');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _list(
    String table,
    String workspaceId,
    List<String> warnings,
  ) async {
    try {
      return fetchAllRepositoryPages<Map<String, dynamic>>(
        pageSize: privacyExportPageSize,
        loadPage: (from, to) async {
          final rows = await _client
              .from(table)
              .select()
              .eq('workspace_id', workspaceId)
              .order('id')
              .range(from, to);
          return List<Map<String, dynamic>>.from(rows);
        },
      );
    } catch (_) {
      warnings.add('$table could not be included in this export.');
      return [];
    }
  }
}
