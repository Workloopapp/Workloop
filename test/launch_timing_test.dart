import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/main.dart';

void main() {
  test('launch timing adds no artificial wait', () {
    expect(
      remainingLaunchDuration(const Duration(milliseconds: 250)),
      Duration.zero,
    );
    expect(
      remainingLaunchDuration(const Duration(milliseconds: 700)),
      Duration.zero,
    );
    expect(
      remainingLaunchDuration(const Duration(milliseconds: 2000)),
      Duration.zero,
    );
  });
}
