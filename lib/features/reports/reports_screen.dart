import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/documents/workloop_document_viewer.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/business_clock_provider.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_settings_provider.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import 'report_builder.dart';
import 'cashflow_forecast.dart';
import 'cashflow_widgets.dart';
import 'report_export.dart';
import 'report_models.dart';
import 'report_widgets.dart';
import 'reports_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportKind _kind = ReportKind.overview;
  ReportPeriod _period = ReportPeriod.month;
  ReportRange? _custom;
  CashflowAssumptions _forecast = const CashflowAssumptions();
  int _visible = 30;
  bool _sharing = false;
  String? _openingWorkspace;
  bool _revoked = false;
  String? _userId;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authRepositoryProvider);
    _userId = auth.currentUserId;
    _authSubscription = auth.authChanges.listen((event) {
      if (mounted && event.session?.user.id != _userId) {
        setState(() => _revoked = true);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(invoicesProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(appointmentsProvider);
    ref.invalidate(clientsProvider);
    ref.invalidate(allTasksProvider);
    ref.invalidate(workspaceSettingsProvider);
    ref.invalidate(reportsSourceProvider);
    try {
      await ref.read(reportsSourceProvider.future);
    } catch (_) {
      /* Visible retry state. */
    }
  }

  Future<void> _choosePeriod(
    ReportPeriod period,
    ReportSource source,
    DateTime now,
  ) async {
    if (period == ReportPeriod.custom) {
      final today = source.civil(now);
      final current =
          _custom ?? _period.range(today, earliest: source.earliestDay(now));
      DateTime local(DateTime day) => DateTime(day.year, day.month, day.day);
      final earliest = source.earliestDay(now);
      final first = earliest.year < 2000 ? local(earliest) : DateTime(2000);
      final selected = await showDateRangePicker(
        context: context,
        firstDate: first,
        lastDate: local(today),
        initialDateRange: DateTimeRange(
          start: local(
            current.start.isBefore(reportDay(first)) ? first : current.start,
          ),
          end: local(current.end.subtract(const Duration(days: 1))),
        ),
        helpText: 'Choose the dates to include',
        saveText: 'Show report',
      );
      if (!mounted || selected == null) return;
      _custom = ReportRange(
        selected.start,
        reportDay(selected.end).add(const Duration(days: 1)),
      );
    }
    setState(() {
      _period = period;
      _visible = 30;
    });
  }

  bool _canExport(ReportSource source) {
    final workspace = ref.read(workspaceIdProvider);
    final reportSource = ref.read(reportsSourceProvider);
    return !_revoked &&
        _userId != null &&
        ref.read(authRepositoryProvider).currentUserId == _userId &&
        !workspace.isLoading &&
        !workspace.hasError &&
        workspace.value == source.workspaceId &&
        !reportSource.isLoading &&
        !reportSource.hasError &&
        identical(reportSource.value, source);
  }

  Future<void> _exportCsv(
    ReportSource source,
    BusinessReport report,
    ReportRange range,
    DateTime now,
  ) async {
    if (_sharing || !_canExport(source)) return;
    setState(() => _sharing = true);
    try {
      final fileName =
          'workloop-${report.kind.name}-${reportDate(source.civil(now))}.csv';
      final bytes = reportCsvBytes(
        report: report,
        source: source,
        range: range,
        generatedAt: now,
      );
      if (!_canExport(source)) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'text/csv', name: fileName)],
          fileNameOverrides: [fileName],
          title: report.kind.label,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your report couldn’t be shared. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _viewPdf(
    ReportSource source,
    BusinessReport report,
    ReportRange range,
    DateTime now,
  ) {
    if (!_canExport(source)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkloopDocumentViewerScreen(
          workspaceId: source.workspaceId,
          title: report.kind.label,
          fileName:
              'workloop-${report.kind.name}-${reportDate(source.civil(now))}.pdf',
          mimeType: 'application/pdf',
          loadBytes: () => buildReportPdf(
            report: report,
            source: source,
            range: range,
            generatedAt: now,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(reportsSourceProvider);
    final workspace = ref.watch(workspaceIdProvider);
    final now = ref.watch(businessNowProvider);
    // A retained report route must never switch silently to another business.
    ref.listen(workspaceIdProvider, (previous, next) {
      if (_openingWorkspace != null &&
          !next.isLoading &&
          (next.hasError || next.value != _openingWorkspace)) {
        setState(() => _revoked = true);
      }
    });
    if (_openingWorkspace == null &&
        !workspace.isLoading &&
        !workspace.hasError) {
      _openingWorkspace = workspace.value;
    }
    final tokens = SlateTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: WorkloopAppCanvas(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageX,
                  AppSpacing.sm,
                  AppSpacing.pageX,
                  AppSpacing.md,
                ),
                child: WorkloopRouteHeader(
                  title: 'Reports',
                  trailing: WorkloopIconButton(
                    icon: LucideIcons.refreshCw,
                    semanticLabel: 'Refresh reports',
                    onTap: _refresh,
                  ),
                ),
              ),
              Expanded(
                child: _revoked
                    ? const Center(
                        child: Text(
                          'Your account or business has changed. Go back and open Reports again to see the right information.',
                        ),
                      )
                    : workspace.isLoading || source.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : workspace.hasError || source.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.pageX),
                        child: SlateErrorState(
                          message:
                              'We couldn’t load all the information for your reports. Try again to see complete, up-to-date figures.',
                          onRetry: _refresh,
                        ),
                      )
                    : source.value == null ||
                          source.value!.workspaceId != workspace.value
                    ? const Center(
                        child: Text(
                          'Go back to your business and open Reports again.',
                        ),
                      )
                    : _content(source.value!, now, tokens),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
    ReportSource source,
    DateTime now,
    WorkloopThemeTokens tokens,
  ) {
    final cashflow = _kind == ReportKind.forecast
        ? buildCashflowForecast(
            source: source,
            now: now,
            assumptions: _forecast,
          )
        : null;
    final range =
        cashflow?.range ??
        (_period == ReportPeriod.custom && _custom != null
            ? _custom!
            : _period.range(
                source.civil(now),
                earliest: source.earliestDay(now),
              ));
    final report =
        cashflow?.report ??
        buildBusinessReport(
          source: source,
          kind: _kind,
          range: range,
          now: now,
        );
    final rows = report.rows.take(_visible).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageX,
          0,
          AppSpacing.pageX,
          AppSpacing.xxl,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            'Understand your money, your work and what’s ahead.',
            style: TextStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          WorkloopPickerField<ReportKind>(
            key: const ValueKey('report-kind'),
            value: _kind,
            title: 'Choose a report',
            hint: 'Report',
            valueMaxLines: 2,
            options: [
              for (final kind in ReportKind.values)
                WorkloopPickerOption(
                  value: kind,
                  label: kind.label,
                  subtitle: kind.description,
                ),
            ],
            onChanged: (kind) => setState(() {
              _kind = kind;
              _visible = 30;
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _kind.description,
            style: TextStyle(color: tokens.textSecondary, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_kind == ReportKind.forecast) ...[
            WorkloopPickerField<int>(
              key: const ValueKey('forecast-horizon'),
              value: _forecast.days,
              title: 'How far ahead?',
              hint: 'Forecast length',
              options: [
                for (final days in [30, 60, 90])
                  WorkloopPickerOption(value: days, label: 'Next $days days'),
              ],
              onChanged: (days) => setState(() {
                _forecast = CashflowAssumptions(
                  days: days,
                  startingCashPence: _forecast.startingCashPence,
                  weeklyCostsPence: _forecast.weeklyCostsPence,
                  includeBookings: _forecast.includeBookings,
                  includeOverdue: _forecast.includeOverdue,
                  paymentDelayDays: _forecast.paymentDelayDays,
                );
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              range.label,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
          ] else if (_kind != ReportKind.outstanding) ...[
            WorkloopPickerField<ReportPeriod>(
              key: const ValueKey('report-period'),
              value: _period,
              title: 'Which dates would you like to see?',
              hint: 'Dates',
              valueMaxLines: 2,
              options: [
                for (final period in ReportPeriod.values)
                  WorkloopPickerOption(value: period, label: period.label),
              ],
              onChanged: (period) => _choosePeriod(period, source, now),
            ),
            if (_period == ReportPeriod.custom)
              TextButton(
                onPressed: () =>
                    _choosePeriod(ReportPeriod.custom, source, now),
                child: const Text('Change these dates'),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              range.label,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
          ] else
            Text(
              'What you’re owed today · ${reportFriendlyDate(source.civil(now))}',
              style: TextStyle(color: tokens.textSecondary),
            ),
          const SizedBox(height: 4),
          Text(
            'Dates use ${source.timezone} · Amounts in £ (GBP)',
            style: TextStyle(color: tokens.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                onPressed: _sharing
                    ? null
                    : () => _viewPdf(source, report, range, now),
                icon: const Icon(LucideIcons.fileText, size: 17),
                label: const Text('PDF summary'),
              ),
              OutlinedButton.icon(
                onPressed: _sharing
                    ? null
                    : () => _exportCsv(source, report, range, now),
                icon: const Icon(LucideIcons.download, size: 17),
                label: Text(_sharing ? 'Preparing…' : 'Export spreadsheet'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (cashflow != null) ...[
            CashflowControls(
              assumptions: _forecast,
              onApply: (value) => setState(() => _forecast = value),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (report.notices.isNotEmpty) ...[
            WorkloopPaperPanel(
              title: 'Before you use this forecast',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final notice in report.notices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        notice,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (cashflow != null) ...[
            CashflowChart(forecast: cashflow, assumptions: _forecast),
            const SizedBox(height: AppSpacing.md),
          ],
          ReportMetrics(metrics: report.metrics),
          const SizedBox(height: AppSpacing.md),
          WorkloopPaperPanel(
            title: 'How to read this report',
            child: Text(
              report.basis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          WorkloopPaperPanel(
            title: _kind == ReportKind.forecast
                ? 'Week by week · ${report.rows.length}'
                : 'Your breakdown · ${report.rows.length}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rows.isEmpty)
                  Text(
                    report.emptyMessage,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ReportRecord(columns: report.columns, values: rows[i]),
                ],
                if (_visible < report.rows.length)
                  TextButton(
                    onPressed: () => setState(() => _visible += 30),
                    child: Text(
                      'Show more (${report.rows.length - _visible} left)',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Use PDF for a summary you can read or share. The spreadsheet (CSV) includes the full breakdown and opens in Excel, Numbers or Google Sheets.',
            style: TextStyle(color: tokens.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
