import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/finance/payment_collection_sheet.dart';

void main() {
  test('refund amounts parse exact pennies without rounding', () {
    expect(parseRefundAmountMinor('12.34', 2000), 1234);
    expect(parseRefundAmountMinor(' 0.01 ', 2000), 1);
    expect(parseRefundAmountMinor('12.3', 2000), 1230);
    expect(parseRefundAmountMinor('20', 2000), 2000);
  });
  test(
    'invalid and excessive refunds do not crash or silently change amount',
    () {
      for (final input in [
        'NaN',
        'Infinity',
        '-Infinity',
        '1e2',
        '-1',
        '0',
        '',
        '12.345',
        '20.01',
        '999999999999999999999999',
      ]) {
        expect(parseRefundAmountMinor(input, 2000), isNull, reason: input);
      }
    },
  );
}
