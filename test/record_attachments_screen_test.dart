import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/notes/notes_screen.dart';
import 'package:workloop/shared/attachments/record_attachment.dart';
import 'package:workloop/shared/attachments/record_attachment_picker.dart';
import 'package:workloop/shared/attachments/record_attachments_repository.dart';
import 'package:workloop/shared/attachments/record_attachments_screen.dart';
import 'package:workloop/shared/documents/workloop_document_viewer.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/repositories/notes_repository.dart';

const _workspace = '10000000-0000-4000-8000-000000000001';
const _target = AttachmentTarget.booking(
  '20000000-0000-4000-8000-000000000001',
);
final _file = RecordAttachmentFile.checked(
  'Access.txt',
  Uint8List.fromList(utf8.encode('Gate code supplied on arrival.')),
);

class _Auth extends Fake implements AuthRepository {
  String? user = 'owner';
  final events = StreamController<AuthState>.broadcast();
  @override
  String? get currentUserId => user;
  @override
  Stream<AuthState> get authChanges => events.stream;
}

class _Picker extends Fake implements RecordAttachmentPicker {
  Completer<RecordAttachmentFile?>? pending;
  int calls = 0;
  @override
  Future<bool> discardUnscopedRecovery() async => false;
  @override
  Future<RecordAttachmentFile?> pick(RecordAttachmentSource source) async {
    calls++;
    return pending == null ? _file : pending!.future;
  }
}

class _Attachments extends Fake implements RecordAttachmentsRepository {
  final files = <RecordAttachment>[];
  final uploadIds = <String?>[];
  bool failUpload = false;
  bool failList = false;
  int downloads = 0;
  @override
  Future<List<RecordAttachment>> list({
    required String workspaceId,
    required AttachmentTarget target,
  }) async {
    if (failList) throw StateError('Offline');
    return files
        .where(
          (file) => file.workspaceId == workspaceId && file.target == target,
        )
        .toList();
  }

  @override
  Future<RecordAttachment> upload({
    required String workspaceId,
    required AttachmentTarget target,
    required String fileName,
    required Uint8List bytes,
    String? attachmentId,
  }) async {
    uploadIds.add(attachmentId);
    if (failUpload) throw StateError('Offline');
    final file = RecordAttachment(
      id: attachmentId!,
      workspaceId: workspaceId,
      target: target,
      fileName: fileName,
      mimeType: 'text/plain',
      sizeBytes: bytes.length,
      path: '$workspaceId/${target.id}/$attachmentId.txt',
      createdAt: DateTime(2026, 9, 12),
    );
    files.add(file);
    return file;
  }

  @override
  Future<Uint8List> download(RecordAttachment attachment) async {
    downloads++;
    return _file.bytes;
  }

  @override
  Future<void> delete(RecordAttachment attachment) async =>
      files.remove(attachment);
}

class _Notes extends Fake implements NotesRepository {
  final ids = <String?>[];
  int updates = 0;
  bool failCreate = false;
  @override
  Future<String> create({
    required String workspaceId,
    required String title,
    required String body,
    String? contactId,
    String? appointmentId,
    bool pinned = false,
    String? noteId,
  }) async {
    ids.add(noteId);
    if (failCreate) throw StateError('Response lost');
    return noteId!;
  }

  @override
  Future<void> update({
    required String noteId,
    required String title,
    required String body,
    String? contactId,
    String? appointmentId,
    required bool pinned,
  }) async {
    updates++;
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required _Auth auth,
  required _Attachments repository,
  required _Picker picker,
  double scale = 1,
  String Function()? workspace,
  _Notes? notes,
}) async {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(auth.events.close);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      workspaceIdProvider.overrideWith(
        (ref) async => workspace?.call() ?? _workspace,
      ),
      recordAttachmentsRepositoryProvider.overrideWithValue(repository),
      recordAttachmentPickerProvider.overrideWithValue(picker),
      if (notes != null) ...[
        notesRepositoryProvider.overrideWithValue(notes),
        allNotesProvider.overrideWith((ref) async => <SlateNote>[]),
      ],
    ],
  );
  addTearDown(container.dispose);
  await container.read(workspaceIdProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: notes == null
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RecordAttachmentsScreen(
                          workspaceId: _workspace,
                          target: _target,
                          recordTitle: 'Window cleaning',
                        ),
                      ),
                    ),
                    child: const Text('Open booking files'),
                  ),
                ),
              )
            : const NotesScreen(showBackButton: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (notes == null) {
    await tester.tap(find.text('Open booking files'));
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> _pickFile(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Add'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.ensureVisible(find.text('Choose file'));
  await tester.tap(find.text('Choose file'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'failed upload retains one identity, retries and opens text in app',
    (tester) async {
      final repository = _Attachments()..failUpload = true;
      await _mount(
        tester,
        auth: _Auth(),
        repository: repository,
        picker: _Picker(),
        scale: 2,
      );
      await _pickFile(tester);
      expect(repository.uploadIds, hasLength(1));
      await tester.scrollUntilVisible(
        find.text('Waiting to upload'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Waiting to upload'), findsOneWidget);
      repository.failUpload = false;
      await tester.scrollUntilVisible(
        find.text('Retry upload'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Retry upload'));
      await tester.pumpAndSettle();
      expect(repository.uploadIds, hasLength(2));
      expect(repository.uploadIds[1], repository.uploadIds.first);
      expect(repository.uploadIds.first, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(repository.files, hasLength(1));
      await tester.scrollUntilVisible(
        find.text('Access.txt'),
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Access.txt'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkloopDocumentViewerScreen), findsOneWidget);
      expect(find.text('Gate code supplied on arrival.'), findsOneWidget);
      expect(repository.downloads, 1);
      await tester.tap(find.bySemanticsLabel('Back').first);
      await tester.pumpAndSettle();
      expect(find.text('Window cleaning'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching workspace during native selection discards result', (
    tester,
  ) async {
    var workspace = _workspace;
    final repository = _Attachments();
    final picker = _Picker()..pending = Completer<RecordAttachmentFile?>();
    final container = await _mount(
      tester,
      auth: _Auth(),
      repository: repository,
      picker: picker,
      workspace: () => workspace,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Choose file'));
    await tester.pump();
    workspace = 'another-business';
    container.invalidate(workspaceIdProvider);
    await tester.pump();
    picker.pending!.complete(_file);
    await tester.pumpAndSettle();
    expect(repository.uploadIds, isEmpty);
    expect(find.text('Window cleaning'), findsNothing);
    expect(find.text('Access.txt'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Back').first);
    await tester.pumpAndSettle();
    expect(find.text('Open booking files'), findsOneWidget);
  });

  testWidgets(
    'load failure offers retry and never claims an empty collection',
    (tester) async {
      final repository = _Attachments()..failList = true;
      await _mount(
        tester,
        auth: _Auth(),
        repository: repository,
        picker: _Picker(),
      );
      expect(
        find.text(
          'Could not load attachments. Your files have not been removed.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('No photos or files yet'), findsNothing);
      repository.failList = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No photos or files yet'), findsOneWidget);
    },
  );

  testWidgets('new note saves once for attachments then updates same note', (
    tester,
  ) async {
    final notes = _Notes()..failCreate = true;
    await _mount(
      tester,
      auth: _Auth(),
      repository: _Attachments(),
      picker: _Picker(),
      notes: notes,
    );
    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Site notes\nCheck the gate.',
    );
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save this note.'), findsOneWidget);
    notes.failCreate = false;
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(notes.ids, hasLength(2));
    expect(notes.ids[0], notes.ids[1]);
    expect(find.byType(RecordAttachmentsScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Site notes\nGate checked.');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(notes.ids, hasLength(2));
    expect(notes.updates, 1);
    expect(find.byType(RecordAttachmentsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
