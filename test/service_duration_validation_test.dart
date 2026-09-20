import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/repositories/services_repository.dart';

void main() {
  test('service duration accepts the product boundaries', () {
    expect(() => validateServiceDurationMinutes(5), returnsNormally);
    expect(() => validateServiceDurationMinutes(1440), returnsNormally);
  });

  test('service duration rejects impossible public values', () {
    for (final duration in const [0, 1, 1441, 9999999]) {
      expect(
        () => validateServiceDurationMinutes(duration),
        throwsArgumentError,
        reason: '$duration minutes must never reach Supabase',
      );
    }
  });
}
