import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/business_documents_provider.dart';
import '../../../shared/providers/business_clock_provider.dart';
import '../../../shared/providers/business_document_defaults_provider.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../settings/business_document_settings_screen.dart';
import 'business_document.dart';
import 'business_document_detail_screen.dart';
import 'business_document_editor_screen.dart';

class BusinessDocumentsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final int createRequest;
  final String? initialClientId;
  const BusinessDocumentsScreen({
    super.key,
    this.embedded = false,
    this.createRequest = 0,
    this.initialClientId,
  });
  @override
  ConsumerState<BusinessDocumentsScreen> createState() =>
      _BusinessDocumentsState();
}

class _BusinessDocumentsState extends ConsumerState<BusinessDocumentsScreen> {
  String _type = 'invoice';
  String _filter = 'all';
  String _query = '';

  @override
  void didUpdateWidget(covariant BusinessDocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.createRequest != oldWidget.createRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _create();
      });
    }
  }

  Future<void> _create() async {
    final result = await Navigator.push<BusinessDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessDocumentEditorScreen(
          type: _type,
          initialClientId: widget.initialClientId,
        ),
      ),
    );
    if (mounted && result != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDocumentDetailScreen(documentId: result.id),
        ),
      );
    }
  }

  bool _matches(BusinessDocument doc, DateTime today) {
    if (doc.type != _type ||
        (widget.initialClientId != null &&
            doc.contactId != widget.initialClientId)) {
      return false;
    }
    final label = doc.statusLabel(now: today);
    if (_filter == 'draft' && !doc.isDraft) return false;
    if (_filter == 'open' &&
        (doc.isDraft ||
            ['Paid', 'Cancelled', 'Accepted', 'Declined'].contains(label))) {
      return false;
    }
    if (_filter == 'closed' &&
        !['Paid', 'Cancelled', 'Accepted', 'Declined'].contains(label)) {
      return false;
    }
    final text = '${doc.customerName} ${doc.reference} ${doc.notes} $label'
        .toLowerCase();
    return _query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(businessDocumentsProvider);
    final today = ref.watch(workspaceTodayProvider);
    final defaults = ref.watch(businessDocumentDefaultsProvider).value;
    final content = <Widget>[
      if (!widget.embedded)
        WorkloopRouteHeader(
          title: 'Invoices & quotes',
          onBack: () => Navigator.pop(context),
          trailing: WorkloopTopAction(label: 'Create', onTap: _create),
        ),
      if (!widget.embedded) const SizedBox(height: 20),
      if (widget.embedded)
        Row(
          children: [
            const Expanded(
              child: Text(
                'Invoices & quotes',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BusinessDocumentSettingsScreen(),
            ),
          ),
          icon: const Icon(Icons.business_outlined, size: 18),
          label: const Text('Invoice setup'),
        ),
      ),
      if (defaults != null && !defaults.isReady)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Before your first invoice, add ${defaults.missingDetails.join(', ')} in Invoice setup.',
          ),
        ),
      const SizedBox(height: 12),
      WorkloopNavigationControl<String>(
        selected: _type,
        segments: const [
          WorkloopSegment(value: 'invoice', label: 'Invoices'),
          WorkloopSegment(value: 'quote', label: 'Quotes'),
        ],
        onChanged: (value) => setState(() {
          _type = value;
          _filter = 'all';
        }),
      ),
      const SizedBox(height: 16),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Find a customer or reference',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final option in [
            ('all', 'All'),
            ('draft', 'Drafts'),
            ('open', _type == 'quote' ? 'Awaiting decision' : 'To collect'),
            ('closed', _type == 'quote' ? 'Decided' : 'Paid / cancelled'),
          ])
            ChoiceChip(
              label: Text(option.$2),
              selected: _filter == option.$1,
              onSelected: (_) => setState(() => _filter = option.$1),
            ),
        ],
      ),
      const SizedBox(height: 16),
      documents.when(
        loading: () => const SlateLoadingBlock(height: 160),
        error: (_, _) => SlateErrorState(
          message:
              'Could not load documents. Check your connection and try again.',
          onRetry: () => ref.invalidate(businessDocumentsProvider),
        ),
        data: (all) {
          final records = all.where((doc) => _matches(doc, today)).toList();
          if (records.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _query.isNotEmpty || _filter != 'all'
                        ? 'No matching documents'
                        : _type == 'quote'
                        ? 'Agree the work and price'
                        : 'Send an invoice and track what is paid',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _type == 'quote'
                        ? 'Quote the work, record the customer’s decision, then reuse it for their invoice.'
                        : 'Request a deposit if needed. Each issued invoice shares one balance with Money.',
                  ),
                  const SizedBox(height: 20),
                  SlateButton(
                    label: _type == 'quote' ? 'Create quote' : 'Create invoice',
                    onPressed: _create,
                  ),
                ],
              ),
            );
          }
          return Column(
            children: records
                .map(
                  (doc) => Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          doc.customerName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${doc.reference} · ${doc.statusLabel(now: today)}\n${documentDate(doc.issueDate)}${doc.hasDeposit ? ' · Deposit ${documentMoney(doc.depositPence)}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Text(documentMoney(doc.totalPence)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BusinessDocumentDetailScreen(
                              documentId: doc.id,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                )
                .toList(),
          );
        },
      ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: content,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(businessDocumentsProvider);
            await ref.read(businessDocumentsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.pageX),
            physics: const AlwaysScrollableScrollPhysics(),
            children: content,
          ),
        ),
      ),
    );
  }
}
