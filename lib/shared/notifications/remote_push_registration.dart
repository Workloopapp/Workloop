import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Registration confirms server acceptance of this device's token. It is not
/// evidence that APNs/FCM delivered a notification to the device.
enum RemotePushRegistrationStatus {
  idle,
  registering,
  registered,
  retrying,
  failed,
}

final remotePushRegistrationStatusProvider =
    NotifierProvider<
      RemotePushRegistrationNotifier,
      RemotePushRegistrationStatus
    >(RemotePushRegistrationNotifier.new);

class RemotePushRegistrationNotifier
    extends Notifier<RemotePushRegistrationStatus> {
  @override
  RemotePushRegistrationStatus build() => RemotePushRegistrationStatus.idle;

  void update(RemotePushRegistrationStatus value) => state = value;
}
