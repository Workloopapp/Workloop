import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/shared/attachments/record_attachment.dart';
import 'package:workloop/shared/attachments/record_attachments_repository.dart';
import 'package:workloop/shared/repositories/clients_repository.dart';

const workspace = '91000000-0000-4000-8000-000000000001';
const targetId = '91000000-0000-4000-8000-000000000002';
const attachmentId = '91000000-0000-4000-8000-000000000003';
const target = AttachmentTarget.booking(targetId);
final bytes = Uint8List.fromList('%PDF-1.7\nexample'.codeUnits);

Map<String, dynamic> attachmentRow({AttachmentTarget target = target}) => {
  'id': attachmentId,
  'workspace_id': workspace,
  target.column: target.id,
  'file_name': 'work.pdf',
  'mime_type': 'application/pdf',
  'size_bytes': bytes.length,
  'content_hash': sha256.convert(bytes).toString(),
  'object_path': '$workspace/$targetId/$attachmentId.pdf',
  'created_at': '2026-09-12T12:00:00Z',
};

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

SupabaseClient client(Future<http.Response> Function(http.Request) handle) =>
    SupabaseClient(
      'https://example.supabase.co',
      'fake-anon-key',
      httpClient: MockClient((request) async {
        final response = await handle(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

void main() {
  test('validates bytes and name before upload and freezes selected bytes', () {
    for (final entry in [
      ('photo.jpg', <int>[255, 216, 255], 'image/jpeg'),
      ('photo.png', <int>[137, 80, 78, 71, 13, 10, 26, 10], 'image/png'),
      ('photo.webp', 'RIFF0000WEBP'.codeUnits, 'image/webp'),
      ('work.pdf', bytes.toList(), 'application/pdf'),
      ('work.txt', utf8.encode('Gate code\nCafé'), 'text/plain'),
    ]) {
      final input = Uint8List.fromList(entry.$2);
      final checked = RecordAttachmentFile.checked(entry.$1, input);
      expect(checked.mimeType, entry.$3);
      input[0] = 0;
      expect(checked.bytes[0], entry.$2[0]);
    }
    for (final entry in [
      ('work.exe', <int>[1, 2, 3]),
      ('work.svg', '<svg/>'.codeUnits),
      ('work.txt', <int>[255, 0, 254]),
      ('../work.pdf', bytes.toList()),
      ('work\n.pdf', bytes.toList()),
      ('work.pdf', <int>[]),
    ]) {
      expect(
        () => RecordAttachmentFile.checked(
          entry.$1,
          Uint8List.fromList(entry.$2),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => RecordAttachmentFile.checked(
        'big.txt',
        Uint8List(recordAttachmentMaxBytes + 1),
      ),
      throwsFormatException,
    );
  });

  test(
    'list pins workspace and target, surfaces errors, and models all targets',
    () async {
      final api = client((request) async {
        expect(request.url.queryParameters['workspace_id'], 'eq.$workspace');
        expect(request.url.queryParameters['appointment_id'], 'eq.$targetId');
        expect(
          request.url.queryParameters['order'],
          startsWith('created_at.desc'),
        );
        expect(request.url.queryParameters['order'], contains(',id.asc'));
        return json([attachmentRow()]);
      });
      addTearDown(api.dispose);
      final rows = await RecordAttachmentsRepository(
        api,
      ).list(workspaceId: workspace, target: target);
      expect(rows.single.target, target);
      for (final link in [
        const AttachmentTarget.note(targetId),
        const AttachmentTarget.client(targetId),
      ]) {
        expect(
          RecordAttachment.fromMap(attachmentRow(target: link)).target,
          link,
        );
      }
      final failing = client(
        (_) async => json({'message': 'Offline', 'code': 'PGRST000'}, 503),
      );
      addTearDown(failing.dispose);
      await expectLater(
        RecordAttachmentsRepository(
          failing,
        ).list(workspaceId: workspace, target: target),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test(
    'metadata is reserved before bytes and response-loss retry reuses identity',
    () async {
      final calls = <String>[];
      var uploads = 0;
      final api = client((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/record_attachments') {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map;
            expect(body['id'], attachmentId);
            expect(
              request.headers['prefer'],
              contains('resolution=ignore-duplicates'),
            );
            return http.Response('', 201);
          }
          return json(attachmentRow());
        }
        if (request.method == 'POST') {
          uploads++;
          if (uploads == 1) {
            return json({'Key': attachmentRow()['object_path']});
          }
          return json({'message': 'Already exists', 'statusCode': '409'}, 409);
        }
        expect(request.method, 'GET');
        return http.Response.bytes(bytes, 200);
      });
      addTearDown(api.dispose);
      final repo = RecordAttachmentsRepository(api);
      for (var i = 0; i < 2; i++) {
        final saved = await repo.upload(
          workspaceId: workspace,
          target: target,
          fileName: 'work.pdf',
          bytes: bytes,
          attachmentId: attachmentId,
        );
        expect(saved.id, attachmentId);
      }
      expect(calls.first, 'POST /rest/v1/record_attachments');
      expect(calls.where((call) => call.startsWith('DELETE')), isEmpty);
      expect(uploads, 2);
    },
  );

  test(
    'failed metadata never uploads, failed bytes cleanup precedes metadata',
    () async {
      final calls = <String>[];
      final api = client((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/record_attachments') {
          if (request.method == 'GET') return json(attachmentRow());
          return http.Response('', 201);
        }
        if (request.method == 'DELETE') return json([]);
        return json({'message': 'Unavailable', 'statusCode': '403'}, 403);
      });
      addTearDown(api.dispose);
      await expectLater(
        RecordAttachmentsRepository(api).upload(
          workspaceId: workspace,
          target: target,
          fileName: 'work.pdf',
          bytes: bytes,
          attachmentId: attachmentId,
        ),
        throwsA(isA<StorageException>()),
      );
      expect(
        calls[calls.length - 2],
        'DELETE /storage/v1/object/record-attachments',
      );
      expect(calls.last, 'DELETE /rest/v1/record_attachments');
      final denied = client((request) async {
        expect(request.url.path, '/rest/v1/record_attachments');
        return json({'message': 'Denied', 'code': '42501'}, 403);
      });
      addTearDown(denied.dispose);
      await expectLater(
        RecordAttachmentsRepository(denied).upload(
          workspaceId: workspace,
          target: target,
          fileName: 'work.pdf',
          bytes: bytes,
          attachmentId: attachmentId,
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test(
    'failed file removal retains metadata and blocks client deletion',
    () async {
      final calls = <String>[];
      final api = client((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/contacts') {
          return json({'workspace_id': workspace});
        }
        if (request.url.path == '/rest/v1/record_attachments') {
          return json([
            attachmentRow(target: const AttachmentTarget.client(targetId)),
          ]);
        }
        return json({'message': 'Unavailable', 'statusCode': '403'}, 403);
      });
      addTearDown(api.dispose);
      await expectLater(
        ClientsRepository(api).delete(targetId),
        throwsA(isA<StorageException>()),
      );
      expect(calls.where((call) => call.startsWith('DELETE /rest')), isEmpty);
    },
  );

  test(
    'retry with different contents cannot overwrite the original attachment',
    () async {
      var calls = 0;
      final api = client((request) async {
        calls++;
        expect(request.url.path, '/rest/v1/record_attachments');
        return request.method == 'POST'
            ? http.Response('', 201)
            : json(attachmentRow());
      });
      addTearDown(api.dispose);
      await expectLater(
        RecordAttachmentsRepository(api).upload(
          workspaceId: workspace,
          target: target,
          fileName: 'work.pdf',
          bytes: Uint8List.fromList('%PDF-different'.codeUnits),
          attachmentId: attachmentId,
        ),
        throwsFormatException,
      );
      expect(calls, 2);
    },
  );

  test(
    'pre-migration deletion ignores only the exact absent attachments table',
    () async {
      for (final failure in [
        (
          'PGRST205',
          "Could not find the table 'public.record_attachments' in the schema cache",
          true,
        ),
        ('42P01', 'relation "record_attachments" does not exist', true),
        ('42501', 'permission denied for table record_attachments', false),
        (
          'PGRST205',
          "Could not find the table 'public.notes' in the schema cache",
          false,
        ),
        ('PGRST000', 'record_attachments temporarily unavailable', false),
      ]) {
        final api = client(
          (_) async => json({'message': failure.$2, 'code': failure.$1}, 400),
        );
        addTearDown(api.dispose);
        final deletion = RecordAttachmentsRepository(
          api,
        ).deleteForTarget(workspaceId: workspace, target: target);
        if (failure.$3) {
          await deletion;
        } else {
          await expectLater(deletion, throwsA(isA<PostgrestException>()));
        }
      }
    },
  );
}
