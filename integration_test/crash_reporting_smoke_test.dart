// Explicit device-only verification. This is never imported by the app, never
// sends during normal integration discovery: profile mode and explicit reporting
// are both required. Debug/release runs skip it. No account signs in.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:workloop/shared/diagnostics/crash_reporter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'send one sanitized Workloop crash-report verification',
    (tester) async {
      expect(
        kProfileMode,
        isTrue,
        reason: 'Use a dedicated profile device build.',
      );
      expect(
        workloopCrashReportingEnabled,
        isTrue,
        reason: 'Enable reporting explicitly for this diagnostic build.',
      );
      await Firebase.initializeApp();
      final reporter = WorkloopCrashReporter(FirebaseCrashReportSink());
      expect(
        await reporter.initialize(
          firebaseReady: Future.value(true),
          enabled: workloopCrashReportingEnabled,
        ),
        isTrue,
      );
      await reporter.record(
        StateError('Workloop diagnostic verification'),
        StackTrace.current,
      );
      // SDK acceptance is not proof of server delivery/symbolication. Check the
      // intended Firebase iOS app for this build and stack before claiming success.
    },
    skip: !kProfileMode || !workloopCrashReportingEnabled,
  );
}
