import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'cashflow_forecast.dart';
import 'report_models.dart';

class CashflowControls extends StatefulWidget {
  final CashflowAssumptions assumptions;
  final ValueChanged<CashflowAssumptions> onApply;
  const CashflowControls({
    super.key,
    required this.assumptions,
    required this.onApply,
  });
  @override
  State<CashflowControls> createState() => _CashflowControlsState();
}

class _CashflowControlsState extends State<CashflowControls> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _cash;
  late final TextEditingController _costs;
  late bool _bookings;
  late bool _overdue;
  late int _delay;
  @override
  void initState() {
    super.initState();
    String value(int? amount) =>
        amount == null ? '' : (amount / 100).toStringAsFixed(2);
    _cash = TextEditingController(
      text: value(widget.assumptions.startingCashPence),
    );
    _costs = TextEditingController(
      text: value(widget.assumptions.weeklyCostsPence),
    );
    _bookings = widget.assumptions.includeBookings;
    _overdue = widget.assumptions.includeOverdue;
    _delay = widget.assumptions.paymentDelayDays;
  }

  @override
  void dispose() {
    _cash.dispose();
    _costs.dispose();
    super.dispose();
  }

  String? _validate(String? text, {bool costs = false}) {
    try {
      final value = forecastInputPence(text ?? '');
      if (costs && value != null && value < 0) {
        return 'Weekly costs must be £0 or more.';
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  @override
  Widget build(BuildContext context) => WorkloopPaperPanel(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      key: const ValueKey('forecast-assumptions'),
      title: const Text('Adjust your forecast'),
      subtitle: const Text('Starting cash, expected costs and payment timing'),
      childrenPadding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkloopFormField(
                label: 'Cash available now',
                isRequired: false,
                helperText:
                    'Your available business cash after today’s payments. Leave blank to see cash changes only.',
                child: TextFormField(
                  key: const ValueKey('forecast-starting-cash'),
                  controller: _cash,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '£ ',
                    hintText: 'Enter your current cash',
                  ),
                  validator: _validate,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              WorkloopFormField(
                label: 'Extra weekly costs',
                isRequired: false,
                helperText:
                    'Allow for regular bills, supplies, tax or money you take out. Leave out costs already saved with a future date. Enter 0 if you expect none.',
                child: TextFormField(
                  key: const ValueKey('forecast-weekly-costs'),
                  controller: _costs,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '£ ',
                    hintText: 'Expected costs per week',
                  ),
                  validator: (text) => _validate(text, costs: true),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              WorkloopPickerField<int>(
                value: _delay,
                title: 'When will payments arrive?',
                hint: 'Payment timing',
                valueMaxLines: 2,
                options: const [
                  WorkloopPickerOption(value: 0, label: 'On the expected date'),
                  WorkloopPickerOption(value: 7, label: 'One week later'),
                  WorkloopPickerOption(value: 14, label: 'Two weeks later'),
                ],
                onChanged: (value) => setState(() => _delay = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include upcoming bookings'),
                subtitle: const Text(
                  'Estimate payment on the booking date when no payment is linked yet.',
                ),
                value: _bookings,
                onChanged: (value) => setState(() => _bookings = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include overdue and undated payments'),
                subtitle: const Text(
                  'Assume they arrive today, plus any payment delay chosen above. Only include money you expect to collect.',
                ),
                value: _overdue,
                onChanged: (value) => setState(() => _overdue = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  FocusScope.of(context).unfocus();
                  widget.onApply(
                    CashflowAssumptions(
                      days: widget.assumptions.days,
                      startingCashPence: forecastInputPence(_cash.text),
                      weeklyCostsPence: forecastInputPence(_costs.text),
                      includeBookings: _bookings,
                      includeOverdue: _overdue,
                      paymentDelayDays: _delay,
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Forecast updated. Your business records have not changed.',
                      ),
                    ),
                  );
                },
                child: const Text('Update forecast'),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'These assumptions are used for this report only. They reset when you close Reports.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class CashflowChart extends StatelessWidget {
  final CashflowForecast forecast;
  final CashflowAssumptions assumptions;
  const CashflowChart({
    super.key,
    required this.forecast,
    required this.assumptions,
  });
  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final values = <int>[
      assumptions.startingCashPence ?? 0,
      for (final day in forecast.days)
        day.closingCashPence ?? day.cumulativeChangePence,
    ];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    return WorkloopPaperPanel(
      title: assumptions.startingCashPence == null
          ? 'Expected change in cash'
          : 'How your cash could change',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${reportMoney(low)} to ${reportMoney(high)}',
            style: TextStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            image: true,
            label:
                'Cash forecast starts at ${reportMoney(values.first)} and ends at ${reportMoney(values.last)}. Lowest ${reportMoney(low)}, highest ${reportMoney(high)}. The weekly breakdown follows below.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 130,
                child: CustomPaint(
                  painter: _CashflowPainter(
                    values,
                    tokens.accentInk,
                    tokens.divider,
                    tokens.warning,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            children: [
              Text('Today · ${reportMoney(values.first)}'),
              Text('Day ${assumptions.days} · ${reportMoney(values.last)}'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The horizontal line marks £0. Estimates change when payments, bookings or costs change.',
            style: TextStyle(color: tokens.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CashflowPainter extends CustomPainter {
  final List<int> values;
  final Color line;
  final Color axis;
  final Color negative;
  _CashflowPainter(this.values, this.line, this.axis, this.negative);
  @override
  void paint(Canvas canvas, Size size) {
    final minimum = math.min(0, values.reduce(math.min)).toDouble();
    final maximum = math.max(0, values.reduce(math.max)).toDouble();
    final span = math.max(100.0, maximum - minimum);
    double y(num value) => 6 + (maximum - value) / span * (size.height - 12);
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    for (var i = 1; i < values.length; i++) {
      canvas.drawLine(
        Offset((i - 1) * size.width / (values.length - 1), y(values[i - 1])),
        Offset(i * size.width / (values.length - 1), y(values[i])),
        Paint()
          ..color = values[i] < 0 ? negative : line
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CashflowPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.line != line ||
      oldDelegate.axis != axis ||
      oldDelegate.negative != negative;
}
