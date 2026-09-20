import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const recordAttachmentMaxBytes = 10 * 1024 * 1024;
const recordAttachmentBucket = 'record-attachments';

enum AttachmentTargetType { booking, note, client }

class AttachmentTarget {
  final AttachmentTargetType type;
  final String id;

  const AttachmentTarget.booking(this.id) : type = AttachmentTargetType.booking;
  const AttachmentTarget.note(this.id) : type = AttachmentTargetType.note;
  const AttachmentTarget.client(this.id) : type = AttachmentTargetType.client;

  String get column => switch (type) {
    AttachmentTargetType.booking => 'appointment_id',
    AttachmentTargetType.note => 'note_id',
    AttachmentTargetType.client => 'contact_id',
  };

  @override
  bool operator ==(Object other) =>
      other is AttachmentTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

class RecordAttachment {
  final String id;
  final String workspaceId;
  final AttachmentTarget target;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String path;
  final DateTime createdAt;
  final String? contentHash;

  const RecordAttachment({
    required this.id,
    required this.workspaceId,
    required this.target,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.path,
    required this.createdAt,
    this.contentHash,
  });

  factory RecordAttachment.fromMap(Map<String, dynamic> row) {
    final target = row['appointment_id'] != null
        ? AttachmentTarget.booking(row['appointment_id'] as String)
        : row['note_id'] != null
        ? AttachmentTarget.note(row['note_id'] as String)
        : AttachmentTarget.client(row['contact_id'] as String);
    return RecordAttachment(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      target: target,
      fileName: row['file_name'] as String,
      mimeType: row['mime_type'] as String,
      sizeBytes: (row['size_bytes'] as num).toInt(),
      path: row['object_path'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      contentHash: row['content_hash'] as String?,
    );
  }

  bool get isImage => mimeType.startsWith('image/');
}

/// Checks the actual bytes before any metadata or Storage write. Plain text
/// must be explicitly named .txt and valid UTF-8; HTML/SVG are never rendered.
class RecordAttachmentFile {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String extension;
  final String contentHash;

  RecordAttachmentFile._({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.extension,
  }) : contentHash = sha256.convert(bytes).toString();

  factory RecordAttachmentFile.checked(String fileName, Uint8List bytes) {
    final name = fileName.trim();
    if (name.isEmpty ||
        name.length > 200 ||
        name.contains(RegExp(r'[/\\\x00-\x1f\x7f]'))) {
      throw const FormatException('Choose a file with a valid name.');
    }
    if (bytes.isEmpty || bytes.length > recordAttachmentMaxBytes) {
      throw const FormatException('Choose a file between 1 byte and 10 MB.');
    }
    bool starts(List<int> signature, [int offset = 0]) =>
        bytes.length >= signature.length + offset &&
        signature.indexed.every(
          (value) => bytes[value.$1 + offset] == value.$2,
        );
    late String mime;
    late String extension;
    if (starts([0xff, 0xd8, 0xff])) {
      mime = 'image/jpeg';
      extension = 'jpg';
    } else if (starts([137, 80, 78, 71, 13, 10, 26, 10])) {
      mime = 'image/png';
      extension = 'png';
    } else if (starts('RIFF'.codeUnits) && starts('WEBP'.codeUnits, 8)) {
      mime = 'image/webp';
      extension = 'webp';
    } else if (starts('%PDF-'.codeUnits)) {
      mime = 'application/pdf';
      extension = 'pdf';
    } else if (name.toLowerCase().endsWith('.txt')) {
      try {
        final text = utf8.decode(bytes, allowMalformed: false);
        if (text.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
          throw const FormatException();
        }
      } on FormatException {
        throw const FormatException('Choose a plain UTF-8 text document.');
      }
      mime = 'text/plain';
      extension = 'txt';
    } else {
      throw const FormatException(
        'Choose a JPEG, PNG, WebP, PDF or text file.',
      );
    }
    return RecordAttachmentFile._(
      fileName: name,
      mimeType: mime,
      bytes: Uint8List.fromList(bytes).asUnmodifiableView(),
      extension: extension,
    );
  }
}
