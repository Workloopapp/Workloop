import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/repositories/business_logo_repository.dart';

void main() {
  test('workspace and restored onboarding draft retain optional logo', () {
    const url =
        'https://example.supabase.co/storage/v1/object/public/business-logos/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222.png';
    expect(
      Workspace.fromMap({
        'id': 'workspace',
        'name': 'Business',
        'logo_url': url,
      }).toMap()['logo_url'],
      url,
    );
    final draft = OnboardingState.fromJson(
      const OnboardingState(logoUrl: url).toJson(),
    );
    expect(draft.copyWith(businessName: 'Updated').logoUrl, url);
    expect(draft.copyWith(logoUrl: '').logoUrl, isEmpty);
    expect(OnboardingState.fromJson({}).logoUrl, isEmpty);
  });

  test('logo upload rejects empty, oversized and unsupported bytes', () {
    expect(() => businessLogoMimeType(Uint8List(0)), throwsFormatException);
    expect(
      () => businessLogoMimeType(Uint8List(businessLogoMaxBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => businessLogoMimeType(Uint8List.fromList('<svg/>'.codeUnits)),
      throwsFormatException,
    );
    expect(
      businessLogoMimeType(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
      'image/png',
    );
    expect(
      businessLogoMimeType(Uint8List.fromList([255, 216, 255])),
      'image/jpeg',
    );
  });

  test(
    'logo loads only project immutable objects, never external or private URLs',
    () {
      const base = 'https://example.supabase.co';
      const path =
          '/storage/v1/object/public/business-logos/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222.png';
      expect(isTrustedBusinessLogoUrl('$base$path', baseUrl: base), isTrue);
      for (final invalid in [
        'https://evil.test$path',
        '$base$path?token=secret',
        'http://example.supabase.co$path',
        '$base/storage/v1/object/public/expense-receipts/private.png',
        '$base$path#fragment',
        'https://user@example.supabase.co$path',
      ]) {
        expect(
          isTrustedBusinessLogoUrl(invalid, baseUrl: base),
          isFalse,
          reason: invalid,
        );
      }
    },
  );
}
