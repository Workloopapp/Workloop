import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/slate_models.dart';
import '../repositories/slate_repositories.dart';
import 'business_clock_provider.dart';
import 'workspace_provider.dart';

// Used on dashboard — only open tasks due today or earlier
final tasksProvider = FutureProvider<List<SlateTask>>((ref) async {
  final today = ref.watch(businessTodayProvider);
  final tasks = await ref.watch(allTasksProvider.future);
  return tasks.where((task) {
    final due = task.dueDate?.toLocal();
    return task.status == 'open' &&
        due != null &&
        !DateTime(due.year, due.month, due.day).isAfter(today);
  }).toList();
});

// Used on tasks screen — all tasks open and done
final allTasksProvider = FutureProvider<List<SlateTask>>((ref) async {
  final workspaceId = await ref.watch(workspaceIdProvider.future);
  if (workspaceId == null) return [];

  return ref.watch(tasksRepositoryProvider).list(workspaceId);
});

final taskChecklistProvider = FutureProvider.autoDispose
    .family<List<TaskChecklistItem>, String>((ref, taskId) async {
      final workspaceId = await ref.watch(workspaceIdProvider.future);
      if (workspaceId == null) return [];
      return ref.watch(tasksRepositoryProvider).checklistItems(taskId);
    });

final appointmentTasksProvider = FutureProvider.autoDispose
    .family<List<SlateTask>, String>((ref, appointmentId) async {
      final tasks = await ref.watch(allTasksProvider.future);
      return tasks
          .where((item) => item.appointmentId == appointmentId)
          .toList();
    });
