import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/workspace_provider.dart';
import 'record_attachment.dart';
import 'record_attachments_repository.dart';

final recordAttachmentsProvider = FutureProvider.autoDispose
    .family<List<RecordAttachment>, AttachmentTarget>((ref, target) async {
      final workspaceId = await ref.watch(workspaceIdProvider.future);
      if (workspaceId == null) return [];
      return ref
          .watch(recordAttachmentsRepositoryProvider)
          .list(workspaceId: workspaceId, target: target);
    });
