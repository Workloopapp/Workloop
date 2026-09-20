import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/notes_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/notes_repository.dart';
import '../../shared/repositories/tasks_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import 'import_models.dart';

enum TextImportType { notes, tasks }

class TextImportScreen extends ConsumerStatefulWidget {
  final TextImportType type;

  const TextImportScreen({super.key, required this.type});

  @override
  ConsumerState<TextImportScreen> createState() => _TextImportScreenState();
}

class _TextImportScreenState extends ConsumerState<TextImportScreen> {
  final List<({String name, String content})> _files = [];
  final Set<int> _selected = {};
  bool _loading = false;
  bool _importing = false;
  String? _message;

  String get _noun => widget.type == TextImportType.notes ? 'notes' : 'tasks';

  Future<void> _chooseFiles() async {
    if (_loading || _importing) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.type == TextImportType.notes
            ? const ['txt', 'md', 'markdown']
            : const ['txt', 'md'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null) return;
      final files = <({String name, String content})>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        String content;
        try {
          content = utf8.decode(file.bytes!);
        } on FormatException {
          content = latin1.decode(file.bytes!);
        }
        if (content.trim().isNotEmpty) {
          files.add((name: file.name, content: content.trim()));
        }
      }
      if (!mounted) return;
      setState(() {
        _files
          ..clear()
          ..addAll(files);
        _selected
          ..clear()
          ..addAll(List.generate(files.length, (index) => index));
        _message = files.isEmpty ? 'No readable text was found.' : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'The selected files could not be read.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    if (_importing || _selected.isEmpty) return;
    final attemptedIndices =
        _selected.where((index) => index >= 0 && index < _files.length).toList()
          ..sort();
    if (attemptedIndices.isEmpty) return;
    setState(() {
      _importing = true;
      _message = null;
    });
    var imported = 0;
    var failedItems = 0;
    final completedFileIndices = <int>{};
    final failedTaskLines = <int, List<String>>{};
    final failedFiles = <String>[];
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null) throw StateError('Workspace unavailable');
      for (final index in attemptedIndices) {
        final file = _files[index];
        if (widget.type == TextImportType.notes) {
          try {
            final lines = file.content.split(RegExp(r'\r?\n'));
            final titleCandidate = lines.first
                .replaceFirst(RegExp(r'^#+\s*'), '')
                .trim();
            await ref
                .read(notesRepositoryProvider)
                .create(
                  workspaceId: workspaceId,
                  title: titleCandidate.isEmpty
                      ? _titleFromFile(file.name)
                      : titleCandidate,
                  body: file.content,
                );
            imported++;
            completedFileIndices.add(index);
          } catch (_) {
            failedItems++;
            failedFiles.add(file.name);
          }
        } else {
          final failures = <String>[];
          for (final line in taskTitlesFromImportText(file.content)) {
            try {
              await ref
                  .read(tasksRepositoryProvider)
                  .create(
                    workspaceId: workspaceId,
                    title: line,
                    priority: 'medium',
                  );
              imported++;
            } catch (_) {
              failures.add(line);
              failedItems++;
            }
          }
          if (failures.isEmpty) {
            completedFileIndices.add(index);
          } else {
            failedTaskLines[index] = failures;
            failedFiles.add(file.name);
          }
        }
      }
      final result = reconcileImportAttempt(
        attempted: attemptedIndices,
        completed: completedFileIndices,
      );
      final itemName = widget.type == TextImportType.notes ? 'note' : 'task';
      final summary = failedItems == 0
          ? '$imported ${imported == 1 ? itemName : _noun} ${imported == 1 ? 'was' : 'were'} created.'
          : '$imported ${imported == 1 ? itemName : _noun} ${imported == 1 ? 'was' : 'were'} created. '
                '$failedItems ${failedItems == 1 ? itemName : _noun} '
                '${failedItems == 1 ? 'remains' : 'remain'} selected to retry.';
      if (mounted) {
        setState(() {
          final originalFiles = List.of(_files);
          final originalSelection = Set<int>.of(_selected);
          final nextFiles = <({String name, String content})>[];
          final nextSelection = <int>{};
          for (var index = 0; index < originalFiles.length; index++) {
            if (result.completed.contains(index)) continue;
            final file = originalFiles[index];
            final retryLines = failedTaskLines[index];
            final nextIndex = nextFiles.length;
            nextFiles.add(
              retryLines == null
                  ? file
                  : (name: file.name, content: retryLines.join('\n')),
            );
            if (result.retryable.contains(index) ||
                (!attemptedIndices.contains(index) &&
                    originalSelection.contains(index))) {
              nextSelection.add(nextIndex);
            }
          }
          _files
            ..clear()
            ..addAll(nextFiles);
          _selected
            ..clear()
            ..addAll(nextSelection);
          _message = summary;
        });
      }
      ref.invalidate(allNotesProvider);
      ref.invalidate(tasksProvider);
      if (!mounted) return;
      if (imported > 0) {
        SlateHaptics.success();
      } else {
        SlateHaptics.warning();
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${_capitalise(_noun)} imported'),
          content: Text(
            failedItems == 0
                ? summary
                : '$summary Affected ${failedFiles.length == 1 ? 'file' : 'files'}: ${failedFiles.take(3).join(', ')}${failedFiles.length > 3 ? '…' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted && failedItems == 0) Navigator.pop(context, imported);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'The import could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _titleFromFile(String name) {
    return name.replaceFirst(
      RegExp(r'\.(txt|md|markdown)$', caseSensitive: false),
      '',
    );
  }

  String _capitalise(String value) {
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final isNotes = widget.type == TextImportType.notes;
    return WorkloopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkloopRouteHeader(title: 'Import ${isNotes ? 'notes' : 'tasks'}'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isNotes
                ? 'Apple Notes and Google Keep do not provide safe direct access. Exported .txt and .md files keep you in control.'
                : 'Each non-empty line becomes an open task. Review the files before confirming.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          WorkloopPrimaryButton(
            label: _loading ? 'Reading files…' : 'Choose files',
            icon: LucideIcons.fileUp,
            onPressed: _loading || _importing ? null : _chooseFiles,
          ),
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              container: true,
              liveRegion: true,
              label: _message!,
              child: ExcludeSemantics(
                child: Text(
                  _message!,
                  style: TextStyle(color: AppColors.of(context).t3),
                ),
              ),
            ),
          ],
          if (_files.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: WorkloopSectionHeader(
                    label:
                        '${_files.length} ${_files.length == 1 ? 'file' : 'files'} ready',
                  ),
                ),
                WorkloopTextButton(
                  label: _selected.length == _files.length
                      ? 'Clear'
                      : 'Select all',
                  onPressed: _importing
                      ? null
                      : () => setState(() {
                          if (_selected.length == _files.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(
                                List.generate(_files.length, (index) => index),
                              );
                          }
                        }),
                ),
              ],
            ),
            WorkloopSurface(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  for (var index = 0; index < _files.length; index++)
                    WorkloopListRow(
                      flat: true,
                      onTap: _importing
                          ? null
                          : () => setState(() {
                              if (!_selected.add(index)) {
                                _selected.remove(index);
                              }
                            }),
                      showDivider: index != _files.length - 1,
                      leading: Checkbox.adaptive(
                        value: _selected.contains(index),
                        onChanged: _importing
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  _selected.add(index);
                                } else {
                                  _selected.remove(index);
                                }
                              }),
                      ),
                      title: Text(
                        _files[index].name,
                        style: TextStyle(
                          color: AppColors.of(context).t1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _files[index].content.replaceAll(RegExp(r'\s+'), ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.of(context).t3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            WorkloopPrimaryButton(
              label: _importing ? 'Importing…' : 'Import selected',
              icon: LucideIcons.download,
              onPressed: _importing || _selected.isEmpty ? null : _import,
            ),
          ],
        ],
      ),
    );
  }
}
