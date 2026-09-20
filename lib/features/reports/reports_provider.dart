import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/slate_models.dart';
import '../../shared/providers/appointments_provider.dart';
import '../../shared/providers/clients_provider.dart';
import '../../shared/providers/finance_provider.dart';
import '../../shared/providers/tasks_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/providers/workspace_settings_provider.dart';
import 'report_models.dart';

/// Reuses complete, paginated workspace reads. Fail closed if any source fails;
/// an unavailable collection must never become a convincing zero in a report.
final reportsSourceProvider = FutureProvider.autoDispose<ReportSource>((
  ref,
) async {
  final workspaceFuture = ref.watch(workspaceProvider.future);
  final settingsFuture = ref.watch(workspaceSettingsProvider.future);
  final paymentsFuture = ref.watch(invoicesProvider.future);
  final expensesFuture = ref.watch(expensesProvider.future);
  final bookingsFuture = ref.watch(appointmentsProvider.future);
  final clientsFuture = ref.watch(clientsProvider.future);
  final tasksFuture = ref.watch(allTasksProvider.future);
  final (
    workspace,
    settings,
    payments,
    expenses,
    bookings,
    clients,
    tasks,
  ) = await (
    workspaceFuture,
    settingsFuture,
    paymentsFuture,
    expensesFuture,
    bookingsFuture,
    clientsFuture,
    tasksFuture,
  ).wait;
  final id = workspace?['id'] as String?;
  if (id == null) throw StateError('A workspace is required to run reports.');
  return ReportSource(
    workspaceId: id,
    businessName: workspace?['name'] as String? ?? 'Your business',
    timezone: settings?['timezone'] as String? ?? 'Europe/London',
    payments: payments.where((p) => p.workspaceId == id).toList(),
    expenses: expenses.where((e) => e.workspaceId == id).toList(),
    bookings: bookings
        .map(Appointment.fromMap)
        .where((b) => b.workspaceId == id)
        .toList(),
    clients: clients.where((c) => c.workspaceId == id).toList(),
    tasks: tasks.where((t) => t.workspaceId == id).toList(),
  );
});
