import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import '../../../shared/widgets/business_logo_editor.dart';

const List<String> industries = [
  'Hair & Barbering',
  'Beauty & Aesthetics',
  'Health & Fitness',
  'Massage & Therapy',
  'Cleaning & Home Services',
  'Mobile Valeting & Detailing',
  'Mobile Trades',
  'Tutoring & Coaching',
  'Photography',
  'Other',
];

class ObProfile extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const ObProfile({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<ObProfile> createState() => _ObProfileState();
}

class _ObProfileState extends ConsumerState<ObProfile> {
  final _firstNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _occupationController = TextEditingController();
  String? _selectedIndustry;
  bool _logoSaving = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingProvider);
    _firstNameController.text = draft.firstName;
    _businessNameController.text = draft.businessName;
    _selectedIndustry = draft.industry.isEmpty
        ? null
        : industries.contains(draft.industry)
        ? draft.industry
        : 'Other';
    if (_selectedIndustry == 'Other' && draft.industry != 'Other') {
      _occupationController.text = draft.industry;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _businessNameController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      !_logoSaving &&
      _firstNameController.text.trim().isNotEmpty &&
      _businessNameController.text.trim().isNotEmpty &&
      _selectedIndustry != null &&
      (_selectedIndustry != 'Other' ||
          _occupationController.text.trim().isNotEmpty);

  void _saveDraft() {
    final notifier = ref.read(onboardingProvider.notifier);
    notifier.setName(
      _firstNameController.text.trim(),
      _businessNameController.text.trim(),
    );
    notifier.setIndustry(
      _selectedIndustry == 'Other'
          ? _occupationController.text.trim().isEmpty
                ? 'Other'
                : _occupationController.text.trim()
          : _selectedIndustry ?? '',
    );
    setState(() {});
  }

  void _continue() {
    if (!_canContinue) return;
    _saveDraft();
    FocusScope.of(context).unfocus();
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
            'Make Workloop\nyour own.',
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
            'Start with your name and the work you do. You can refine your business details later.',
            style: TextStyle(fontSize: 15, color: AppColors.of(context).t3),
          ),
          const SizedBox(height: 32),
          _label('Your name'),
          const SizedBox(height: 8),
          _field(
            controller: _firstNameController,
            hint: 'Alex',
            onChanged: (_) => _saveDraft(),
          ),
          const SizedBox(height: 20),
          _label('Business name'),
          const SizedBox(height: 8),
          _field(
            controller: _businessNameController,
            hint: 'Your trading name, or your own name',
            onChanged: (_) => _saveDraft(),
          ),
          const SizedBox(height: 20),
          BusinessLogoEditor(
            logoUrl: ref.watch(onboardingProvider).logoUrl,
            onBusyChanged: (value) {
              if (mounted) setState(() => _logoSaving = value);
            },
            onChanged: (url) async =>
                ref.read(onboardingProvider.notifier).setLogoUrl(url ?? ''),
          ),
          const SizedBox(height: 20),
          _label('What do you do?'),
          const SizedBox(height: 8),
          WorkloopPickerField<String>(
            value: _selectedIndustry,
            title: 'Choose your occupation',
            hint: 'Select the closest match',
            searchHint: 'Search occupations',
            options: industries
                .map(
                  (industry) =>
                      WorkloopPickerOption(value: industry, label: industry),
                )
                .toList(),
            onChanged: (value) {
              _selectedIndustry = value;
              _saveDraft();
            },
          ),
          if (_selectedIndustry == 'Other') ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('custom-occupation'),
              controller: _occupationController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              maxLength: 80,
              onChanged: (_) => _saveDraft(),
              onSubmitted: (_) => _continue(),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                label: WorkloopFieldLabel('Your occupation', isRequired: true),
                hintText: 'For example, dog groomer or gardener',
                helperText: 'Use the words your customers know.',
              ),
            ),
          ],
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _canContinue ? _continue : null,
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return WorkloopFieldLabel(
      text,
      isRequired: true,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.of(context).t2,
        letterSpacing: 0,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required Function(String) onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      style: TextStyle(color: AppColors.of(context).t1, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.of(context).t3),
        filled: true,
        fillColor: AppColors.of(context).bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.of(context).border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.of(context).border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: AppColors.of(context).green,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
    );
  }
}
