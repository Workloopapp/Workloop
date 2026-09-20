import '../../../shared/widgets/business_logo_editor.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../business_document_settings_screen.dart';
import '../../finance/documents/business_document.dart' show parseDocumentMoney;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../../shared/repositories/slate_repositories.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/public_booking_url.dart';
import '../../../shared/utils/public_profile_routes.dart';
import '../../../shared/utils/working_hours.dart';
import '../../../shared/widgets/slate_ui.dart';
import '../../../shared/widgets/workloop_form_field.dart';
import '../providers/settings_providers.dart';
import 'service_add_ons_editor.dart';
import 'settings_helpers.dart';
import 'settings_services_section.dart';

final _profileHandlePattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$');

enum SettingsBusinessSection { business, workingHours, publicProfile, services }

class SettingsBusinessController {
  VoidCallback? _showAddService;

  void showAddService() => _showAddService?.call();
}

class SettingsBusinessTab extends ConsumerStatefulWidget {
  final SettingsBusinessSection initialSection;
  final bool showOnlySelected;
  final SettingsBusinessController? controller;

  const SettingsBusinessTab({
    super.key,
    this.initialSection = SettingsBusinessSection.business,
    this.showOnlySelected = false,
    this.controller,
  });

  @override
  ConsumerState<SettingsBusinessTab> createState() =>
      _SettingsBusinessTabState();
}

class _HoursBlockControllers {
  final TextEditingController startController;
  final TextEditingController endController;

  _HoursBlockControllers({required String start, required String end})
    : startController = TextEditingController(text: start),
      endController = TextEditingController(text: end);
}

class _SettingsBusinessTabState extends ConsumerState<SettingsBusinessTab> {
  final _scrollController = ScrollController();
  final _businessKey = GlobalKey();
  final _workingHoursKey = GlobalKey();
  final _publicProfileKey = GlobalKey();
  final _servicesKey = GlobalKey();
  bool _editingInfo = false;
  bool _businessInfoHydrated = false;
  bool _saving = false;
  bool _profileHydrated = false;
  String _savedHandle = '';

  int? _serviceDurationMinutes(
    TextEditingController hoursController,
    TextEditingController minutesController,
  ) {
    final hours = int.tryParse(
      hoursController.text.trim().isEmpty ? '0' : hoursController.text.trim(),
    );
    final minutes = int.tryParse(
      minutesController.text.trim().isEmpty
          ? '0'
          : minutesController.text.trim(),
    );
    if (hours == null ||
        minutes == null ||
        hours < 0 ||
        minutes < 0 ||
        minutes > 59) {
      return null;
    }
    final total = (hours * 60) + minutes;
    return total >= 5 && total <= 1440 ? total : null;
  }

  Future<void> _scrollToSection() async {
    if (widget.showOnlySelected) return;
    if (widget.initialSection == SettingsBusinessSection.business) return;
    await Future<void>.delayed(
      AppMotion.responsive(context, const Duration(milliseconds: 280)),
    );
    if (!mounted) return;
    final key = switch (widget.initialSection) {
      SettingsBusinessSection.business => _businessKey,
      SettingsBusinessSection.workingHours => _workingHoursKey,
      SettingsBusinessSection.publicProfile => _publicProfileKey,
      SettingsBusinessSection.services => _servicesKey,
    };
    final target = key.currentContext;
    if (target == null) return;
    if (!target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: AppMotion.responsive(context, AppMotion.deliberate),
      curve: AppMotion.curve,
      alignment: 0.04,
    );
  }

  bool _shows(SettingsBusinessSection section) {
    return !widget.showOnlySelected || widget.initialSection == section;
  }

  String _bookingMode = 'manual';
  late TextEditingController _ownerNameController;
  late TextEditingController _nameController;
  late TextEditingController _industryController;
  late TextEditingController _handleController;
  late TextEditingController _bioController;
  late TextEditingController _noticeController;

  @override
  void initState() {
    super.initState();
    _ownerNameController = TextEditingController();
    _nameController = TextEditingController();
    _industryController = TextEditingController();
    _handleController = TextEditingController();
    _bioController = TextEditingController();
    _noticeController = TextEditingController();
    widget.controller?._showAddService = _showAddServiceSheet;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSection());
  }

  @override
  void didUpdateWidget(covariant SettingsBusinessTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._showAddService = null;
      widget.controller?._showAddService = _showAddServiceSheet;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._showAddService == _showAddServiceSheet) {
      widget.controller?._showAddService = null;
    }
    _scrollController.dispose();
    _ownerNameController.dispose();
    _nameController.dispose();
    _industryController.dispose();
    _handleController.dispose();
    _bioController.dispose();
    _noticeController.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _saveInfo(String workspaceId) async {
    if (_saving) return;
    final ownerName = _ownerNameController.text.trim();
    if (ownerName.isEmpty) {
      _snack('Add your name', AppColors.of(context).warning);
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _snack('Add your business name', AppColors.of(context).warning);
      return;
    }
    setState(() => _saving = true);
    try {
      await Future.wait([
        ref.read(authRepositoryProvider).updateFirstName(ownerName),
        ref.read(workspaceRepositoryProvider).update(workspaceId, {
          'name': _nameController.text.trim(),
          'industry': _industryController.text.trim().isEmpty
              ? null
              : _industryController.text.trim(),
        }),
      ]);
      if (!mounted) return;
      ref.invalidate(workspaceProvider);
      setState(() {
        _editingInfo = false;
        _saving = false;
      });
      if (mounted) {
        _snack('Business details updated', AppColors.of(context).green);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(
        'Business details could not be saved.',
        AppColors.of(context).error,
      );
    }
  }

  Future<void> _saveProfile(String workspaceId) async {
    if (_saving) return;
    final handle = _handleController.text.trim().toLowerCase();
    final handleChanged = handle != _savedHandle;
    if (handle.length < 3) {
      _snack(
        'Handle must be at least 3 characters',
        AppColors.of(context).warning,
      );
      return;
    }
    if (handle.length > 40) {
      _snack(
        'Handle must be 40 characters or fewer',
        AppColors.of(context).warning,
      );
      return;
    }
    if (!_profileHandlePattern.hasMatch(handle)) {
      _snack(
        'Use letters, numbers, and hyphens. Start and end with a letter or number.',
        AppColors.of(context).warning,
      );
      return;
    }
    if (handleChanged && isReservedPublicHandle(handle)) {
      _snack(
        'That booking link is reserved by Workloop. Choose another handle.',
        AppColors.of(context).warning,
      );
      return;
    }
    setState(() => _saving = true);
    if (handleChanged) {
      try {
        final available = await ref
            .read(profileRepositoryProvider)
            .isHandleAvailable(handle);
        if (!mounted) return;
        if (_handleController.text.trim().toLowerCase() != handle) {
          setState(() => _saving = false);
          _snack(
            'The handle changed while it was being checked. Tap save again.',
            AppColors.of(context).warning,
          );
          return;
        }
        if (!available) {
          setState(() => _saving = false);
          _snack(
            'That booking link is already taken. Choose another handle.',
            AppColors.of(context).warning,
          );
          return;
        }
      } catch (_) {
        if (mounted) {
          setState(() => _saving = false);
          _snack(
            'Couldn’t check that booking link. Check your connection and try again.',
            AppColors.of(context).error,
          );
        }
        return;
      }
    }
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateWorkspaceProfile(
            workspaceId: workspaceId,
            values: {
              'handle': handle,
              'bio': _bioController.text.trim().isEmpty
                  ? null
                  : _bioController.text.trim(),
              'notice_text': _noticeController.text.trim().isEmpty
                  ? null
                  : _noticeController.text.trim(),
              'booking_mode': _bookingMode,
            },
          );
      if (!mounted) return;
      ref.invalidate(settingsBusinessProfileProvider);
      setState(() {
        _savedHandle = handle;
        _profileHydrated = false;
        _saving = false;
      });
      if (mounted) _snack('Booking page updated', AppColors.of(context).green);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(
        'The booking page could not be saved.',
        AppColors.of(context).error,
      );
    }
  }

  void _showHoursSheet(Map<String, dynamic> settings) {
    final rawHours = Map<String, dynamic>.from(
      settings['working_hours'] as Map? ?? {},
    );
    final enabled = <String, bool>{};
    final blockControllers = <String, List<_HoursBlockControllers>>{};
    var saving = false;
    String? error;
    Map<String, String> hoursErrors = {};

    for (final day in workingHourDays) {
      final shortDay = shortToLongDay.entries
          .firstWhere((entry) => entry.value == day)
          .key;
      final rawDay = rawHours[day] ?? rawHours[shortDay];
      final value = rawDay is Map
          ? Map<String, dynamic>.from(rawDay)
          : <String, dynamic>{};
      final blocks = workingHourBlocks(
        value.isEmpty ? defaultWorkingHours()[day] : value,
      );
      enabled[day] =
          value['enabled'] as bool? ?? blocks.isNotEmpty && day != 'Sunday';
      blockControllers[day] = blocks.isEmpty
          ? [_HoursBlockControllers(start: '09:00', end: '17:00')]
          : blocks
                .map(
                  (block) => _HoursBlockControllers(
                    start: block.start,
                    end: block.end,
                  ),
                )
                .toList();
    }

    showWorkloopBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) => SlateSheetFrame(
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                Text(
                  'Working Hours',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'These hours appear on your public profile and will guide booking rules.',
                  style: TextStyle(color: AppColors.of(ctx).t3, fontSize: 13),
                ),
                const SizedBox(height: 18),
                ...workingHourDays.map((day) {
                  final blocks = blockControllers[day]!;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.of(ctx).bgInteract,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.of(ctx).border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                day,
                                style: TextStyle(
                                  color: AppColors.of(ctx).t1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Semantics(
                              label: '$day working hours',
                              value: enabled[day]! ? 'Working' : 'Off',
                              child: Switch.adaptive(
                                value: enabled[day]!,
                                onChanged: (value) =>
                                    setModal(() => enabled[day] = value),
                              ),
                            ),
                          ],
                        ),
                        if (hoursErrors[day] case final dayError?)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              dayError,
                              style: TextStyle(
                                color: AppColors.of(ctx).error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (enabled[day]!) ...[
                          const SizedBox(height: 8),
                          ...blocks.asMap().entries.map((entry) {
                            final index = entry.key;
                            final block = entry.value;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == blocks.length - 1 ? 0 : 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _timeField(
                                      ctx,
                                      label: 'Start',
                                      controller: block.startController,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _timeField(
                                      ctx,
                                      label: 'End',
                                      controller: block.endController,
                                    ),
                                  ),
                                  if (blocks.length > 1) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip:
                                          'Remove $day time block ${index + 1}',
                                      constraints: const BoxConstraints(
                                        minWidth: AppSpacing.minTouch,
                                        minHeight: AppSpacing.minTouch,
                                      ),
                                      onPressed: () => setModal(
                                        () => blocks.removeAt(index),
                                      ),
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: AppColors.of(ctx).t3,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () => setModal(
                              () => blocks.add(
                                _HoursBlockControllers(
                                  start: '16:00',
                                  end: '21:00',
                                ),
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.of(ctx).green,
                              minimumSize: const Size(
                                AppSpacing.minTouch,
                                AppSpacing.minTouch,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text(
                              'Add another block',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (blocks.length > 1) ...[
                            const SizedBox(height: 8),
                            Text(
                              'The gap between blocks is treated as a break.',
                              style: TextStyle(
                                color: AppColors.of(ctx).t3,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 10),
                if (error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: AppColors.of(ctx).error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                saveBtn(
                  ctx,
                  label: 'Save Hours',
                  loading: saving,
                  onTap: () async {
                    if (saving) return;
                    setModal(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final workspaceId = await ref.read(
                        workspaceIdProvider.future,
                      );
                      if (!mounted || !ctx.mounted) return;
                      if (workspaceId == null) {
                        throw StateError('Workspace unavailable');
                      }
                      final nextHours = <String, dynamic>{};
                      for (final day in workingHourDays) {
                        final blocks = blockControllers[day]!
                            .map(
                              (block) => {
                                'start': block.startController.text.trim(),
                                'end': block.endController.text.trim(),
                              },
                            )
                            .toList();
                        nextHours[day] = {
                          'enabled': enabled[day],
                          'blocks': blocks,
                          if (blocks.isNotEmpty) 'start': blocks.first['start'],
                          if (blocks.isNotEmpty) 'end': blocks.last['end'],
                        };
                      }
                      final validation = validateWorkingHours(nextHours);
                      setModal(() => hoursErrors = validation);
                      if (validation.isNotEmpty) {
                        setModal(() => saving = false);
                        return;
                      }
                      await ref
                          .read(workspaceSettingsRepositoryProvider)
                          .update(workspaceId, {'working_hours': nextHours});
                      if (!mounted) return;
                      ref.invalidate(settingsWorkspaceSettingsProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        _snack(
                          'Working hours updated',
                          AppColors.of(context).green,
                        );
                      }
                    } catch (_) {
                      if (!ctx.mounted) {
                        if (mounted) {
                          _snack(
                            'Working hours could not be saved.',
                            AppColors.of(context).error,
                          );
                        }
                        return;
                      }
                      setModal(() {
                        saving = false;
                        error =
                            'Couldn’t save working hours. Your previous hours are unchanged.';
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      style: TextStyle(color: AppColors.of(context).t1, fontSize: 14),
      decoration: InputDecoration(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        label: WorkloopFieldLabel(label, isRequired: true),
        labelStyle: TextStyle(color: AppColors.of(context).t3),
        filled: true,
        fillColor: AppColors.of(context).bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.of(context).border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.of(context).border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.of(context).green,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  void _showAddServiceSheet() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final durationHoursCtrl = TextEditingController(text: '1');
    final durationMinutesCtrl = TextEditingController(text: '0');
    final descCtrl = TextEditingController();
    bool showOnProfile = true;
    bool saving = false;
    String? error;
    String? priceError;

    showWorkloopBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AnimatedPadding(
          duration: AppMotion.responsive(context, AppMotion.fast),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SlateSheetFrame(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New service or package',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.of(ctx).t1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'For a bundle, use one combined name, duration and total price. You can add optional extras after saving.',
                    style: TextStyle(
                      color: AppColors.of(ctx).t3,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  settingsField(
                    ctx,
                    label: 'SERVICE NAME',
                    isRequired: true,
                    controller: nameCtrl,
                    hint: 'e.g. 1-on-1 PT Session',
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  settingsField(
                    ctx,
                    label: 'DESCRIPTION',
                    isRequired: false,
                    controller: descCtrl,
                    hint: 'Optional public description',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  settingsField(
                    ctx,
                    label: 'PRICE (£)',
                    isRequired: true,
                    controller: priceCtrl,
                    errorText: priceError,
                    helperText: 'Enter 0 for a free service.',
                    hint: '65',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const WorkloopFieldLabel('Duration', isRequired: true),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Enter a total of 5 minutes to 24 hours. An empty hours or minutes field counts as 0.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: settingsField(
                          ctx,
                          label: 'Hours',
                          controller: durationHoursCtrl,
                          hint: '1',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: settingsField(
                          ctx,
                          label: 'Minutes',
                          controller: durationMinutesCtrl,
                          hint: '30',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showOnProfile,
                    title: Text(
                      'Show on public profile',
                      style: TextStyle(
                        color: AppColors.of(ctx).t1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Clients can request this service from your link.',
                      style: TextStyle(
                        color: AppColors.of(ctx).t3,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (value) => setModal(() => showOnProfile = value),
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: AppColors.of(ctx).error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  saveBtn(
                    ctx,
                    label: 'Add Service',
                    loading: saving,
                    onTap: () async {
                      if (saving) return;
                      if (nameCtrl.text.trim().isEmpty) {
                        setModal(
                          () => error = 'Add a service name to continue.',
                        );
                        return;
                      }
                      final pricePence = parseDocumentMoney(priceCtrl.text);
                      setModal(
                        () => priceError = pricePence == null
                            ? 'Use a valid price with up to two decimal places.'
                            : null,
                      );
                      if (pricePence == null) return;
                      final durationMins = _serviceDurationMinutes(
                        durationHoursCtrl,
                        durationMinutesCtrl,
                      );
                      if (durationMins == null) {
                        setModal(
                          () => error =
                              'Use a duration from 5 minutes to 24 hours.',
                        );
                        return;
                      }
                      setModal(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final wsId = await ref.read(workspaceIdProvider.future);
                        if (wsId == null) {
                          throw StateError('Workspace unavailable');
                        }
                        await ref
                            .read(servicesRepositoryProvider)
                            .create(
                              workspaceId: wsId,
                              name: nameCtrl.text.trim(),
                              price: pricePence / 100,
                              durationMins: durationMins,
                              description: descCtrl.text,
                              showOnProfile: showOnProfile,
                            );
                        ref.invalidate(settingsServicesProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _snack('Service added', AppColors.of(context).green);
                        }
                      } catch (_) {
                        if (!ctx.mounted) {
                          if (mounted) {
                            _snack(
                              'The service could not be added.',
                              AppColors.of(context).error,
                            );
                          }
                          return;
                        }
                        setModal(() {
                          saving = false;
                          error =
                              'Couldn’t add this service. Nothing was saved. Please try again.';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditServiceSheet(Map<String, dynamic> svc) {
    final nameCtrl = TextEditingController(text: svc['name'] as String? ?? '');
    final priceCtrl = TextEditingController(
      text: currencyInputValue(svc['price'] as num?),
    );
    final initialDuration = (svc['duration_mins'] as num? ?? 60).toInt();
    final durationHoursCtrl = TextEditingController(
      text: '${initialDuration ~/ 60}',
    );
    final durationMinutesCtrl = TextEditingController(
      text: '${initialDuration.remainder(60)}',
    );
    final descCtrl = TextEditingController(
      text: svc['description'] as String? ?? '',
    );
    bool showOnProfile = svc['show_on_profile'] as bool? ?? true;
    bool saving = false;
    String? error;
    String? priceError;

    showWorkloopBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AnimatedPadding(
          duration: AppMotion.responsive(context, AppMotion.fast),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SlateSheetFrame(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Edit Service',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.of(ctx).t1,
                        ),
                      ),
                      WorkloopTextButton(
                        label: 'Delete',
                        destructive: true,
                        onPressed: saving
                            ? null
                            : () async {
                                final deleted = await _confirmDelete(svc);
                                if (deleted && ctx.mounted) Navigator.pop(ctx);
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  settingsField(
                    ctx,
                    label: 'SERVICE NAME',
                    isRequired: true,
                    controller: nameCtrl,
                    hint: 'e.g. 1-on-1 PT Session',
                  ),
                  const SizedBox(height: 12),
                  settingsField(
                    ctx,
                    label: 'DESCRIPTION',
                    isRequired: false,
                    controller: descCtrl,
                    hint: 'Optional public description',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  settingsField(
                    ctx,
                    label: 'PRICE (£)',
                    isRequired: true,
                    controller: priceCtrl,
                    errorText: priceError,
                    helperText: 'Enter 0 for a free service.',
                    hint: '65',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const WorkloopFieldLabel('Duration', isRequired: true),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Enter a total of 5 minutes to 24 hours. An empty hours or minutes field counts as 0.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: settingsField(
                          ctx,
                          label: 'Hours',
                          controller: durationHoursCtrl,
                          hint: '1',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: settingsField(
                          ctx,
                          label: 'Minutes',
                          controller: durationMinutesCtrl,
                          hint: '30',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showOnProfile,
                    title: Text(
                      'Show on public profile',
                      style: TextStyle(
                        color: AppColors.of(ctx).t1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Clients can request this service from your link.',
                      style: TextStyle(
                        color: AppColors.of(ctx).t3,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (value) => setModal(() => showOnProfile = value),
                  ),
                  Divider(height: 32, color: AppColors.of(ctx).border),
                  ServiceAddOnsEditor(
                    workspaceId: svc['workspace_id'] as String,
                    serviceId: svc['id'] as String,
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: AppColors.of(ctx).error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  saveBtn(
                    ctx,
                    label: 'Save Changes',
                    loading: saving,
                    onTap: () async {
                      if (saving) return;
                      if (nameCtrl.text.trim().isEmpty) {
                        setModal(
                          () => error = 'Add a service name to continue.',
                        );
                        return;
                      }
                      final pricePence = parseDocumentMoney(priceCtrl.text);
                      setModal(
                        () => priceError = pricePence == null
                            ? 'Use a valid price with up to two decimal places.'
                            : null,
                      );
                      if (pricePence == null) return;
                      final durationMins = _serviceDurationMinutes(
                        durationHoursCtrl,
                        durationMinutesCtrl,
                      );
                      if (durationMins == null) {
                        setModal(
                          () => error =
                              'Use a duration from 5 minutes to 24 hours.',
                        );
                        return;
                      }
                      setModal(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await ref
                            .read(servicesRepositoryProvider)
                            .update(svc['id'] as String, {
                              'name': nameCtrl.text.trim(),
                              'price': pricePence / 100,
                              'duration_mins': durationMins,
                              'description': descCtrl.text.trim().isEmpty
                                  ? null
                                  : descCtrl.text.trim(),
                              'show_on_profile': showOnProfile,
                            });
                        ref.invalidate(settingsServicesProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _snack(
                            'Service updated',
                            AppColors.of(context).green,
                          );
                        }
                      } catch (_) {
                        if (!ctx.mounted) {
                          if (mounted) {
                            _snack(
                              'The service could not be updated.',
                              AppColors.of(context).error,
                            );
                          }
                          return;
                        }
                        setModal(() {
                          saving = false;
                          error =
                              'Couldn’t save this service. Your previous details are unchanged.';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(Map<String, dynamic> svc) async {
    var deleting = false;
    String? deleteError;

    final deleted = await showWorkloopBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => PopScope(
          canPop: !deleting,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete "${svc['name']}"?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "This won't affect existing bookings.",
                  style: TextStyle(fontSize: 14, color: AppColors.of(ctx).t3),
                  textAlign: TextAlign.center,
                ),
                if (deleteError != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      deleteError!,
                      style: TextStyle(
                        color: AppColors.of(ctx).error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                saveBtn(
                  ctx,
                  label: 'Delete Service',
                  color: AppColors.of(ctx).error,
                  loading: deleting,
                  onTap: () async {
                    if (deleting) return;
                    setModal(() {
                      deleting = true;
                      deleteError = null;
                    });
                    try {
                      await ref
                          .read(servicesRepositoryProvider)
                          .delete(svc['id'] as String);
                    } catch (_) {
                      if (!ctx.mounted) return;
                      setModal(() {
                        deleting = false;
                        deleteError =
                            'Couldn’t delete this service. Nothing was removed. Please try again.';
                      });
                      return;
                    }
                    ref.invalidate(settingsServicesProvider);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: TextButton(
                    onPressed: deleting
                        ? null
                        : () => Navigator.pop(ctx, false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.of(ctx).t3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (deleted == true && mounted) {
      _snack('Service deleted', AppColors.of(context).error);
    }
    return deleted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final profile = ref.watch(settingsBusinessProfileProvider);
    final workspaceSettings = ref.watch(settingsWorkspaceSettingsProvider);
    final services = ref.watch(settingsServicesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(workspaceProvider);
        ref.invalidate(settingsBusinessProfileProvider);
        ref.invalidate(settingsWorkspaceSettingsProvider);
        ref.invalidate(settingsServicesProvider);
      },
      color: AppColors.of(context).green,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageX,
          0,
          AppSpacing.pageX,
          40,
        ),
        children: [
          if (_shows(SettingsBusinessSection.business)) ...[
            // ── Business info ────────────────────────────────────────────────
            KeyedSubtree(
              key: _businessKey,
              child: Text(
                'Business info',
                style: TextStyle(
                  color: AppColors.of(context).t1,
                  fontSize: widget.showOnlySelected ? 22 : 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            workspace.when(
              loading: () => skeletonBox(context, 80),
              error: (_, _) => SlateErrorState(
                message: 'Could not load workspace',
                onRetry: () => ref.invalidate(workspaceProvider),
              ),
              data: (ws) {
                if (!_businessInfoHydrated) {
                  _ownerNameController.text =
                      ref.read(authRepositoryProvider).currentFirstName ?? '';
                  _nameController.text = ws?['name'] as String? ?? '';
                  _industryController.text = ws?['industry'] as String? ?? '';
                  _businessInfoHydrated = true;
                }
                final editing = widget.showOnlySelected || _editingInfo;
                return Container(
                  decoration: BoxDecoration(
                    color: widget.showOnlySelected
                        ? Colors.transparent
                        : AppColors.of(context).bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: widget.showOnlySelected
                        ? null
                        : Border.all(color: AppColors.of(context).border),
                  ),
                  child: editing
                      ? Padding(
                          padding: EdgeInsets.all(
                            widget.showOnlySelected ? 0 : 16,
                          ),
                          child: Column(
                            children: [
                              BusinessLogoEditor(
                                logoUrl: ws?['logo_url'] as String?,
                                onChanged: (url) async {
                                  await ref
                                      .read(workspaceRepositoryProvider)
                                      .update(ws!['id'] as String, {
                                        'logo_url': url,
                                      });
                                  ref.invalidate(workspaceProvider);
                                },
                              ),
                              const SizedBox(height: 16),
                              settingsField(
                                context,
                                label: 'YOUR NAME',
                                isRequired: true,
                                controller: _ownerNameController,
                                hint: 'Your first name',
                              ),
                              const SizedBox(height: 12),
                              settingsField(
                                context,
                                label: 'BUSINESS NAME',
                                isRequired: true,
                                controller: _nameController,
                                hint: 'Your business name',
                              ),
                              const SizedBox(height: 12),
                              settingsField(
                                context,
                                label: 'INDUSTRY',
                                isRequired: false,
                                controller: _industryController,
                                hint: 'e.g. Health & Fitness',
                              ),
                              const SizedBox(height: 16),
                              if (widget.showOnlySelected)
                                saveBtn(
                                  context,
                                  label: 'Save business details',
                                  loading: _saving,
                                  onTap: () => _saveInfo(ws?['id'] as String),
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => setState(
                                          () => _editingInfo = false,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.of(
                                            context,
                                          ).t2,
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                          side: BorderSide(
                                            color: AppColors.of(context).border,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _saving
                                            ? null
                                            : () => _saveInfo(
                                                ws?['id'] as String,
                                              ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.of(
                                            context,
                                          ).brandAccent,
                                          foregroundColor: AppColors.of(
                                            context,
                                          ).onBrandAccent,
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: _saving
                                            ? SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: AppColors.of(
                                                        context,
                                                      ).onBrandAccent,
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Text(
                                                'Save',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            tappableRow(
                              context,
                              label: 'Business name',
                              value: ws?['name'] as String? ?? '—',
                              onTap: () {
                                _nameController.text =
                                    ws?['name'] as String? ?? '';
                                _industryController.text =
                                    ws?['industry'] as String? ?? '';
                                setState(() => _editingInfo = true);
                              },
                            ),
                            Divider(
                              height: 1,
                              color: AppColors.of(context).border,
                            ),
                            tappableRow(
                              context,
                              label: 'Industry',
                              value: ws?['industry'] as String? ?? '—',
                              onTap: () {
                                _nameController.text =
                                    ws?['name'] as String? ?? '';
                                _industryController.text =
                                    ws?['industry'] as String? ?? '';
                                setState(() => _editingInfo = true);
                              },
                            ),
                          ],
                        ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            WorkloopListRow(
              flat: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              leading: Icon(
                LucideIcons.fileText,
                color: AppColors.of(context).t2,
              ),
              title: const Text(
                'Invoice setup',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Legal details, address and payment terms',
                style: TextStyle(fontSize: 13, color: AppColors.of(context).t2),
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const BusinessDocumentSettingsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],

          if (_shows(SettingsBusinessSection.workingHours)) ...[
            KeyedSubtree(
              key: _workingHoursKey,
              child: sectionLabel('Working Hours'),
            ),
            const SizedBox(height: 10),
            workspaceSettings.when(
              loading: () => skeletonBox(context, 80),
              error: (_, _) => SlateErrorState(
                message: 'Could not load working hours',
                onRetry: () =>
                    ref.invalidate(settingsWorkspaceSettingsProvider),
              ),
              data: (settings) {
                final hours = Map<String, dynamic>.from(
                  settings?['working_hours'] as Map? ?? {},
                );
                final openDays = hours.entries
                    .where((entry) {
                      final value = entry.value;
                      if (value is! Map) return false;
                      return Map<String, dynamic>.from(value)['enabled'] ==
                          true;
                    })
                    .map((entry) => entry.key.substring(0, 3))
                    .join(', ');
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.of(context).bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.of(context).border),
                  ),
                  child: tappableRow(
                    context,
                    label: 'Availability',
                    value: openDays.isEmpty ? 'Not set' : openDays,
                    onTap: () => _showHoursSheet(settings ?? {}),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
          ],

          if (_shows(SettingsBusinessSection.publicProfile)) ...[
            KeyedSubtree(
              key: _publicProfileKey,
              child: sectionLabel('Booking page'),
            ),
            const SizedBox(height: 10),
            workspace.when(
              loading: () => skeletonBox(context, 140),
              error: (_, _) => SlateErrorState(
                message: 'Could not load profile controls',
                onRetry: () => ref.invalidate(workspaceProvider),
              ),
              data: (ws) => profile.when(
                loading: () => skeletonBox(context, 140),
                error: (_, _) => SlateErrorState(
                  message: 'Could not load booking page',
                  onRetry: () =>
                      ref.invalidate(settingsBusinessProfileProvider),
                ),
                data: (bp) {
                  if (!_profileHydrated) {
                    _handleController.text = bp?.handle ?? '';
                    _savedHandle = bp?.handle.trim().toLowerCase() ?? '';
                    _bioController.text = bp?.bio ?? '';
                    _noticeController.text = bp?.noticeText ?? '';
                    _bookingMode = bp?.bookingMode ?? 'manual';
                    _profileHydrated = true;
                  }
                  return Container(
                    padding: EdgeInsets.all(widget.showOnlySelected ? 0 : 16),
                    decoration: BoxDecoration(
                      color: widget.showOnlySelected
                          ? Colors.transparent
                          : AppColors.of(context).bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: widget.showOnlySelected
                          ? null
                          : Border.all(color: AppColors.of(context).border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customers can view your services and send a preferred time. You confirm every booking yourself.',
                          style: TextStyle(
                            color: AppColors.of(context).t3,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        settingsField(
                          context,
                          label: 'HANDLE',
                          isRequired: true,
                          controller: _handleController,
                          hint: 'your-handle',
                          maxLength: 40,
                        ),
                        const SizedBox(height: 12),
                        settingsField(
                          context,
                          label: 'BIO',
                          isRequired: false,
                          controller: _bioController,
                          hint: 'A short public description',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        settingsField(
                          context,
                          label: 'NOTICE',
                          isRequired: false,
                          controller: _noticeController,
                          hint: 'Optional seasonal notice',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        _BookingModeControl(
                          value: _bookingMode,
                          onChanged: (value) =>
                              setState(() => _bookingMode = value),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          publicBookingPageDisplayUrl(
                            _handleController.text.isEmpty
                                ? 'your-handle'
                                : _handleController.text,
                          ),
                          style: TextStyle(
                            color: AppColors.of(context).t3,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        saveBtn(
                          context,
                          label: 'Save booking page',
                          loading: _saving,
                          onTap: () => _saveProfile(ws?['id'] as String),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 28),
          ],

          if (_shows(SettingsBusinessSection.services))
            KeyedSubtree(
              key: _servicesKey,
              child: SettingsServicesSection(
                services: services,
                onAdd: _showAddServiceSheet,
                onEdit: _showEditServiceSheet,
                onRetry: () => ref.invalidate(settingsServicesProvider),
                showAddAction: !widget.showOnlySelected,
              ),
            ),
        ],
      ),
    );
  }
}

class _BookingModeControl extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _BookingModeControl({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BOOKING MODE',
          style: TextStyle(
            color: AppColors.of(context).t3,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: WorkloopFilterChip(
                label: 'Accept requests',
                selected: value == 'manual',
                onTap: () => onChanged('manual'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WorkloopFilterChip(
                label: 'Closed',
                selected: value == 'closed',
                onTap: () => onChanged('closed'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
