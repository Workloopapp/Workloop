import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/shared/providers/business_documents_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/business_documents_repository.dart';
import 'package:workloop/shared/repositories/payments_repository.dart';

const _workspace = 'a1100000-0000-4000-8000-000000000001';
const _documentId = 'a1200000-0000-4000-8000-000000000001';

Map<String, dynamic> _document({String workspace = _workspace}) => {
  'id': _documentId,
  'workspace_id': workspace,
  'type': 'invoice',
  'status': 'draft',
  'issue_date': '2026-09-08',
  'due_date': '2026-09-15',
  'service_date': '2026-09-08',
  'revision': 3,
  'subtotal': 30.38,
  'tax_rate': 20,
  'tax_amount': 6.08,
  'total': 36.46,
  'business_snapshot': {'name': 'Sample business', 'address': 'Business road'},
  'client_snapshot': {'name': 'Sample client', 'address': 'Client road'},
  'items': [
    {
      'description': 'Work',
      'quantity': 1.5,
      'unit_price': 20.25,
      'line_total': 30.38,
    },
  ],
};

SupabaseClient _client(Future<http.Response> Function(http.Request) handle) =>
    SupabaseClient(
      'https://example.supabase.co',
      'fake-anon-key',
      httpClient: MockClient((request) async {
        final response = await handle(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

class _DelayedDocuments extends BusinessDocumentsRepository {
  final first = Completer<List<BusinessDocument>>();
  _DelayedDocuments(super.client);

  @override
  Future<List<BusinessDocument>> list(String workspaceId) async =>
      workspaceId == _workspace
      ? first.future
      : [BusinessDocument.fromMap(_document(workspace: workspaceId))];
}

void main() {
  test('document reads pin both workspace and document identity', () async {
    final reads = <Uri>[];
    final client = _client((request) async {
      reads.add(request.url);
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/business_documents');
      expect(request.url.queryParameters['workspace_id'], 'eq.$_workspace');
      return _json(
        request.url.queryParameters.containsKey('id')
            ? _document()
            : [_document()],
      );
    });
    addTearDown(client.dispose);
    final repository = BusinessDocumentsRepository(client);
    expect((await repository.list(_workspace)).single.id, _documentId);
    expect(
      (await repository.get(_workspace, _documentId)).workspaceId,
      _workspace,
    );
    expect(reads.last.queryParameters['id'], 'eq.$_documentId');
    expect(reads.first.queryParameters['order'], startsWith('created_at.desc'));
    expect(reads.first.queryParameters['order'], contains(',id.'));
    expect(
      reads.first.queryParameters['select'],
      contains(
        'payment_state:invoices!business_documents_workspace_id_invoice_id_fkey(amount_paid)',
      ),
    );
  });

  test(
    'dated receipt and refund preserve identity, exact amount and retry date',
    () async {
      final calls = <({String name, Map<String, dynamic> body})>[];
      final client = _client((request) async {
        calls.add((
          name: request.url.pathSegments.last,
          body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
        ));
        return _json(_document());
      });
      addTearDown(client.dispose);
      final repository = BusinessDocumentsRepository(client);
      final document = BusinessDocument.fromMap(_document());
      await repository.recordReceived(
        document,
        1025,
        DateTime(2026, 9, 7),
        'same-dated-receipt-key',
      );
      await repository.recordReceived(
        document,
        1025,
        DateTime(2026, 9, 7),
        'same-dated-receipt-key',
      );
      await repository.recordReceived(
        document,
        225,
        DateTime(2026, 9, 8),
        'same-dated-refund-key',
        refund: true,
      );
      expect(calls[0].name, 'record_document_payment_received');
      expect(calls[0].body, calls[1].body);
      expect(calls[0].body, {
        'p_workspace_id': _workspace,
        'p_document_id': _documentId,
        'p_amount': '10.25',
        'p_received_date': '2026-09-07',
        'p_idempotency_key': 'same-dated-receipt-key',
      });
      expect(calls[2].name, 'record_document_refund');
      expect(calls[2].body['p_amount'], '2.25');
    },
  );

  test(
    'draft write uses one atomic RPC and decimal money without client totals',
    () async {
      final writes = <Map<String, dynamic>>[];
      final client = _client((request) async {
        expect(request.url.path, '/rest/v1/rpc/save_business_document');
        expect(request.method, 'POST');
        writes.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return _json(_document());
      });
      addTearDown(client.dispose);
      final repository = BusinessDocumentsRepository(client);
      final document = BusinessDocument.fromMap(_document());
      final saved = await repository.save(
        workspaceId: _workspace,
        id: _documentId,
        revision: 3,
        document: {'type': 'invoice', 'notes': 'Customer scope'},
        items: document.items,
      );
      expect(writes, hasLength(1));
      expect(writes.single['p_document_id'], _documentId);
      expect(writes.single['p_workspace_id'], _workspace);
      expect(writes.single['p_expected_revision'], 3);
      expect(writes.single['p_items'], [
        {'description': 'Work', 'quantity': '1.50', 'unit_price': '20.25'},
      ]);
      expect(saved.totalPence, 3646);
      expect(saved.items.single.totalPence, 3038);
    },
  );

  test(
    'ambiguous changed creation retry exposes server conflict instead of false success',
    () async {
      final client = _client(
        (request) async => _json({
          'code': 'P0001',
          'message': 'This draft was already saved. Reopen it before editing.',
          'details': null,
          'hint': null,
        }, status: 400),
      );
      addTearDown(client.dispose);
      await expectLater(
        BusinessDocumentsRepository(client).save(
          workspaceId: _workspace,
          id: _documentId,
          document: {'type': 'invoice', 'notes': 'Changed after response loss'},
          items: BusinessDocument.fromMap(_document()).items,
        ),
        throwsA(
          isA<PostgrestException>().having(
            (error) => error.message,
            'recoverable conflict',
            'This draft was already saved. Reopen it before editing.',
          ),
        ),
      );
    },
  );

  test(
    'lifecycle RPCs send only their supported identity and revision fields',
    () async {
      final calls = <({String name, Map<String, dynamic> body})>[];
      final client = _client((request) async {
        calls.add((
          name: request.url.pathSegments.last,
          body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
        ));
        return _json(_document());
      });
      addTearDown(client.dispose);
      final repository = BusinessDocumentsRepository(client);
      final document = BusinessDocument.fromMap(_document());
      await repository.issue(document);
      await repository.quoteStatus(document, 'accepted');
      await repository.convertQuote(document);
      await repository.cancel(document);
      await repository.deleteDraft(document);
      await repository.recordPayment(
        document,
        1025,
        'stable-payment-retry-key',
      );
      await repository.recordPayment(
        document,
        1025,
        'stable-payment-retry-key',
      );
      expect(calls[0].body['p_expected_revision'], 3);
      expect(calls[1].body['p_status'], 'accepted');
      for (final call in calls.skip(2)) {
        expect(call.body.containsKey('p_expected_revision'), false);
        expect(call.body['p_workspace_id'], _workspace);
        expect(call.body['p_document_id'], _documentId);
      }
      expect(calls[5].body['p_amount'], '10.25');
      expect(calls[5].body, calls[6].body);
    },
  );

  test(
    'late old-workspace document response cannot replace current workspace data',
    () async {
      final client = _client((_) async => _json([]));
      addTearDown(client.dispose);
      final repository = _DelayedDocuments(client);
      var workspace = _workspace;
      final container = ProviderContainer(
        overrides: [
          workspaceIdProvider.overrideWith((ref) async => workspace),
          businessDocumentsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        businessDocumentsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(workspaceIdProvider.future);
      await Future<void>.delayed(Duration.zero);
      workspace = 'a1100000-0000-4000-8000-000000000002';
      container.invalidate(workspaceIdProvider);
      final current = await container.read(businessDocumentsProvider.future);
      expect(current.single.workspaceId, workspace);
      repository.first.complete([BusinessDocument.fromMap(_document())]);
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(businessDocumentsProvider)
            .requireValue
            .single
            .workspaceId,
        workspace,
      );
    },
  );

  test(
    'receipt enrichment leaves legacy invoices compatible and includes every document delta',
    () async {
      var receiptReads = 0;
      var includeDocument = false;
      final client = _client((request) async {
        if (request.url.path == '/rest/v1/business_document_receipts') {
          receiptReads++;
          expect(
            request.url.queryParameters['invoice_id'],
            contains('managed-invoice'),
          );
          return _json([
            {
              'id': 'receipt-1',
              'invoice_id': 'managed-invoice',
              'amount': 30,
              'received_at': '2026-08-31T12:00:00Z',
            },
            {
              'id': 'receipt-2',
              'invoice_id': 'managed-invoice',
              'amount': 70,
              'received_at': '2026-09-01T12:00:00Z',
            },
            {
              'id': 'receipt-3',
              'invoice_id': 'managed-invoice',
              'amount': -25,
              'received_at': '2026-09-02T12:00:00Z',
            },
          ]);
        }
        expect(request.url.path, '/rest/v1/invoices');
        return _json([
          {
            'id': 'legacy',
            'workspace_id': _workspace,
            'status': 'paid',
            'total': 10,
            'amount_paid': 10,
            'issue_date': '2026-09-08',
          },
          if (includeDocument)
            {
              'id': 'managed-invoice',
              'workspace_id': _workspace,
              'source_document_id': _documentId,
              'status': 'sent',
              'total': 100,
              'amount_paid': 75,
              'issue_date': '2026-08-01',
            },
        ]);
      });
      addTearDown(client.dispose);
      final repository = PaymentsRepository(client);
      expect((await repository.list(_workspace)).single.collectedAmount, 10);
      expect(receiptReads, 0);
      includeDocument = true;
      final managed = (await repository.list(_workspace)).last;
      expect(receiptReads, 1);
      expect(managed.receipts, hasLength(3));
      expect(
        managed.receivedAmountBetween(
          DateTime.utc(2026, 9),
          DateTime.utc(2026, 10),
        ),
        45,
      );
      expect(managed.outstandingAmount, 25);
    },
  );

  test(
    'receipt load failure fails financial read rather than reporting zero income',
    () async {
      final client = _client((request) async {
        if (request.url.path == '/rest/v1/business_document_receipts') {
          return _json({
            'code': '42501',
            'message': 'receipt permission denied',
          }, status: 403);
        }
        return _json([
          {
            'id': 'managed-invoice',
            'workspace_id': _workspace,
            'source_document_id': _documentId,
            'status': 'paid',
            'total': 100,
            'amount_paid': 100,
            'issue_date': '2026-09-08',
          },
        ]);
      });
      addTearDown(client.dispose);
      await expectLater(
        PaymentsRepository(client).list(_workspace),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
