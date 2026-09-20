import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';

class ObRevenueTarget extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const ObRevenueTarget({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  ConsumerState<ObRevenueTarget> createState() => _ObRevenueTargetState();
}

class _ObRevenueTargetState extends ConsumerState<ObRevenueTarget> {
  final _controller = TextEditingController();
  double? _selected;

  final List<double> _presets = [1000, 2000, 3000, 5000, 7500, 10000];

  @override
  void initState() {
    super.initState();
    final target = ref.read(onboardingProvider).revenueTarget;
    if (target > 0) {
      if (_presets.contains(target)) {
        _selected = target;
      } else {
        _controller.text = currencyInputValue(target);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasValue => _controller.text.trim().isNotEmpty || _selected != null;

  void _continue() {
    final target =
        double.tryParse(_controller.text.replaceAll(',', '')) ?? _selected ?? 0;
    ref.read(onboardingProvider.notifier).setRevenueTarget(target);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.pageX),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Set your\nrevenue target.',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).t1,
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "How much do you want to earn per month? We'll turn this into a weekly finance target and track your progress.",
            style: TextStyle(
              fontSize: 15,
              color: AppColors.of(context).t3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          const WorkloopFieldLabel('Monthly revenue target', isRequired: false),
          const SizedBox(height: AppSpacing.sm),
          // Custom input
          Container(
            decoration: BoxDecoration(
              color: AppColors.of(context).bgCard,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.of(context).border),
            ),
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Text(
                    '£',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.of(context).t2,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.of(context).t1,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.of(context).t3,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    onChanged: (_) => setState(() => _selected = null),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear revenue target',
                    onPressed: () {
                      _controller.clear();
                      setState(() {});
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.of(context).t3,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Preset chips
          Text(
            'OR CHOOSE A TARGET',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: AppColors.of(context).t3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _presets.map((amount) {
              final active = _selected == amount && _controller.text.isEmpty;
              return WorkloopFilterChip(
                label: formatPounds(amount),
                selected: active,
                onTap: () => setState(() {
                  _selected = amount;
                  _controller.clear();
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _hasValue ? _continue : null,
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: WorkloopTextButton(
              label: 'Skip — set this later in settings',
              onPressed: widget.onNext,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
