import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/finance/documents/business_document.dart';
import 'repository_pagination.dart';
import 'supabase_client_provider.dart';

final businessDocumentsRepositoryProvider =
    Provider<BusinessDocumentsRepository>(
      (ref) => BusinessDocumentsRepository(ref.watch(supabaseClientProvider)),
    );

class BusinessDocumentsRepository {
  static const _selection =
      '*,payment_state:invoices!business_documents_workspace_id_invoice_id_fkey(amount_paid)';
  final SupabaseClient client;
  const BusinessDocumentsRepository(this.client);

  Future<List<BusinessDocument>> list(String workspaceId) async {
    final rows = await fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async => List<Map<String, dynamic>>.from(
        await client
            .from('business_documents')
            .select(_selection)
            .eq('workspace_id', workspaceId)
            .order('created_at', ascending: false)
            .order('id')
            .range(from, to),
      ),
    );
    return rows.map(BusinessDocument.fromMap).toList();
  }

  Future<BusinessDocument> get(String workspaceId, String id) async =>
      BusinessDocument.fromMap(
        await client
            .from('business_documents')
            .select(_selection)
            .eq('workspace_id', workspaceId)
            .eq('id', id)
            .single(),
      );

  Future<BusinessDocument> save({
    required String workspaceId,
    required String id,
    required Map<String, dynamic> document,
    required List<BusinessDocumentItem> items,
    int? revision,
  }) => _call('save_business_document', {
    'p_workspace_id': workspaceId,
    'p_document_id': id,
    'p_expected_revision': revision,
    'p_document': document,
    'p_items': items.map((item) => item.toMap()).toList(),
  });

  Future<BusinessDocument> issue(BusinessDocument document) =>
      _call('issue_business_document', _identity(document));

  Future<BusinessDocument> quoteStatus(
    BusinessDocument document,
    String status,
  ) => _call('set_quote_status', {..._identity(document), 'p_status': status});

  Future<BusinessDocument> convertQuote(BusinessDocument document) =>
      _call('convert_quote_to_invoice', _identity(document, revision: false));

  Future<BusinessDocument> cancel(BusinessDocument document) =>
      _call('cancel_business_document', _identity(document, revision: false));

  Future<void> deleteDraft(BusinessDocument document) async {
    await client.rpc(
      'delete_business_document',
      params: _identity(document, revision: false),
    );
  }

  Future<BusinessDocument> recordPayment(
    BusinessDocument document,
    int pence,
    String key,
  ) => _call('record_document_payment', {
    ..._identity(document, revision: false),
    'p_amount': documentMoneyInput(pence),
    'p_idempotency_key': key,
  });

  Future<BusinessDocument> recordReceived(
    BusinessDocument document,
    int pence,
    DateTime date,
    String key, {
    bool refund = false,
  }) => _call(
    refund ? 'record_document_refund' : 'record_document_payment_received',
    {
      ..._identity(document, revision: false),
      'p_amount': documentMoneyInput(pence),
      'p_received_date': documentDate(date),
      'p_idempotency_key': key,
    },
  );

  Map<String, dynamic> _identity(
    BusinessDocument document, {
    bool revision = true,
  }) => {
    'p_workspace_id': document.workspaceId,
    'p_document_id': document.id,
    if (revision) 'p_expected_revision': document.revision,
  };

  Future<BusinessDocument> _call(
    String name,
    Map<String, dynamic> params,
  ) async {
    final data = await client.rpc(name, params: params);
    return BusinessDocument.fromMap(Map<String, dynamic>.from(data as Map));
  }
}
