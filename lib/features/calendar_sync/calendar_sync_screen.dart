import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/utils/calendar_export.dart';
import '../../shared/widgets/slate_ui.dart';
import '../imports/calendar_import_screen.dart';

class CalendarSyncScreen extends ConsumerWidget {
  const CalendarSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageX,
                AppSpacing.screenTop,
                AppSpacing.pageX,
                40,
              ),
              children: [
                const WorkloopRouteHeader(
                  title: 'Calendar tools',
                  backSemanticLabel: 'Back to settings',
                ),
                const SizedBox(height: AppSpacing.xxl),
                const WorkloopSectionHeader(label: 'Import events'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Choose calendar events, review them, then create them once as Workloop bookings.',
                  style: TextStyle(
                    color: AppColors.of(context).t2,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                WorkloopPrimaryButton(
                  label: 'Import calendar events',
                  icon: LucideIcons.download,
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CalendarImportScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const WorkloopSectionHeader(label: 'Export bookings'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Save a point-in-time .ics file of your current bookings. This is not a live two-way connection.',
                  style: TextStyle(
                    color: AppColors.of(context).t2,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _ExportActions(
                  onSave: () => _saveIcsFile(context, ref),
                  onCopy: () => _copyIcsData(context, ref),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const WorkloopSectionHeader(label: 'What to expect'),
                const SizedBox(height: AppSpacing.xs),
                const _SyncRow(
                  icon: LucideIcons.download,
                  label: 'One-time import',
                  value: 'Available',
                ),
                const _SyncRow(
                  icon: LucideIcons.alertTriangle,
                  label: 'Conflict detection',
                  value: 'Active in booking form',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _icsData(WidgetRef ref) async {
    final rows = await ref.read(appointmentsProvider.future);
    return buildWorkloopIcs(rows);
  }

  Future<void> _saveIcsFile(BuildContext context, WidgetRef ref) async {
    try {
      final ics = await _icsData(ref);
      final result = await FilePicker.saveFile(
        dialogTitle: 'Save Workloop calendar',
        fileName: 'workloop-bookings.ics',
        type: FileType.custom,
        allowedExtensions: const ['ics'],
        bytes: Uint8List.fromList(utf8.encode(ics)),
      );
      if (!context.mounted || result == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Calendar file saved')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calendar file could not be saved'),
          backgroundColor: AppColors.of(context).error,
        ),
      );
    }
  }

  Future<void> _copyIcsData(BuildContext context, WidgetRef ref) async {
    try {
      final ics = await _icsData(ref);
      await Clipboard.setData(ClipboardData(text: ics));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calendar export data copied'),
          backgroundColor: AppColors.of(context).success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calendar export data could not be copied'),
          backgroundColor: AppColors.of(context).error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _ExportActions extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onCopy;
  const _ExportActions({required this.onSave, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkloopPrimaryButton(
          label: 'Save calendar file',
          icon: LucideIcons.download,
          secondary: true,
          onPressed: onSave,
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: WorkloopTextButton(
            label: 'Copy raw calendar data',
            onPressed: onCopy,
          ),
        ),
      ],
    );
  }
}

class _SyncRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SyncRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final useStackedLayout =
            constraints.maxWidth < 340 || textScaler.scale(12) > 15;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.of(context).bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Row(
            crossAxisAlignment: useStackedLayout
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.of(context).t3, size: 17),
              const SizedBox(width: 12),
              Expanded(
                child: useStackedLayout
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SyncRowLabel(label),
                          const SizedBox(height: AppSpacing.xxs),
                          _SyncRowValue(value),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: _SyncRowLabel(label)),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(child: _SyncRowValue(value, alignEnd: true)),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SyncRowLabel extends StatelessWidget {
  final String label;

  const _SyncRowLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppColors.of(context).t1,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SyncRowValue extends StatelessWidget {
  final String value;
  final bool alignEnd;

  const _SyncRowValue(this.value, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: TextStyle(
        color: AppColors.of(context).t3,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
