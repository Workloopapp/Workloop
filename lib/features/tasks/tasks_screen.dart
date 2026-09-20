import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/slate_models.dart';
import '../../shared/notifications/local_reminder_plan.dart';
import '../../shared/notifications/local_reminder_service.dart';
import '../../shared/notifications/notification_route.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/notifications_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/repositories/slate_repositories.dart';
import '../../shared/utils/workflow_idempotency.dart';
import '../../shared/widgets/slate_ui.dart';
import '../../shared/widgets/workloop_form_field.dart';
import '../../shared/widgets/record_link_unavailable.dart';
import 'task_filters.dart';
import '../appointments/appointments_screen.dart';
import '../clients/client_record_link_screen.dart';
import '../imports/text_import_screen.dart';
import '../work/work_workspace_switcher.dart';

part 'task_logic.dart';
part 'task_card.dart';
part 'task_detail_widgets.dart';
part 'task_editor_widgets.dart';

class TasksScreen extends ConsumerStatefulWidget {
  final int createRequest;
  final VoidCallback? onOpenSchedule;
  final VoidCallback? onOpenNotes;
  final bool embedded;
  final String? initialTaskId;
  final bool showBackButton;

  const TasksScreen({
    super.key,
    this.createRequest = 0,
    this.onOpenSchedule,
    this.onOpenNotes,
    this.embedded = false,
    this.initialTaskId,
    this.showBackButton = false,
  });

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  _TaskView _view = _TaskView.now;
  bool _didHandleInitialTask = false;
  String? _scheduledInitialId;
  bool _initialRecordMissing = false;

  @override
  void initState() {
    super.initState();
    if (widget.createRequest != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showTaskEditor(context);
      });
    }
  }

  @override
  void didUpdateWidget(covariant TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTaskId != oldWidget.initialTaskId) {
      _didHandleInitialTask = false;
      _scheduledInitialId = null;
      _initialRecordMissing = false;
    }
    if (widget.createRequest == oldWidget.createRequest ||
        widget.createRequest == 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showTaskEditor(context);
    });
  }

  Future<void> _refreshTaskList() async {
    ref.invalidate(allTasksProvider);
    try {
      await ref.read(allTasksProvider.future);
    } catch (_) {
      // The provider's visible error state offers retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialTaskId != null) ref.watch(workspaceIdProvider);
    final tasks = ref.watch(allTasksProvider);
    if (_initialRecordMissing) {
      return WorkloopRecordLinkUnavailable(
        recordName: 'Task',
        onRetry: () {
          setState(() {
            _didHandleInitialTask = false;
            _initialRecordMissing = false;
          });
          ref.invalidate(allTasksProvider);
        },
      );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageX,
              AppSpacing.screenTop,
              AppSpacing.pageX,
              0,
            ),
            child: widget.showBackButton
                ? WorkloopRouteHeader(
                    title: 'Tasks',
                    backSemanticLabel: 'Back to tasks',
                    onBack: () =>
                        workloopGoBack(context, fallbackLocation: '/tasks'),
                    trailing: WorkloopTopAction(
                      label: 'New task',
                      semanticLabel: 'New task',
                      onTap: () => _showTaskEditor(context),
                    ),
                  )
                : WorkloopPageHeader(
                    title: widget.onOpenSchedule == null ? 'Tasks' : 'Work',
                    subtitle: MediaQuery.textScalerOf(context).scale(1) >= 1.4
                        ? ''
                        : widget.onOpenSchedule == null
                        ? 'Know what needs doing next.'
                        : 'Your schedule, tasks and notes.',
                    color: widget.onOpenSchedule == null
                        ? AppColors.of(context).modTasks
                        : AppColors.of(context).modCalendar,
                    trailing: WorkloopTopAction(
                      label: 'New task',
                      semanticLabel: 'New task',
                      onTap: () => _showTaskEditor(context),
                    ),
                  ),
          ),
          if (widget.onOpenSchedule != null && widget.onOpenNotes != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
              child: WorkWorkspaceSwitcher(
                selected: WorkWorkspaceSection.tasks,
                onChanged: (section) {
                  switch (section) {
                    case WorkWorkspaceSection.schedule:
                      widget.onOpenSchedule!();
                    case WorkWorkspaceSection.tasks:
                      break;
                    case WorkWorkspaceSection.notes:
                      widget.onOpenNotes!();
                  }
                },
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
        Expanded(
          child: tasks.when(
            loading: () => _skeletonList(),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageX),
              child: SlateErrorState(
                message: 'Could not load tasks',
                onRetry: () => ref.invalidate(allTasksProvider),
              ),
            ),
            data: (data) {
              _openInitialTask(data);
              final sorted = [...data]..sort(_taskSort);
              final sections = _sectionsForView(sorted, _view);
              final counts = _countsForTasks(sorted);

              return RefreshIndicator(
                onRefresh: _refreshTaskList,
                color: AppColors.of(context).accentPrimary,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pageX,
                    0,
                    AppSpacing.pageX,
                    AppSpacing.shellBottomClearance(context),
                  ),
                  children: [
                    _TaskViewSwitcher(
                      value: _view,
                      counts: counts,
                      onChanged: (view) => setState(() => _view = view),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (sections.every((section) => section.tasks.isEmpty))
                      _emptyState(context)
                    else
                      ...sections
                          .where((section) => section.tasks.isNotEmpty)
                          .map(
                            (section) => _TaskSectionView(
                              section: section,
                              onOpen: _showTaskDetails,
                              onCompleteRequest: _confirmComplete,
                              onReopen: _reopenTask,
                              onDelete: _confirmDelete,
                            ),
                          ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: WorkloopTexturedBackdrop()),
          SafeArea(bottom: false, child: content),
        ],
      ),
    );
  }

  Widget _skeletonList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageX,
        0,
        AppSpacing.pageX,
        40,
      ),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) =>
          const SlateLoadingBlock(height: 80, radius: AppRadius.md),
    );
  }

  Widget _emptyState(BuildContext context) {
    final title = switch (_view) {
      _TaskView.now => 'Nothing to do',
      _TaskView.later => 'Nothing planned yet',
      _TaskView.done => 'No completed tasks',
    };
    final subtitle = switch (_view) {
      _TaskView.now => 'Your current list is clear.',
      _TaskView.later => 'Future tasks will appear here.',
      _TaskView.done => 'Completed tasks will appear here.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 42),
      child: Column(
        children: [
          WorkloopEmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: title,
            subtitle: subtitle,
          ),
          if (_view != _TaskView.done) ...[
            const SizedBox(height: AppSpacing.xs),
            WorkloopTextButton(
              label: 'Import a task list',
              onPressed: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const TextImportScreen(type: TextImportType.tasks),
                  ),
                );
                if (!mounted) return;
                ref.invalidate(allTasksProvider);
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showTaskDetails(SlateTask initialTask) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/tasks/${initialTask.id}'),
        builder: (ctx) => Consumer(
          builder: (context, ref, _) {
            final workspace = ref.watch(workspaceIdProvider);
            final records = ref.watch(allTasksProvider);
            if (workspace.isLoading || workspace.hasError) {
              return _TaskDetailStatus(
                loading: workspace.isLoading,
                onRetry: () => ref.invalidate(workspaceIdProvider),
              );
            }
            if (workspace.value != initialTask.workspaceId) {
              return WorkloopRecordLinkUnavailable(
                recordName: 'Task',
                onRetry: () => ref.invalidate(workspaceIdProvider),
              );
            }
            if (records.isLoading || records.hasError) {
              return _TaskDetailStatus(
                loading: records.isLoading,
                onRetry: () => ref.invalidate(allTasksProvider),
              );
            }
            // Client saves already invalidate the task collection and its
            // joined name. Read that canonical row for this open route too.
            final task = records.value
                ?.where(
                  (record) =>
                      record.id == initialTask.id &&
                      record.workspaceId == initialTask.workspaceId,
                )
                .firstOrNull;
            if (task == null) {
              return WorkloopRecordLinkUnavailable(
                recordName: 'Task',
                onRetry: () => ref.invalidate(allTasksProvider),
              );
            }
            final checklist = ref.watch(taskChecklistProvider(task.id));

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  const Positioned.fill(child: WorkloopTexturedBackdrop()),
                  SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.pageX,
                            AppSpacing.screenTop,
                            AppSpacing.pageX,
                            0,
                          ),
                          child: WorkloopRouteHeader(
                            title: 'Task',
                            backSemanticLabel: 'Back to tasks',
                            trailing: WorkloopIconButton(
                              icon: LucideIcons.pencil,
                              semanticLabel: 'Edit task',
                              color: AppColors.of(context).modTasks,
                              backgroundColor: AppColors.of(
                                context,
                              ).modTasks.withValues(alpha: 0.10),
                              onTap: () async {
                                Navigator.pop(ctx);
                                await Future<void>.delayed(Duration.zero);
                                if (mounted) {
                                  await _showTaskEditor(
                                    this.context,
                                    task: task,
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageX,
                              0,
                              AppSpacing.pageX,
                              AppSpacing.xxl,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: task.status == 'done'
                                        ? AppColors.of(context).t3
                                        : AppColors.of(context).t1,
                                    decoration: task.status == 'done'
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${task.status == 'done' ? 'Completed' : _priorityLabel(task.priority)} task',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.of(context).t3,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                _TaskContextPanel(
                                  task: task,
                                  onOpenClient: task.contactId == null
                                      ? null
                                      : () => Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            settings: RouteSettings(
                                              name:
                                                  '/clients/${task.contactId}',
                                            ),
                                            builder: (_) =>
                                                ClientRecordLinkScreen(
                                                  clientId: task.contactId!,
                                                ),
                                          ),
                                        ),
                                  onOpenBooking: task.appointmentId == null
                                      ? null
                                      : () => Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            settings: RouteSettings(
                                              name:
                                                  '/bookings/${task.appointmentId}',
                                            ),
                                            builder: (_) => AppointmentsScreen(
                                              initialAppointmentId:
                                                  task.appointmentId!,
                                              showBackButton: true,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                _TaskChecklistPanel(
                                  items: checklist,
                                  onAdd: () => _showChecklistEditor(task),
                                  onRetry: () => ref.invalidate(
                                    taskChecklistProvider(task.id),
                                  ),
                                  onToggle: (item) =>
                                      _toggleChecklistItem(task, item),
                                  onEdit: (item) =>
                                      _showChecklistEditor(task, item: item),
                                  onDelete: (item) =>
                                      _deleteChecklistItem(task, item),
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                SlateButton(
                                  label: task.status == 'done'
                                      ? 'Reopen Task'
                                      : 'Mark Complete',
                                  icon: task.status == 'done'
                                      ? LucideIcons.rotateCcw
                                      : LucideIcons.checkCircle,
                                  onPressed: () async {
                                    final changed = task.status == 'done'
                                        ? await _reopenTask(task)
                                        : await _confirmComplete(task);
                                    if (changed && ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                  },
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                SlateButton(
                                  label: 'Delete Task',
                                  destructive: true,
                                  onPressed: () async {
                                    final deleted = await _confirmDelete(task);
                                    if (deleted && ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                  },
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
          },
        ),
      ),
    );
    _refreshTasks();
  }

  void _openInitialTask(List<SlateTask> records) {
    final id = widget.initialTaskId?.trim();
    final snapshot = ref.read(allTasksProvider);
    final workspace = ref.read(workspaceIdProvider);
    if (_didHandleInitialTask ||
        id == null ||
        id.isEmpty ||
        _scheduledInitialId == id ||
        snapshot.isLoading ||
        snapshot.hasError ||
        !snapshot.hasValue ||
        workspace.isLoading ||
        workspace.hasError ||
        workspace.value == null) {
      return;
    }
    final workspaceId = workspace.value;
    _scheduledInitialId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _scheduledInitialId != id ||
          widget.initialTaskId?.trim() != id) {
        return;
      }
      _scheduledInitialId = null;
      final current = ref.read(allTasksProvider);
      final currentWorkspace = ref.read(workspaceIdProvider);
      if (current.isLoading ||
          current.hasError ||
          !current.hasValue ||
          currentWorkspace.isLoading ||
          currentWorkspace.hasError ||
          currentWorkspace.value != workspaceId) {
        return;
      }
      SlateTask? match;
      for (final record in current.value ?? <SlateTask>[]) {
        if (record.id == id) {
          match = record;
          break;
        }
      }
      _didHandleInitialTask = true;
      if (match == null) {
        setState(() => _initialRecordMissing = true);
      } else {
        _showTaskDetails(match);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showTaskEditor(BuildContext context, {SlateTask? task}) async {
    String priority = task?.priority ?? 'medium';
    DateTime? dueDate = task?.dueDate;
    String? selectedClientId = task?.contactId;
    String reminderTiming = task?.reminderTiming ?? 'none';
    final draftChecklist = <String>[];
    final createIdempotencyKey = task == null
        ? createWorkflowIdempotencyKey()
        : null;
    var saving = false;
    var allowPop = false;
    var showOptions =
        task?.priority != null && task!.priority != 'medium' ||
        task?.reminderTiming != null && task!.reminderTiming != 'none';

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(
          name: task == null ? null : '/tasks/${task.id}',
        ),
        builder: (ctx) => _TaskEditorState(
          initialTitle: task?.title ?? '',
          builder: (ctx, setModal, titleController, checklistController) {
            bool hasChanges() {
              return titleController.text != (task?.title ?? '') ||
                  priority != (task?.priority ?? 'medium') ||
                  dueDate != task?.dueDate ||
                  selectedClientId != task?.contactId ||
                  reminderTiming != (task?.reminderTiming ?? 'none') ||
                  draftChecklist.isNotEmpty;
            }

            bool canScheduleReminder(String timing) {
              if (timing == 'none') return true;
              return planTaskReminder(
                    SlateTask(
                      id: task?.id ?? 'draft',
                      workspaceId: task?.workspaceId ?? '',
                      title: titleController.text.trim(),
                      dueDate: dueDate,
                      reminderTiming: timing,
                    ),
                    now: DateTime.now(),
                  ) !=
                  null;
            }

            final clients = ref.watch(clientsProvider);
            Future<void> save() async {
              if (saving || titleController.text.trim().isEmpty) return;
              final reminderChanged =
                  task == null ||
                  reminderTiming != task.reminderTiming ||
                  dueDate != task.dueDate;
              if (reminderTiming != 'none' && reminderChanged) {
                if (!canScheduleReminder(reminderTiming)) {
                  setModal(() => showOptions = true);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'That 09:00 reminder time has passed. Choose a later due date or No reminder.',
                      ),
                    ),
                  );
                  return;
                }
                final permission = await ref
                    .read(localReminderServiceProvider)
                    .requestPermission();
                if (!ctx.mounted) return;
                if (permission != LocalReminderPermission.granted) {
                  setModal(() => showOptions = true);
                  final message =
                      permission == LocalReminderPermission.unsupported
                      ? 'Choose No reminder to save this task outside the iOS or Android app.'
                      : 'Allow notifications, or choose No reminder before saving this task.';
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(message)));
                  return;
                }
              }
              setModal(() => saving = true);
              try {
                final saved = await _saveTask(
                  task: task,
                  title: titleController.text,
                  priority: priority,
                  dueDate: dueDate,
                  clientId: selectedClientId,
                  reminderTiming: reminderTiming,
                  checklistTitles: draftChecklist,
                  createIdempotencyKey: createIdempotencyKey,
                );
                if (!ctx.mounted) return;
                if (!saved) {
                  setModal(() => saving = false);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Could not access this workspace. Your task was not saved.',
                      ),
                      backgroundColor: AppColors.of(ctx).error,
                    ),
                  );
                  return;
                }
              } catch (_) {
                if (!ctx.mounted) return;
                setModal(() => saving = false);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      task == null
                          ? 'Could not create this task. Nothing was added. Please try again.'
                          : 'Could not save these task changes. Please try again.',
                    ),
                    backgroundColor: AppColors.of(ctx).error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              allowPop = true;
              setModal(() {});
              await Future<void>.delayed(Duration.zero);
              if (ctx.mounted) Navigator.pop(ctx);
            }

            Future<void> handleBack() async {
              if (!hasChanges()) {
                allowPop = true;
                setModal(() {});
                await Future<void>.delayed(Duration.zero);
                if (ctx.mounted) Navigator.pop(ctx);
                return;
              }
              final choice = await _confirmTaskEditorExit(ctx);
              if (!ctx.mounted || choice == null) return;
              if (choice == _TaskEditorExit.keepEditing) return;
              if (choice == _TaskEditorExit.save) {
                await save();
                return;
              }
              allowPop = true;
              setModal(() {});
              await Future<void>.delayed(Duration.zero);
              if (ctx.mounted) Navigator.pop(ctx);
            }

            return PopScope(
              canPop: allowPop || !hasChanges(),
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) handleBack();
              },
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  children: [
                    const Positioned.fill(child: WorkloopTexturedBackdrop()),
                    SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pageX,
                              AppSpacing.screenTop,
                              AppSpacing.pageX,
                              0,
                            ),
                            child: WorkloopRouteHeader(
                              title: task == null ? 'New task' : 'Edit task',
                              backSemanticLabel: 'Back to tasks',
                              onBack: handleBack,
                              trailing: _TaskSaveAction(
                                label: task == null ? 'Add' : 'Save',
                                loading: saving,
                                enabled: titleController.text.trim().isNotEmpty,
                                onTap: save,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.pageX,
                                0,
                                AppSpacing.pageX,
                                AppSpacing.xxl,
                              ),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _TaskFormSectionLabel(
                                    'Task details',
                                    subtitle:
                                        'Keep the next action clear and specific.',
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  TextField(
                                    controller: titleController,
                                    autofocus: task == null,
                                    minLines: 1,
                                    maxLines: 3,
                                    textInputAction: TextInputAction.done,
                                    style: TextStyle(
                                      color: AppColors.of(ctx).t1,
                                    ),
                                    decoration: const InputDecoration(
                                      label: WorkloopFieldLabel(
                                        'Task title',
                                        isRequired: true,
                                      ),
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      hintText: 'What needs to happen?',
                                    ),
                                    onChanged: (_) => setModal(() {}),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  if (task == null) ...[
                                    _TaskTemplatePicker(
                                      onSelect: (template) {
                                        setModal(() {
                                          if (titleController.text
                                              .trim()
                                              .isEmpty) {
                                            titleController.text =
                                                template.title;
                                          }
                                          priority = template.priority;
                                          if (template.dueInDays != null) {
                                            dueDate = _dateOnly(
                                              DateTime.now().add(
                                                Duration(
                                                  days: template.dueInDays!,
                                                ),
                                              ),
                                            );
                                            reminderTiming =
                                                template.dueInDays == 0
                                                ? 'today'
                                                : 'day_before';
                                            showOptions = true;
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: AppSpacing.xl),
                                  ],
                                  const _TaskFormSectionLabel(
                                    'When and who',
                                    subtitle:
                                        'Add timing and client context when useful.',
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  clients.when(
                                    loading: () => const SlateLoadingBlock(
                                      height: 58,
                                      radius: AppRadius.md,
                                    ),
                                    error: (_, _) => SlateErrorState(
                                      message: 'Could not load clients.',
                                      onRetry: () =>
                                          ref.invalidate(clientsProvider),
                                    ),
                                    data: (data) => _ClientPicker(
                                      clients: data,
                                      selectedClientId: selectedClientId,
                                      onChanged: (value) => setModal(
                                        () => selectedClientId = value,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _DueDatePicker(
                                    dueDate: dueDate,
                                    onChanged: (value) =>
                                        setModal(() => dueDate = value),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  _TaskOptionsDisclosure(
                                    expanded: showOptions,
                                    onTap: () => setModal(
                                      () => showOptions = !showOptions,
                                    ),
                                  ),
                                  if (showOptions) ...[
                                    const SizedBox(height: AppSpacing.lg),
                                    WorkloopFieldLabel(
                                      'Priority',
                                      isRequired: false,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.of(ctx).t3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _PriorityChoice(
                                          value: 'high',
                                          label: 'High',
                                          selected: priority,
                                          color: AppColors.of(ctx).error,
                                          onTap: (value) =>
                                              setModal(() => priority = value),
                                        ),
                                        const SizedBox(width: 8),
                                        _PriorityChoice(
                                          value: 'medium',
                                          label: 'Medium',
                                          selected: priority,
                                          color: AppColors.of(ctx).warning,
                                          onTap: (value) =>
                                              setModal(() => priority = value),
                                        ),
                                        const SizedBox(width: 8),
                                        _PriorityChoice(
                                          value: 'low',
                                          label: 'Low',
                                          selected: priority,
                                          color: AppColors.of(ctx).t3,
                                          onTap: (value) =>
                                              setModal(() => priority = value),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    _ReminderPicker(
                                      value: reminderTiming,
                                      enabled: dueDate != null,
                                      onChanged: (value) async {
                                        if (value != 'none') {
                                          if (!canScheduleReminder(value)) {
                                            ScaffoldMessenger.of(
                                              ctx,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'That 09:00 reminder time has passed. Choose a later due date.',
                                                ),
                                              ),
                                            );
                                            return;
                                          }
                                          final permission = await ref
                                              .read(
                                                localReminderServiceProvider,
                                              )
                                              .requestPermission();
                                          if (!ctx.mounted) return;
                                          if (permission !=
                                              LocalReminderPermission.granted) {
                                            final message =
                                                permission ==
                                                    LocalReminderPermission
                                                        .unsupported
                                                ? 'Scheduled reminders are available in the iOS and Android apps.'
                                                : 'Enable notifications in your device settings to use task reminders.';
                                            ScaffoldMessenger.of(
                                              ctx,
                                            ).showSnackBar(
                                              SnackBar(content: Text(message)),
                                            );
                                            return;
                                          }
                                        }
                                        setModal(() => reminderTiming = value);
                                      },
                                    ),
                                    if (task == null) ...[
                                      const SizedBox(height: AppSpacing.xl),
                                      _DraftChecklistEditor(
                                        controller: checklistController,
                                        items: draftChecklist,
                                        onAdd: () {
                                          final title = checklistController.text
                                              .trim();
                                          if (title.isEmpty) return;
                                          setModal(() {
                                            draftChecklist.add(title);
                                            checklistController.clear();
                                          });
                                        },
                                        onRemove: (index) => setModal(
                                          () => draftChecklist.removeAt(index),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    if (mounted) {
      _refreshTasks();
      _refreshTaskNotifications();
    }
  }

  Future<_TaskEditorExit?> _confirmTaskEditorExit(BuildContext context) {
    return showDialog<_TaskEditorExit>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.of(context).bgCard,
        title: const Text('Save task changes?'),
        content: const Text('You have changes that have not been saved yet.'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _TaskEditorExit.keepEditing),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _TaskEditorExit.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _TaskEditorExit.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<bool> _saveTask({
    SlateTask? task,
    required String title,
    required String priority,
    required DateTime? dueDate,
    required String? clientId,
    required String reminderTiming,
    required List<String> checklistTitles,
    required String? createIdempotencyKey,
  }) async {
    if (title.trim().isEmpty) return false;
    final workspaceId = await ref.read(workspaceIdProvider.future);
    if (workspaceId == null) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    final savedReminderTiming = dueDate == null ? 'none' : reminderTiming;
    final reminderChanged =
        task == null ||
        task.reminderTiming != savedReminderTiming ||
        task.dueDate != dueDate;
    final taskId = task == null
        ? await ref
              .read(tasksRepositoryProvider)
              .createWithChecklist(
                workspaceId: workspaceId,
                title: title,
                priority: priority,
                dueDate: dueDate,
                contactId: clientId,
                reminderTiming: savedReminderTiming,
                checklistTitles: checklistTitles,
                idempotencyKey: createIdempotencyKey!,
              )
        : task.id;
    if (task != null) {
      await ref
          .read(tasksRepositoryProvider)
          .update(
            taskId: task.id,
            appointmentId: task.appointmentId,
            title: title,
            priority: priority,
            dueDate: dueDate,
            contactId: clientId,
            reminderTiming: savedReminderTiming,
          );
    }
    if (reminderChanged) {
      await _maybeCreateDueNotification(
        workspaceId,
        taskId,
        title,
        dueDate,
        savedReminderTiming,
      );
    }
    return true;
  }

  Future<void> _maybeCreateDueNotification(
    String workspaceId,
    String taskId,
    String title,
    DateTime? dueDate,
    String reminderTiming,
  ) async {
    if (dueDate == null || reminderTiming == 'none') return;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final shouldCreateNow = switch (reminderTiming) {
      'today' => dueDateOnly == todayDate,
      'day_before' => !dueDateOnly.isAfter(
        todayDate.add(const Duration(days: 1)),
      ),
      'week_before' => !dueDateOnly.isAfter(
        todayDate.add(const Duration(days: 7)),
      ),
      _ => false,
    };
    if (shouldCreateNow) {
      try {
        await ref
            .read(notificationsRepositoryProvider)
            .create(
              workspaceId: workspaceId,
              type: 'task_due',
              title: 'Task due soon',
              body: title.trim(),
              deepLink: workloopNotificationEntityRoute(
                WorkloopNotificationEntity.task,
                taskId,
              ),
            );
      } catch (_) {
        // The saved task is the source of truth. Notification support is
        // additive and must never turn a committed task into a failed save.
      }
    }
  }

  void _showChecklistEditor(SlateTask task, {TaskChecklistItem? item}) {
    final controller = TextEditingController(text: item?.title ?? '');
    final closeDuration = AppMotion.responsive(
      context,
      AppMotion.deliberate + AppMotion.fast,
    );
    var saving = false;
    String? errorMessage;

    showWorkloopBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return SlateSheetFrame(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item == null ? 'Add checklist item' : 'Edit checklist item',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(color: AppColors.of(ctx).t1),
                  decoration: const InputDecoration(
                    label: WorkloopFieldLabel(
                      'Checklist item',
                      isRequired: true,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    hintText: 'What needs checking off?',
                  ),
                ),
                const SizedBox(height: 18),
                if (errorMessage != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      errorMessage!,
                      style: TextStyle(
                        color: AppColors.of(ctx).error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                SlateButton(
                  label: saving
                      ? 'Saving...'
                      : item == null
                      ? 'Add Item'
                      : 'Save Item',
                  icon: item == null ? LucideIcons.plus : LucideIcons.check,
                  onPressed: saving
                      ? null
                      : () async {
                          final title = controller.text.trim();
                          if (title.isEmpty) return;
                          setModal(() {
                            saving = true;
                            errorMessage = null;
                          });
                          try {
                            if (item == null) {
                              final existing = await ref.read(
                                taskChecklistProvider(task.id).future,
                              );
                              await ref
                                  .read(tasksRepositoryProvider)
                                  .addChecklistItem(
                                    workspaceId: task.workspaceId,
                                    taskId: task.id,
                                    title: title,
                                    position: existing.length,
                                  );
                            } else {
                              await ref
                                  .read(tasksRepositoryProvider)
                                  .updateChecklistItem(
                                    itemId: item.id,
                                    title: title,
                                  );
                            }
                            ref.invalidate(taskChecklistProvider(task.id));
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (_) {
                            if (!ctx.mounted) return;
                            setModal(() {
                              saving = false;
                              errorMessage = item == null
                                  ? 'Could not add this checklist item. Please try again.'
                                  : 'Could not save this checklist item. Please try again.';
                            });
                          }
                        },
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(
      () => _disposeControllerAfterSheetClose(controller, closeDuration),
    );
  }

  void _disposeControllerAfterSheetClose(
    TextEditingController controller,
    Duration closeDuration,
  ) {
    Future.delayed(closeDuration, controller.dispose);
  }

  Future<void> _toggleChecklistItem(
    SlateTask task,
    TaskChecklistItem item,
  ) async {
    try {
      await ref
          .read(tasksRepositoryProvider)
          .updateChecklistItemStatus(
            itemId: item.id,
            completed: !item.completed,
          );
      if (!mounted) return;
      ref.invalidate(taskChecklistProvider(task.id));
    } catch (_) {
      if (!mounted) return;
      _showTaskFailure(
        'Could not update this checklist item. Nothing was changed.',
      );
    }
  }

  Future<void> _deleteChecklistItem(
    SlateTask task,
    TaskChecklistItem item,
  ) async {
    try {
      await ref.read(tasksRepositoryProvider).deleteChecklistItem(item.id);
      if (!mounted) return;
      ref.invalidate(taskChecklistProvider(task.id));
    } catch (_) {
      if (!mounted) return;
      _showTaskFailure(
        'Could not delete this checklist item. Nothing was removed.',
      );
    }
  }

  Future<bool> _confirmComplete(SlateTask task) async {
    var saving = false;
    String? errorMessage;
    final completed = await showWorkloopBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => PopScope(
          canPop: !saving,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Complete this task?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.of(ctx).t3),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.of(ctx).error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SlateButton(
                  label: saving ? 'Completing...' : 'Mark Complete',
                  icon: LucideIcons.checkCircle,
                  onPressed: saving
                      ? null
                      : () async {
                          setSheetState(() {
                            saving = true;
                            errorMessage = null;
                          });
                          try {
                            await ref
                                .read(tasksRepositoryProvider)
                                .updateStatus(task.id, 'done');
                            _refreshTasks();
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (_) {
                            if (!ctx.mounted) return;
                            setSheetState(() {
                              saving = false;
                              errorMessage =
                                  'Could not complete this task. Nothing was changed. Please try again.';
                            });
                          }
                        },
                ),
                const SizedBox(height: 10),
                SlateButton(
                  label: 'Cancel',
                  secondary: true,
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return completed ?? false;
  }

  Future<bool> _reopenTask(SlateTask task) async {
    try {
      await ref.read(tasksRepositoryProvider).updateStatus(task.id, 'open');
      _refreshTasks();
      return true;
    } catch (_) {
      _showTaskFailure('Could not reopen this task. Nothing was changed.');
      return false;
    }
  }

  Future<bool> _confirmDelete(SlateTask task) async {
    var deleting = false;
    String? errorMessage;
    final deleted = await showWorkloopBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => PopScope(
          canPop: !deleting,
          child: SlateSheetFrame(
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete task?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(ctx).t1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.title,
                  style: TextStyle(fontSize: 14, color: AppColors.of(ctx).t3),
                  textAlign: TextAlign.center,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.of(ctx).error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SlateButton(
                  label: deleting ? 'Deleting...' : 'Delete Task',
                  destructive: true,
                  onPressed: deleting
                      ? null
                      : () async {
                          setSheetState(() {
                            deleting = true;
                            errorMessage = null;
                          });
                          try {
                            await ref
                                .read(tasksRepositoryProvider)
                                .delete(task.id);
                            _refreshTasks();
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (_) {
                            if (!ctx.mounted) return;
                            setSheetState(() {
                              deleting = false;
                              errorMessage =
                                  'Could not delete this task. Nothing was removed. Please try again.';
                            });
                          }
                        },
                ),
                const SizedBox(height: 10),
                SlateButton(
                  label: 'Cancel',
                  secondary: true,
                  onPressed: deleting ? null : () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return deleted ?? false;
  }

  void _refreshTasks() {
    ref.invalidate(allTasksProvider);
    ref.invalidate(tasksProvider);
  }

  void _refreshTaskNotifications() {
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  void _showTaskFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.of(context).error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TaskViewSwitcher extends StatelessWidget {
  final _TaskView value;
  final _TaskCounts counts;
  final ValueChanged<_TaskView> onChanged;

  const _TaskViewSwitcher({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return WorkloopNavigationControl<_TaskView>(
      selected: value,
      color: AppColors.of(context).modTasks,
      emphasized: false,
      onChanged: onChanged,
      segments: _TaskView.values
          .map(
            (view) => WorkloopSegment<_TaskView>(
              value: view,
              label: _viewLabel(view),
              badge: '${_viewCount(view, counts)}',
            ),
          )
          .toList(),
    );
  }
}

class _TaskSectionView extends StatelessWidget {
  final _TaskSection section;
  final ValueChanged<SlateTask> onOpen;
  final ValueChanged<SlateTask> onCompleteRequest;
  final ValueChanged<SlateTask> onReopen;
  final ValueChanged<SlateTask> onDelete;

  const _TaskSectionView({
    required this.section,
    required this.onOpen,
    required this.onCompleteRequest,
    required this.onReopen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkloopSectionHeader(
            label: '${section.title}  ${section.tasks.length}',
            quiet: true,
          ),
          const SizedBox(height: 6),
          ...section.tasks.map(
            (task) => _TaskCard(
              task: task,
              onOpen: () => onOpen(task),
              onCompleteRequest: () => onCompleteRequest(task),
              onReopen: () => onReopen(task),
              onDelete: () => onDelete(task),
            ),
          ),
        ],
      ),
    );
  }
}

/// Controllers belong to the route until its reverse transition has unmounted.
class _TaskEditorState extends StatefulWidget {
  final String initialTitle;
  final Widget Function(
    BuildContext,
    StateSetter,
    TextEditingController,
    TextEditingController,
  )
  builder;
  const _TaskEditorState({required this.initialTitle, required this.builder});

  @override
  State<_TaskEditorState> createState() => _TaskEditorStateState();
}

class _TaskEditorStateState extends State<_TaskEditorState> {
  late final TextEditingController titleController;
  final checklistController = TextEditingController();

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    titleController.dispose();
    checklistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, setState, titleController, checklistController);
}
