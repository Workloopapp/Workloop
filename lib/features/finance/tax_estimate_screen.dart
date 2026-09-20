import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/documents/workloop_document_viewer.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_settings_provider.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'expense_records_repository.dart';
import 'tax_estimate.dart';
import 'tax_recorded_figures.dart';
import 'widgets/money_editor_widgets.dart';

class TaxEstimateScreen extends ConsumerWidget {
  const TaxEstimateScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(workspaceIdProvider)
      .when(
        skipLoadingOnRefresh: false,
        data: (workspace) => workspace == null
            ? const Scaffold(
                body: Center(
                  child: Text('Open your business to estimate tax.'),
                ),
              )
            : _TaxEstimateEditor(
                key: ValueKey(workspace),
                workspaceId: workspace,
              ),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const Scaffold(
          body: Center(child: Text('Your business could not be loaded.')),
        ),
      );
}

class _TaxEstimateEditor extends ConsumerStatefulWidget {
  final String workspaceId;
  const _TaxEstimateEditor({super.key, required this.workspaceId});
  @override
  ConsumerState<_TaxEstimateEditor> createState() => _TaxEstimateScreenState();
}

class _TaxEstimateScreenState extends ConsumerState<_TaxEstimateEditor> {
  final _income = TextEditingController();
  final _expenses = TextEditingController(text: '0');
  final _vehicle = TextEditingController(text: '0');
  final _paid = TextEditingController(text: '0');
  final _reserve = TextEditingController(text: '0');
  final _carMiles = TextEditingController();
  final _motorcycleMiles = TextEditingController();
  bool _eligible = false,
      _reviewed = false,
      _mileageConfirmed = false,
      _busy = false;
  bool _loaded = false;
  bool _mileageLoaded = false;
  String _jurisdiction = 'england';
  VehicleExpenseMethod _method = VehicleExpenseMethod.actual;
  TaxEstimate? _result;
  TaxEstimateInput? _calculatedInput;
  int _revision = 0;

  @override
  void dispose() {
    for (final controller in [
      _income,
      _expenses,
      _vehicle,
      _paid,
      _reserve,
      _carMiles,
      _motorcycleMiles,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed({bool mileageChanged = false}) => setState(() {
    _result = null;
    _calculatedInput = null;
    _reviewed = false;
    if (mileageChanged) _mileageConfirmed = false;
    _revision++;
  });

  Future<void> _calculate(List<MileageEntry> mileage) async {
    if (_busy ||
        ref.read(workspaceIdProvider).value != widget.workspaceId ||
        !_eligible ||
        !_reviewed ||
        _method == VehicleExpenseMethod.mileage && !_mileageConfirmed) {
      return;
    }
    setState(() => _busy = true);
    final revision = _revision;
    try {
      int parse(TextEditingController value) =>
          parseHundredths(value.text) ??
          (throw const FormatException(
            'Enter pounds and pence in every amount field.',
          ));
      final input = TaxEstimateInput(
        turnoverMinor: parse(_income),
        nonVehicleExpensesMinor: parse(_expenses),
        actualVehicleExpensesMinor: _method == VehicleExpenseMethod.actual
            ? parse(_vehicle)
            : 0,
        paidToHmrcMinor: parse(_paid),
        reserveMinor: parse(_reserve),
        vehicleMethod: _method,
        jurisdiction: _jurisdiction,
        eligible: _eligible,
        annualCarVanMilesHundredths: _method == VehicleExpenseMethod.mileage
            ? parse(_carMiles)
            : null,
        annualMotorcycleMilesHundredths: _method == VehicleExpenseMethod.mileage
            ? parse(_motorcycleMiles)
            : null,
      );
      if (_method == VehicleExpenseMethod.mileage) {
        final logged = mileageTotals(mileage);
        if (input.annualCarVanMilesHundredths! < logged.carVan ||
            input.annualMotorcycleMilesHundredths! < logged.motorcycle) {
          throw const FormatException(
            'Annual mileage must include the business miles already logged. Update the forecast or correct your log.',
          );
        }
      }
      final result = TaxEstimate.calculate(
        input,
        mileageMinor: _method == VehicleExpenseMethod.mileage
            ? mileageDeductionMinor(mileage)
            : 0,
      );
      await ref
          .read(expenseRecordsRepositoryProvider)
          .saveTaxInput(widget.workspaceId, input);
      if (!mounted ||
          ref.read(workspaceIdProvider).value != widget.workspaceId ||
          revision != _revision) {
        return;
      }
      setState(() {
        _result = result;
        _calculatedInput = input;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Could not save this estimate. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _amount(
    String label,
    TextEditingController controller, {
    String? helper,
    bool miles = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: WorkloopFormField(
      label: label,
      isRequired: true,
      helperText: helper,
      child: TextField(
        key: ValueKey('tax-amount-$label'),
        controller: controller,
        enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => _changed(),
        decoration: InputDecoration(
          prefixText: miles ? null : '£ ',
          suffixText: miles ? 'miles' : null,
        ),
      ),
    ),
  );

  Widget _line(String label, int value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(14) > 20
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(
                  '£${formatHundredths(value)}',
                  style: TextStyle(
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: Text(label)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '£${formatHundredths(value)}',
                  style: TextStyle(
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
    ),
  );

  Future<void> _export() async {
    if (ref.read(workspaceIdProvider).value != widget.workspaceId) return;
    final result = _result;
    final input = _calculatedInput;
    if (result == null || input == null) return;
    final report = StringBuffer(
      'Workloop sole-trader tax estimate\n2026/27 · ${input.jurisdiction.replaceAll('_', ' ')}\nRules: ${SoleTraderTaxRules.version}\n\n',
    );
    if (input.vehicleMethod == VehicleExpenseMethod.mileage) {
      report.writeln(
        'Reviewed annual car/van miles: ${formatHundredths(input.annualCarVanMilesHundredths!)}',
      );
      report.writeln(
        'Reviewed annual motorcycle miles: ${formatHundredths(input.annualMotorcycleMilesHundredths!)}',
      );
      report.writeln(
        'Mileage totals are forecasts including logged journeys, not additional journey records.',
      );
    }
    for (final row in {
      'Reviewed annual turnover': input.turnoverMinor,
      'Allowable costs excluding vehicle': input.nonVehicleExpensesMinor,
      'Vehicle deduction (${input.vehicleMethod.name})':
          result.vehicleDeductionMinor,
      'Estimated taxable profit': result.profitMinor,
      'Personal allowance': result.personalAllowanceMinor,
      'Income Tax': result.incomeTaxMinor,
      'Class 4 National Insurance': result.class4Minor,
      'Estimated annual liability': result.liabilityMinor,
      'Paid to HMRC towards 2026/27': input.paidToHmrcMinor,
      'Outstanding annual liability': result.outstandingMinor,
      'Tax reserve': input.reserveMinor,
      'Reserve shortfall': result.reserveShortfallMinor,
      'Indicative next payment on account (each)':
          result.indicativeNextPaymentOnAccountMinor,
    }.entries) {
      report.writeln('${row.key}: £${formatHundredths(row.value)}');
    }
    report.writeln(
      '\nEstimate for entered totals, not an HMRC calculation or filing. No other taxable income, reliefs, student loans, benefit charges or loss relief. Reserve excludes advance payments on account. Check HMRC statements for amounts due.',
    );
    for (final source in SoleTraderTaxRules.sources.entries) {
      report.writeln('${source.key}: ${source.value}');
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkloopDocumentViewerScreen(
          workspaceId: widget.workspaceId,
          title: 'Tax estimate 2026/27',
          fileName: 'workloop-tax-estimate-2026-27.txt',
          mimeType: 'text/plain',
          loadBytes: () async =>
              Uint8List.fromList(utf8.encode(report.toString())),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedTaxEstimateProvider(widget.workspaceId));
    final mileage = ref.watch(mileageEntriesProvider);
    final structure = ref
        .watch(workspaceSettingsProvider)
        .value?['business_structure'];
    final unsupportedBusiness =
        structure == 'limited_company' || structure == 'other';
    ref.listen(mileageEntriesProvider, (previous, next) {
      if (_method == VehicleExpenseMethod.mileage &&
          previous?.value != next.value) {
        _changed(mileageChanged: true);
      }
    });
    if (!_loaded && saved.hasValue) {
      _loaded = true;
      final input = saved.value;
      if (input != null) {
        _income.text = formatHundredths(input.turnoverMinor);
        _expenses.text = formatHundredths(input.nonVehicleExpensesMinor);
        _vehicle.text = formatHundredths(input.actualVehicleExpensesMinor);
        _paid.text = formatHundredths(input.paidToHmrcMinor);
        _reserve.text = formatHundredths(input.reserveMinor);
        _method = input.vehicleMethod;
        _jurisdiction = input.jurisdiction;
        if (input.annualCarVanMilesHundredths != null) {
          _carMiles.text = formatHundredths(input.annualCarVanMilesHundredths!);
          _motorcycleMiles.text = formatHundredths(
            input.annualMotorcycleMilesHundredths!,
          );
        }
      }
    }
    if (_loaded && !_mileageLoaded && mileage.hasValue && !mileage.isLoading) {
      try {
        final totals = mileageTotals(mileage.value!);
        if (_carMiles.text.isEmpty) {
          _carMiles.text = formatHundredths(totals.carVan);
          _motorcycleMiles.text = formatHundredths(totals.motorcycle);
        }
        _mileageLoaded = true;
      } on FormatException {
        /* The mileage section shows the log error. */
      }
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageX,
                    vertical: AppSpacing.md,
                  ),
                  child: WorkloopRouteHeader(
                    title: 'Tax estimate',
                    backSemanticLabel: 'Back to Money',
                    onBack: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: saved.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: TextButton(
                        onPressed: () => ref.invalidate(
                          savedTaxEstimateProvider(widget.workspaceId),
                        ),
                        child: const Text(
                          'Could not load tax settings · retry',
                        ),
                      ),
                    ),
                    data: (_) => ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageX,
                        0,
                        AppSpacing.pageX,
                        AppSpacing.xxl,
                      ),
                      children: [
                        const Text(
                          'Plan what to put aside',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          '6 April 2026–5 April 2027. An estimate from your reviewed annual figures, not an HMRC return or filing service.',
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        MoneyFormSection(
                          title: 'Is this estimate right for you?',
                          child: Column(
                            children: [
                              if (unsupportedBusiness)
                                const Padding(
                                  padding: EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  child: Text(
                                    'Your saved business structure is not a sole trader. This estimate does not cover company or partnership tax. Check your business details if that is incorrect.',
                                  ),
                                ),
                              WorkloopFormField(
                                label: 'Tax residence',
                                isRequired: true,
                                child: WorkloopPickerField<String>(
                                  valueMaxLines: 3,
                                  enabled: !_busy,
                                  value: _jurisdiction,
                                  title: 'Tax residence',
                                  hint: 'Choose residence',
                                  options: const [
                                    WorkloopPickerOption(
                                      value: 'england',
                                      label: 'England',
                                    ),
                                    WorkloopPickerOption(
                                      value: 'wales',
                                      label: 'Wales',
                                    ),
                                    WorkloopPickerOption(
                                      value: 'northern_ireland',
                                      label: 'Northern Ireland',
                                    ),
                                    WorkloopPickerOption(
                                      value: 'scotland',
                                      label: 'Scotland · not supported',
                                    ),
                                  ],
                                  onChanged: (value) {
                                    _changed();
                                    setState(() {
                                      _jurisdiction = value;
                                      _eligible = false;
                                    });
                                  },
                                ),
                              ),
                              if (_jurisdiction == 'scotland')
                                const Padding(
                                  padding: EdgeInsets.all(AppSpacing.md),
                                  child: Text(
                                    'Scottish rates are not covered yet. Use HMRC or an accountant for your calculation.',
                                  ),
                                ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _eligible,
                                onChanged:
                                    _jurisdiction == 'scotland' ||
                                        _busy ||
                                        unsupportedBusiness
                                    ? null
                                    : (value) => setState(() {
                                        _eligible = value ?? false;
                                        _result = null;
                                      }),
                                title: const WorkloopFieldLabel(
                                  'I am a sole trader with no other taxable income',
                                  isRequired: true,
                                ),
                                subtitle: const Text(
                                  'One UK business, not VAT registered. I record money when received or paid, use a 5 April year end, and meet the conditions below.',
                                ),
                              ),
                              const ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text('Check the tax conditions'),
                                children: [
                                  Text(
                                    'You must be UK resident all year and liable to Class 4 National Insurance throughout. This estimate does not cover employment, pension, property, savings, dividends or foreign income; student loans, Child Benefit charge, pension/Gift Aid relief, marriage/blind allowance, CIS deductions, losses brought forward or capital allowances. Voluntary Class 2 is excluded. If any apply, use HMRC or your accountant.',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        TaxRecordedFigures(
                          onUseIncome: _busy
                              ? null
                              : (amount) {
                                  _income.text = formatHundredths(amount);
                                  _changed();
                                },
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        MoneyFormSection(
                          title: 'Reviewed annual figures',
                          subtitle:
                              'Enter your expected totals for the whole tax year, including business activity outside Workloop. No automatic annualisation.',
                          child: Column(
                            children: [
                              _amount('Annual business income', _income),
                              _amount(
                                'Other allowable costs',
                                _expenses,
                                helper:
                                    'Exclude personal spending and all vehicle ownership/running costs. Do not also claim the trading allowance.',
                              ),
                              WorkloopFormField(
                                label: 'Vehicle expense method',
                                isRequired: true,
                                child:
                                    WorkloopPickerField<VehicleExpenseMethod>(
                                      valueMaxLines: 3,
                                      enabled: !_busy,
                                      value: _method,
                                      title: 'Vehicle costs',
                                      hint: 'Choose method',
                                      options: const [
                                        WorkloopPickerOption(
                                          value: VehicleExpenseMethod.actual,
                                          label: 'Actual allowable costs',
                                        ),
                                        WorkloopPickerOption(
                                          value: VehicleExpenseMethod.mileage,
                                          label: 'Business mileage',
                                        ),
                                      ],
                                      onChanged: (value) {
                                        _changed();
                                        setState(() {
                                          _method = value;
                                          _mileageConfirmed = false;
                                        });
                                      },
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (_method == VehicleExpenseMethod.actual)
                                _amount(
                                  'Allowable vehicle costs',
                                  _vehicle,
                                  helper:
                                      'Business-use share only. Logged mileage is excluded. Use zero if you have no vehicle costs.',
                                ),
                              if (_method == VehicleExpenseMethod.mileage) ...[
                                mileage.when(
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (_, _) => TextButton(
                                    onPressed: () =>
                                        ref.invalidate(mileageEntriesProvider),
                                    child: const Text(
                                      'Mileage unavailable · retry',
                                    ),
                                  ),
                                  data: (entries) {
                                    try {
                                      return _line(
                                        'Deduction from journeys logged so far',
                                        mileageDeductionMinor(entries),
                                      );
                                    } on FormatException catch (error) {
                                      return Text(error.message);
                                    }
                                  },
                                ),
                                const Text(
                                  'Use the log as your starting point, then include expected business miles for the rest of the tax year below. This does not add journeys to your log. Cars/vans combined: 55p for the first 10,000 miles, then 25p. Motorcycles: 24p.',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _amount(
                                  'Annual car / van miles',
                                  _carMiles,
                                  miles: true,
                                ),
                                _amount(
                                  'Annual motorcycle miles',
                                  _motorcycleMiles,
                                  miles: true,
                                  helper:
                                      'Enter zero if you do not use a motorcycle.',
                                ),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _mileageConfirmed,
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() {
                                          _mileageConfirmed = value ?? false;
                                          _result = null;
                                        }),
                                  title: const WorkloopFieldLabel(
                                    'My mileage method and forecast are correct',
                                    isRequired: true,
                                  ),
                                  subtitle: const Text(
                                    'I included actual and expected business miles for the whole year. Every vehicle uses mileage consistently, with no prior capital allowance or purchase-cost claim and no commercial-design cars. Private travel, ordinary commuting and vehicle running/ownership costs are excluded from other expenses. Eligible parking and other travel can be claimed separately. This estimate uses one method for all vehicles.',
                                  ),
                                ),
                              ],
                              _amount(
                                'Paid to HMRC for 2026/27',
                                _paid,
                                helper:
                                    'Include payments on account allocated to this tax year only. Exclude previous-year bills.',
                              ),
                              _amount('Saved towards this tax', _reserve),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _reviewed,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(
                                        () => _reviewed = value ?? false,
                                      ),
                                title: const WorkloopFieldLabel(
                                  'I reviewed these annual figures',
                                  isRequired: true,
                                ),
                                subtitle: const Text(
                                  'Income and costs are complete estimates for the whole tax year. Only allowable business costs are included.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed:
                              _busy ||
                                  !_eligible ||
                                  unsupportedBusiness ||
                                  !_reviewed ||
                                  _method == VehicleExpenseMethod.mileage &&
                                      (!_mileageConfirmed || !mileage.hasValue)
                              ? null
                              : () => _calculate(mileage.value ?? []),
                          child: Text(
                            _busy ? 'Saving…' : 'Calculate and save estimate',
                          ),
                        ),
                        if (_result case final result?
                            when !unsupportedBusiness) ...[
                          const SizedBox(height: AppSpacing.xl),
                          MoneyFormSection(
                            title: 'Your annual estimate',
                            child: Column(
                              children: [
                                _line('Taxable profit', result.profitMinor),
                                _line('Income Tax', result.incomeTaxMinor),
                                _line(
                                  'Class 4 National Insurance',
                                  result.class4Minor,
                                ),
                                const Divider(),
                                _line(
                                  'Estimated annual liability',
                                  result.liabilityMinor,
                                  strong: true,
                                ),
                                _line(
                                  'Remaining after HMRC payments',
                                  result.outstandingMinor,
                                ),
                                _line(
                                  'Still to set aside',
                                  result.reserveShortfallMinor,
                                  strong: true,
                                ),
                                const Text(
                                  'This reserve covers the annual liability only. Advance payments for the next year may require extra cash.',
                                ),
                                if (result.indicativeNextPaymentOnAccountMinor >
                                    0) ...[
                                  _line(
                                    'Indicative next advance payment',
                                    result.indicativeNextPaymentOnAccountMinor,
                                  ),
                                  const Text(
                                    'Usually due on 31 January 2028 and again on 31 July 2028 towards 2027/28. Your 2026/27 balancing payment is due by 31 January 2028. Existing payments on account for 2026/27 may be due earlier. Check your HMRC statement; this is not a bill.',
                                  ),
                                ] else
                                  const Text(
                                    'The 2026/27 balancing payment is due by 31 January 2028. Check your HMRC statement for any existing payments on account.',
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _export,
                                  icon: const Icon(Icons.description_outlined),
                                  label: const Text('View report'),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        const Text(
                          'Rules checked 8 September 2026. HMRC guidance',
                        ),
                        for (final source in SoleTraderTaxRules.sources.entries)
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(source.value),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(source.key),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
