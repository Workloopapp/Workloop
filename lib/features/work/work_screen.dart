import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/slate_ui.dart';
import '../appointments/appointments_screen.dart';
import '../notes/notes_screen.dart';
import '../public_profile/booking_requests_screen.dart';
import '../tasks/tasks_screen.dart';
import 'work_workspace_switcher.dart';

/// The stable command surface for the three parts of doing the work.
///
/// The header and peer navigation stay mounted while the retained content
/// below changes. This keeps Schedule, Tasks and Notes feeling like one
/// workspace and preserves each section's filters, scroll position and drafts.
class WorkScreen extends ConsumerStatefulWidget {
  final ValueNotifier<WorkWorkspaceSection>? sectionController;
  final WorkWorkspaceSection initialSection;
  final DateTime? referenceDate;

  const WorkScreen({
    super.key,
    this.sectionController,
    this.initialSection = WorkWorkspaceSection.schedule,
    this.referenceDate,
  });

  @override
  ConsumerState<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends ConsumerState<WorkScreen> {
  late final ValueNotifier<WorkWorkspaceSection> _internalController;
  int _bookingCreateRequest = 0;
  int _taskCreateRequest = 0;
  int _noteCreateRequest = 0;

  ValueNotifier<WorkWorkspaceSection> get _sectionController =>
      widget.sectionController ?? _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = ValueNotifier(widget.initialSection);
  }

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    final requests = ref.watch(bookingRequestsProvider);
    final activeRequestCount = requests.maybeWhen(
      data: (items) => items
          .where(
            (item) => item.status == 'pending' || item.status == 'contacted',
          )
          .length,
      orElse: () => 0,
    );

    return ValueListenableBuilder<WorkWorkspaceSection>(
      valueListenable: _sectionController,
      builder: (context, section, _) {
        return Scaffold(
          // Workloop's shared observer targets the visible section. Flutter's
          // default handler would scroll every position on the inherited
          // controller, including the retained hidden Tasks/Notes lists.
          primary: false,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              const Positioned.fill(child: WorkloopTexturedBackdrop()),
              SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageX,
                        AppSpacing.screenTop,
                        AppSpacing.pageX,
                        0,
                      ),
                      child: WorkloopPageHeader(
                        title: 'Work',
                        subtitle:
                            MediaQuery.textScalerOf(context).scale(1) >= 1.4
                            ? ''
                            : 'Your schedule, tasks and notes.',
                        color: tokens.accent,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            WorkloopIconButton(
                              icon: LucideIcons.inbox,
                              semanticLabel: activeRequestCount == 0
                                  ? 'Booking requests'
                                  : 'Booking requests, $activeRequestCount active',
                              size: AppSpacing.minTouch,
                              badge: activeRequestCount == 0
                                  ? null
                                  : _RequestBadge(count: activeRequestCount),
                              onTap: _openRequests,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            WorkloopTopAction(
                              label: _createLabel(section),
                              semanticLabel: _createLabel(section),
                              onTap: () => _requestCreate(section),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.pageX,
                      ),
                      child: WorkWorkspaceSwitcher(
                        selected: section,
                        onChanged: (value) => _sectionController.value = value,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: IndexedStack(
                        index: section.index,
                        children: [
                          AppointmentsScreen(
                            embedded: true,
                            createRequest: _bookingCreateRequest,
                          ),
                          TasksScreen(
                            embedded: true,
                            createRequest: _taskCreateRequest,
                          ),
                          NotesScreen(
                            embedded: true,
                            showBackButton: false,
                            createRequest: _noteCreateRequest,
                            referenceDate: widget.referenceDate,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _createLabel(WorkWorkspaceSection section) => switch (section) {
    WorkWorkspaceSection.schedule => 'New booking',
    WorkWorkspaceSection.tasks => 'New task',
    WorkWorkspaceSection.notes => 'New note',
  };

  void _requestCreate(WorkWorkspaceSection section) {
    setState(() {
      switch (section) {
        case WorkWorkspaceSection.schedule:
          _bookingCreateRequest += 1;
        case WorkWorkspaceSection.tasks:
          _taskCreateRequest += 1;
        case WorkWorkspaceSection.notes:
          _noteCreateRequest += 1;
      }
    });
  }

  Future<void> _openRequests() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const BookingRequestsScreen()),
    );
    if (!mounted) return;
    ref.invalidate(bookingRequestsProvider);
  }
}

class _RequestBadge extends StatelessWidget {
  final int count;

  const _RequestBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final tokens = SlateTheme.of(context);
    return Positioned(
      right: -3,
      top: -3,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: tokens.accentStrong,
          borderRadius: BorderRadius.circular(AppRadius.capsule),
          border: Border.all(color: tokens.background, width: 2),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            color: tokens.onAccent,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
