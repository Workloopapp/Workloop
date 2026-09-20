import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/workloop_capabilities.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/business_documents_provider.dart';
import '../../shared/providers/business_clock_provider.dart';
import '../../shared/providers/dashboard_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_settings_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/currency_format.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/income_target_indicator.dart';
import '../../shared/widgets/record_link_unavailable.dart';
import '../../shared/widgets/workloop_studio_graphics.dart';
import 'add_payment_screen.dart';
import 'documents/business_document.dart';
import 'documents/business_document_editor_screen.dart';
import 'documents/business_document_detail_screen.dart';
import 'documents/business_documents_screen.dart';
import 'mileage_screen.dart';
import 'expense_editor_screen.dart';
import 'payment_collection_sheet.dart';
import 'money_profit.dart';
import 'money_timeline.dart';
import 'widgets/money_timeline_widgets.dart';
import 'widgets/money_summary_widgets.dart';
import 'widgets/monthly_target_editor.dart';
import 'widgets/payment_cards.dart';

part 'finance_screen_widgets.dart';

enum FinanceInitialFocus { top, followUps }

enum MoneySection { made, documents, spent, owed }

class FinanceScreen extends ConsumerStatefulWidget {
  final FinanceInitialFocus initialFocus;
  final int createRequest;
  final DateTime? referenceDate;
  final String? initialPaymentId;
  final bool showBackButton;

  const FinanceScreen({
    super.key,
    this.initialFocus = FinanceInitialFocus.top,
    this.createRequest = 0,
    this.referenceDate,
    this.initialPaymentId,
    this.showBackButton = false,
  });

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  static const _recentHistoryLimit = 5;
  static const _searchHistoryLimit = 25;

  MoneySection _section = MoneySection.made;
  FinancePeriod _period = FinancePeriod.week;
  int _documentCreateRequest = 0;
  bool _showAllIncome = false;
  bool _showAllExpenses = false;
  bool _showHistory = false;
  bool _showTrend = false;
  bool _showCategories = false;
  MoneyTimelineFilter _timelineFilter = MoneyTimelineFilter.all;
  final _paymentsSearch = TextEditingController();
  final _expensesSearch = TextEditingController();
  final _owedSearch = TextEditingController();
  DateTime? _customStart;
  DateTime? _customEnd;
  final _scrollController = ScrollController();
  final _followUpsKey = GlobalKey();
  final _timelineKey = GlobalKey();
  bool _didApplyInitialFocus = false;
  bool _didHandleInitialPayment = false;
  String? _scheduledInitialId;
  bool _initialRecordMissing = false;

  DateTime get _now => widget.referenceDate ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.initialFocus == FinanceInitialFocus.followUps) {
      _section = MoneySection.owed;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialFocus());
    if (widget.createRequest != 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openRequestedCreateFlow(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant FinanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPaymentId != oldWidget.initialPaymentId) {
      _didHandleInitialPayment = false;
      _scheduledInitialId = null;
      _initialRecordMissing = false;
    }
    if (widget.initialFocus != oldWidget.initialFocus &&
        widget.initialFocus == FinanceInitialFocus.followUps) {
      _didApplyInitialFocus = false;
      _section = MoneySection.owed;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialFocus());
    }
    if (widget.createRequest != oldWidget.createRequest &&
        widget.createRequest != 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openRequestedCreateFlow(),
      );
    }
  }

  @override
  void dispose() {
    _paymentsSearch.dispose();
    _expensesSearch.dispose();
    _owedSearch.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyInitialFocus() {
    if (!mounted ||
        _didApplyInitialFocus ||
        widget.initialFocus != FinanceInitialFocus.followUps) {
      return;
    }
    final targetContext = _followUpsKey.currentContext;
    if (targetContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialFocus());
      return;
    }
    _didApplyInitialFocus = true;
    Scrollable.ensureVisible(
      targetContext,
      duration: AppMotion.responsive(context, AppMotion.standard),
      curve: AppMotion.curve,
      alignment: 0.08,
    );
  }

  void _openRequestedCreateFlow() {
    if (!mounted) return;
    _showMoneyCreateSheet(context);
  }

  void _openInitialPayment(List<Payment> records) {
    final id = widget.initialPaymentId?.trim();
    final snapshot = ref.read(invoicesProvider);
    final workspace = ref.read(workspaceIdProvider);
    if (_didHandleInitialPayment ||
        id == null ||
        id.isEmpty ||
        _scheduledInitialId == id ||
        snapshot.isLoading ||
        snapshot.hasError ||
        !snapshot.hasValue ||
        workspace.isLoading ||
        workspace.hasError ||
        workspace.value == null) {
      return;
    }
    final workspaceId = workspace.value;
    _scheduledInitialId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _scheduledInitialId != id ||
          widget.initialPaymentId?.trim() != id) {
        return;
      }
      _scheduledInitialId = null;
      final current = ref.read(invoicesProvider);
      final currentWorkspace = ref.read(workspaceIdProvider);
      if (current.isLoading ||
          current.hasError ||
          !current.hasValue ||
          currentWorkspace.isLoading ||
          currentWorkspace.hasError ||
          currentWorkspace.value != workspaceId) {
        return;
      }
      Payment? match;
      for (final record in current.value ?? <Payment>[]) {
        if (record.id == id) {
          match = record;
          break;
        }
      }
      _didHandleInitialPayment = true;
      if (match == null) {
        setState(() => _initialRecordMissing = true);
      } else {
        _showPaymentActionsSheet(context, match);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showPaymentSetup(String workspaceId) async {
    final action = await showPaymentSetupSheet(
      context: context,
      workspaceId: workspaceId,
    );
    if (!mounted || action != PaymentSetupAction.viewOwed) return;
    SlateHaptics.action();
    setState(() => _section = MoneySection.owed);
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: AppMotion.responsive(context, AppMotion.standard),
        curve: AppMotion.curve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Refresh the current-month goal when a retained Money tab crosses midnight.
    ref.watch(businessTodayProvider);
    if (widget.initialPaymentId != null) ref.watch(workspaceIdProvider);
    final tokens = SlateTheme.of(context);
    final paymentCollectionEnabled = ref.watch(
      paymentCollectionEnabledProvider,
    );
    final invoices = ref.watch(invoicesProvider);
    if (_initialRecordMissing) {
      return WorkloopRecordLinkUnavailable(
        recordName: 'Payment',
        onRetry: () {
          setState(() {
            _didHandleInitialPayment = false;
            _initialRecordMissing = false;
          });
          ref.invalidate(invoicesProvider);
        },
      );
    }
    final expenses = ref.watch(expensesProvider);
    final settings = ref.watch(workspaceSettingsProvider);
    if (invoices.hasValue) {
      _openInitialPayment(invoices.value ?? const []);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                SlateHaptics.action();
                _refreshMoney();
                try {
                  await Future.wait<Object?>([
                    ref.read(invoicesProvider.future),
                    ref.read(expensesProvider.future),
                    ref.read(financeSummaryProvider.future),
                  ]);
                } catch (_) {
                  // Existing Money sections expose retry without false totals.
                }
              },
              color: tokens.accent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  AppSpacing.screenTop,
                  AppSpacing.pageX,
                  AppSpacing.shellBottomClearance(context),
                ),
                children: [
                  Column(
                    children: [
                      if (widget.showBackButton)
                        WorkloopRouteHeader(
                          title: 'Money',
                          backSemanticLabel: 'Back to money',
                          onBack: () => workloopGoBack(
                            context,
                            fallbackLocation: '/payments',
                          ),
                          trailing: _section == MoneySection.documents
                              ? WorkloopTopAction(
                                  label: 'Create',
                                  semanticLabel: 'Create invoice or quote',
                                  onTap: () =>
                                      setState(() => _documentCreateRequest++),
                                )
                              : WorkloopTopAction(
                                  label: 'Add',
                                  semanticLabel: 'Add money',
                                  onTap: () => _showMoneyCreateSheet(context),
                                ),
                        )
                      else
                        WorkloopPageHeader(
                          title: 'Money',
                          subtitle: 'See what came in, went out and is owed.',
                          color: AppColors.of(context).modFinance,
                          trailing: _section == MoneySection.documents
                              ? WorkloopTopAction(
                                  label: 'Create',
                                  semanticLabel: 'Create invoice or quote',
                                  onTap: () =>
                                      setState(() => _documentCreateRequest++),
                                )
                              : WorkloopTopAction(
                                  label: 'Add',
                                  semanticLabel: 'Add money',
                                  onTap: () => _showMoneyCreateSheet(context),
                                ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      _moneyNavigation(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AnimatedSwitcher(
                    duration: AppMotion.responsive(context, AppMotion.standard),
                    switchInCurve: AppMotion.curve,
                    switchOutCurve: AppMotion.curve,
                    child: KeyedSubtree(
                      key: ValueKey(_section),
                      child: _buildMoneySection(
                        invoices: invoices,
                        expenses: expenses,
                        settings: settings,
                        paymentCollectionEnabled: paymentCollectionEnabled,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyNavigation() {
    const segments = [
      WorkloopSegment(value: MoneySection.made, label: 'Overview'),
      WorkloopSegment(value: MoneySection.documents, label: 'Invoices'),
      WorkloopSegment(value: MoneySection.spent, label: 'Spent'),
      WorkloopSegment(value: MoneySection.owed, label: 'Owed'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Retain readable labels at accessibility sizes. The shared folder tabs
        // scroll horizontally only when all four labels cannot fit the phone.
        var segmentWidth = AppSpacing.minTouch;
        for (final segment in segments) {
          final label = TextPainter(
            text: TextSpan(
              text: segment.label,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          segmentWidth = math.max(segmentWidth, label.width + 14);
          label.dispose();
        }
        final needsScroll =
            segmentWidth * segments.length > constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(
              constraints.maxWidth,
              segmentWidth * segments.length,
            ),
            child: WorkloopNavigationControl<MoneySection>(
              selected: _section,
              segments: segments,
              color: AppColors.of(context).modFinance,
              enableSwipeSelection: !needsScroll,
              onChanged: _selectMoneySection,
            ),
          ),
        );
      },
    );
  }

  void _selectMoneySection(MoneySection section) {
    setState(() => _section = section);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Widget _buildMoneySection({
    required AsyncValue<List<Payment>> invoices,
    required AsyncValue<List<Expense>> expenses,
    required AsyncValue<Map<String, dynamic>?> settings,
    required bool paymentCollectionEnabled,
  }) {
    final range = _selectedRange();
    return switch (_section) {
      MoneySection.documents => BusinessDocumentsScreen(
        embedded: true,
        createRequest: _documentCreateRequest,
      ),
      MoneySection.made => invoices.when(
        loading: () => const SlateLoadingBlock(height: 360, radius: 18),
        error: (_, _) => SlateErrorState(
          message: 'Could not load income',
          onRetry: () => ref.invalidate(invoicesProvider),
        ),
        data: (payments) => _incomeSection(
          payments: payments,
          expenses: expenses,
          settings: settings,
          range: range,
          paymentCollectionEnabled: paymentCollectionEnabled,
          periodSummary: PeriodMoneySummary.from(
            payments: payments,
            expenses: const [],
            range: range,
            now: _now,
          ),
        ),
      ),
      MoneySection.spent => expenses.when(
        loading: () => const SlateLoadingBlock(height: 360, radius: 18),
        error: (_, _) => SlateErrorState(
          message: 'Could not load expenses',
          onRetry: () => ref.invalidate(expensesProvider),
        ),
        data: (expenseRows) => _outgoingSection(
          expenses: expenseRows,
          range: range,
          periodSummary: PeriodMoneySummary.from(
            payments: const [],
            expenses: expenseRows,
            range: range,
            now: _now,
          ),
        ),
      ),
      MoneySection.owed => invoices.when(
        loading: () => const SlateLoadingBlock(height: 360, radius: 18),
        error: (_, _) => SlateErrorState(
          message: 'Could not load payments owed',
          onRetry: () => ref.invalidate(invoicesProvider),
        ),
        data: _owedSection,
      ),
    };
  }

  Widget _periodSelector(MoneyPeriodRange range) {
    return MoneyPeriodSwitcher(
      selected: _period,
      customLabel: _period == FinancePeriod.custom ? range.label : null,
      onSelected: (period) async {
        if (period == FinancePeriod.custom) {
          await _showCustomPeriodSheet(context);
          return;
        }
        setState(() {
          _period = period;
          _showAllIncome = false;
          _showAllExpenses = false;
        });
      },
    );
  }

  Widget _incomeSection({
    required List<Payment> payments,
    required AsyncValue<List<Expense>> expenses,
    required AsyncValue<Map<String, dynamic>?> settings,
    required MoneyPeriodRange range,
    required PeriodMoneySummary periodSummary,
    required bool paymentCollectionEnabled,
  }) {
    final income =
        payments
            .where(
              (payment) =>
                  receivedAmountFor(payment) != 0 || payment.status == 'paid',
            )
            .where(
              (payment) => payment.cashReceipts.any(
                (receipt) => _inRange(receipt.receivedAt, range),
              ),
            )
            .toList()
          ..sort((a, b) => b.receivedDate.compareTo(a.receivedDate));
    final monthlyIncome = receivedIncomeForMonth(payments, _now, now: _now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (payments.any((payment) => outstandingAmountFor(payment) > 0)) ...[
          _overviewPaymentAttention(payments),
          const SizedBox(height: AppSpacing.md),
        ],
        _periodSelector(range),
        const SizedBox(height: AppSpacing.md),
        WorkloopPaperPanel(
          title: 'Cash summary',
          child: expenses.when(
            loading: () => Column(
              children: [
                _MoneySummaryFigure(
                  label: 'Money received',
                  value: periodSummary.paid,
                  compact: true,
                  onTap: () => _showCashHistory(MoneyTimelineFilter.income),
                ),
                const SlateLoadingBlock(height: 80, radius: AppRadius.md),
              ],
            ),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MoneySummaryFigure(
                  label: 'Money received',
                  value: periodSummary.paid,
                  compact: true,
                  onTap: () => _showCashHistory(MoneyTimelineFilter.income),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Spending and net profit are unavailable.'),
                WorkloopTextButton(
                  label: 'Retry expenses',
                  onPressed: () => ref.invalidate(expensesProvider),
                ),
              ],
            ),
            data: (rows) {
              final summary = PeriodMoneySummary.from(
                payments: payments,
                expenses: rows,
                range: range,
                now: _now,
              );
              final hasActivity =
                  income.isNotEmpty ||
                  rows.any((row) => _inRange(row.expenseDate, range));
              final figures = [
                _MoneySummaryFigure(
                  label: 'Money received',
                  value: summary.paid,
                  compact: true,
                  detail:
                      '${income.length} payment${income.length == 1 ? '' : 's'} ${range.label.toLowerCase()}',
                  onTap: () => _showCashHistory(MoneyTimelineFilter.income),
                ),
                _MoneySummaryFigure(
                  label: 'Money spent',
                  value: summary.expenses,
                  compact: true,
                  onTap: () => _showCashHistory(MoneyTimelineFilter.expenses),
                ),
              ];
              return _NetProfitGraphic(
                data: buildMoneyProfitData(
                  payments: payments,
                  expenses: rows,
                  range: range,
                  now: _now,
                ),
                periodLabel: range.label,
                showChart: hasActivity,
                expanded: _showTrend,
                onToggle: () => setState(() => _showTrend = !_showTrend),
                breakdown: LayoutBuilder(
                  builder: (context, constraints) {
                    if (MediaQuery.textScalerOf(context).scale(14) > 20 ||
                        constraints.maxWidth < 270) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          figures.first,
                          const SizedBox(height: AppSpacing.sm),
                          figures.last,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: figures.first),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: figures.last),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _paymentsTimeline(payments: payments, expenses: expenses, range: range),
        const Divider(height: AppSpacing.md),
        settings.when(
          loading: () =>
              const SlateLoadingBlock(height: 112, radius: AppRadius.md),
          error: (_, _) => SlateErrorState(
            message: 'Could not load your Money target',
            onRetry: () => ref.invalidate(workspaceSettingsProvider),
          ),
          data: (values) {
            final monthlyTarget =
                (values?['revenue_target'] as num?)?.toDouble() ?? 0;
            return Column(
              children: [
                _IncomeTargetProgress(
                  made: monthlyIncome,
                  target: monthlyTarget,
                  onEditTarget: () => _showTargetSheet(context, monthlyTarget),
                ),
              ],
            );
          },
        ),
        if (settings.value?['workspace_id'] case final String workspaceId) ...[
          const Divider(height: AppSpacing.md),
          PaymentSetupCard(
            compact: true,
            onTap: () => _showPaymentSetup(workspaceId),
          ),
        ],
      ],
    );
  }

  Widget _overviewPaymentAttention(List<Payment> payments) {
    final owed = payments
        .where((payment) => outstandingAmountFor(payment) > 0)
        .toList();
    final total = owed.fold<double>(
      0,
      (sum, payment) => sum + outstandingAmountFor(payment),
    );
    final overdue = owed
        .where(
          (payment) =>
              moneyStatusFor(payment, now: _now) == MoneyStatus.overdue,
        )
        .length;
    return WorkloopModuleRow(
      key: const ValueKey('money-payment-attention'),
      icon: LucideIcons.wallet,
      title: '${formatPounds(total)} waiting to be paid',
      subtitle:
          '${owed.length} payment${owed.length == 1 ? '' : 's'}${overdue == 0 ? '' : ' · $overdue overdue'} · View owed',
      subtitleMaxLines: 3,
      semanticLabel: 'View payments owed, ${formatPounds(total)} outstanding',
      color: AppColors.of(context).modFinance,
      showDivider: true,
      onTap: () => _selectMoneySection(MoneySection.owed),
    );
  }

  void _showCashHistory(MoneyTimelineFilter filter) {
    setState(() {
      _showHistory = true;
      _timelineFilter = filter;
      _paymentsSearch.clear();
      _showAllIncome = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _timelineKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: AppMotion.responsive(context, AppMotion.standard),
        curve: AppMotion.curve,
        alignment: 0,
      );
    });
  }

  Widget _paymentsTimeline({
    required List<Payment> payments,
    required AsyncValue<List<Expense>> expenses,
    required MoneyPeriodRange range,
  }) {
    final needsExpenses = _timelineFilter != MoneyTimelineFilter.income;
    final waiting = needsExpenses && !expenses.hasValue && !expenses.hasError;
    final failed = needsExpenses && expenses.hasError;
    final query = _paymentsSearch.text.trim();
    final entries = buildMoneyTimeline(
      payments: payments,
      expenses: expenses.value ?? const [],
      range: range,
      filter: _timelineFilter,
      query: query,
    );
    final searching = query.isNotEmpty;
    final previewLimit = searching ? _searchHistoryLimit : _recentHistoryLimit;
    final visible = _showAllIncome ? entries : entries.take(previewLimit);
    final disclosure = _MoneyDisclosure(
      key: const ValueKey('money-history-toggle'),
      title: 'Payments',
      subtitle: _showHistory ? null : 'View and search income and expenses',
      expanded: _showHistory,
      onTap: () => setState(() => _showHistory = !_showHistory),
    );
    if (!_showHistory) {
      return Column(key: _timelineKey, children: [disclosure]);
    }
    return Column(
      key: _timelineKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        disclosure,
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Income and expenses · ${range.label} · Newest first',
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        WorkloopSearchField(
          key: const ValueKey('payments-search'),
          controller: _paymentsSearch,
          hintText: 'Search income and expenses',
          semanticLabel:
              'Search income and expenses in ${range.label.toLowerCase()}',
          onChanged: (_) => setState(() => _showAllIncome = false),
        ),
        const SizedBox(height: AppSpacing.sm),
        WorkloopSegmentedControl<MoneyTimelineFilter>(
          selected: _timelineFilter,
          segments: const [
            WorkloopSegment(value: MoneyTimelineFilter.all, label: 'All'),
            WorkloopSegment(value: MoneyTimelineFilter.income, label: 'Income'),
            WorkloopSegment(
              value: MoneyTimelineFilter.expenses,
              label: 'Expenses',
            ),
          ],
          onChanged: (filter) => setState(() {
            _timelineFilter = filter;
            _showAllIncome = false;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (waiting)
          const SlateLoadingBlock(height: 150, radius: AppRadius.md)
        else if (failed)
          Text(
            'Expenses are unavailable. Retry above, or choose Income to view received payments.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 13,
              height: 1.4,
            ),
          )
        else if (entries.isEmpty)
          WorkloopEmptyState(
            icon: searching ? LucideIcons.search : LucideIcons.arrowDownUp,
            title: searching
                ? 'No matching payments'
                : 'No ${switch (_timelineFilter) {
                    MoneyTimelineFilter.all => 'payments',
                    MoneyTimelineFilter.income => 'income',
                    MoneyTimelineFilter.expenses => 'expenses',
                  }} in this period',
            subtitle: searching
                ? 'Try a name, description or amount, or change the dates or filter.'
                : 'Recorded income and expenses appear here. Unpaid amounts stay in Owed.',
          )
        else ...[
          if (searching)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${entries.length} result${entries.length == 1 ? '' : 's'} · ${range.label}',
                style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
              ),
            ),
          if (entries.length > previewLimit)
            WorkloopTextButton(
              label: _showAllIncome
                  ? searching
                        ? 'Show first $_searchHistoryLimit results'
                        : 'Show recent payments'
                  : 'View all ${entries.length} ${searching ? 'results' : 'payments'}',
              onPressed: () => setState(() => _showAllIncome = !_showAllIncome),
            ),
          for (final entry in visible)
            if (entry.payment case final payment?)
              PaymentCard(
                key: ValueKey('income-${entry.stableKey}'),
                payment: payment,
                showReceivedEntry: true,
                receivedEntryAmount: entry.amount,
                receivedEntryDate: entry.date,
                onTap: () => _showPaymentActionsSheet(context, payment),
                onDelete: payment.sourceDocumentId == null
                    ? () => _confirmDeletePayment(context, payment)
                    : null,
              )
            else if (entry.expense case final expense?)
              MoneyExpenseRow(
                key: ValueKey('expense-${expense.id}'),
                expense: expense,
                onTap: () => _showExpenseSheet(context, expense: expense),
                onDelete: () => _confirmDeleteExpense(context, expense),
              ),
        ],
      ],
    );
  }

  Widget _outgoingSection({
    required List<Expense> expenses,
    required MoneyPeriodRange range,
    required PeriodMoneySummary periodSummary,
  }) {
    final outgoing =
        expenses
            .where((expense) => _inRange(expense.expenseDate, range))
            .toList()
          ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    final query = _expensesSearch.text.trim();
    final matches = outgoing
        .where((expense) => expenseMatchesSearch(expense, query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _periodSelector(range),
        const SizedBox(height: AppSpacing.md),
        _MoneySectionHero(
          label: 'Spent ${range.label.toLowerCase()}',
          value: periodSummary.expenses,
          detail:
              '${outgoing.length} expense${outgoing.length == 1 ? '' : 's'} · ${range.label}',
        ),
        if (periodSummary.categoryTotals.isNotEmpty) ...[
          _MoneyDisclosure(
            title: 'Spending by category',
            expanded: _showCategories,
            onTap: () => setState(() => _showCategories = !_showCategories),
          ),
          if (_showCategories)
            ExpenseCategorySummary(summary: periodSummary, showHeading: false),
        ],
        WorkloopTextButton(
          label: 'Business mileage',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MileageScreen()),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        WorkloopSectionHeader(
          label: 'Expenses & receipts',
          actionLabel: 'Add',
          onAction: () => _showExpenseSheet(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        WorkloopSearchField(
          key: const ValueKey('expense-search'),
          controller: _expensesSearch,
          hintText: 'Search expenses',
          semanticLabel: 'Search expenses in ${range.label.toLowerCase()}',
          onChanged: (_) => setState(() => _showAllExpenses = false),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (outgoing.isEmpty)
          const WorkloopEmptyState(
            icon: LucideIcons.receipt,
            title: 'Nothing spent in this period',
            subtitle: 'Business expenses you record will appear here.',
          )
        else if (matches.isEmpty)
          const WorkloopEmptyState(
            icon: LucideIcons.search,
            title: 'No matching expenses',
            subtitle:
                'Try a category, description or amount, or change the dates.',
          )
        else ...[
          if (query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${matches.length} result${matches.length == 1 ? '' : 's'} · ${range.label}',
                style: TextStyle(color: AppColors.of(context).t3, fontSize: 12),
              ),
            ),
          if (matches.length >
              (query.isEmpty ? _recentHistoryLimit : _searchHistoryLimit))
            WorkloopTextButton(
              label: _showAllExpenses
                  ? query.isEmpty
                        ? 'Show recent expenses'
                        : 'Show first $_searchHistoryLimit results'
                  : 'View all ${matches.length} ${query.isEmpty ? 'expenses' : 'results'}',
              onPressed: () =>
                  setState(() => _showAllExpenses = !_showAllExpenses),
            ),
          ...(_showAllExpenses
                  ? matches
                  : matches.take(
                      query.isEmpty ? _recentHistoryLimit : _searchHistoryLimit,
                    ))
              .map(
                (expense) => MoneyExpenseRow(
                  key: ValueKey('expense-${expense.id}'),
                  expense: expense,
                  onTap: () => _showExpenseSheet(context, expense: expense),
                  onDelete: () => _confirmDeleteExpense(context, expense),
                ),
              ),
        ],
      ],
    );
  }

  Widget _owedSection(List<Payment> payments) {
    final owed =
        payments.where((payment) => outstandingAmountFor(payment) > 0).toList()
          ..sort((a, b) {
            final aOverdue = moneyStatusFor(a) == MoneyStatus.overdue;
            final bOverdue = moneyStatusFor(b) == MoneyStatus.overdue;
            if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
            return (a.dueDate ?? a.issueDate).compareTo(
              b.dueDate ?? b.issueDate,
            );
          });
    final owedTotal = owed.fold<double>(
      0,
      (total, payment) => total + outstandingAmountFor(payment),
    );
    final matches = owed
        .where((payment) => paymentMatchesSearch(payment, _owedSearch.text))
        .toList();
    return Column(
      key: _followUpsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MoneySectionHero(
          label: 'You are owed',
          value: owedTotal,
          detail:
              '${owed.length} payment${owed.length == 1 ? '' : 's'} waiting to be paid',
        ),
        const SizedBox(height: AppSpacing.lg),
        const WorkloopSectionHeader(label: 'Payments owed'),
        const SizedBox(height: AppSpacing.xs),
        WorkloopSearchField(
          key: const ValueKey('owed-search'),
          controller: _owedSearch,
          hintText: 'Search payments owed',
          semanticLabel: 'Search payments owed',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (owed.isEmpty)
          const _QuietMoneyState()
        else if (matches.isEmpty)
          const WorkloopEmptyState(
            icon: LucideIcons.search,
            title: 'No matching payments owed',
            subtitle: 'Try a client name, payment reference or amount.',
          )
        else
          ...matches.map(
            (payment) => PaymentCard(
              payment: payment,
              onTap: () => _showPaymentActionsSheet(context, payment),
              onDelete: payment.sourceDocumentId == null
                  ? () => _confirmDeletePayment(context, payment)
                  : null,
            ),
          ),
      ],
    );
  }

  bool _inRange(DateTime date, MoneyPeriodRange range) {
    return !date.isBefore(range.start) && date.isBefore(range.end);
  }

  Future<void> _recordPayment(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddPaymentScreen()),
    );
    _refreshMoney();
  }

  Future<void> _showMoneyCreateSheet(BuildContext context) async {
    final action = await showWorkloopBottomSheet<_MoneyCreateAction>(
      context: context,
      builder: (sheetContext) => SlateSheetFrame(
        scrollable: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add to Money',
              style: TextStyle(
                color: AppColors.of(sheetContext).t1,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Choose what you want to record.',
              style: TextStyle(
                color: AppColors.of(sheetContext).t3,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _MoneyCreateChoice(
              icon: LucideIcons.banknote,
              label: 'Record income',
              description: 'Money received or waiting to be paid.',
              onTap: () =>
                  Navigator.pop(sheetContext, _MoneyCreateAction.income),
            ),
            _MoneyCreateChoice(
              icon: LucideIcons.fileText,
              label: 'Create invoice',
              description: 'An itemised document for your customer.',
              onTap: () =>
                  Navigator.pop(sheetContext, _MoneyCreateAction.invoice),
            ),
            _MoneyCreateChoice(
              icon: LucideIcons.clipboardList,
              label: 'Create quote',
              description: 'Agree the work and price before invoicing.',
              onTap: () =>
                  Navigator.pop(sheetContext, _MoneyCreateAction.quote),
            ),
            _MoneyCreateChoice(
              icon: LucideIcons.receipt,
              label: 'Add expense',
              description: 'Money spent by the business.',
              showDivider: false,
              onTap: () =>
                  Navigator.pop(sheetContext, _MoneyCreateAction.expense),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;
    switch (action) {
      case _MoneyCreateAction.income:
        await _recordPayment(context);
      case _MoneyCreateAction.expense:
        await _showExpenseSheet(context);
      case _MoneyCreateAction.invoice:
      case _MoneyCreateAction.quote:
        final document = await Navigator.push<BusinessDocument>(
          context,
          MaterialPageRoute(
            builder: (_) => BusinessDocumentEditorScreen(
              type: action == _MoneyCreateAction.quote ? 'quote' : 'invoice',
            ),
          ),
        );
        if (context.mounted && document != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  BusinessDocumentDetailScreen(documentId: document.id),
            ),
          );
        }
        _refreshMoney();
    }
  }

  void _refreshMoney() {
    ref.invalidate(invoicesProvider);
    ref.invalidate(businessDocumentsProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(dashboardRevenueProvider);
    ref.invalidate(clientCrmRecordsProvider);
  }

  void _refreshPayment(Payment payment) {
    _refreshMoney();
    if (payment.appointmentId != null) {
      ref.invalidate(appointmentPaymentsProvider(payment.appointmentId!));
    }
  }

  MoneyPeriodRange _selectedRange() {
    final now = _now;
    switch (_period) {
      case FinancePeriod.week:
        final start = startOfWeek(now);
        return MoneyPeriodRange(
          start: start,
          end: addBusinessCalendarDays(start, 7),
          label: 'This week',
        );
      case FinancePeriod.month:
        final start = DateTime(now.year, now.month, 1);
        return MoneyPeriodRange(
          start: start,
          end: DateTime(now.year, now.month + 1, 1),
          label: 'This month',
        );
      case FinancePeriod.custom:
        final start = _customStart ?? DateTime(now.year, now.month, 1);
        final end = _customEnd ?? now;
        return MoneyPeriodRange(
          start: DateTime(start.year, start.month, start.day),
          end: addBusinessCalendarDays(end, 1),
          label: '${_formatDate(start)} - ${_formatDate(end)}',
        );
    }
  }

  Future<void> _showCustomPeriodSheet(BuildContext context) async {
    var start = _customStart ?? _now.subtract(const Duration(days: 29));
    var end = _customEnd ?? _now;

    await showWorkloopBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickStart() async {
            final picked = await showWorkloopDatePicker(
              context: context,
              initialDate: start,
              firstDate: _now.subtract(const Duration(days: 730)),
              lastDate: end,
            );
            if (picked != null) setSheetState(() => start = picked);
          }

          Future<void> pickEnd() async {
            final picked = await showWorkloopDatePicker(
              context: context,
              initialDate: end,
              firstDate: start,
              lastDate: _now.add(const Duration(days: 365)),
            );
            if (picked != null) setSheetState(() => end = picked);
          }

          return SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom period',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(context).t1,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DatePickTile(
                        label: 'From',
                        value: _formatDate(start),
                        onTap: pickStart,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DatePickTile(
                        label: 'To',
                        value: _formatDate(end),
                        onTap: pickEnd,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SlateButton(
                  label: 'Apply Period',
                  icon: LucideIcons.calendarRange,
                  onPressed: () {
                    setState(() {
                      _period = FinancePeriod.custom;
                      _customStart = start;
                      _customEnd = end;
                      _showAllIncome = false;
                      _showAllExpenses = false;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTargetSheet(BuildContext context, double monthlyTarget) {
    showWorkloopBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MonthlyTargetEditor(
        initialTarget: monthlyTarget,
        onSave: (target) async {
          final repository = ref.read(workspaceSettingsRepositoryProvider);
          final workspaceId = await ref.read(workspaceIdProvider.future);
          if (!mounted || workspaceId == null) {
            throw StateError('No active business');
          }
          await repository.update(workspaceId, {'revenue_target': target});
          if (!mounted) return;
          ref.invalidate(workspaceSettingsProvider);
          ref.invalidate(financeSummaryProvider);
          ref.invalidate(dashboardRevenueProvider);
        },
      ),
    );
  }

  Future<void> _showExpenseSheet(
    BuildContext context, {
    Expense? expense,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExpenseEditorScreen(expense: expense)),
    );
    _refreshMoney();
  }

  Future<bool> _confirmDeleteExpense(
    BuildContext context,
    Expense expense,
  ) async {
    var deleting = false;
    String? errorMessage;
    final deleted = await showWorkloopBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => PopScope(
          canPop: !deleting,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete expense?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${expense.category} · ${formatPounds(expense.amount)}',
                  style: TextStyle(fontSize: 14, color: AppColors.of(ctx).t3),
                  textAlign: TextAlign.center,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.of(ctx).error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SlateButton(
                  label: deleting ? 'Deleting...' : 'Delete Expense',
                  destructive: true,
                  onPressed: deleting
                      ? null
                      : () async {
                          setSheetState(() {
                            deleting = true;
                            errorMessage = null;
                          });
                          try {
                            await ref
                                .read(expensesRepositoryProvider)
                                .delete(expense.id);
                            _refreshMoney();
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (_) {
                            if (!ctx.mounted) return;
                            setSheetState(() {
                              deleting = false;
                              errorMessage =
                                  'Could not confirm this deletion. The expense remains visible; check your connection and try again.';
                            });
                          }
                        },
                ),
                const SizedBox(height: 10),
                SlateButton(
                  label: 'Cancel',
                  secondary: true,
                  onPressed: deleting ? null : () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return deleted ?? false;
  }

  void _showPaymentActionsSheet(BuildContext context, Payment payment) {
    if (payment.sourceDocumentId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDocumentDetailScreen(
            documentId: payment.sourceDocumentId!,
          ),
        ),
      ).then((_) {
        if (mounted) _refreshPayment(payment);
      });
      return;
    }
    final clientName = payment.clientName ?? 'Unknown client';
    final received = receivedAmountFor(payment);
    final outstanding = outstandingAmountFor(payment);
    final partPaid = received > 0 && outstanding > 0;
    final amount = received != 0 || payment.status == 'paid'
        ? received
        : outstanding;
    final description = payment.notes ?? '';
    final canMarkPaid =
        outstanding > 0 &&
        (payment.status == 'sent' ||
            payment.status == 'pending' ||
            payment.status == 'overdue');
    var updating = false;
    String? errorMessage;

    showWorkloopBottomSheet(
      context: context,
      routeSettings: RouteSettings(name: '/payments/${payment.id}'),
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => PopScope(
          canPop: !updating,
          child: SlateSheetFrame(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.76,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          received < 0
                              ? 'Refund recorded'
                              : partPaid
                              ? 'Part-paid income'
                              : outstanding <= 0
                              ? 'Income received'
                              : 'To collect',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.of(ctx).t3,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          amount < 0
                              ? '-${formatPounds(amount.abs())}'
                              : formatPounds(amount),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: AppColors.of(ctx).t1,
                            letterSpacing: 0,
                          ),
                        ),
                        if (partPaid) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${formatPounds(received)} received · ${formatPounds(outstanding)} still to collect',
                            style: TextStyle(
                              color: AppColors.of(ctx).t2,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          clientName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.of(ctx).t1,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          _paymentTiming(payment),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.of(ctx).t3,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.of(ctx).t3,
                            ),
                          ),
                        ],
                        if (payment.appointmentId != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.calendarCheck,
                                size: 14,
                                color: AppColors.of(ctx).t3,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Linked to booking',
                                style: TextStyle(
                                  color: AppColors.of(ctx).t3,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (errorMessage != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.of(ctx).error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (canMarkPaid) ...[
                      if (ref.read(paymentCollectionEnabledProvider)) ...[
                        SlateButton(
                          label: 'Get paid with Stripe',
                          icon: LucideIcons.creditCard,
                          onPressed: updating
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) async {
                                    if (!context.mounted) return;
                                    final completed =
                                        await showPaymentCollectionSheet(
                                          context: context,
                                          payment: payment,
                                        );
                                    if (!completed || !context.mounted) return;
                                    _refreshPayment(payment);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${formatPounds(payment.outstandingAmount)} payment accepted',
                                        ),
                                      ),
                                    );
                                  });
                                },
                        ),
                        const SizedBox(height: 10),
                      ],
                      SlateButton(
                        label: updating ? 'Updating...' : 'Mark as Received',
                        icon: LucideIcons.checkCircle,
                        secondary: true,
                        onPressed: updating
                            ? null
                            : () async {
                                setSheetState(() {
                                  updating = true;
                                  errorMessage = null;
                                });
                                try {
                                  await _markPaymentPaid(context, payment);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (_) {
                                  if (!ctx.mounted) return;
                                  setSheetState(() {
                                    updating = false;
                                    errorMessage =
                                        'Could not mark this payment as received. Nothing visible has changed; check your connection and try again.';
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (payment.stripeAmountPaid > 0 &&
                        ref.read(paymentCollectionEnabledProvider)) ...[
                      SlateButton(
                        label: 'Card payment details',
                        icon: LucideIcons.creditCard,
                        secondary: true,
                        onPressed: updating
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) async {
                                  if (!context.mounted) return;
                                  final changed =
                                      await showPaymentCollectionSheet(
                                        context: context,
                                        payment: payment,
                                      );
                                  if (changed) _refreshPayment(payment);
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                    ] else if (payment.stripeAmountPaid <= 0) ...[
                      SlateButton(
                        label: 'Edit income',
                        icon: LucideIcons.pencil,
                        secondary: true,
                        onPressed: updating
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) async {
                                  if (!context.mounted) return;
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      settings: RouteSettings(
                                        name: '/payments/${payment.id}',
                                      ),
                                      builder: (_) =>
                                          AddPaymentScreen(payment: payment),
                                    ),
                                  );
                                  _refreshPayment(payment);
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      SlateButton(
                        label: 'Delete income',
                        icon: LucideIcons.trash2,
                        destructive: true,
                        onPressed: updating
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _confirmDeletePayment(context, payment);
                              },
                      ),
                      const SizedBox(height: 10),
                    ],
                    SlateButton(
                      label: 'Close',
                      secondary: true,
                      onPressed: updating ? null : () => Navigator.pop(ctx),
                    ),
                    const SizedBox(height: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markPaymentPaid(BuildContext context, Payment payment) async {
    final amount = outstandingAmountFor(payment);
    await ref.read(paymentsRepositoryProvider).markPaid(payment);
    _refreshPayment(payment);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${formatPounds(amount)} marked as received',
            style: TextStyle(color: AppColors.of(context).onBrandAccent),
          ),
          backgroundColor: AppColors.of(context).brandAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      );
    }
  }

  Future<bool> _confirmDeletePayment(
    BuildContext context,
    Payment payment,
  ) async {
    final clientName = payment.clientName ?? 'Unknown';
    final amount = payment.total;
    var deleting = false;
    String? errorMessage;

    final deleted = await showWorkloopBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => PopScope(
          canPop: !deleting,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete income entry?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$clientName · ${formatPounds(amount)}',
                  style: TextStyle(fontSize: 14, color: AppColors.of(ctx).t3),
                  textAlign: TextAlign.center,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.of(ctx).error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SlateButton(
                  label: deleting ? 'Deleting...' : 'Delete income',
                  destructive: true,
                  onPressed: deleting
                      ? null
                      : () async {
                          setSheetState(() {
                            deleting = true;
                            errorMessage = null;
                          });
                          try {
                            await ref
                                .read(paymentsRepositoryProvider)
                                .delete(payment.id);
                            _refreshPayment(payment);
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (_) {
                            if (!ctx.mounted) return;
                            setSheetState(() {
                              deleting = false;
                              errorMessage =
                                  'Could not confirm this deletion. The income entry remains visible; check your connection and try again.';
                            });
                          }
                        },
                ),
                const SizedBox(height: 10),
                SlateButton(
                  label: 'Cancel',
                  secondary: true,
                  onPressed: deleting ? null : () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return deleted ?? false;
  }

  String _paymentTiming(Payment payment) {
    final received = receivedAmountFor(payment);
    if (payment.status == 'paid' || received != 0) {
      final due = outstandingAmountFor(payment) > 0 && payment.dueDate != null
          ? ' · Due ${_formatDate(payment.dueDate!)}'
          : '';
      return '${received < 0 ? 'Recorded' : 'Received'} ${_formatDate(payment.receivedDate)}$due';
    }
    final dueDate = payment.dueDate;
    if (dueDate == null || dueDate.millisecondsSinceEpoch == 0) {
      return 'Created ${_formatDate(payment.issueDate)}';
    }
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return 'Due ${_formatDate(dueDate)} · ${diff.abs()}d late';
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    return 'Due ${_formatDate(dueDate)} · ${diff}d';
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

enum _MoneyCreateAction { income, expense, invoice, quote }

class _MoneyCreateChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool showDivider;

  const _MoneyCreateChoice({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return WorkloopListRow(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      leading: Container(
        width: AppSpacing.minTouch,
        height: AppSpacing.minTouch,
        decoration: BoxDecoration(
          color: tokens.surfaceSubtle,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: tokens.accentInk, size: 19),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: 13,
          height: 1.35,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: tokens.textTertiary,
        size: 18,
      ),
      showDivider: showDivider,
      onTap: onTap,
    );
  }
}
