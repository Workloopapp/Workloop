// Fictional fixture for native surface checks. No saved session or backend.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/features/finance/documents/business_document.dart';
import 'package:workloop/features/finance/receipt_capture_service.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/business_documents_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/providers/workspace_settings_provider.dart';
import 'package:workloop/shared/repositories/business_documents_repository.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/supabase_client_provider.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

const nativeProbeWorkspace = 'native-probe-fictional-workspace';
const nativeProbeDocumentId = 'native-probe-fictional-invoice';

class _NoBackend implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native QA has no backend access.');
}

class _FictionalAuth implements AuthRepository {
  @override
  String get currentUserId => 'native-probe-fictional-user';

  @override
  Stream<AuthState> get authChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Native QA has no account access.');
}

class _NoSavedCapture extends ReceiptCaptureService {
  @override
  Future<bool> discardUnscopedRecovery() async => false;
}

BusinessDocument nativeProbeDocument() => BusinessDocument.fromMap({
  'id': nativeProbeDocumentId,
  'workspace_id': nativeProbeWorkspace,
  'type': 'invoice',
  'status': 'sent',
  'revision': 2,
  'issued_at': '2026-09-08T12:00:00Z',
  'issue_date': '2026-09-08',
  'due_date': '2026-09-15',
  'service_date': '2026-09-08',
  'invoice_number': 'QA-FICTIONAL-001',
  'invoice_id': 'native-probe-fictional-payment',
  'subtotal': 100,
  'tax_rate': 0,
  'tax_amount': 0,
  'total': 100,
  'notes': 'Fictional native QA document. No payment is requested.',
  'business_snapshot': {
    'name': 'Fictional QA Business',
    'legal_name': 'Example Owner',
    'address': 'Example address, UK',
    'email': 'qa@example.invalid',
  },
  'client_snapshot': {
    'name': 'Fictional QA Customer',
    'address': 'Example customer address',
  },
  'items': [
    {
      'description': 'Fictional demonstration service',
      'quantity': 1,
      'unit_price': 100,
      'line_total': 100,
      'position': 0,
    },
  ],
});

Widget nativeProbeHost(Widget screen) {
  final noBackend = _NoBackend();
  final document = nativeProbeDocument();
  return ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(noBackend),
      authRepositoryProvider.overrideWithValue(_FictionalAuth()),
      workspaceIdProvider.overrideWith((_) async => nativeProbeWorkspace),
      workspaceSettingsProvider.overrideWith(
        (_) async => {'timezone': 'Europe/London'},
      ),
      businessDocumentsRepositoryProvider.overrideWithValue(
        BusinessDocumentsRepository(noBackend),
      ),
      businessDocumentProvider(
        nativeProbeDocumentId,
      ).overrideWith((_) async => document),
      invoicesProvider.overrideWith((_) async => <Payment>[]),
      paymentCollectionEnabledProvider.overrideWithValue(false),
      receiptCaptureServiceProvider.overrideWithValue(_NoSavedCapture()),
    ],
    child: Consumer(
      builder: (context, ref, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: ref.watch(workspaceIdProvider).hasValue
            ? WorkloopAppCanvas(child: screen)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    ),
  );
}
