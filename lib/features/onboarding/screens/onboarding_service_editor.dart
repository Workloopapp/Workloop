import '../../finance/documents/business_document.dart' show parseDocumentMoney;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';

/// Owns input state until the sheet is removed, including its exit transition.
class OnboardingServiceEditor extends StatefulWidget {
  final Map<String, dynamic> service;
  final bool creating;

  const OnboardingServiceEditor({
    super.key,
    required this.service,
    this.creating = false,
  });

  @override
  State<OnboardingServiceEditor> createState() =>
      _OnboardingServiceEditorState();
}

class _OnboardingServiceEditorState extends State<OnboardingServiceEditor> {
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  late final TextEditingController durationHoursController;
  late final TextEditingController durationMinutesController;
  late final TextEditingController priceController;
  String? error;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(
      text: widget.service['name']?.toString() ?? '',
    );
    descriptionController = TextEditingController(
      text: widget.service['description']?.toString() ?? '',
    );
    final initialDuration = (widget.service['duration'] as num? ?? 60).toInt();
    durationHoursController = TextEditingController(
      text: '${initialDuration ~/ 60}',
    );
    durationMinutesController = TextEditingController(
      text: '${initialDuration.remainder(60)}',
    );
    priceController = TextEditingController(
      text: (widget.service['price'] as num? ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    durationHoursController.dispose();
    durationMinutesController.dispose();
    priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final editorHeight = math.max(
      120.0,
      math.min(
        media.size.height * 0.72,
        media.size.height - media.viewInsets.bottom - 140,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SlateSheetFrame(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: editorHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.creating ? 'Add your service' : 'Edit service',
                  style: TextStyle(
                    color: AppColors.of(context).t1,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Add the details your customers need to book.',
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                WorkloopFormField(
                  label: 'Service name',
                  isRequired: true,
                  child: TextField(
                    controller: nameController,
                    autofocus: widget.creating,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'For example, Conservatory roof clean',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                WorkloopFormField(
                  label: 'Description',
                  isRequired: false,
                  helperText: 'Shown to customers on your booking page.',
                  child: TextField(
                    key: const ValueKey('onboarding-service-description'),
                    controller: descriptionController,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'What’s included in this service?',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                WorkloopFieldLabel(
                  'Duration',
                  isRequired: true,
                  style: TextStyle(
                    color: AppColors.of(context).t3,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter a total of 5 minutes to 24 hours. An empty hours or minutes field counts as 0.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackFields =
                        constraints.maxWidth < 360 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    final hoursField = WorkloopFormField(
                      label: 'Hours',
                      child: TextField(
                        controller: durationHoursController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '1'),
                      ),
                    );
                    final minutesField = WorkloopFormField(
                      label: 'Minutes',
                      child: TextField(
                        controller: durationMinutesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '30'),
                      ),
                    );
                    if (stackFields) {
                      return Column(
                        children: [
                          hoursField,
                          const SizedBox(height: 10),
                          minutesField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: hoursField),
                        const SizedBox(width: 12),
                        Expanded(child: minutesField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                WorkloopFormField(
                  label: 'Price',
                  isRequired: true,
                  helperText: 'Enter 0 for a free service.',
                  child: TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(prefixText: '£'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: TextStyle(color: AppColors.of(context).error),
                  ),
                ],
                const SizedBox(height: 18),
                SlateButton(
                  label: widget.creating ? 'Add service' : 'Save service',
                  onPressed: () {
                    final name = nameController.text.trim();
                    final hours = int.tryParse(
                      durationHoursController.text.trim().isEmpty
                          ? '0'
                          : durationHoursController.text.trim(),
                    );
                    final minutes = int.tryParse(
                      durationMinutesController.text.trim().isEmpty
                          ? '0'
                          : durationMinutesController.text.trim(),
                    );
                    final duration = hours == null || minutes == null
                        ? null
                        : (hours * 60) + minutes;
                    final pricePence = parseDocumentMoney(priceController.text);
                    if (name.isEmpty ||
                        duration == null ||
                        (hours ?? -1) < 0 ||
                        (minutes ?? -1) < 0 ||
                        (minutes ?? 60) > 59 ||
                        duration < 5 ||
                        duration > 1440 ||
                        pricePence == null) {
                      setState(() {
                        error =
                            'Add a name, a duration from 5 minutes to 24 hours, and a valid price.';
                      });
                      return;
                    }
                    Navigator.pop(context, {
                      'name': name,
                      'description': descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                      'duration': duration,
                      'price': pricePence / 100,
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
