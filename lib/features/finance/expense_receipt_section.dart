import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/documents/workloop_document_viewer.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../core/theme/app_theme.dart';
import 'receipt_capture_service.dart';

import 'expense_records_repository.dart';
import 'widgets/money_editor_widgets.dart';

Future<ReceiptFile?> pickExpenseReceipt() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    withData: true,
  );
  if (result == null) return null;
  final file = result.files.single;
  if (file.size > receiptMaxBytes || file.bytes == null) {
    throw const FormatException(
      'Choose a JPEG, PNG or PDF receipt up to 10 MB.',
    );
  }
  return ReceiptFile.checked(file.name, file.bytes!);
}

final expenseReceiptPickerProvider = Provider<Future<ReceiptFile?> Function()>(
  (ref) => pickExpenseReceipt,
);

class ExpenseReceiptSection extends ConsumerStatefulWidget {
  final String? expenseId;
  final ReceiptFile? pending;
  final ValueChanged<ReceiptFile?> onChanged;
  final ValueChanged<bool>? onPickingChanged;
  final bool reading;
  final VoidCallback? onReadDetails;
  final VoidCallback? onCancelReading;
  final bool busy;
  const ExpenseReceiptSection({
    super.key,
    this.expenseId,
    this.pending,
    required this.onChanged,
    this.onPickingChanged,
    this.reading = false,
    this.onReadDetails,
    this.onCancelReading,
    this.busy = false,
  });

  @override
  ConsumerState<ExpenseReceiptSection> createState() =>
      _ExpenseReceiptSectionState();
}

class _ExpenseReceiptSectionState extends ConsumerState<ExpenseReceiptSection> {
  bool _picking = true;
  String? get expenseId => widget.expenseId;
  ReceiptFile? get pending => widget.pending;
  bool get busy => widget.busy || _picking || _activeWorkspaceId == null;
  ValueChanged<ReceiptFile?> get onChanged => widget.onChanged;
  String? get _activeWorkspaceId {
    final workspace = ref.read(workspaceIdProvider);
    return workspace.isLoading || workspace.hasError ? null : workspace.value;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkInterruptedCapture(),
    );
  }

  Future<void> _checkInterruptedCapture() async {
    if (!mounted) return;
    widget.onPickingChanged?.call(true);
    try {
      final interrupted = await ref
          .read(receiptCaptureServiceProvider)
          .discardUnscopedRecovery();
      if (interrupted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The previous receipt capture was interrupted. Take or choose the photo again so it attaches to the correct expense.',
            ),
          ),
        );
      }
    } catch (_) {
      // Retrieval never opens permissions and must not prevent a fresh choice.
    } finally {
      if (mounted) _setPicking(false);
    }
  }

  void _setPicking(bool picking) {
    setState(() => _picking = picking);
    widget.onPickingChanged?.call(picking);
  }

  Future<void> _pick() async {
    if (busy) return;
    final workspace = _activeWorkspaceId;
    if (workspace == null) return;
    _setPicking(true);
    try {
      final source = await showWorkloopBottomSheet<ReceiptCaptureSource>(
        context: context,
        builder: (sheetContext) => SlateSheetFrame(
          scrollable: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add a receipt',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Keep the whole receipt readable. Photos are saved as high-quality copies, up to 10 MB.',
              ),
              const SizedBox(height: AppSpacing.md),
              for (final option in const [
                (
                  ReceiptCaptureSource.camera,
                  Icons.camera_alt_outlined,
                  'Take photo',
                  'Photograph the receipt now',
                ),
                (
                  ReceiptCaptureSource.photos,
                  Icons.photo_library_outlined,
                  'Photo library',
                  'Choose a receipt photo on your phone',
                ),
                (
                  ReceiptCaptureSource.file,
                  Icons.attach_file,
                  'Choose file',
                  'Attach a JPEG, PNG or PDF from Files',
                ),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(option.$2),
                  title: Text(option.$3),
                  subtitle: Text(option.$4),
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                ),
            ],
          ),
        ),
      );
      if (source == null || !mounted || _activeWorkspaceId != workspace) {
        return;
      }
      final file = source == ReceiptCaptureSource.file
          ? await ref.read(expenseReceiptPickerProvider)()
          : await ref.read(receiptCaptureServiceProvider).pick(source);
      if (file != null && mounted && _activeWorkspaceId == workspace) {
        onChanged(file);
      }
    } catch (error) {
      if (mounted && _activeWorkspaceId == workspace) {
        _error(context, error);
      }
    } finally {
      if (mounted) _setPicking(false);
    }
  }

  static void _error(BuildContext context, Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ReceiptCaptureException
                ? error.message
                : error is FormatException
                ? error.message
                : 'Could not open this receipt. Try again.',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceIdProvider);
    return MoneyFormSection(
      title: 'Receipt',
      isRequired: false,
      subtitle:
          'Take a photo, choose from your library, or attach a PDF, up to 10 MB. We will suggest details for you to check before using them. Keep the supplier, date, items and total readable.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expenseId != null)
            ref
                .watch(expenseReceiptsProvider(expenseId!))
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => TextButton(
                    onPressed: () =>
                        ref.invalidate(expenseReceiptsProvider(expenseId!)),
                    child: const Text('Receipts unavailable · retry'),
                  ),
                  data: (receipts) => Column(
                    children: receipts
                        .map(
                          (receipt) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(receipt.name),
                            subtitle: Text(
                              '${receipt.mimeType == 'application/pdf' ? 'PDF' : 'Photo'}'
                              '${receipt.sizeBytes == null ? '' : ' · ${(receipt.sizeBytes! / 1024).ceil()} KB'} · Tap to view receipt',
                            ),
                            onTap: busy
                                ? null
                                : () async {
                                    try {
                                      final workspace = ref
                                          .read(workspaceIdProvider)
                                          .value;
                                      if (workspace == null ||
                                          !receipt.path.startsWith(
                                            '$workspace/',
                                          )) {
                                        return;
                                      }
                                      final repository = ref.read(
                                        expenseRecordsRepositoryProvider,
                                      );
                                      await Navigator.push<void>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              WorkloopDocumentViewerScreen(
                                                workspaceId: workspace,
                                                title: 'Receipt',
                                                fileName: receipt.name,
                                                mimeType: receipt.mimeType,
                                                loadBytes: () => repository
                                                    .download(receipt),
                                              ),
                                        ),
                                      );
                                    } catch (error) {
                                      if (context.mounted) {
                                        _error(context, error);
                                      }
                                    }
                                  },
                            trailing: IconButton(
                              tooltip: 'Remove receipt',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: busy
                                  ? null
                                  : () async {
                                      final workspace = ref
                                          .read(workspaceIdProvider)
                                          .value;
                                      if (workspace == null ||
                                          !receipt.path.startsWith(
                                            '$workspace/',
                                          )) {
                                        return;
                                      }
                                      final remove = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Remove receipt?'),
                                          content: const Text(
                                            'The expense will remain. The receipt file will be deleted.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Keep'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (remove != true ||
                                          !context.mounted ||
                                          ref.read(workspaceIdProvider).value !=
                                              workspace) {
                                        return;
                                      }
                                      try {
                                        await ref
                                            .read(
                                              expenseRecordsRepositoryProvider,
                                            )
                                            .removeReceipt(receipt);
                                        ref.invalidate(
                                          expenseReceiptsProvider(expenseId!),
                                        );
                                      } catch (error) {
                                        if (context.mounted) {
                                          _error(context, error);
                                        }
                                      }
                                    },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
          if (pending != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(pending!.name),
              subtitle: const Text('Saved copy · attaches when you save'),
              trailing: IconButton(
                tooltip: 'Discard attachment',
                onPressed: busy ? null : () => onChanged(null),
                icon: const Icon(Icons.close),
              ),
            ),
          if (pending != null && widget.reading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
            const Text('Reading receipt on your device…'),
            TextButton(
              onPressed: widget.onCancelReading,
              child: const Text('Enter details manually'),
            ),
          ] else if (pending != null && widget.onReadDetails != null)
            TextButton.icon(
              onPressed: busy ? null : widget.onReadDetails,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Read receipt details'),
            ),
          TextButton.icon(
            onPressed: busy ? null : _pick,
            icon: const Icon(Icons.attach_file),
            label: Text(
              pending == null
                  ? 'Attach receipt photo or PDF'
                  : 'Choose another receipt',
            ),
          ),
        ],
      ),
    );
  }
}
