import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/clients_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import 'import_models.dart';
import 'client_file_import.dart';

class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key});

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  CsvTable? _table;
  String? _fileName;
  final Map<int, ClientImportField> _mapping = {};
  final Set<int> _completedRows = {};
  final Set<int> _excludedRows = {};
  int _previewLimit = 20;
  bool _loading = false;
  bool _importing = false;
  bool _reviewing = false;
  bool _skipDuplicates = true;
  String? _error;

  Future<void> _chooseFile() async {
    if (_loading || _importing || _reviewing) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'vcf'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('File could not be read');
      final table = parseClientFile(bytes, fileName: file.name);
      final mapping = <int, ClientImportField>{};
      for (var index = 0; index < table.headers.length; index++) {
        final field = guessClientImportField(table.headers[index]);
        mapping[index] = mapping.containsValue(field)
            ? ClientImportField.ignore
            : field;
      }
      if (!mounted) return;
      setState(() {
        _table = table;
        _fileName = file.name;
        _mapping
          ..clear()
          ..addAll(mapping);
        _completedRows.clear();
        _excludedRows.clear();
        _previewLimit = 20;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : 'This file could not be prepared. Choose a CSV or vCard file and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasNameMapping => [
    ClientImportField.name,
    ClientImportField.givenName,
    ClientImportField.familyName,
  ].any(_mapping.containsValue);

  List<ImportCandidate> _candidates({bool includeExcluded = false}) {
    final table = _table;
    if (table == null || !_hasNameMapping) return const [];
    return [
      for (var index = 0; index < table.rows.length; index++)
        if (!_completedRows.contains(index) &&
            (includeExcluded || !_excludedRows.contains(index)) &&
            _field(table.rows[index], ClientImportField.name) != null)
          ImportCandidate(
            sourceId: 'csv-$index',
            name: _field(table.rows[index], ClientImportField.name)!,
            phone: _field(table.rows[index], ClientImportField.phone),
            email: _field(table.rows[index], ClientImportField.email),
            address: _field(table.rows[index], ClientImportField.address),
          ),
    ];
  }

  String? _field(List<String> row, ClientImportField field) =>
      clientImportValue(row, _mapping, field);

  Future<void> _import() async {
    if (_importing || _reviewing) return;
    final table = _table;
    if (table == null) return;
    final candidates = _candidates();
    if (!_hasNameMapping) {
      setState(
        () => _error =
            'Choose a client name column, or first and last name columns.',
      );
      return;
    }
    if (candidates.isEmpty) {
      setState(
        () => _error = _candidates(includeExcluded: true).isEmpty
            ? 'No rows contain a client name. Check the name columns above.'
            : 'Select at least one client to import.',
      );
      return;
    }
    setState(() => _reviewing = true);
    bool? confirmed;
    try {
      confirmed = await showWorkloopBottomSheet<bool>(
        context: context,
        builder: (context) => SlateSheetFrame(
          scrollable: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review client import',
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${candidates.length} selected clients are ready. Unselected contacts stay in your file. Rows without a name will be reported.',
                style: TextStyle(color: AppColors.of(context).t3, height: 1.45),
              ),
              const SizedBox(height: AppSpacing.lg),
              WorkloopPrimaryButton(
                label: 'Import clients',
                icon: LucideIcons.download,
                onPressed: () => Navigator.pop(context, true),
              ),
              const SizedBox(height: AppSpacing.xs),
              WorkloopPrimaryButton(
                label: 'Keep reviewing',
                secondary: true,
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
    if (!mounted || confirmed != true) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    var imported = 0;
    var skipped = 0;
    final completedThisAttempt = <int>{};
    final failures = <String>[];
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null) throw StateError('Workspace unavailable');
      final existingClients = await ref.read(clientsProvider.future);
      final existing = existingClients
          .map(
            (client) =>
                (name: client.name, phone: client.phone, email: client.email),
          )
          .toList();
      final repository = ref.read(clientsRepositoryProvider);
      for (var index = 0; index < table.rows.length; index++) {
        if (_completedRows.contains(index) || _excludedRows.contains(index)) {
          continue;
        }
        final row = table.rows[index];
        final name = _field(row, ClientImportField.name);
        if (name == null) {
          failures.add('Row ${index + 2}: missing name');
          continue;
        }
        final candidate = ImportCandidate(
          sourceId: 'csv-$index',
          name: name,
          phone: _field(row, ClientImportField.phone),
          email: _field(row, ClientImportField.email),
          address: _field(row, ClientImportField.address),
        );
        if (_skipDuplicates &&
            isLikelyDuplicate(candidate: candidate, existing: existing)) {
          skipped++;
          completedThisAttempt.add(index);
          continue;
        }
        try {
          final tags = (_field(row, ClientImportField.tags) ?? '')
              .split(RegExp(r'[|;]'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
          await repository.create(
            workspaceId: workspaceId,
            name: name,
            phone: candidate.phone,
            email: candidate.email,
            address: candidate.address,
            notes: _field(row, ClientImportField.notes),
            source: _fileName?.toLowerCase().endsWith('.vcf') == true
                ? 'vCard import'
                : 'CSV import',
            status: 'lead',
            preferredContactMethod: candidate.email?.isNotEmpty == true
                ? 'email'
                : 'phone',
            tags: {...tags, 'imported'}.toList(),
          );
          imported++;
          completedThisAttempt.add(index);
          existing.add((
            name: candidate.name,
            phone: candidate.phone,
            email: candidate.email,
          ));
        } catch (_) {
          failures.add('Row ${index + 2}: $name');
        }
      }
      final attemptedRows = List.generate(table.rows.length, (index) => index)
          .where(
            (index) =>
                !_completedRows.contains(index) &&
                !_excludedRows.contains(index),
          );
      final result = reconcileImportAttempt(
        attempted: attemptedRows,
        completed: completedThisAttempt,
      );
      final summary =
          '$imported ${imported == 1 ? 'client was' : 'clients were'} imported'
          '${skipped > 0 ? '; $skipped likely ${skipped == 1 ? 'duplicate was' : 'duplicates were'} skipped' : ''}.'
          '${result.retryable.isNotEmpty ? ' ${result.retryable.length} ${result.retryable.length == 1 ? 'row remains' : 'rows remain'} to retry.' : ''}';
      if (mounted) {
        setState(() {
          _completedRows.addAll(result.completed);
          _error = failures.isEmpty ? null : summary;
        });
      }
      ref.invalidate(clientsProvider);
      ref.invalidate(clientCrmRecordsProvider);
      if (!mounted) return;
      if (imported > 0 || skipped > 0) {
        SlateHaptics.success();
      } else {
        SlateHaptics.warning();
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import complete'),
          content: SingleChildScrollView(
            child: Text(
              failures.isEmpty
                  ? summary
                  : '$summary\n\nRows needing attention:\n${failures.take(8).join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted && failures.isEmpty) Navigator.pop(context, imported);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The import could not be completed. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = _table;
    final preview = _candidates(includeExcluded: true);
    final previewRows = preview.take(_previewLimit).toList();
    return WorkloopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkloopRouteHeader(title: 'Import clients'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Bring contacts from Apple Contacts, Google Contacts or a spreadsheet. Choose a CSV or vCard (.vcf), review the details and select who to import.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          WorkloopPrimaryButton(
            label: _loading ? 'Reading file…' : 'Choose contact file',
            icon: LucideIcons.fileUp,
            onPressed: _loading || _importing || _reviewing
                ? null
                : _chooseFile,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              container: true,
              liveRegion: true,
              label: _error!,
              child: ExcludeSemantics(
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: AppColors.of(context).error,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
          if (table != null) ...[
            const SizedBox(height: AppSpacing.xl),
            WorkloopSurface(
              child: Row(
                children: [
                  Icon(
                    LucideIcons.fileSpreadsheet,
                    color: AppColors.of(context).t2,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fileName ?? 'Contact file',
                          style: TextStyle(
                            color: AppColors.of(context).t1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${table.rows.length - _completedRows.length} rows remaining'
                          '${_completedRows.isNotEmpty ? ' · ${_completedRows.length} completed' : ''}'
                          ' · ${table.headers.length} columns',
                          style: TextStyle(
                            color: AppColors.of(context).t3,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const WorkloopSectionHeader(label: 'Match columns'),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Required: a client name, from a full-name column or first/last name columns. All other details are optional.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var index = 0; index < table.headers.length; index++) ...[
              Text(
                table.headers[index].isEmpty
                    ? 'Column ${index + 1}'
                    : table.headers[index],
                style: TextStyle(
                  color: AppColors.of(context).t2,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              WorkloopPickerField<ClientImportField>(
                value: _mapping[index],
                title: 'Map ${table.headers[index]}',
                hint: 'Ignore this column',
                options: const [
                  WorkloopPickerOption(
                    value: ClientImportField.ignore,
                    label: 'Ignore this column',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.name,
                    label: 'Full client name',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.givenName,
                    label: 'First name',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.familyName,
                    label: 'Last name',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.phone,
                    label: 'Phone number',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.email,
                    label: 'Email address',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.address,
                    label: 'Booking address',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.notes,
                    label: 'Client notes',
                  ),
                  WorkloopPickerOption(
                    value: ClientImportField.tags,
                    label: 'Tags',
                  ),
                ],
                enabled: !_importing && !_reviewing,
                onChanged: (value) => setState(() {
                  if (value != ClientImportField.ignore) {
                    for (final entry in _mapping.entries.toList()) {
                      if (entry.key != index && entry.value == value) {
                        _mapping[entry.key] = ClientImportField.ignore;
                      }
                    }
                  }
                  _mapping[index] = value;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            const SizedBox(height: AppSpacing.sm),
            WorkloopSectionHeader(
              label: 'Choose clients (${_candidates().length} selected)',
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Review the first phone and email below. Additional vCard numbers and addresses are preserved in client notes. Photos and unsupported fields are not imported.',
              style: TextStyle(
                color: AppColors.of(context).t3,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            for (final candidate in previewRows)
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: !_excludedRows.contains(
                  int.parse(candidate.sourceId.substring(4)),
                ),
                onChanged: _importing || _reviewing
                    ? null
                    : (selected) => setState(() {
                        final index = int.parse(
                          candidate.sourceId.substring(4),
                        );
                        if (selected == true) {
                          _excludedRows.remove(index);
                        } else {
                          _excludedRows.add(index);
                        }
                      }),
                title: Text(candidate.name),
                subtitle: Text(
                  [
                    candidate.phone,
                    candidate.email,
                    candidate.address,
                  ].whereType<String>().join(' · '),
                ),
              ),
            if (preview.length > previewRows.length)
              WorkloopTextButton(
                label:
                    'Show more clients (${preview.length - previewRows.length} remaining)',
                onPressed: () => setState(() => _previewLimit += 20),
              ),
            if (preview.isEmpty)
              Text(
                'No names to preview. Check the name columns above.',
                style: TextStyle(color: AppColors.of(context).t3),
              ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _skipDuplicates,
              onChanged: _importing || _reviewing
                  ? null
                  : (value) => setState(() => _skipDuplicates = value),
              title: const Text('Skip likely duplicates'),
              subtitle: const Text(
                'Matches are checked by name, phone and email.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            WorkloopPrimaryButton(
              label: _importing
                  ? 'Importing…'
                  : _reviewing
                  ? 'Reviewing…'
                  : 'Review import',
              icon: LucideIcons.arrowRight,
              onPressed: _importing || _reviewing ? null : _import,
            ),
          ],
        ],
      ),
    );
  }
}
