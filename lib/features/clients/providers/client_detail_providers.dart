import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/slate_models.dart';
import '../../../shared/providers/appointments_provider.dart';
import '../../../shared/providers/finance_provider.dart';
import '../../../shared/providers/tasks_provider.dart';

// Detail screens use the same workspace collections as Today, Work and Money.
// A mutation or workspace change therefore cannot leave a second client cache
// showing old bookings, tasks or balances.
final clientAppointmentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, clientId) async {
      final rows = await ref.watch(appointmentsProvider.future);
      return rows.where((row) => row['contact_id'] == clientId).toList();
    });

final clientTasksProvider = FutureProvider.autoDispose
    .family<List<SlateTask>, String>((ref, clientId) async {
      final tasks = await ref.watch(allTasksProvider.future);
      return tasks.where((item) => item.contactId == clientId).toList();
    });

final clientPaymentsProvider = FutureProvider.autoDispose
    .family<List<Payment>, String>((ref, clientId) async {
      final payments = await ref.watch(invoicesProvider.future);
      return payments.where((item) => item.contactId == clientId).toList();
    });

/// Refresh the canonical data too: invalidating a filtered view on its own
/// would simply filter the same cached rows again. Errors stay in AsyncValue
/// for the existing retry/error widgets to render.
Future<void> refreshClientAppointments(WidgetRef ref, String clientId) async {
  ref.invalidate(appointmentsProvider);
  ref.invalidate(clientAppointmentsProvider(clientId));
  try {
    await ref.read(clientAppointmentsProvider(clientId).future);
  } catch (_) {}
}

Future<void> refreshClientTasks(WidgetRef ref, String clientId) async {
  ref.invalidate(allTasksProvider);
  ref.invalidate(clientTasksProvider(clientId));
  try {
    await ref.read(clientTasksProvider(clientId).future);
  } catch (_) {}
}

Future<void> refreshClientPayments(WidgetRef ref, String clientId) async {
  ref.invalidate(invoicesProvider);
  ref.invalidate(clientPaymentsProvider(clientId));
  try {
    await ref.read(clientPaymentsProvider(clientId).future);
  } catch (_) {}
}
