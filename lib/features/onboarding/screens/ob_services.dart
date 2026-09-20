import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import 'onboarding_service_editor.dart';

const Map<String, List<Map<String, dynamic>>> industryServices = {
  'Hair & Barbering': [
    {'name': 'Haircut', 'duration': 30, 'price': 25.0},
    {'name': 'Haircut & Beard', 'duration': 45, 'price': 35.0},
    {'name': 'Beard Trim', 'duration': 20, 'price': 15.0},
    {'name': 'Skin Fade', 'duration': 30, 'price': 28.0},
  ],
  'Beauty & Aesthetics': [
    {'name': 'Gel Nails', 'duration': 60, 'price': 35.0},
    {'name': 'Lash Extensions', 'duration': 90, 'price': 55.0},
    {'name': 'Eyebrow Threading', 'duration': 20, 'price': 12.0},
    {'name': 'Facial', 'duration': 60, 'price': 45.0},
  ],
  'Health & Fitness': [
    {'name': '1-to-1 PT Session', 'duration': 60, 'price': 50.0},
    {'name': 'Online Coaching Session', 'duration': 45, 'price': 40.0},
    {'name': 'Group Class', 'duration': 45, 'price': 15.0},
  ],
  'Massage & Therapy': [
    {'name': 'Swedish Massage', 'duration': 60, 'price': 55.0},
    {'name': 'Deep Tissue Massage', 'duration': 60, 'price': 65.0},
    {'name': 'Sports Massage', 'duration': 45, 'price': 50.0},
  ],
  'Cleaning & Home Services': [
    {'name': 'Standard Clean', 'duration': 120, 'price': 60.0},
    {'name': 'Deep Clean', 'duration': 180, 'price': 120.0},
    {'name': 'End of Tenancy Clean', 'duration': 240, 'price': 180.0},
  ],
  'Mobile Trades': [
    {'name': 'Callout & Assessment', 'duration': 60, 'price': 60.0},
    {'name': 'Standard Booking', 'duration': 120, 'price': 120.0},
  ],
  'Mobile Valeting & Detailing': [
    {'name': 'Maintenance Valet', 'duration': 90, 'price': 50.0},
    {'name': 'Full Valet', 'duration': 180, 'price': 120.0},
    {'name': 'Interior Deep Clean', 'duration': 150, 'price': 100.0},
  ],
  'Tutoring & Coaching': [
    {'name': '1-to-1 Session', 'duration': 60, 'price': 45.0},
    {'name': 'Online Session', 'duration': 60, 'price': 40.0},
    {'name': 'Group Session', 'duration': 90, 'price': 20.0},
  ],
  'Photography': [
    {'name': 'Portrait Session', 'duration': 60, 'price': 150.0},
    {'name': 'Event Photography', 'duration': 240, 'price': 400.0},
  ],
  'Other': [
    {'name': 'Consultation', 'duration': 30, 'price': 30.0},
    {'name': '1 Hour Session', 'duration': 60, 'price': 60.0},
  ],
};

class ObServices extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const ObServices({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<ObServices> createState() => _ObServicesState();
}

class _ObServicesState extends ConsumerState<ObServices> {
  List<Map<String, dynamic>> _services = [];

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingProvider);
    _services = draft.servicesReviewed || draft.services.isNotEmpty
        ? draft.services.map((item) => Map<String, dynamic>.from(item)).toList()
        : List<Map<String, dynamic>>.from(
            industryServices[draft.industry] ?? industryServices['Other']!,
          );
  }

  void _removeService(int index) {
    setState(() => _services.removeAt(index));
    ref.read(onboardingProvider.notifier).setServices(_services);
  }

  Future<void> _addService() async {
    final service = await _showServiceEditor(const {
      'name': '',
      'duration': 60,
      'price': 0.0,
    }, creating: true);
    if (service != null && mounted) {
      setState(() => _services.add(service));
      ref.read(onboardingProvider.notifier).setServices(_services);
    }
  }

  Future<void> _editService(int index) async {
    final service = await _showServiceEditor(_services[index]);
    if (service != null && mounted) {
      setState(() => _services[index] = service);
      ref.read(onboardingProvider.notifier).setServices(_services);
    }
  }

  Future<Map<String, dynamic>?> _showServiceEditor(
    Map<String, dynamic> service, {
    bool creating = false,
  }) => showWorkloopBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        OnboardingServiceEditor(service: service, creating: creating),
  );

  void _continue() {
    ref.read(onboardingProvider.notifier).setServices(_services);
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
            'Your services.',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).t1,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These are starting suggestions. Check every price and duration before continuing, or skip and add your own later.',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.of(context).t3,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          ..._services.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return InkWell(
              onTap: () => _editService(i),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.of(context).bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.of(context).border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['name'],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.of(context).t1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatFriendlyDuration(s['duration'] as int)}  ·  ${formatPounds(s['price'] as num)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.of(context).t3,
                            ),
                          ),
                          if ((s['description']?.toString().trim() ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              s['description'].toString().trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.of(context).t2,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    WorkloopIconButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Remove ${s['name']}',
                      color: AppColors.of(context).error,
                      backgroundColor: AppColors.of(context).errorDim,
                      onTap: () => _removeService(i),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_rounded,
                      color: AppColors.of(context).t3,
                      size: 18,
                    ),
                  ],
                ),
              ),
            );
          }),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addService,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.of(context).green,
                backgroundColor: AppColors.of(context).bgCard,
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(color: AppColors.of(context).border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Add a service',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _services.isNotEmpty ? _continue : null,
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: WorkloopTextButton(
              label: 'Skip — add services later',
              onPressed: () {
                ref.read(onboardingProvider.notifier).setServices([]);
                widget.onNext();
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
