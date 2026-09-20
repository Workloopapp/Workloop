import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../documents/workloop_document_viewer.dart';
import '../providers/workspace_provider.dart';
import '../repositories/auth_repository.dart';
import '../utils/workflow_idempotency.dart';
import '../widgets/slate_ui.dart';
import 'record_attachment.dart';
import 'record_attachment_picker.dart';
import 'record_attachments_provider.dart';
import 'record_attachments_repository.dart';

/// One private file workspace, reached from the record that owns the files.
class RecordAttachmentsScreen extends ConsumerStatefulWidget {
  final String workspaceId;
  final AttachmentTarget target;
  final String recordTitle;

  const RecordAttachmentsScreen({
    super.key,
    required this.workspaceId,
    required this.target,
    required this.recordTitle,
  });

  @override
  ConsumerState<RecordAttachmentsScreen> createState() =>
      _RecordAttachmentsScreenState();
}

class _RecordAttachmentsScreenState
    extends ConsumerState<RecordAttachmentsScreen> {
  String? _userId;
  StreamSubscription<AuthState>? _authSubscription;
  bool _busy = false;
  bool _revoked = false;
  bool _allowPop = false;
  bool _confirmingExit = false;
  String? _error;
  RecordAttachmentFile? _pending;
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authRepositoryProvider);
    _userId = auth.currentUserId;
    _revoked = _userId == null;
    _authSubscription = auth.authChanges.listen((event) {
      if (event.session?.user.id != _userId) _revoke();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPicker());
  }

  bool get _sameScope {
    if (!mounted || _revoked || _userId == null) return false;
    final workspace = ref.read(workspaceIdProvider);
    return ref.read(authRepositoryProvider).currentUserId == _userId &&
        !workspace.isLoading &&
        !workspace.hasError &&
        workspace.value == widget.workspaceId;
  }

  void _revoke() {
    if (!mounted || _revoked) return;
    setState(() {
      _revoked = true;
      _pending = null;
      _pendingId = null;
      _error = null;
    });
  }

  Future<void> _recoverPicker() async {
    if (!_sameScope || _busy) {
      final workspace = ref.read(workspaceIdProvider);
      if (!workspace.isLoading &&
          workspace.hasValue &&
          workspace.value != widget.workspaceId) {
        _revoke();
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final interrupted = await ref
          .read(recordAttachmentPickerProvider)
          .discardUnscopedRecovery();
      if (_sameScope && interrupted) {
        setState(
          () => _error =
              'The previous photo selection was interrupted. Choose it again to attach it to this record.',
        );
      }
    } catch (_) {
      // Recovery must never stop a new explicit selection.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _pending = null;
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_sameScope) return;
    ref.invalidate(recordAttachmentsProvider(widget.target));
    try {
      await ref.read(recordAttachmentsProvider(widget.target).future);
    } catch (_) {
      // The list retains an explicit error and retry action.
    }
  }

  Future<void> _pick() async {
    if (_busy || !_sameScope || _pending != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = await showWorkloopBottomSheet<RecordAttachmentSource>(
        context: context,
        builder: (context) => SlateSheetFrame(
          scrollable: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a photo or file',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Keep useful work details here. Files stay private to your business. Up to 10 MB each.',
              ),
              const SizedBox(height: AppSpacing.md),
              for (final option in const [
                (
                  RecordAttachmentSource.camera,
                  Icons.camera_alt_outlined,
                  'Take photo',
                  'Capture the work or an important detail',
                ),
                (
                  RecordAttachmentSource.photos,
                  Icons.photo_library_outlined,
                  'Photo library',
                  'Choose a photo from your phone',
                ),
                (
                  RecordAttachmentSource.file,
                  Icons.attach_file,
                  'Choose file',
                  'JPEG, PNG, WebP, PDF or text',
                ),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(option.$2),
                  title: Text(option.$3),
                  subtitle: Text(option.$4),
                  onTap: () => Navigator.pop(context, option.$1),
                ),
            ],
          ),
        ),
      );
      if (source == null || !_sameScope) return;
      final file = await ref.read(recordAttachmentPickerProvider).pick(source);
      if (file == null || !_sameScope) return;
      setState(() {
        _pending = file;
        _pendingId = createPublicRequestToken();
      });
    } catch (error) {
      if (_sameScope) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_pending != null && _sameScope) await _upload();
  }

  Future<void> _upload() async {
    final file = _pending;
    final id = _pendingId;
    if (_busy || !_sameScope || file == null || id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(recordAttachmentsRepositoryProvider)
          .upload(
            workspaceId: widget.workspaceId,
            target: widget.target,
            fileName: file.fileName,
            bytes: file.bytes,
            attachmentId: id,
          );
      if (!_sameScope) return;
      setState(() {
        _pending = null;
        _pendingId = null;
      });
      await _refresh();
    } catch (error) {
      if (_sameScope) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is FormatException
      ? error.message
      : 'Could not save this change. Check your connection and try again.';

  Future<void> _view(RecordAttachment attachment) async {
    if (_busy || !_sameScope) return;
    final repository = ref.read(recordAttachmentsRepositoryProvider);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkloopDocumentViewerScreen(
          workspaceId: widget.workspaceId,
          title: attachment.fileName,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          loadBytes: () => repository.download(attachment),
        ),
      ),
    );
  }

  Future<void> _remove(RecordAttachment attachment) async {
    if (_busy || !_sameScope) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: Text(
          '${attachment.fileName} will be deleted. The record will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_sameScope || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(recordAttachmentsRepositoryProvider).delete(attachment);
      if (_sameScope) await _refresh();
    } catch (error) {
      if (_sameScope) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    if ((_busy && !_revoked) || _confirmingExit) return;
    if (_pending != null && _sameScope) {
      _confirmingExit = true;
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave without retrying?'),
          content: const Text(
            'This upload has not been confirmed. Stay to retry, or leave and check your saved files later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      _confirmingExit = false;
      if (leave != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    workloopGoBack(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceIdProvider, (_, next) {
      if (!next.isLoading &&
          next.hasValue &&
          next.value != widget.workspaceId) {
        _revoke();
      }
    });
    final workspace = ref.watch(workspaceIdProvider);
    final ready = _sameScope;
    final attachments = ready
        ? ref.watch(recordAttachmentsProvider(widget.target))
        : null;
    return PopScope(
      canPop: _allowPop || _revoked || (!_busy && (_pending == null || !ready)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: WorkloopAppCanvas(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.pageX),
                  child: WorkloopRouteHeader(
                    title: 'Photos & files',
                    onBack: _back,
                    trailing: !ready || _pending != null
                        ? null
                        : TextButton.icon(
                            onPressed: _busy ? null : _pick,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add'),
                          ),
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                Expanded(
                  child: !ready
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.pageX),
                            child: _revoked
                                ? const Text(
                                    'Your business or account changed. Reopen attachments from your current record.',
                                  )
                                : workspace.hasError
                                ? SlateErrorState(
                                    message: 'Could not confirm your business.',
                                    onRetry: () =>
                                        ref.invalidate(workspaceIdProvider),
                                  )
                                : const CircularProgressIndicator(),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageX,
                              0,
                              AppSpacing.pageX,
                              AppSpacing.xl,
                            ),
                            children: [
                              Text(
                                widget.recordTitle,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'Work photos, documents and useful details. Tap a file to view it here.',
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              if (_error != null) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: AppColors.of(context).error,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              if (_pending != null) ...[
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.cloud_upload_outlined,
                                  ),
                                  title: Text(_pending!.fileName),
                                  subtitle: Text(
                                    _busy ? 'Uploading…' : 'Waiting to upload',
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _busy ? null : _upload,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry upload'),
                                ),
                                const Divider(),
                              ],
                              ...attachments!.when(
                                loading: () => [
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ],
                                error: (_, _) => [
                                  SlateErrorState(
                                    message:
                                        'Could not load attachments. Your files have not been removed.',
                                    onRetry: _refresh,
                                  ),
                                ],
                                data: (files) => files.isEmpty
                                    ? [
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: AppSpacing.lg,
                                          ),
                                          child: Text(
                                            'No photos or files yet. Add work photos, reference documents or instructions.',
                                          ),
                                        ),
                                        if (_pending == null)
                                          TextButton.icon(
                                            onPressed: _busy ? null : _pick,
                                            icon: const Icon(Icons.attach_file),
                                            label: const Text(
                                              'Add photo or file',
                                            ),
                                          ),
                                      ]
                                    : files
                                          .map(
                                            (file) => Column(
                                              key: ValueKey(file.id),
                                              children: [
                                                ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  leading: Icon(
                                                    file.mimeType.startsWith(
                                                          'image/',
                                                        )
                                                        ? Icons.image_outlined
                                                        : Icons
                                                              .description_outlined,
                                                  ),
                                                  title: Text(file.fileName),
                                                  subtitle: Text(
                                                    '${file.mimeType.startsWith('image/')
                                                        ? 'Image'
                                                        : file.mimeType == 'application/pdf'
                                                        ? 'PDF'
                                                        : 'Text'} · ${(file.sizeBytes / 1024).ceil()} KB',
                                                  ),
                                                  onTap: _busy
                                                      ? null
                                                      : () => _view(file),
                                                  trailing: IconButton(
                                                    tooltip:
                                                        'Remove ${file.fileName}',
                                                    onPressed: _busy
                                                        ? null
                                                        : () => _remove(file),
                                                    icon: const Icon(
                                                      Icons.more_horiz,
                                                    ),
                                                  ),
                                                ),
                                                const Divider(height: 1),
                                              ],
                                            ),
                                          )
                                          .toList(),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
