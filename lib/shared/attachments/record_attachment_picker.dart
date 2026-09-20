import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'record_attachment.dart';

enum RecordAttachmentSource { camera, photos, file }

final recordAttachmentPickerProvider = Provider(
  (ref) => RecordAttachmentPicker(),
);

class RecordAttachmentPicker {
  final ImagePicker images;
  RecordAttachmentPicker({ImagePicker? images})
    : images = images ?? ImagePicker();

  /// A restarted Android picker no longer has a trusted record/account target.
  Future<bool> discardUnscopedRecovery() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return !(await images.retrieveLostData()).isEmpty;
  }

  Future<RecordAttachmentFile?> pick(RecordAttachmentSource source) async {
    try {
      XFile? file;
      if (source == RecordAttachmentSource.file) {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt'],
          withData: false,
        );
        if (result == null || result.files.isEmpty) return null;
        file = result.xFiles.single;
      } else {
        file = await images.pickImage(
          source: source == RecordAttachmentSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 4096,
          maxHeight: 4096,
          imageQuality: 95,
          requestFullMetadata: false,
        );
      }
      if (file == null) return null;
      if (await file.length() > recordAttachmentMaxBytes) {
        throw const FormatException('Choose a file up to 10 MB.');
      }
      final bytes = await file.readAsBytes();
      if (source == RecordAttachmentSource.file) {
        return RecordAttachmentFile.checked(file.name, bytes);
      }
      // Native pickers can resize or convert photos. Match the saved extension
      // to the resulting bytes rather than retaining a misleading HEIC name.
      final checked = RecordAttachmentFile.checked('Photo.jpg', bytes);
      if (!checked.mimeType.startsWith('image/')) {
        throw const FormatException(
          'Choose a photo, or use Files for a document.',
        );
      }
      final extension = switch (checked.mimeType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
      return RecordAttachmentFile.checked('Photo.$extension', bytes);
    } on PlatformException catch (error) {
      if (error.code.contains('denied') || error.code.contains('access')) {
        throw const FormatException(
          'Allow camera or photo access for Workloop in your phone Settings, then try again. You can also choose a file.',
        );
      }
      if (error.code == 'already_active') {
        throw const FormatException('Finish the open picker, then try again.');
      }
      throw const FormatException(
        'Could not open the camera or file picker. Try on your phone, or choose a different source.',
      );
    }
  }
}
