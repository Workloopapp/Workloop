import 'package:flutter_riverpod/misc.dart';

import 'appointments_provider.dart';
import 'booking_requests_provider.dart';
import 'business_clock_provider.dart';
import 'clients_provider.dart';
import 'finance_provider.dart';
import 'notes_provider.dart';
import 'notifications_provider.dart';
import 'tasks_provider.dart';
import 'workspace_settings_provider.dart';

/// Contact names, email addresses and links are included in these query results.
/// Updating or removing a contact must refresh those joins as well as Clients.
void refreshClientRelatedData(void Function(ProviderOrFamily) invalidate) {
  invalidate(clientsProvider);
  invalidate(appointmentsProvider);
  invalidate(invoicesProvider);
  invalidate(allTasksProvider);
  invalidate(allNotesProvider);
}

/// Refresh the shared source rows after an external change or app resume.
/// Derived totals/detail views react to these dependencies automatically.
/// Invalidating an unobserved provider does not start a background query.
void refreshWorkspaceData(void Function(ProviderOrFamily) invalidate) {
  invalidate(businessClockProvider);
  invalidate(appointmentsProvider);
  invalidate(bookingRequestsProvider);
  invalidate(clientsProvider);
  invalidate(invoicesProvider);
  invalidate(expensesProvider);
  invalidate(allTasksProvider);
  invalidate(allNotesProvider);
  invalidate(servicesProvider);
  invalidate(workspaceSettingsProvider);
  invalidate(notificationsProvider);
  invalidate(unreadNotificationsProvider);
  invalidate(notificationPreferencesProvider);
}
