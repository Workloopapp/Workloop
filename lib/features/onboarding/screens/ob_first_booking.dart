import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/onboarding_provider.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';

class ObFirstBooking extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const ObFirstBooking({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<ObFirstBooking> createState() => _ObFirstBookingState();
}

class _ObFirstBookingState extends ConsumerState<ObFirstBooking> {
  final _clientNameController = TextEditingController();
  String? _selectedService;
  DateTime _selectedDate = DateTime.now();
  int _selectedHour = 9;
  int _selectedMinute = 0;

  @override
  void initState() {
    super.initState();
    final booking = ref.read(onboardingProvider).firstBooking;
    if (booking == null) return;
    _clientNameController.text = booking['clientName'] as String? ?? '';
    final savedService = booking['serviceName'] as String?;
    _selectedService =
        ref
            .read(onboardingProvider)
            .services
            .any((service) => service['name'] == savedService)
        ? savedService
        : null;
    _selectedDate =
        DateTime.tryParse(booking['date'] as String? ?? '') ?? DateTime.now();
    _selectedHour = (booking['hour'] as num?)?.toInt() ?? 9;
    _selectedMinute = (booking['minute'] as num?)?.toInt() ?? 0;
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _clientNameController.text.trim().isNotEmpty && _selectedService != null;

  void _saveAndContinue() {
    if (!_canContinue) return;
    ref.read(onboardingProvider.notifier).setFirstBooking({
      'clientName': _clientNameController.text.trim(),
      'serviceName': _selectedService,
      'date': _selectedDate.toIso8601String().split('T')[0],
      'hour': _selectedHour,
      'minute': _selectedMinute,
    });
    widget.onNext();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showWorkloopDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      title: 'Choose booking date',
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showWorkloopTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _selectedHour, minute: _selectedMinute),
      title: 'Choose booking time',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedHour = picked.hour;
      _selectedMinute = picked.minute;
    });
  }

  String get _formattedDate {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
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
    final isToday =
        _selectedDate.day == DateTime.now().day &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.year == DateTime.now().year;
    if (isToday) return 'Today';
    return '${days[_selectedDate.weekday - 1]} ${_selectedDate.day} ${months[_selectedDate.month - 1]}';
  }

  String get _formattedTime =>
      '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(onboardingProvider).services;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.pageX),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Create your\nfirst booking.',
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
            'Add your first booking to get started.',
            style: TextStyle(fontSize: 15, color: AppColors.of(context).t3),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            services.isEmpty
                ? 'You can skip this step. Add a service in Business when you are ready to book real work.'
                : 'This step is optional. To add a booking, enter the required details and check the date and time. Nothing is added until you finish setup.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.of(context).t3,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),

          // Client name
          _label('Client name'),
          const SizedBox(height: 8),
          TextField(
            controller: _clientNameController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppColors.of(context).t1, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'e.g. Sarah Johnson',
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
          ),
          const SizedBox(height: 20),

          // Service
          _label('Service'),
          const SizedBox(height: 8),
          WorkloopPickerField<String>(
            value: _selectedService,
            title: 'Choose a service',
            hint: 'Select a service',
            searchHint: 'Search services',
            options: services
                .map(
                  (service) => WorkloopPickerOption(
                    value: service['name'] as String,
                    label: service['name'] as String,
                    subtitle: service['duration'] == null
                        ? null
                        : formatFriendlyDuration(
                            (service['duration'] as num).toInt(),
                          ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedService = value),
          ),
          const SizedBox(height: 20),

          // Date and time row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Date', isRequired: null),
                    const SizedBox(height: 8),
                    Semantics(
                      button: true,
                      label: 'Booking date',
                      value: _formattedDate,
                      onTap: _pickDate,
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _pickDate,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: AppColors.of(context).bgCard,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: AppColors.of(context).border,
                              ),
                            ),
                            child: Text(
                              _formattedDate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.of(context).t1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Time', isRequired: null),
                    const SizedBox(height: 8),
                    Semantics(
                      button: true,
                      label: 'Booking time',
                      value: _formattedTime,
                      onTap: _pickTime,
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _pickTime,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: AppColors.of(context).bgCard,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: AppColors.of(context).border,
                              ),
                            ),
                            child: Text(
                              _formattedTime,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.of(context).t1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _canContinue ? _saveAndContinue : null,
              child: const Text(
                'Create booking',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: WorkloopTextButton(
              label: 'Skip — I’ll do this later',
              onPressed: () {
                ref.read(onboardingProvider.notifier).clearFirstBooking();
                widget.onNext();
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _label(String text, {bool? isRequired = true}) {
    return WorkloopFieldLabel(
      text,
      isRequired: isRequired,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.of(context).t2,
        letterSpacing: 0,
      ),
    );
  }
}
