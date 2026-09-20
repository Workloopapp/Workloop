import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/settings/widgets/settings_business_tab.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/notes_repository.dart';
import 'package:workloop/shared/repositories/profile_repository.dart';

class _ControlledNotesRepository extends NotesRepository {
  _ControlledNotesRepository()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final deletion = Completer<void>();
  int deleteCalls = 0;

  @override
  Future<void> delete(String noteId) {
    deleteCalls += 1;
    return deletion.future;
  }
}

class _UnavailableHandleProfileRepository extends ProfileRepository {
  _UnavailableHandleProfileRepository()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  int availabilityChecks = 0;
  int updateCalls = 0;

  @override
  Future<bool> isHandleAvailable(String handle) async {
    availabilityChecks += 1;
    return false;
  }

  @override
  Future<void> updateWorkspaceProfile({
    required String workspaceId,
    required Map<String, dynamic> values,
  }) async {
    updateCalls += 1;
  }
}

void main() {
  const note = SlateNote(
    id: 'note-1',
    workspaceId: 'workspace-1',
    title: 'Launch notes',
    body: 'Keep this note unless deletion succeeds.',
  );

  Future<void> openDeleteDialog(
    WidgetTester tester,
    _ControlledNotesRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allNotesProvider.overrideWith((ref) async => const [note]),
          notesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NotesScreen(showBackButton: false)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Launch notes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Note actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();

    expect(find.text('Delete note?'), findsOneWidget);
  }

  testWidgets(
    'failed note deletion stays in context and offers a retry',
    (tester) async {
      final repository = _ControlledNotesRepository();
      await openDeleteDialog(tester, repository);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();

      expect(repository.deleteCalls, 1);
      expect(find.text('Delete note?'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.deletion.completeError(StateError('offline'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, 1);
      expect(find.text('Delete note?'), findsOneWidget);
      expect(
        find.text(
          'Couldn’t finish deleting this note and its files. Please try again.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Note actions'), findsOneWidget);
      expect(
        find.text('Launch notes\nKeep this note unless deletion succeeds.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('public profile checks a changed handle before saving', (
    tester,
  ) async {
    final repository = _UnavailableHandleProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(
            (ref) async => {
              'id': 'workspace-1',
              'name': 'Launch Studio',
              'industry': 'Beauty',
            },
          ),
          settingsBusinessProfileProvider.overrideWith(
            (ref) async => const BusinessProfile(
              id: 'profile-1',
              workspaceId: 'workspace-1',
              handle: 'launch-studio',
            ),
          ),
          settingsWorkspaceSettingsProvider.overrideWith((ref) async => null),
          settingsServicesProvider.overrideWith((ref) async => const []),
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsBusinessTab(
              initialSection: SettingsBusinessSection.publicProfile,
              showOnlySelected: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'taken-handle');
    await tester.tap(find.text('Save booking page'));
    await tester.pumpAndSettle();

    expect(repository.availabilityChecks, 1);
    expect(repository.updateCalls, 0);
    expect(
      find.text('That booking link is already taken. Choose another handle.'),
      findsOneWidget,
    );
  });
}
