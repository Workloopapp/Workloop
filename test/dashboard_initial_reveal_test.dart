import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/dashboard/dashboard_screen.dart';
import 'package:workloop/main.dart';
import 'package:workloop/shared/models/business_feed_item.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/business_feed_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/setup_checklist_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void main() {
  testWidgets('navigation is usable before slow dashboard sections finish', (
    tester,
  ) async {
    final firstAppointments = Completer<List<Map<String, dynamic>>>();
    final refreshedAppointments = Completer<List<Map<String, dynamic>>>();
    final attention = Completer<List<DashboardAttentionItem>>();
    final finance = Completer<FinanceSummary>();
    var appointmentLoads = 0;
    final authRepository = AuthRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    final summary = FinanceSummary.from(
      payments: const [],
      expenses: const [],
      monthlyTarget: 3000,
      now: DateTime(2026, 8, 11, 9),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          workspaceProvider.overrideWith(
            (ref) async => const {
              'id': 'workspace-1',
              'name': 'Workloop Studio',
            },
          ),
          dashboardClockProvider.overrideWith(
            (ref) => Stream.value(DateTime(2026, 8, 11, 9)),
          ),
          appointmentsProvider.overrideWith((ref) {
            appointmentLoads += 1;
            return appointmentLoads == 1
                ? firstAppointments.future
                : refreshedAppointments.future;
          }),
          dashboardAttentionProvider.overrideWith((ref) => attention.future),
          clientsProvider.overrideWith((ref) async => const <Client>[]),
          invoicesProvider.overrideWith((ref) async => const <Payment>[]),
          financeSummaryProvider.overrideWith((ref) => finance.future),
          allTasksProvider.overrideWith((ref) async => const <SlateTask>[]),
          allNotesProvider.overrideWith((ref) async => const <SlateNote>[]),
          businessFeedProvider.overrideWith(
            (ref) async => const <BusinessFeedItem>[],
          ),
          unreadNotificationsProvider.overrideWith((ref) async => 0),
          setupChecklistDismissedProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WorkspaceGate(child: MainShell()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(WorkloopBottomNav), findsOneWidget);
    expect(find.text('Your day is clear'), findsNothing);
    expect(find.text('Opening Workloop'), findsNothing);

    firstAppointments.complete(const []);
    attention.complete(const []);
    await tester.pump();

    expect(find.byType(WorkloopBottomNav), findsOneWidget);
    expect(find.text('Opening Workloop'), findsNothing);

    finance.complete(summary);
    await tester.pumpAndSettle();

    expect(find.byType(WorkloopBottomNav), findsOneWidget);
    expect(find.text('Today'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
    );
    container.invalidate(workspaceProvider);
    container.invalidate(appointmentsProvider);
    await tester.pump();

    expect(find.byKey(const ValueKey('dashboard-opening')), findsNothing);
    expect(find.byType(WorkloopBottomNav), findsOneWidget);

    refreshedAppointments.complete(const []);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
