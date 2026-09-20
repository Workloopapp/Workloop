import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/clients/client_detail_screen.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/repositories/clients_repository.dart';

class _EditableClientRepository extends ClientsRepository {
  _EditableClientRepository()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  String? name = 'Before edit';
  int writes = 0;

  @override
  Future<void> update(String clientId, Map<String, dynamic> values) async {
    writes++;
    name = values['name'] as String;
  }

  @override
  Future<void> delete(String clientId) async {
    writes++;
    name = null;
  }
}

void main() {
  for (final delete in [false, true]) {
    testWidgets(
      'client ${delete ? 'deletion removes' : 'edit refreshes'} cached joined details across the app',
      (tester) async {
        final repository = _EditableClientRepository();
        var expenseReads = 0;
        final initial = {
          'id': 'client-1',
          'workspace_id': 'workspace-1',
          'name': repository.name,
          'status': 'active',
        };
        final container = ProviderContainer(
          overrides: [
            clientsRepositoryProvider.overrideWithValue(repository),
            clientsProvider.overrideWith(
              (ref) async => repository.name == null
                  ? []
                  : [
                      Client.fromMap({...initial, 'name': repository.name}),
                    ],
            ),
            appointmentsProvider.overrideWith(
              (ref) async => [
                {
                  'id': 'booking-1',
                  'workspace_id': 'workspace-1',
                  'contact_id': repository.name == null ? null : 'client-1',
                  'start_time': '2026-09-06T10:00:00',
                  'status': 'scheduled',
                  'contacts': repository.name == null
                      ? null
                      : {'name': repository.name},
                },
              ],
            ),
            invoicesProvider.overrideWith(
              (ref) async => [
                Payment(
                  id: 'payment-1',
                  workspaceId: 'workspace-1',
                  contactId: repository.name == null ? null : 'client-1',
                  number: 'PAY-1',
                  status: 'sent',
                  issueDate: DateTime(2026, 9, 1),
                  total: 45,
                  clientName: repository.name,
                ),
              ],
            ),
            allTasksProvider.overrideWith(
              (ref) async => [
                SlateTask(
                  id: 'task-1',
                  workspaceId: 'workspace-1',
                  title: 'Prepare',
                  contactId: repository.name == null ? null : 'client-1',
                  clientName: repository.name,
                ),
              ],
            ),
            allNotesProvider.overrideWith(
              (ref) async => [
                SlateNote(
                  id: 'note-1',
                  workspaceId: 'workspace-1',
                  title: 'Details',
                  body: '',
                  contactId: repository.name == null ? null : 'client-1',
                  clientName: repository.name,
                ),
              ],
            ),
            expensesProvider.overrideWith((ref) async {
              expenseReads++;
              return [];
            }),
          ],
        );
        addTearDown(container.dispose);

        await Future.wait<Object?>([
          container.read(appointmentsProvider.future),
          container.read(invoicesProvider.future),
          container.read(allTasksProvider.future),
          container.read(allNotesProvider.future),
          container.read(expensesProvider.future),
        ]);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ClientDetailScreen(client: initial),
                        ),
                      ),
                      child: const Text('Open client'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open client'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        if (delete) {
          await tester.ensureVisible(find.text('Delete client'));
          await tester.tap(find.text('Delete client'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete Client'));
        } else {
          await tester.enterText(
            find.widgetWithText(TextField, 'Person or business name'),
            'After edit',
          );
          await tester.tap(find.text('Save'));
        }
        await tester.pumpAndSettle();
        expect(repository.writes, 1);
        final expected = delete ? null : 'After edit';
        final rows = await container.read(appointmentsProvider.future);
        expect(rows.single['contacts']?['name'], expected);
        expect(
          (await container.read(invoicesProvider.future)).single.clientName,
          expected,
        );
        expect(
          (await container.read(allTasksProvider.future)).single.clientName,
          expected,
        );
        expect(
          (await container.read(allNotesProvider.future)).single.clientName,
          expected,
        );
        await container.read(expensesProvider.future);
        expect(
          expenseReads,
          1,
          reason: 'Client changes must not refresh unrelated expenses.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
