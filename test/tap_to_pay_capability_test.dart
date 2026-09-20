import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/workloop_capabilities.dart';
import 'package:workloop/shared/payments/tap_to_pay_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native collection stays disabled even when the phone supports NFC',
    () async {
      var nativeCalls = 0;
      const channel = MethodChannel('com.ismaeel.workloop/payments');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls++;
            return {'supported': true};
          });
      final service = TapToPayService();
      expect((await service.availability()).supported, isFalse);
      await expectLater(
        service.collect(
          clientSecret: 'pi_test_secret',
          locationId: 'tml_test',
          connectionTokenLoader: () async => 'pst_test',
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'tap_to_pay_disabled',
          ),
        ),
      );
      expect(nativeCalls, 0);
    },
    skip: WorkloopCapabilities.tapToPayEnabled,
  );
}
