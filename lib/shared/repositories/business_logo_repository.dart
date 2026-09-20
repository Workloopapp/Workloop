import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/workflow_idempotency.dart';

import 'supabase_client_provider.dart';
import '../../core/supabase/supabase_config.dart';

const businessLogoMaxBytes = 2 * 1024 * 1024;

String businessLogoMimeType(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > businessLogoMaxBytes) {
    throw const FormatException('Choose a logo smaller than 2 MB.');
  }
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'image/jpeg';
  }
  throw const FormatException('Choose a PNG or JPEG logo.');
}

final businessLogoRepositoryProvider = Provider(
  (ref) => BusinessLogoRepository(ref.watch(supabaseClientProvider)),
);

class BusinessLogoRepository {
  final SupabaseClient _client;
  const BusinessLogoRepository(this._client);

  Future<String> upload(Uint8List bytes, {required String userId}) async {
    final mime = businessLogoMimeType(bytes);
    if (_client.auth.currentUser?.id != userId) {
      throw const AuthException('Your account changed. Try again.');
    }
    // Immutable object names preserve branding on already issued documents.
    final path =
        '$userId/${createPublicRequestToken()}.${mime == 'image/png' ? 'png' : 'jpg'}';
    await _client.storage
        .from('business-logos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, cacheControl: '31536000'),
        );
    if (_client.auth.currentUser?.id != userId) {
      throw const AuthException('Your account changed. Try again.');
    }
    return _client.storage.from('business-logos').getPublicUrl(path);
  }
}

/// Logos only load from this project's immutable public logo bucket.
bool isTrustedBusinessLogoUrl(
  String? value, {
  String baseUrl = SupabaseConfig.supabaseUrl,
}) {
  final uri = Uri.tryParse(value ?? '');
  final base = Uri.tryParse(baseUrl);
  if (uri == null ||
      base == null ||
      base.host.isEmpty ||
      uri.scheme != 'https' ||
      uri.origin != base.origin ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  return RegExp(
    r'^/storage/v1/object/public/business-logos/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}\.(png|jpg)$',
  ).hasMatch(uri.path);
}
