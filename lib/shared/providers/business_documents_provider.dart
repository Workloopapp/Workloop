import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/finance/documents/business_document.dart';
import '../repositories/business_documents_repository.dart';
import 'workspace_provider.dart';

final businessDocumentsProvider = FutureProvider<List<BusinessDocument>>((
  ref,
) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return [];
  return ref.watch(businessDocumentsRepositoryProvider).list(workspaceId);
});

final businessDocumentProvider = FutureProvider.autoDispose
    .family<BusinessDocument, String>((ref, id) async {
      final workspaceId = await ref.watch(workspaceIdProvider.future);
      if (workspaceId == null) {
        throw StateError('Sign in to view this document.');
      }
      return ref
          .watch(businessDocumentsRepositoryProvider)
          .get(workspaceId, id);
    });
