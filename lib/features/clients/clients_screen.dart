import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/widgets/slate_ui.dart';
import '../imports/contacts_import_screen.dart';
import 'add_client_screen.dart';
import 'client_detail_screen.dart';
import 'client_sort.dart';
import 'client_view.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';
  ClientView _view = ClientView.all;
  ClientSortOrder _sortOrder = ClientSortOrder.nextBooking;
  Offset? _lastPointerPosition;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshClients() async {
    ref.invalidate(clientsProvider);
    ref.invalidate(appointmentsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(allTasksProvider);
    ref.invalidate(clientCrmRecordsProvider);
    try {
      await ref.read(clientCrmRecordsProvider.future);
    } catch (_) {
      // Keep refresh errors in the list's existing retry state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(clientCrmRecordsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            bottom: false,
            child: records.when(
              loading: () => const _ClientsLoading(),
              error: (_, _) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  AppSpacing.screenTop,
                  AppSpacing.pageX,
                  AppSpacing.pageX,
                ),
                child: SlateErrorState(
                  message: 'Could not load clients. Check your connection.',
                  onRetry: () {
                    ref.invalidate(clientsProvider);
                    ref.invalidate(clientCrmRecordsProvider);
                  },
                ),
              ),
              data: (data) {
                final filtered = _filterAndSort(data);
                return Listener(
                  onPointerDown: (event) =>
                      _lastPointerPosition = event.position,
                  child: RefreshIndicator(
                    color: AppColors.of(context).accentPrimary,
                    onRefresh: _refreshClients,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageX,
                              AppSpacing.screenTop,
                              AppSpacing.pageX,
                              0,
                            ),
                            child: Column(
                              children: [
                                _Header(onAdd: _openAddClient),
                                if (data.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  _SearchAndSort(
                                    controller: _searchController,
                                    onQueryChanged: (value) =>
                                        setState(() => _query = value.trim()),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (data.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.pageX,
                                AppSpacing.sm,
                                AppSpacing.pageX,
                                0,
                              ),
                              child: _ViewRail(
                                selected: _view,
                                records: data,
                                onChanged: _changeView,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.pageX,
                                AppSpacing.xs,
                                AppSpacing.pageX,
                                0,
                              ),
                              child: _SortToolbar(
                                resultCount: filtered.length,
                                sortOrder: _sortOrder,
                                onSort: _showSortPicker,
                              ),
                            ),
                          ),
                        ],
                        if (data.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(onImport: _openContactsImport),
                          )
                        else if (filtered.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _NoMatches(
                              view: _view,
                              hasQuery: _query.isNotEmpty,
                            ),
                          )
                        else
                          SliverList.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox.shrink(),
                            itemBuilder: (context, index) {
                              final record = filtered[index];
                              return Padding(
                                padding: EdgeInsets.fromLTRB(
                                  AppSpacing.pageX,
                                  index == 0 ? AppSpacing.xs : 0,
                                  AppSpacing.pageX,
                                  index == filtered.length - 1
                                      ? AppSpacing.shellBottomClearance(context)
                                      : 0,
                                ),
                                child: _ClientRow(
                                  record: record,
                                  showInactive:
                                      _view == ClientView.all &&
                                      record.isInactive,
                                  onTap: () {
                                    if (_returnToTopFromClientRow()) return;
                                    _openClient(record);
                                  },
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ClientCrmRecord> _filterAndSort(List<ClientCrmRecord> data) {
    final query = _query.toLowerCase();
    final filtered = data.where((record) {
      final client = record.client;
      final matchesQuery =
          query.isEmpty ||
          client.name.toLowerCase().contains(query) ||
          (client.phone ?? '').toLowerCase().contains(query) ||
          (client.email ?? '').toLowerCase().contains(query) ||
          client.tags.any((tag) => tag.toLowerCase().contains(query));

      final matchesView = clientStatusMatchesView(
        status: client.status,
        view: _view,
      );
      return matchesQuery && matchesView;
    }).toList();

    return sortClientRecords(filtered, _sortOrder);
  }

  void _changeView(ClientView view) {
    if (view == _view) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _view = view);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(0);
        return;
      }
      _scrollController.animateTo(
        0,
        duration: AppMotion.standard,
        curve: AppMotion.curve,
      );
    });
  }

  bool _returnToTopFromClientRow() {
    final position = _lastPointerPosition;
    if (position == null ||
        !_scrollController.hasClients ||
        _scrollController.offset <=
            _scrollController.position.minScrollExtent + 0.5) {
      return false;
    }
    final topExtent = MediaQuery.paddingOf(context).top + 72;
    if (position.dy > topExtent) return false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
      return true;
    }
    _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: AppMotion.standard,
      curve: AppMotion.curve,
    );
    return true;
  }

  Future<void> _showSortPicker() async {
    final selected = await showWorkloopBottomSheet<ClientSortOrder>(
      context: context,
      builder: (context) => _ClientSortSheet(selected: _sortOrder),
    );
    if (selected != null && mounted) {
      setState(() => _sortOrder = selected);
    }
  }

  Future<void> _openAddClient() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddClientScreen()),
    );
    if (!mounted) return;
    ref.invalidate(clientsProvider);
    ref.invalidate(clientCrmRecordsProvider);
  }

  Future<void> _openContactsImport() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ContactsImportScreen()),
    );
    if (!mounted) return;
    ref.invalidate(clientsProvider);
    ref.invalidate(clientCrmRecordsProvider);
  }

  Future<void> _openClient(ClientCrmRecord record) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientDetailScreen(client: record.client.toMap()),
      ),
    );
    if (!mounted) return;
    ref.invalidate(clientsProvider);
    ref.invalidate(clientCrmRecordsProvider);
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onAdd;

  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkloopPageHeader(
          title: 'Clients',
          subtitle: 'Know who needs attention next.',
          color: AppColors.of(context).modClients,
          trailing: WorkloopTopAction(
            label: 'New client',
            semanticLabel: 'New client',
            onTap: onAdd,
          ),
        ),
      ],
    );
  }
}

class _SearchAndSort extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;

  const _SearchAndSort({
    required this.controller,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopSearchField(
      controller: controller,
      onChanged: onQueryChanged,
      hintText: 'Search clients or tags',
      semanticLabel: 'Search clients or tags',
    );
  }
}

class _SortToolbar extends StatelessWidget {
  final int resultCount;
  final ClientSortOrder sortOrder;
  final VoidCallback onSort;

  const _SortToolbar({
    required this.resultCount,
    required this.sortOrder,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final countLabel = resultCount == 1 ? '1 client' : '$resultCount clients';
    return Row(
      children: [
        Expanded(
          child: Text(
            countLabel,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              SlateHaptics.tap();
              onSort();
            },
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: tokens.dividerStrong.withValues(alpha: 0.82),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.arrowUpDown,
                    size: 14,
                    color: tokens.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    sortOrder.label,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ClientSortSheet extends StatelessWidget {
  final ClientSortOrder selected;

  const _ClientSortSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    return SlateSheetFrame(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sort clients',
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose how clients are ordered.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final order in ClientSortOrder.values)
            _ClientSortOption(
              order: order,
              selected: order == selected,
              showDivider: order != ClientSortOrder.values.last,
              onTap: () => Navigator.pop(context, order),
            ),
        ],
      ),
    );
  }
}

class _ClientSortOption extends StatelessWidget {
  final ClientSortOrder order;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  const _ClientSortOption({
    required this.order,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: selected
                ? AppColors.of(context).accentPrimary.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.label,
                          style: TextStyle(
                            color: AppColors.of(context).t1,
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: AppMotion.responsive(context, AppMotion.fast),
                        opacity: selected ? 1 : 0,
                        child: Icon(
                          LucideIcons.check,
                          color: AppColors.of(context).modHome,
                          size: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              indent: AppSpacing.sm,
              endIndent: AppSpacing.sm,
              color: AppColors.of(context).border,
            ),
        ],
      ),
    );
  }
}

class _ViewRail extends StatelessWidget {
  final ClientView selected;
  final List<ClientCrmRecord> records;
  final ValueChanged<ClientView> onChanged;

  const _ViewRail({
    required this.selected,
    required this.records,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopNavigationControl<ClientView>(
      selected: selected,
      onChanged: onChanged,
      segments: [
        WorkloopSegment(
          value: ClientView.all,
          label: 'All',
          badge: '${records.length}',
        ),
        WorkloopSegment(
          value: ClientView.active,
          label: 'Active',
          badge: '${records.where((item) => item.isActive).length}',
        ),
        WorkloopSegment(
          value: ClientView.leads,
          label: 'Leads',
          badge: '${records.where((item) => item.isLead).length}',
        ),
        WorkloopSegment(
          value: ClientView.inactive,
          label: 'Inactive',
          badge: '${records.where((item) => item.isInactive).length}',
        ),
      ],
    );
  }
}

class _ClientRow extends StatelessWidget {
  final ClientCrmRecord record;
  final bool showInactive;
  final VoidCallback onTap;

  const _ClientRow({
    required this.record,
    required this.showInactive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final client = record.client;
    final initials = client.name
        .trim()
        .split(RegExp(r'\s+'))
        .map((word) => word.isEmpty ? '' : word[0])
        .take(2)
        .join()
        .toUpperCase();
    final signal = _clientSignal(record);

    return WorkloopListRow(
      onTap: onTap,
      flat: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.md,
      ),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.of(context).modClients.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: TextStyle(
              color: AppColors.of(context).t1,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      title: Text(
        client.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        signal,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.of(context).t2,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showInactive) ...[
            Text(
              'Inactive',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Icon(
            LucideIcons.chevronRight,
            color: AppColors.of(context).t3,
            size: 16,
          ),
        ],
      ),
    );
  }

  String _clientSignal(ClientCrmRecord record) {
    final next = record.nextBooking;
    if (next != null) return 'Next booking ${_friendlyDate(next.startTime)}';
    final last = record.lastBooking;
    if (last != null) {
      final days = DateTime.now().difference(last.startTime).inDays;
      if (days <= 0) return 'Last booking today';
      if (days == 1) return 'Last booking yesterday';
      return 'Last booking $days days ago';
    }
    if (record.client.tags.isNotEmpty) return record.client.tags.first;
    if (record.client.status == 'lead') return 'Lead';
    return 'No bookings yet';
  }
}

class _ClientsLoading extends StatelessWidget {
  const _ClientsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        AppSpacing.screenTop,
        AppSpacing.pageX,
        AppSpacing.shellBottomClearance(context),
      ),
      itemCount: 7,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, index) => SlateLoadingBlock(
        height: index == 0 ? 116 : 98,
        radius: AppRadius.xl,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WorkloopEmptyState(
              icon: LucideIcons.users,
              title: 'No clients yet',
              subtitle:
                  'Add the people you work with and keep their details in one place.',
            ),
            const SizedBox(height: AppSpacing.xs),
            WorkloopTextButton(
              label: 'Import selected contacts',
              onPressed: onImport,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  final ClientView view;
  final bool hasQuery;

  const _NoMatches({required this.view, required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = hasQuery
        ? (
            LucideIcons.searchX,
            'No matching clients',
            'Try a different name, contact detail, or tag.',
          )
        : switch (view) {
            ClientView.all => (
              LucideIcons.users,
              'No clients yet',
              'Add your first client to begin.',
            ),
            ClientView.active => (
              LucideIcons.userCheck,
              'No active clients',
              'Clients marked active will appear here.',
            ),
            ClientView.leads => (
              LucideIcons.userPlus,
              'No leads yet',
              'New prospects will appear here.',
            ),
            ClientView.inactive => (
              LucideIcons.userMinus,
              'No inactive clients',
              'Clients you pause will appear here.',
            ),
          };

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pageX,
          AppSpacing.xl,
          AppSpacing.pageX,
          AppSpacing.shellBottomClearance(context),
        ),
        child: WorkloopEmptyState(icon: icon, title: title, subtitle: subtitle),
      ),
    );
  }
}

String _friendlyDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  if (target == today) return 'today';
  if (target == today.add(const Duration(days: 1))) return 'tomorrow';
  return '${date.day}/${date.month}';
}
