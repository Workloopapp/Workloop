import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/repository_pagination.dart';
import '../repositories/supabase_client_provider.dart';
import '../utils/workflow_idempotency.dart';
import 'record_attachment.dart';

final recordAttachmentsRepositoryProvider =
    Provider<RecordAttachmentsRepository>(
      (ref) => RecordAttachmentsRepository(ref.watch(supabaseClientProvider)),
    );

class RecordAttachmentsRepository {
  final SupabaseClient client;
  const RecordAttachmentsRepository(this.client);

  Future<List<RecordAttachment>> list({
    required String workspaceId,
    required AttachmentTarget target,
  }) async {
    final rows = await fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async => List<Map<String, dynamic>>.from(
        await client
            .from('record_attachments')
            .select()
            .eq('workspace_id', workspaceId)
            .eq(target.column, target.id)
            .order('created_at', ascending: false)
            .order('id', ascending: true)
            .range(from, to),
      ),
    );
    return rows.map(RecordAttachment.fromMap).toList();
  }

  Future<RecordAttachment> upload({
    required String workspaceId,
    required AttachmentTarget target,
    required String fileName,
    required Uint8List bytes,
    String? attachmentId,
  }) async {
    final file = RecordAttachmentFile.checked(fileName, bytes);
    final id = attachmentId ?? createPublicRequestToken();
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    if (![workspaceId, target.id, id].every(uuid.hasMatch)) {
      throw const FormatException('Save this record before adding a file.');
    }
    final path = '$workspaceId/${target.id}/$id.${file.extension}';
    // Reserve identity first. A lost response can be retried with the same id
    // without a second row, and uploads can only target reserved private paths.
    await client
        .from('record_attachments')
        .upsert(
          {
            'id': id,
            'workspace_id': workspaceId,
            target.column: target.id,
            'object_path': path,
            'file_name': file.fileName,
            'mime_type': file.mimeType,
            'size_bytes': file.bytes.length,
            'content_hash': file.contentHash,
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
    final attachment = RecordAttachment.fromMap(
      await client
          .from('record_attachments')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('id', id)
          .single(),
    );
    if (attachment.target != target ||
        attachment.path != path ||
        attachment.fileName != file.fileName ||
        attachment.mimeType != file.mimeType ||
        attachment.sizeBytes != file.bytes.length ||
        attachment.contentHash != file.contentHash) {
      throw const FormatException('This upload belongs to a different file.');
    }
    try {
      await client.storage
          .from(recordAttachmentBucket)
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(
              contentType: file.mimeType,
              upsert: false,
              cacheControl: '0',
            ),
          );
    } catch (_) {
      // A network error or duplicate may follow a successful upload. Verify
      // the existing immutable object before reporting a failed save.
      try {
        final existing = await download(attachment);
        if (sha256.convert(existing).toString() == file.contentHash) {
          return attachment;
        }
      } catch (_) {
        // Preserve the original upload error below.
      }
      try {
        await delete(attachment);
      } catch (_) {
        // Keep the reservation if bytes cannot be confirmed removed, so the
        // user can retry and account deletion can still discover the file.
      }
      rethrow;
    }
    return attachment;
  }

  Future<Uint8List> download(RecordAttachment attachment) async {
    final bytes = await client.storage
        .from(recordAttachmentBucket)
        .download(attachment.path);
    if (bytes.length != attachment.sizeBytes ||
        bytes.length > recordAttachmentMaxBytes ||
        (attachment.contentHash != null &&
            sha256.convert(bytes).toString() != attachment.contentHash)) {
      throw const FormatException(
        'This file could not be verified. Try again.',
      );
    }
    return bytes;
  }

  Future<void> delete(RecordAttachment attachment) async {
    // Never lose the only cleanup pointer before actual bytes are removed.
    await client.storage.from(recordAttachmentBucket).remove([attachment.path]);
    await client
        .from('record_attachments')
        .delete()
        .eq('workspace_id', attachment.workspaceId)
        .eq('id', attachment.id);
  }

  Future<void> deleteForTarget({
    required String workspaceId,
    required AttachmentTarget target,
  }) async {
    late List<RecordAttachment> attachments;
    try {
      attachments = await list(workspaceId: workspaceId, target: target);
    } on PostgrestException catch (error) {
      // A new app can precede its additive backend migration. Only the exact
      // absent attachment table is safe to ignore when deleting older records.
      // Listing/upload UI still reports that deployment error explicitly.
      if ((error.code == 'PGRST205' || error.code == '42P01') &&
          RegExp(
            r'''["'](?:public\.)?record_attachments["']|\bpublic\.record_attachments\b''',
          ).hasMatch(error.message)) {
        return;
      }
      rethrow;
    }
    for (final attachment in attachments) {
      await delete(attachment);
    }
  }
}
