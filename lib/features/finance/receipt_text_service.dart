import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/repositories/auth_repository.dart';
import 'expense_records_repository.dart';

class ReceiptRecognizedText {
  final String text;
  final int pageCount;
  final int processedPages;
  final bool textTruncated;
  const ReceiptRecognizedText({
    required this.text,
    this.pageCount = 1,
    this.processedPages = 1,
    this.textTruncated = false,
  });
  bool get isPartial => processedPages < pageCount || textTruncated;
}

class ReceiptRecognitionException implements Exception {
  final String message;
  const ReceiptRecognitionException(this.message);
}

final receiptTextServiceProvider = Provider((ref) => ReceiptTextService());

/// Scoped to the receipt workflow so a review cannot outlive its signed-in user.
final receiptAuthIdentityProvider = StreamProvider.autoDispose<String?>((
  ref,
) async* {
  final auth = ref.watch(authRepositoryProvider);
  yield auth.currentUserId;
  yield* auth.authChanges.map((event) => event.session?.user.id);
});

class ReceiptTextService {
  static const _channel = MethodChannel('workloop/receipt_text');

  Future<ReceiptRecognizedText> recognize(ReceiptFile file) async {
    if (file.bytes.isEmpty ||
        file.bytes.length > receiptMaxBytes ||
        !const [
          'image/jpeg',
          'image/png',
          'application/pdf',
        ].contains(file.mimeType)) {
      throw const ReceiptRecognitionException(
        'Choose a JPEG, PNG or PDF receipt up to 10 MB.',
      );
    }
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'recognize',
        {'bytes': file.bytes, 'mimeType': file.mimeType},
      );
      final text = (response?['text'] as String? ?? '').trim();
      if (text.isEmpty) {
        throw const ReceiptRecognitionException(
          'No readable text was found. Try a clearer photo or enter the expense details yourself.',
        );
      }
      return ReceiptRecognizedText(
        text: text.length > 100000 ? text.substring(0, 100000) : text,
        textTruncated:
            response?['textTruncated'] == true || text.length > 100000,
        pageCount: (response?['pageCount'] as num?)?.toInt() ?? 1,
        processedPages: (response?['processedPages'] as num?)?.toInt() ?? 1,
      );
    } on MissingPluginException {
      throw const ReceiptRecognitionException(
        'Receipt reading is unavailable on this device. Your receipt is attached; enter the details yourself.',
      );
    } on PlatformException catch (error) {
      throw ReceiptRecognitionException(switch (error.code) {
        'receipt_locked' =>
          'This PDF is password protected. Attach an unlocked copy or enter the expense details yourself.',
        'invalid_receipt' || 'receipt_unreadable' =>
          'This receipt could not be read. Try a clearer photo or enter the details yourself.',
        _ =>
          'Receipt reading could not finish. Try again or enter the expense details yourself.',
      });
    }
  }
}
