import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as device;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/clients_repository.dart';
import '../../shared/widgets/slate_ui.dart';
import 'import_models.dart';

class ContactsImportScreen extends ConsumerStatefulWidget {
  const ContactsImportScreen({super.key});

  @override
  ConsumerState<ContactsImportScreen> createState() =>
      _ContactsImportScreenState();
}

class _ContactsImportScreenState extends ConsumerState<ContactsImportScreen> {
  final _searchController = TextEditingController();
  List<ImportCandidate> _contacts = const [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _importing = false;
  bool _reviewing = false;
  bool _includeDuplicates = false;
  String _query = '';
  String? _message;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (_loading || _importing || _reviewing) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      var permission = await device.FlutterContacts.permissions.check(
        device.PermissionType.read,
      );
      if (permission == device.PermissionStatus.notDetermined ||
          permission == device.PermissionStatus.denied) {
        permission = await device.FlutterContacts.permissions.request(
          device.PermissionType.read,
        );
      }
      if (permission != device.PermissionStatus.granted &&
          permission != device.PermissionStatus.limited) {
        if (!mounted) return;
        setState(() {
          _message = permission == device.PermissionStatus.restricted
              ? 'Contacts access is restricted on this device.'
              : 'Contacts access is off. You can enable it in system settings.';
        });
        return;
      }

      final existingClients = await ref.read(clientsProvider.future);
      final existing = existingClients
          .map(
            (client) =>
                (name: client.name, phone: client.phone, email: client.email),
          )
          .toList();
      final contacts = await device.FlutterContacts.getAll(
        properties: const {
          device.ContactProperty.name,
          device.ContactProperty.phone,
          device.ContactProperty.email,
          device.ContactProperty.address,
          device.ContactProperty.organization,
        },
      );
      final mapped =
          contacts
              .map((contact) {
                final displayName = contact.displayName?.trim();
                final organisation = contact.organizations.isEmpty
                    ? null
                    : contact.organizations.first.name?.trim();
                final name = displayName?.isNotEmpty == true
                    ? displayName!
                    : organisation ?? '';
                if (name.isEmpty) return null;
                final candidate = ImportCandidate(
                  sourceId: contact.id ?? name,
                  name: name,
                  phone: contact.phones.isEmpty
                      ? null
                      : contact.phones.first.number,
                  email: contact.emails.isEmpty
                      ? null
                      : contact.emails.first.address,
                  address: contact.addresses.isEmpty
                      ? null
                      : contact.addresses.first.formatted,
                );
                return candidate.copyWith(
                  likelyDuplicate: isLikelyDuplicate(
                    candidate: candidate,
                    existing: existing,
                  ),
                );
              })
              .whereType<ImportCandidate>()
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      if (!mounted) return;
      setState(() {
        _contacts = mapped;
        _selected.clear();
        _message = mapped.isEmpty ? 'No importable contacts were found.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Contacts could not be loaded. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSettings() async {
    await device.FlutterContacts.permissions.openSettings();
  }

  List<ImportCandidate> get _visibleContacts {
    final query = normaliseImportValue(_query);
    if (query.isEmpty) return _contacts;
    return _contacts.where((contact) {
      return normaliseImportValue(contact.name).contains(query) ||
          normaliseImportValue(contact.email).contains(query) ||
          normalisePhone(contact.phone).contains(normalisePhone(query));
    }).toList();
  }

  Future<void> _reviewImport() async {
    if (_reviewing || _importing) return;
    final candidates = _contacts
        .where((item) => _selected.contains(item.sourceId))
        .where((item) => _includeDuplicates || !item.likelyDuplicate)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one new contact.')),
      );
      return;
    }
    setState(() => _reviewing = true);
    try {
      final confirmed = await showWorkloopBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SlateSheetFrame(
          scrollable: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review contact import',
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${candidates.length} ${candidates.length == 1 ? 'client' : 'clients'} will be created with available name, phone, email and postal address details.',
                style: TextStyle(
                  color: AppColors.of(context).t3,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              WorkloopPrimaryButton(
                label: 'Import ${candidates.length}',
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
      if (confirmed == true) await _import(candidates);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _import(List<ImportCandidate> candidates) async {
    if (_importing || candidates.isEmpty) return;
    final attemptedIds = candidates.map((candidate) => candidate.sourceId);
    setState(() {
      _importing = true;
      _message = null;
    });
    var success = 0;
    final completedIds = <String>{};
    final failures = <String>[];
    try {
      final workspaceId = await ref.read(workspaceIdProvider.future);
      if (workspaceId == null) throw StateError('Workspace unavailable');
      final repository = ref.read(clientsRepositoryProvider);
      for (final candidate in candidates) {
        try {
          await repository.create(
            workspaceId: workspaceId,
            name: candidate.name,
            phone: candidate.phone,
            email: candidate.email,
            address: candidate.address,
            source: 'Device contacts',
            status: 'lead',
            preferredContactMethod: candidate.email?.isNotEmpty == true
                ? 'email'
                : 'phone',
            tags: const ['imported'],
          );
          success++;
          completedIds.add(candidate.sourceId);
        } catch (_) {
          failures.add(candidate.name);
        }
      }
      final result = reconcileImportAttempt(
        attempted: attemptedIds,
        completed: completedIds,
      );
      final summary = failures.isEmpty
          ? '$success ${success == 1 ? 'client was' : 'clients were'} added.'
          : '$success ${success == 1 ? 'client was' : 'clients were'} added. '
                '${result.retryable.length} ${result.retryable.length == 1 ? 'contact remains' : 'contacts remain'} selected to retry.';
      if (mounted) {
        setState(() {
          _contacts = _contacts
              .where((contact) => !result.completed.contains(contact.sourceId))
              .toList();
          _selected
            ..removeAll(result.completed)
            ..addAll(result.retryable);
          _message = summary;
        });
      }
      ref.invalidate(clientsProvider);
      ref.invalidate(clientCrmRecordsProvider);
      if (!mounted) return;
      if (success > 0) {
        SlateHaptics.success();
      } else {
        SlateHaptics.warning();
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import complete'),
          content: Text(
            failures.isEmpty
                ? summary
                : '$summary Could not add: ${failures.take(3).join(', ')}${failures.length > 3 ? '…' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (failures.isEmpty && mounted) Navigator.pop(context, success);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The selected contacts could not be imported. They remain selected to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleContacts;
    final duplicateCount = _contacts
        .where((item) => _selected.contains(item.sourceId))
        .where((item) => item.likelyDuplicate)
        .length;
    return WorkloopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ImportHeader(
            title: 'Import contacts',
            onBack: () => workloopGoBack(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose exactly which device contacts to bring in. Only the people you confirm are added to your workspace.',
            style: TextStyle(
              color: AppColors.of(context).t2,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_contacts.isEmpty && !_loading) ...[
            WorkloopSurface(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.contact,
                    size: 30,
                    color: AppColors.of(context).t2,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _message ?? 'Contact access has not been requested.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  WorkloopPrimaryButton(
                    label: 'Choose contacts',
                    icon: LucideIcons.contact,
                    onPressed: _loading || _importing || _reviewing
                        ? null
                        : _loadContacts,
                  ),
                  if (_message?.contains('settings') == true) ...[
                    const SizedBox(height: AppSpacing.xs),
                    WorkloopTextButton(
                      label: 'Open system settings',
                      onPressed: _openSettings,
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_loading) ...[
            const Center(child: CircularProgressIndicator()),
          ] else ...[
            WorkloopSearchField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              hintText: 'Search contacts',
              semanticLabel: 'Search device contacts',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selected.length} selected',
                    style: TextStyle(
                      color: AppColors.of(context).t2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                WorkloopTextButton(
                  label: _selected.length == visible.length
                      ? 'Clear'
                      : 'Select all',
                  onPressed: _importing || _reviewing
                      ? null
                      : () => setState(() {
                          if (_selected.length == visible.length) {
                            _selected.clear();
                          } else {
                            _selected.addAll(
                              visible.map((item) => item.sourceId),
                            );
                          }
                        }),
                ),
              ],
            ),
            WorkloopSurface(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: visible.isEmpty
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Text(
                          'No contacts match this search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.of(context).t3),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: visible.length,
                        itemBuilder: (context, index) => _ContactRow(
                          contact: visible[index],
                          selected: _selected.contains(visible[index].sourceId),
                          enabled: !_importing && !_reviewing,
                          showDivider: index != visible.length - 1,
                          onChanged: (selected) {
                            if (_importing || _reviewing) return;
                            setState(() {
                              if (selected) {
                                _selected.add(visible[index].sourceId);
                              } else {
                                _selected.remove(visible[index].sourceId);
                              }
                            });
                          },
                        ),
                      ),
              ),
            ),
            if (duplicateCount > 0) ...[
              const SizedBox(height: AppSpacing.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _includeDuplicates,
                onChanged: _importing || _reviewing
                    ? null
                    : (value) => setState(() => _includeDuplicates = value),
                title: const Text('Create likely duplicates separately'),
                subtitle: Text(
                  _includeDuplicates
                      ? 'The $duplicateCount possible ${duplicateCount == 1 ? 'match will' : 'matches will'} also be imported.'
                      : '$duplicateCount possible ${duplicateCount == 1 ? 'match will' : 'matches will'} be skipped.',
                ),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                container: true,
                liveRegion: true,
                label: _message!,
                child: ExcludeSemantics(
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: AppColors.of(context).t3,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            WorkloopPrimaryButton(
              label: _importing
                  ? 'Importing…'
                  : _reviewing
                  ? 'Reviewing…'
                  : 'Review import',
              icon: LucideIcons.arrowRight,
              onPressed: _selected.isEmpty || _importing || _reviewing
                  ? null
                  : _reviewImport,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ImportCandidate contact;
  final bool selected;
  final bool enabled;
  final bool showDivider;
  final ValueChanged<bool> onChanged;

  const _ContactRow({
    required this.contact,
    required this.selected,
    required this.enabled,
    required this.showDivider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      contact.phone,
      contact.email,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return WorkloopListRow(
      flat: true,
      onTap: enabled ? () => onChanged(!selected) : null,
      showDivider: showDivider,
      leading: Checkbox.adaptive(
        value: selected,
        onChanged: enabled ? (value) => onChanged(value ?? false) : null,
      ),
      title: Text(
        contact.name,
        style: TextStyle(
          color: AppColors.of(context).t1,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.of(context).t3),
            ),
      trailing: contact.likelyDuplicate
          ? Text(
              'Possible match',
              style: TextStyle(
                color: AppColors.of(context).warning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

class _ImportHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _ImportHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return WorkloopRouteHeader(title: title, onBack: onBack);
  }
}
