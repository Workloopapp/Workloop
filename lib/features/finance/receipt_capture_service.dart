import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'expense_records_repository.dart';

enum ReceiptCaptureSource { camera, photos, file }

class ReceiptCaptureException implements Exception {
  final String message;
  const ReceiptCaptureException(this.message);
}

final receiptCaptureServiceProvider = Provider(
  (ref) => ReceiptCaptureService(),
);

class ReceiptCaptureService {
  final ImagePicker picker;
  ReceiptCaptureService({ImagePicker? picker})
    : picker = picker ?? ImagePicker();

  /// A killed Android activity has lost its expense/account context. Never
  /// attach cached native results to whichever business opens next.
  Future<bool> discardUnscopedRecovery() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final lost = await picker.retrieveLostData();
    return !lost.isEmpty;
  }

  Future<ReceiptFile?> pick(ReceiptCaptureSource source) async {
    assert(source != ReceiptCaptureSource.file);
    try {
      final photo = await picker.pickImage(
        source: source == ReceiptCaptureSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
        // PHPicker selects individual photos; do not request broad library
        // metadata access just to attach a receipt.
        requestFullMetadata: false,
      );
      if (photo == null) return null;
      if (await photo.length() > receiptMaxBytes) {
        throw const ReceiptCaptureException(
          'This photo is over 10 MB. Crop to the receipt or choose a smaller photo, then try again.',
        );
      }
      final bytes = await photo.readAsBytes();
      ReceiptFile checked;
      try {
        checked = ReceiptFile.checked('receipt-photo', bytes);
      } on FormatException {
        throw const ReceiptCaptureException(
          'The photo could not be saved as JPEG or PNG. HEIC photos need a compatible copy: try Take photo, or export a JPEG and choose it from Files.',
        );
      }
      final extension = checked.mimeType == 'image/png' ? 'png' : 'jpg';
      if (!checked.mimeType.startsWith('image/')) {
        throw const ReceiptCaptureException(
          'Choose a receipt photo. Use Choose file for a PDF.',
        );
      }
      // Native image pickers may convert HEIC or resize a photo. A neutral
      // extension matched to the bytes avoids claiming original-file fidelity.
      return ReceiptFile(
        name: 'Receipt photo.$extension',
        mimeType: checked.mimeType,
        bytes: checked.bytes,
      );
    } on PlatformException catch (error) {
      final camera = source == ReceiptCaptureSource.camera;
      if (error.code.contains('restricted')) {
        throw ReceiptCaptureException(
          '${camera ? 'Camera' : 'Photo'} access is restricted on this device. Choose a file instead, or check the device restrictions.',
        );
      }
      if (error.code.contains('denied') || error.code.contains('access')) {
        throw ReceiptCaptureException(
          'Allow ${camera ? 'Camera' : 'Photos'} for Workloop in your phone Settings, then return and try again. You can also choose a file.',
        );
      }
      if (error.code == 'already_active') {
        throw const ReceiptCaptureException(
          'Finish the open photo picker, then try again.',
        );
      }
      throw ReceiptCaptureException(
        camera
            ? 'The camera is unavailable here. Use your phone directly, choose a photo, or choose a file.'
            : 'The photo library could not open. Try again or choose a file.',
      );
    }
  }
}
