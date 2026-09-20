import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/shared/diagnostics/crash_reporter.dart';

class _Sink implements CrashReportSink {
  final enabled = <bool>[];
  final records = <({String category, String stack, bool fatal})>[];
  int deleted = 0;
  bool failConfigure = false;
  bool failRecord = false;

  @override
  Future<void> setCollectionEnabled(bool value) async {
    if (failConfigure) throw StateError('private provider details');
    enabled.add(value);
  }

  @override
  Future<void> deleteUnsentReports() async => deleted++;

  @override
  Future<void> record(
    String category,
    StackTrace stack, {
    required bool fatal,
  }) async {
    if (failRecord) throw StateError('private transport details');
    records.add((category: category, stack: stack.toString(), fatal: fatal));
  }
}

class _PrivateError {
  @override
  String toString() => throw StateError('Must never inspect original error');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final codeStack = StackTrace.fromString(
    '#0 SaveFlow.save (package:workloop/features/example.dart:42:7)',
  );

  test(
    'debug build cannot enable crash reporting through a production define',
    () {
      expect(kDebugMode, isTrue);
      expect(workloopCrashReportingEnabled, isFalse);
    },
  );

  test('only fixed error categories leave Dart, including plugin errors', () {
    expect(
      safeCrashCategory(StateError('client@example.invalid')),
      'Workloop unhandled StateError',
    );
    expect(
      safeCrashCategory(
        PlatformException(
          code: 'secret',
          message: 'client',
          details: {'token': 'private'},
        ),
      ),
      'Workloop unhandled PlatformException',
    );
    expect(
      safeCrashCategory(_PrivateError()),
      'Workloop unhandled UnhandledError',
    );
    expect(
      safeCrashCategory(FlutterError('private'), framework: true),
      'Workloop framework FlutterError',
    );
    expect(
      safeCrashCategory(RangeError('private')),
      'Workloop unhandled RangeError',
    );
  });

  test(
    'keeps static package code and SDK frames but removes private content',
    () {
      final safe = sanitizeCrashStack(
        StackTrace.fromString('''
#0 SaveFlow.save (package:workloop/features/example.dart:42:7)
#1 Future._propagateToListeners (dart:async/future_impl.dart:3:4)
#2 main (file:///Users/customer/private.dart:1:1)
#3 request (https://api.invalid/private?token=secret:1:1)
#4 details (package:workloop/private.dart?client=secret:1:1)
client@example.invalid £50 Bearer private-token
'''),
      ).toString();
      expect(safe, contains('SaveFlow.save'));
      expect(safe, contains('dart:async/future_impl.dart'));
      for (final private in [
        'Users',
        'customer',
        'https',
        'secret',
        'Bearer',
        '£50',
      ]) {
        expect(safe, isNot(contains(private)));
      }
    },
  );

  test(
    'preserves AOT symbol addresses and build ID needed for symbolication',
    () {
      final safe = sanitizeCrashStack(
        StackTrace.fromString('''
build_id: '8deece9b0e5bf1aa541b5a91e171282e'
#00 abs 0000000100ad20 virt 00000000ad20 _kDartIsolateSnapshotInstructions+0x123
#01 abs 0000000100bd20 virt 00000000bd20
#02 abs 0000000100bd20 private-customer@example.invalid
loading_unit: private path with tokens
'''),
      ).toString();
      expect(safe, contains("build_id: '8deece9b0e5bf1aa541b5a91e171282e'"));
      expect(safe, contains('_kDartIsolateSnapshotInstructions+0x123'));
      expect(safe, contains('#01 abs'));
      expect(safe, isNot(contains('private')));
      expect(safe, isNot(contains('loading_unit')));
    },
  );

  test(
    'missing and unrecognized traces stay nonempty without fabricated frames',
    () {
      expect(sanitizeCrashStack(null).toString(), '<stack unavailable>');
      expect(
        sanitizeCrashStack(
          StackTrace.fromString('customer private text'),
        ).toString(),
        '<stack unavailable>',
      );
    },
  );

  test('stack frame payload is bounded', () {
    final trace = List.generate(
      100,
      (i) => '#$i Flow.run (package:workloop/code.dart:$i:1)',
    ).join('\n');
    expect(
      sanitizeCrashStack(StackTrace.fromString(trace)).toString().split('\n'),
      hasLength(48),
    );
  });

  test(
    'unavailable Firebase never touches a native reporting plugin',
    () async {
      final sink = _Sink();
      final reporter = WorkloopCrashReporter(sink);
      expect(
        await reporter.initialize(
          firebaseReady: Future.value(false),
          enabled: true,
        ),
        isFalse,
      );
      await reporter.record(StateError('private'), codeStack);
      expect(sink.enabled, isEmpty);
      expect(sink.records, isEmpty);
    },
  );

  test(
    'disabled build disables collection and clears unsent reports',
    () async {
      final sink = _Sink();
      final reporter = WorkloopCrashReporter(sink);
      expect(
        await reporter.initialize(
          firebaseReady: Future.value(true),
          enabled: false,
        ),
        isFalse,
      );
      await reporter.record(StateError('private'), codeStack);
      expect(sink.enabled, [false]);
      expect(sink.deleted, 1);
      expect(sink.records, isEmpty);
    },
  );

  test('enabled build preserves native previous-launch reports', () async {
    final sink = _Sink();
    final reporter = WorkloopCrashReporter(sink);
    expect(
      await reporter.initialize(
        firebaseReady: Future.value(true),
        enabled: true,
      ),
      isTrue,
    );
    await reporter.record(StateError('client@example.invalid'), codeStack);
    expect(sink.enabled, [true]);
    expect(sink.deleted, 0);
    expect(sink.records.single.category, 'Workloop unhandled StateError');
    expect(sink.records.single.stack, codeStack.toString());
    expect(sink.records.single.fatal, isTrue);
  });

  test(
    'an early failure waits for Firebase without blocking app startup',
    () async {
      final sink = _Sink();
      final reporter = WorkloopCrashReporter(sink);
      final firebase = Completer<bool>();
      final ready = reporter.initialize(
        firebaseReady: firebase.future,
        enabled: true,
      );
      final report = reporter.record(_PrivateError(), codeStack);
      expect(sink.records, isEmpty);
      firebase.complete(true);
      await ready;
      await report;
      expect(sink.records.single.category, 'Workloop unhandled UnhandledError');
    },
  );

  test(
    'configuration errors are contained and not recursively reported',
    () async {
      final sink = _Sink()..failConfigure = true;
      final reporter = WorkloopCrashReporter(sink);
      expect(
        await reporter.initialize(
          firebaseReady: Future.value(true),
          enabled: true,
        ),
        isFalse,
      );
      await reporter.record(StateError('private'), codeStack);
      expect(sink.records, isEmpty);
    },
  );

  test('transport failures never escape the reporting handler', () async {
    final sink = _Sink()..failRecord = true;
    final reporter = WorkloopCrashReporter(sink);
    await reporter.initialize(firebaseReady: Future.value(true), enabled: true);
    await expectLater(
      reporter.record(StateError('private'), codeStack),
      completes,
    );
  });

  test(
    'same source error deduplicates regardless of private message contents',
    () async {
      final sink = _Sink();
      final reporter = WorkloopCrashReporter(sink);
      await reporter.initialize(
        firebaseReady: Future.value(true),
        enabled: true,
      );
      await reporter.record(StateError('customer A'), codeStack);
      await reporter.record(StateError('customer B'), codeStack);
      expect(sink.records, hasLength(1));
    },
  );

  test(
    'error storm is bounded without dropping the first distinct failures',
    () async {
      final sink = _Sink();
      final reporter = WorkloopCrashReporter(sink);
      await reporter.initialize(
        firebaseReady: Future.value(true),
        enabled: true,
      );
      for (var i = 0; i < 30; i++) {
        await reporter.record(
          StateError('private'),
          StackTrace.fromString(
            '#0 Flow.run (package:workloop/code.dart:$i:1)',
          ),
        );
      }
      expect(sink.records, hasLength(20));
    },
  );

  test(
    'framework handler preserves presentation without reading diagnostic context',
    () async {
      final old = FlutterError.onError;
      final oldPlatform = PlatformDispatcher.instance.onError;
      final presented = <FlutterErrorDetails>[];
      FlutterError.onError = presented.add;
      final sink = _Sink();
      final reporter = WorkloopCrashReporter(sink);
      addTearDown(() {
        reporter.removeHandlers();
        FlutterError.onError = old;
        PlatformDispatcher.instance.onError = oldPlatform;
      });
      await reporter.initialize(
        firebaseReady: Future.value(true),
        enabled: true,
      );
      reporter.installHandlers();
      final details = FlutterErrorDetails(
        exception: FlutterError('private customer details'),
        stack: codeStack,
        informationCollector: () => throw StateError('must not read'),
      );
      FlutterError.onError!(details);
      await Future<void>.delayed(Duration.zero);
      expect(presented, [details]);
      expect(sink.records.single.category, 'Workloop framework FlutterError');
    },
  );

  test(
    'platform handler preserves previous result and idempotent hook teardown',
    () async {
      final oldFlutter = FlutterError.onError;
      final oldPlatform = PlatformDispatcher.instance.onError;
      var previousCalls = 0;
      bool previous(Object _, StackTrace _) {
        previousCalls++;
        return true;
      }

      PlatformDispatcher.instance.onError = previous;
      final sink = _Sink();
      final reporter = WorkloopCrashReporter(sink);
      addTearDown(() {
        reporter.removeHandlers();
        FlutterError.onError = oldFlutter;
        PlatformDispatcher.instance.onError = oldPlatform;
      });
      await reporter.initialize(
        firebaseReady: Future.value(true),
        enabled: true,
      );
      reporter.installHandlers();
      reporter.installHandlers();
      expect(
        PlatformDispatcher.instance.onError!(StateError('private'), codeStack),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(previousCalls, 1);
      expect(sink.records, hasLength(1));
      reporter.removeHandlers();
      expect(PlatformDispatcher.instance.onError, same(previous));
    },
  );
}
