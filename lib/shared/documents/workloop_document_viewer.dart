import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../providers/workspace_provider.dart';
import '../repositories/auth_repository.dart';
import '../widgets/slate_ui.dart';
import 'document_open_exception.dart';

/// A private, in-memory view of the same bytes that can be exported.
/// Loading stays with the existing generator/repository supplied by the caller.
class WorkloopDocumentViewerScreen extends ConsumerStatefulWidget {
  final String workspaceId;
  final String title;
  final String fileName;
  final String mimeType;
  final Future<Uint8List> Function() loadBytes;

  const WorkloopDocumentViewerScreen({
    super.key,
    required this.workspaceId,
    required this.title,
    required this.fileName,
    required this.mimeType,
    required this.loadBytes,
  });

  @override
  ConsumerState<WorkloopDocumentViewerScreen> createState() =>
      _WorkloopDocumentViewerState();
}

class _WorkloopDocumentViewerState
    extends ConsumerState<WorkloopDocumentViewerScreen> {
  String? _userId;
  StreamSubscription<AuthState>? _authSubscription;
  Uint8List? _bytes;
  LayoutCallback? _pdfBuilder;
  String? _error;
  bool _loading = true;
  bool _sharing = false;
  bool _revoked = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authRepositoryProvider);
    _userId = auth.currentUserId;
    _authSubscription = auth.authChanges.listen((event) {
      if (event.session?.user.id != _userId) _revoke();
    });
    _load();
  }

  bool get _sameAccount =>
      mounted &&
      !_revoked &&
      _userId != null &&
      ref.read(authRepositoryProvider).currentUserId == _userId;

  bool get _sameWorkspace {
    final workspace = ref.read(workspaceIdProvider);
    return _sameAccount &&
        !workspace.isLoading &&
        !workspace.hasError &&
        workspace.value == widget.workspaceId;
  }

  void _revoke() {
    if (!mounted || _revoked) return;
    setState(() {
      _revoked = true;
      _bytes = null;
      _pdfBuilder = null;
      _loading = false;
      _error = null;
      _loadGeneration++;
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (!_sameAccount) {
      _revoke();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _bytes = null;
      _pdfBuilder = null;
    });
    try {
      final workspace = await ref.read(workspaceIdProvider.future);
      if (!_sameWorkspace || workspace != widget.workspaceId) {
        _revoke();
        return;
      }
      final bytes = await widget.loadBytes();
      if (generation != _loadGeneration) return;
      if (!_sameWorkspace) {
        _revoke();
        return;
      }
      if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Document is empty or too large.');
      }
      if (!const [
        'application/pdf',
        'image/jpeg',
        'image/png',
        'image/webp',
        'text/plain',
      ].contains(widget.mimeType)) {
        throw const FormatException('Unsupported document type.');
      }
      if (widget.mimeType == 'text/plain') utf8.decode(bytes);
      setState(() {
        _bytes = bytes;
        // Keep the renderer callback stable while share controls update.
        _pdfBuilder = (_) async => bytes;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration && !_revoked) {
        setState(
          () => _error = error is DocumentOpenException
              ? error.message
              : 'Could not open this document. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _share() async {
    final bytes = _bytes;
    if (bytes == null || _sharing || !_sameWorkspace) return;
    setState(() => _sharing = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: widget.mimeType,
              name: widget.fileName,
            ),
          ],
          fileNameOverrides: [widget.fileName],
          subject: widget.title,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (_sameWorkspace) {
        setState(() => _error = 'Could not share this copy. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _bytes = null;
    _pdfBuilder = null;
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceIdProvider, (_, next) {
      if (next.hasValue && next.value != widget.workspaceId) _revoke();
    });
    final workspace = ref.watch(workspaceIdProvider);
    final canDisplay =
        !_revoked &&
        _sameAccount &&
        !workspace.isLoading &&
        !workspace.hasError &&
        workspace.value == widget.workspaceId;
    final bytes = canDisplay ? _bytes : null;
    return Scaffold(
      body: WorkloopAppCanvas(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  12,
                  AppSpacing.pageX,
                  12,
                ),
                child: WorkloopRouteHeader(
                  title: canDisplay ? widget.title : 'Document',
                  trailing: bytes == null
                      ? null
                      : TextButton.icon(
                          onPressed: _sharing ? null : _share,
                          icon: const Icon(Icons.ios_share_outlined, size: 18),
                          label: Text(_sharing ? 'Sharing…' : 'Share'),
                        ),
                ),
              ),
              if (_revoked || (!_sameAccount && !_loading))
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.pageX),
                      child: Text(
                        'Your account changed. Close this document and reopen it from your current business.',
                      ),
                    ),
                  ),
                )
              else if (workspace.hasError)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.pageX),
                      child: SlateErrorState(
                        message: 'Could not confirm your business. Try again.',
                        onRetry: () => ref.invalidate(workspaceIdProvider),
                      ),
                    ),
                  ),
                )
              else if (_loading || !canDisplay)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (bytes == null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.pageX),
                      child: SlateErrorState(
                        message: _error ?? 'Could not open this document.',
                        onRetry: _load,
                      ),
                    ),
                  ),
                )
              else ...[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageX,
                    ),
                    child: Text(_error!),
                  ),
                Expanded(child: _document(bytes)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _document(Uint8List bytes) {
    if (widget.mimeType == 'text/plain') {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pageX),
        child: SizedBox(
          width: double.infinity,
          child: SelectableText(utf8.decode(bytes)),
        ),
      );
    }
    if (widget.mimeType.startsWith('image/')) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pageX),
        child: WorkloopDocumentImage(
          image: MemoryImage(bytes),
          label: widget.title == 'Receipt' ? 'Receipt image' : widget.fileName,
        ),
      );
    }
    return PdfPreview.builder(
      key: ValueKey(_loadGeneration),
      build: _pdfBuilder!,
      allowPrinting: false,
      allowSharing: false,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      dynamicLayout: false,
      dpi: 144,
      scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
      loadingWidget: const Center(child: CircularProgressIndicator()),
      onError: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageX),
          child: SlateErrorState(
            message: 'Could not display this PDF. Try again or share a copy.',
            onRetry: _load,
          ),
        ),
      ),
      pagesBuilder: (_, pages) => ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.pageX),
        itemCount: pages.length,
        itemBuilder: (_, index) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Page ${index + 1} of ${pages.length}'),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: pages[index].aspectRatio,
                child: WorkloopDocumentImage(
                  image: pages[index].image,
                  label: 'Page ${index + 1}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same accessible zoom controls serve receipt images and PDF pages.
class WorkloopDocumentImage extends StatefulWidget {
  final ImageProvider image;
  final String label;
  const WorkloopDocumentImage({
    super.key,
    required this.image,
    required this.label,
  });
  @override
  State<WorkloopDocumentImage> createState() => _WorkloopDocumentImageState();
}

class _WorkloopDocumentImageState extends State<WorkloopDocumentImage> {
  final _transform = TransformationController();
  double _scale = 1;

  void _zoom(double scale) {
    setState(() {
      _scale = scale.clamp(1, 5);
      _transform.value = Matrix4.diagonal3Values(_scale, _scale, 1);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    widget.image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ClipRect(
          child: ColoredBox(
            color: Colors.white,
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              panEnabled: _scale > 1,
              onInteractionUpdate: (_) =>
                  setState(() => _scale = _transform.value.getMaxScaleOnAxis()),
              child: Center(
                child: Image(
                  image: widget.image,
                  fit: BoxFit.contain,
                  semanticLabel: widget.label,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Could not display this image.'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Zoom out ${widget.label}',
            onPressed: _scale <= 1 ? null : () => _zoom(_scale / 1.5),
            icon: const Icon(Icons.zoom_out),
          ),
          TextButton(onPressed: () => _zoom(1), child: const Text('Fit')),
          IconButton(
            tooltip: 'Zoom in ${widget.label}',
            onPressed: _scale >= 5 ? null : () => _zoom(_scale * 1.5),
            icon: const Icon(Icons.zoom_in),
          ),
        ],
      ),
    ],
  );
}
