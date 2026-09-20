import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/workloop_capabilities.dart';
import '../../../shared/documents/workloop_document_viewer.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import '../../../shared/models/slate_models.dart';
import '../../../shared/providers/business_documents_provider.dart';
import '../../../shared/providers/business_clock_provider.dart';
import '../../../shared/providers/clients_provider.dart';
import '../../../shared/providers/dashboard_provider.dart';
import '../../../shared/providers/finance_provider.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/providers/workspace_settings_provider.dart';
import '../../../shared/repositories/business_documents_repository.dart';
import '../../../shared/utils/workflow_idempotency.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../payment_collection_sheet.dart';
import 'business_document.dart';
import 'business_document_body.dart';
import 'business_document_editor_screen.dart';
import 'business_document_pdf.dart';

class BusinessDocumentDetailScreen extends ConsumerStatefulWidget {
  final String documentId;
  const BusinessDocumentDetailScreen({super.key, required this.documentId});
  @override
  ConsumerState<BusinessDocumentDetailScreen> createState() =>
      _DocumentDetailState();
}

class _DocumentDetailState extends ConsumerState<BusinessDocumentDetailScreen> {
  bool _busy = false;
  String? _error;

  bool _sameWorkspace(BusinessDocument document) {
    final workspace = ref.read(workspaceIdProvider);
    return !workspace.isLoading &&
        !workspace.hasError &&
        workspace.value == document.workspaceId;
  }

  void _refresh() {
    ref.invalidate(businessDocumentProvider(widget.documentId));
    ref.invalidate(businessDocumentsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(dashboardRevenueProvider);
    ref.invalidate(clientCrmRecordsProvider);
  }

  Future<BusinessDocument?> _action(
    BusinessDocument document,
    Future<BusinessDocument> Function() action,
  ) async {
    if (_busy || !_sameWorkspace(document)) {
      return null;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await action();
      if (!mounted || !_sameWorkspace(document)) {
        return null;
      }
      _refresh();
      return value;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PostgrestException && error.code == 'P0001'
              ? error.message
              : 'Could not complete that action. Refresh the document and try again.',
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String label) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(label),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _issue(BusinessDocument document) async {
    if (document.missingIssueDetails.isNotEmpty) {
      final edit = await _confirm(
        'Complete the ${document.title.toLowerCase()} details',
        'Add ${document.missingIssueDetails.join(', ')} before issuing.',
        'Edit draft',
      );
      if (edit && mounted) await _edit(document);
      return;
    }
    final yes = await _confirm(
      'Issue this ${document.title.toLowerCase()}?',
      'Check the customer, business details and amounts. Once issued, these details are fixed. ${document.isQuote ? 'You can then share it with the customer.' : 'The outstanding amount will appear in Money.'}',
      'Issue',
    );
    if (!yes || !mounted) return;
    await _action(
      document,
      () => ref.read(businessDocumentsRepositoryProvider).issue(document),
    );
  }

  Future<void> _edit(BusinessDocument document) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessDocumentEditorScreen(document: document),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _view(BusinessDocument document) async {
    if (_busy || !_sameWorkspace(document)) {
      return;
    }
    final repository = ref.read(businessDocumentsRepositoryProvider);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkloopDocumentViewerScreen(
          workspaceId: document.workspaceId,
          title: document.reference,
          fileName:
              '${document.reference.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '-')}.pdf',
          mimeType: 'application/pdf',
          loadBytes: () async => buildBusinessDocumentPdf(
            await repository.get(document.workspaceId, document.id),
          ),
        ),
      ),
    );
  }

  Future<void> _recordPayment(
    BusinessDocument document,
    Payment payment, {
    bool refund = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(workspaceSettingsProvider.future);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not load your business date. Try again.';
        });
      }
      return;
    }
    if (!mounted || !_sameWorkspace(document)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final today = ref.read(workspaceTodayProvider);
    final maximum =
        ((refund
                    ? (payment.collectedAmount - payment.stripeAmountPaid)
                          .clamp(0, payment.collectedAmount)
                    : payment.outstandingAmount) *
                100)
            .round();
    final controller = TextEditingController(
      text: documentMoneyInput(
        refund ? maximum : (payment.collectionAmount * 100).round(),
      ),
    );
    var date = DateTime(today.year, today.month, today.day);
    var submitted = false;
    final key = createWorkflowIdempotencyKey();
    String? error;
    bool saving = false;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: Text(
              refund
                  ? 'Record refund returned'
                  : payment.depositOutstandingAmount > 0
                  ? 'Record deposit received'
                  : 'Record payment received',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    refund
                        ? 'Only record a cash or bank refund you have already returned. Use Stripe to return card payments.'
                        : 'Record money you have already received by cash or bank transfer. Card payments update automatically.',
                  ),
                  const SizedBox(height: 16),
                  WorkloopFormField(
                    label: refund ? 'Amount returned' : 'Amount received',
                    isRequired: true,
                    child: TextField(
                      controller: controller,
                      enabled: !saving && !submitted,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(prefixText: '£ '),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: saving || submitted
                        ? null
                        : () async {
                            final chosen = await showWorkloopDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(
                                today.year,
                                today.month,
                                today.day,
                              ),
                            );
                            if (chosen != null && ctx.mounted) {
                              update(() => date = chosen);
                            }
                          },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${refund ? 'Returned' : 'Received'} ${documentDate(date)}',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Back'),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        final amount = parseDocumentMoney(controller.text);
                        if (amount == null || amount <= 0 || amount > maximum) {
                          update(
                            () => error =
                                'Enter an amount up to ${documentMoney(maximum)}.',
                          );
                          return;
                        }
                        if (ref.read(workspaceIdProvider).value !=
                            document.workspaceId) {
                          return;
                        }
                        update(() {
                          saving = true;
                          submitted = true;
                          error = null;
                        });
                        try {
                          await ref
                              .read(businessDocumentsRepositoryProvider)
                              .recordReceived(
                                document,
                                amount,
                                date,
                                key,
                                refund: refund,
                              );
                          if (mounted &&
                              ref.read(workspaceIdProvider).value ==
                                  document.workspaceId) {
                            _refresh();
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (_) {
                          if (ctx.mounted) {
                            update(() {
                              saving = false;
                              error =
                                  'Could not confirm this entry. Retry the same entry, or close and refresh to check the balance.';
                            });
                          }
                        }
                      },
                child: Text(
                  saving
                      ? 'Recording…'
                      : submitted
                      ? 'Retry same entry'
                      : refund
                      ? 'Record returned'
                      : 'Record received',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    // The dialog's text field remains mounted during its exit animation.
    await route.completed;
    if (mounted) setState(() => _busy = false);
    if (mounted &&
        submitted &&
        ref.read(workspaceIdProvider).value == document.workspaceId) {
      _refresh();
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(workspaceTodayProvider);
    final snapshot = ref.watch(businessDocumentProvider(widget.documentId));
    final workspace = ref.watch(workspaceIdProvider);
    final scopeReady =
        !workspace.isLoading &&
        !workspace.hasError &&
        workspace.value != null &&
        snapshot.value?.workspaceId == workspace.value;
    final payments = ref.watch(invoicesProvider);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.pageX),
                child: WorkloopRouteHeader(
                  title: scopeReady ? snapshot.value!.reference : 'Document',
                  onBack: _busy
                      ? () {}
                      : () => workloopGoBack(
                          context,
                          fallbackLocation: '/payments',
                        ),
                  trailing: IconButton(
                    tooltip: 'Refresh document',
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    4,
                    AppSpacing.pageX,
                    32,
                  ),
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_error!),
                      ),
                    snapshot.when(
                      skipLoadingOnRefresh: false,
                      loading: () => const SlateLoadingBlock(height: 220),
                      error: (_, _) => SlateErrorState(
                        message: 'Could not load this document.',
                        onRetry: _refresh,
                      ),
                      data: (document) {
                        if (!scopeReady) {
                          return SlateErrorState(
                            message:
                                'Could not confirm this document’s business. Try again.',
                            onRetry: () => ref.invalidate(workspaceIdProvider),
                          );
                        }
                        final repository = ref.read(
                          businessDocumentsRepositoryProvider,
                        );
                        Payment? payment;
                        for (final entry
                            in payments.isLoading || payments.hasError
                                ? <Payment>[]
                                : payments.value ?? <Payment>[]) {
                          if (entry.id == document.invoiceId) payment = entry;
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              document.customerName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${document.statusLabel(now: today)} · ${documentDate(document.issueDate)}',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              documentMoney(document.totalPence),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (payment != null &&
                                document.status != 'cancelled')
                              Text(
                                '${documentMoney((payment.collectedAmount * 100).round())} received · ${documentMoney((payment.outstandingAmount * 100).round())} outstanding',
                              ),
                            if (document.hasDeposit &&
                                document.status != 'cancelled') ...[
                              const SizedBox(height: 12),
                              Text(
                                '${documentMoney(document.depositPence)} deposit requested${document.depositDueDate == null ? '' : ' by ${documentDate(document.depositDueDate!)}'}',
                              ),
                              if (payment != null)
                                Text(
                                  payment.depositOutstandingAmount > 0
                                      ? '${documentMoney((payment.depositOutstandingAmount * 100).round())} deposit still to receive'
                                      : 'Deposit received · remaining balance ${documentMoney((payment.outstandingAmount * 100).round())}',
                                ),
                            ],
                            const SizedBox(height: 20),
                            if (document.invoiceId != null &&
                                payment == null &&
                                document.status != 'cancelled') ...[
                              Text(
                                payments.isLoading
                                    ? 'Loading payment balance…'
                                    : 'Payment balance unavailable. Refresh before collecting payment.',
                              ),
                              if (!payments.isLoading)
                                TextButton.icon(
                                  onPressed: _busy ? null : _refresh,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry payment balance'),
                                ),
                              const SizedBox(height: 12),
                            ],
                            if (document.isDraft) ...[
                              SlateButton(
                                label: 'Review / edit draft',
                                secondary: true,
                                onPressed: _busy ? null : () => _edit(document),
                              ),
                              const SizedBox(height: 12),
                              SlateButton(
                                label: 'Issue ${document.title.toLowerCase()}',
                                onPressed: _busy
                                    ? null
                                    : () => _issue(document),
                              ),
                              const SizedBox(height: 12),
                            ],
                            SlateButton(
                              label: document.isDraft
                                  ? 'View draft PDF'
                                  : 'View PDF',
                              secondary: true,
                              onPressed: _busy ? null : () => _view(document),
                            ),
                            if (document.isQuote &&
                                document.status == 'sent') ...[
                              const SizedBox(height: 12),
                              SlateButton(
                                label: 'Record customer acceptance',
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await _confirm(
                                              'Has the customer accepted?',
                                              document.statusLabel(
                                                        now: today,
                                                      ) ==
                                                      'Expired'
                                                  ? 'This quote has expired. Record acceptance only if you and the customer have agreed that its work, prices and terms still apply.'
                                                  : 'Only record acceptance after the customer has agreed to this quote.',
                                              'Record accepted',
                                            ) &&
                                            mounted) {
                                          await _action(
                                            document,
                                            () => repository.quoteStatus(
                                              document,
                                              'accepted',
                                            ),
                                          );
                                        }
                                      },
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await _confirm(
                                              'Record quote declined?',
                                              'This records the customer’s decision without sending a message.',
                                              'Record declined',
                                            ) &&
                                            mounted) {
                                          await _action(
                                            document,
                                            () => repository.quoteStatus(
                                              document,
                                              'declined',
                                            ),
                                          );
                                        }
                                      },
                                child: const Text('Record declined'),
                              ),
                            ],
                            if (document.isQuote &&
                                document.status == 'accepted') ...[
                              const SizedBox(height: 12),
                              SlateButton(
                                label: 'Create / open invoice',
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final invoice = await _action(
                                          document,
                                          () =>
                                              repository.convertQuote(document),
                                        );
                                        if (context.mounted &&
                                            invoice != null) {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  BusinessDocumentDetailScreen(
                                                    documentId: invoice.id,
                                                  ),
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ],
                            if (payment != null &&
                                payment.outstandingAmount > 0 &&
                                document.status != 'cancelled') ...[
                              const SizedBox(height: 12),
                              SlateButton(
                                label: payment.depositOutstandingAmount > 0
                                    ? 'Record deposit received'
                                    : 'Record payment received',
                                onPressed: _busy
                                    ? null
                                    : () => _recordPayment(document, payment!),
                              ),
                              if (ref.watch(
                                paymentCollectionEnabledProvider,
                              )) ...[
                                const SizedBox(height: 12),
                                SlateButton(
                                  label: payment.depositOutstandingAmount > 0
                                      ? 'Request deposit by card'
                                      : 'Collect card payment',
                                  secondary: true,
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await showPaymentCollectionSheet(
                                            context: context,
                                            payment: payment!,
                                          );
                                          if (mounted) _refresh();
                                        },
                                ),
                              ],
                            ],
                            if (payment != null &&
                                payment.collectedAmount >
                                    payment.stripeAmountPaid &&
                                document.status != 'cancelled')
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _recordPayment(
                                        document,
                                        payment!,
                                        refund: true,
                                      ),
                                child: const Text(
                                  'Record a cash / bank refund',
                                ),
                              ),
                            if (document.contactId != null ||
                                document.appointmentId != null ||
                                document.sourceQuoteId != null) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (document.contactId != null)
                                    TextButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => context.push(
                                              '/clients/${Uri.encodeComponent(document.contactId!)}',
                                            ),
                                      icon: const Icon(
                                        Icons.person_outline,
                                        size: 18,
                                      ),
                                      label: const Text('View client'),
                                    ),
                                  if (document.appointmentId != null)
                                    TextButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => context.push(
                                              '/bookings/${Uri.encodeComponent(document.appointmentId!)}',
                                            ),
                                      icon: const Icon(
                                        Icons.event_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('View booking'),
                                    ),
                                  if (document.sourceQuoteId != null)
                                    TextButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    BusinessDocumentDetailScreen(
                                                      documentId: document
                                                          .sourceQuoteId!,
                                                    ),
                                              ),
                                            ),
                                      icon: const Icon(
                                        Icons.description_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('View original quote'),
                                    ),
                                ],
                              ),
                            ],
                            BusinessDocumentBody(document: document),
                            if (payment != null &&
                                payment.cashReceipts.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              const Text(
                                'Payment history',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              ...([...payment.cashReceipts]..sort(
                                    (a, b) =>
                                        b.receivedAt.compareTo(a.receivedAt),
                                  ))
                                  .map(
                                    (receipt) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${receipt.amount < 0 ? 'Refund recorded' : 'Payment received'} · ${documentDate(receipt.receivedAt.toLocal())}',
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            documentMoney(
                                              (receipt.amount * 100).round(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final copy =
                                          await Navigator.push<
                                            BusinessDocument
                                          >(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  BusinessDocumentEditorScreen(
                                                    copyFrom: document,
                                                  ),
                                            ),
                                          );
                                      if (mounted && copy != null) {
                                        _refresh();
                                        if (context.mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  BusinessDocumentDetailScreen(
                                                    documentId: copy.id,
                                                  ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                              child: const Text('Copy to a new draft'),
                            ),
                            if (document.isDraft)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (!await _confirm(
                                              'Delete this draft?',
                                              'This draft has not been issued.',
                                              'Delete draft',
                                            ) ||
                                            !mounted) {
                                          return;
                                        }
                                        await _action(document, () async {
                                          await repository.deleteDraft(
                                            document,
                                          );
                                          return document;
                                        });
                                        if (context.mounted && _error == null) {
                                          Navigator.pop(context);
                                        }
                                      },
                                child: const Text('Delete draft'),
                              ),
                            if (!document.isDraft &&
                                ![
                                  'cancelled',
                                  'paid',
                                ].contains(document.status))
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await _confirm(
                                              'Cancel this ${document.title.toLowerCase()}?',
                                              'The issued document will be retained. An invoice can only be cancelled when no payment or active card collection exists.',
                                              'Cancel document',
                                            ) &&
                                            mounted) {
                                          await _action(
                                            document,
                                            () => repository.cancel(document),
                                          );
                                        }
                                      },
                                child: const Text('Cancel document'),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
