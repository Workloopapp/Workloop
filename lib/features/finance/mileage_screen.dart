import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/utils/workflow_idempotency.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import 'expense_records_repository.dart';
import 'tax_estimate.dart';
import 'widgets/money_editor_widgets.dart';

class MileageScreen extends ConsumerWidget {
  const MileageScreen({super.key});
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    MileageEntry? entry,
  }) async {
    final workspace = await ref.read(workspaceIdProvider.future);
    if (workspace == null ||
        !context.mounted ||
        ref.read(workspaceIdProvider).value != workspace) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MileageEditor(
          entry: entry,
          workspaceId: workspace,
          recent: ref.read(mileageEntriesProvider).isLoading
              ? const []
              : ref.read(mileageEntriesProvider).value ?? const [],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, List<MileageEntry> entries) async {
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    final content = StringBuffer('Date,Miles,Vehicle,Type,Business purpose\n');
    for (final entry in entries) {
      // Prefix user text to prevent spreadsheet formula execution on opening.
      String safe(String value) =>
          cell(RegExp(r'^[=+@\-\t\r]').hasMatch(value) ? "'$value" : value);
      content.writeln(
        '${entry.date.toIso8601String().split('T').first},${formatHundredths(entry.milesHundredths)},${safe(entry.vehicle)},${entry.vehicleType},${safe(entry.purpose)}',
      );
    }
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(content.toString())),
            mimeType: 'text/csv',
            name: 'workloop-mileage.csv',
          ),
        ],
        fileNameOverrides: ['workloop-mileage.csv'],
        title: 'Workloop business mileage',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(mileageEntriesProvider);
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
                    title: 'Business mileage',
                    backSemanticLabel: 'Back to Money',
                    onBack: () => Navigator.pop(context),
                    trailing: IconButton(
                      tooltip: 'Log journey',
                      onPressed: () => _edit(context, ref),
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ),
                Expanded(
                  child: entries.when(
                    skipLoadingOnRefresh: false,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: TextButton(
                        onPressed: () => ref.invalidate(mileageEntriesProvider),
                        child: const Text('Could not load mileage · retry'),
                      ),
                    ),
                    data: (rows) => RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(mileageEntriesProvider);
                        await ref.read(mileageEntriesProvider.future);
                      },
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.pageX,
                        ),
                        children: [
                          const Text(
                            'Keep a record of business journeys',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            'Log the date, business purpose, vehicle and miles. Exclude private travel and ordinary commuting. A mileage deduction is not a cash expense.',
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton.icon(
                            onPressed: () => _edit(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Log journey'),
                          ),
                          if (rows.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _export(context, rows),
                              icon: const Icon(Icons.ios_share),
                              label: const Text('Export mileage log'),
                            ),
                          const SizedBox(height: AppSpacing.lg),
                          if (rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: AppSpacing.xl,
                              ),
                              child: Text(
                                'No journeys yet. Add your first business journey when you return.',
                              ),
                            ),
                          for (final entry in rows) ...[
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.purpose),
                              subtitle: Text(
                                '${entry.date.day}/${entry.date.month}/${entry.date.year} · ${entry.vehicle}\n${formatHundredths(entry.milesHundredths)} business miles',
                              ),
                              onTap: () => _edit(context, ref, entry: entry),
                            ),
                            const Divider(height: 1),
                          ],
                          const SizedBox(height: AppSpacing.xxl),
                        ],
                      ),
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

class _MileageEditor extends ConsumerStatefulWidget {
  final MileageEntry? entry;
  final String workspaceId;
  final List<MileageEntry> recent;
  const _MileageEditor({
    this.entry,
    required this.workspaceId,
    this.recent = const [],
  });
  @override
  ConsumerState<_MileageEditor> createState() => _MileageEditorState();
}

class _MileageEditorState extends ConsumerState<_MileageEditor> {
  final _miles = TextEditingController(),
      _purpose = TextEditingController(),
      _vehicle = TextEditingController();
  late DateTime _date;
  String _type = 'car_van';
  bool _busy = false;
  final _form = GlobalKey<FormState>();
  final _creationId = createPublicRequestToken();
  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _date = entry?.date ?? DateTime.now();
    if (entry != null) {
      _miles.text = formatHundredths(entry.milesHundredths);
      _purpose.text = entry.purpose;
      _vehicle.text = entry.vehicle;
      _type = entry.vehicleType;
    } else if (widget.recent.isNotEmpty) {
      _vehicle.text = widget.recent.first.vehicle;
      _type = widget.recent.first.vehicleType;
    }
  }

  @override
  void dispose() {
    _miles.dispose();
    _purpose.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || ref.read(workspaceIdProvider).value != widget.workspaceId) {
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseRecordsRepositoryProvider)
          .saveJourney(
            workspaceId: widget.workspaceId,
            id: widget.entry?.id,
            creationId: _creationId,
            date: _date,
            milesHundredths: parseHundredths(_miles.text) ?? 0,
            purpose: _purpose.text,
            vehicle: _vehicle.text,
            vehicleType: _type,
          );
      if (!mounted ||
          ref.read(workspaceIdProvider).value != widget.workspaceId) {
        return;
      }
      ref.invalidate(mileageEntriesProvider);
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Could not save this journey. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete journey?'),
        content: const Text(
          'This removes the journey from your mileage log and future tax estimates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (remove != true ||
        !mounted ||
        ref.read(workspaceIdProvider).value != widget.workspaceId) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseRecordsRepositoryProvider)
          .deleteJourney(widget.entry!.id);
      if (!mounted ||
          ref.read(workspaceIdProvider).value != widget.workspaceId) {
        return;
      }
      ref.invalidate(mileageEntriesProvider);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete this journey. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(workspaceIdProvider).value != widget.workspaceId) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business changed')),
        body: const Center(
          child: Text('Reopen mileage from your current business.'),
        ),
      );
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
                    title: widget.entry == null
                        ? 'Log journey'
                        : 'Edit journey',
                    backSemanticLabel: 'Back to mileage',
                    onBack: () {
                      if (!_busy) Navigator.pop(context);
                    },
                    trailing: MoneySaveAction(
                      label: 'Save',
                      loading: _busy,
                      enabled: !_busy,
                      onTap: _save,
                    ),
                  ),
                ),
                Expanded(
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.pageX),
                      children: [
                        MoneyDateField(
                          label: 'Journey date',
                          value: '${_date.day}/${_date.month}/${_date.year}',
                          onTap: () async {
                            if (_busy) return;
                            final date = await showWorkloopDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null && mounted) {
                              setState(() => _date = date);
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TextFormField(
                          controller: _miles,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            label: WorkloopFieldLabel(
                              'Business miles',
                              isRequired: true,
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            hintText: 'e.g. 12.50',
                            errorMaxLines: 3,
                          ),
                          validator: (value) {
                            final miles = parseHundredths(value ?? '');
                            return miles == null ||
                                    miles <= 0 ||
                                    miles > 1000000
                                ? 'Enter business miles above 0 and up to 10,000, with up to two decimal places.'
                                : null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TextFormField(
                          controller: _purpose,
                          enabled: !_busy,
                          maxLength: 500,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            label: WorkloopFieldLabel(
                              'Business purpose and route',
                              isRequired: true,
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            hintText:
                                'Client visit · workshop to client and back',
                            errorMaxLines: 3,
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Add where you went and the business reason.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _vehicle,
                          enabled: !_busy,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            label: WorkloopFieldLabel(
                              'Vehicle',
                              isRequired: true,
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            hintText: 'e.g. AB12 CDE',
                            errorMaxLines: 3,
                          ),
                          validator: (value) {
                            final name = (value ?? '').trim().toLowerCase();
                            if (name.isEmpty) {
                              return 'Add a registration or consistent vehicle name.';
                            }
                            if (widget.recent.any(
                              (entry) =>
                                  entry.id != widget.entry?.id &&
                                  entry.vehicle.toLowerCase() == name &&
                                  entry.vehicleType != _type,
                            )) {
                              return 'This vehicle already has a different type. Use its existing type or correct the earlier journey.';
                            }
                            return null;
                          },
                        ),
                        if (widget.entry == null && widget.recent.isNotEmpty)
                          const Text(
                            'Your most recent vehicle is filled in. Change it if you used a different one.',
                          ),
                        const SizedBox(height: AppSpacing.md),
                        WorkloopFormField(
                          label: 'Vehicle type',
                          isRequired: true,
                          child: WorkloopPickerField<String>(
                            enabled: !_busy,
                            value: _type,
                            title: 'Vehicle type',
                            hint: 'Choose vehicle type',
                            options: const [
                              WorkloopPickerOption(
                                value: 'car_van',
                                label: 'Car or van',
                              ),
                              WorkloopPickerOption(
                                value: 'motorcycle',
                                label: 'Motorcycle',
                              ),
                            ],
                            onChanged: (value) => setState(() => _type = value),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const Text(
                          'Use the same vehicle name for every journey. In Tax estimate, choose actual costs or mileage to avoid claiming the same vehicle costs twice.',
                        ),
                        if (widget.entry != null)
                          TextButton(
                            onPressed: _busy ? null : _delete,
                            child: const Text('Delete journey'),
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
