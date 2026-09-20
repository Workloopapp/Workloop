import 'dart:async';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Local/debug builds do not send diagnostics. Profile builds may explicitly
/// enable the same production path for device verification, without a test flag.
const workloopCrashReportingEnabled =
    !kDebugMode && bool.fromEnvironment('WORKLOOP_CRASH_REPORTING_ENABLED');

abstract interface class CrashReportSink {
  Future<void> setCollectionEnabled(bool enabled);
  Future<void> deleteUnsentReports();
  Future<void> record(String category, StackTrace stack, {required bool fatal});
}

class FirebaseCrashReportSink implements CrashReportSink {
  @override
  Future<void> setCollectionEnabled(bool enabled) =>
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);

  @override
  Future<void> deleteUnsentReports() =>
      FirebaseCrashlytics.instance.deleteUnsentReports();

  @override
  Future<void> record(
    String category,
    StackTrace stack, {
    required bool fatal,
  }) => FirebaseCrashlytics.instance.recordError(
    category,
    stack,
    fatal: fatal,
    printDetails: false,
  );
}

/// No exception messages, Flutter context, information collectors, request data,
/// custom logs, user identifiers or activity breadcrumbs cross this boundary.
/// Native Crashlytics reports remain governed by the native SDK's data policy.
class WorkloopCrashReporter {
  WorkloopCrashReporter(this._sink);

  final CrashReportSink _sink;
  Future<bool>? _ready;
  final Set<String> _reported = {};
  FlutterExceptionHandler? _previousFlutterHandler;
  ErrorCallback? _previousPlatformHandler;
  FlutterExceptionHandler? _flutterHandler;
  ErrorCallback? _platformHandler;

  Future<bool> initialize({
    required Future<bool> firebaseReady,
    required bool enabled,
  }) => _ready ??= _configure(firebaseReady, enabled);

  Future<bool> _configure(Future<bool> firebaseReady, bool enabled) async {
    try {
      if (!await firebaseReady.timeout(const Duration(seconds: 5))) {
        return false;
      }
      await _sink
          .setCollectionEnabled(enabled)
          .timeout(const Duration(seconds: 3));
      if (!enabled) {
        // Do not carry local/debug failures into a later enabled build.
        await _sink.deleteUnsentReports().timeout(const Duration(seconds: 3));
      }
      return enabled;
    } catch (_) {
      // Reporting availability must not block sign-in or become another report.
      return false;
    }
  }

  void installHandlers() {
    if (_flutterHandler != null) return;
    _previousFlutterHandler = FlutterError.onError;
    _previousPlatformHandler = PlatformDispatcher.instance.onError;
    _flutterHandler = (details) {
      unawaited(record(details.exception, details.stack, framework: true));
      (_previousFlutterHandler ?? FlutterError.presentError)(details);
    };
    _platformHandler = (error, stack) {
      unawaited(record(error, stack));
      // Keep the platform's normal unhandled-error behavior. A report is not a
      // recovery and must not silently hide a broken operation.
      return _previousPlatformHandler?.call(error, stack) ?? false;
    };
    FlutterError.onError = _flutterHandler;
    PlatformDispatcher.instance.onError = _platformHandler;
  }

  /// Idempotent teardown also avoids removing a subsequently installed handler.
  void removeHandlers() {
    if (identical(FlutterError.onError, _flutterHandler)) {
      FlutterError.onError = _previousFlutterHandler;
    }
    if (identical(PlatformDispatcher.instance.onError, _platformHandler)) {
      PlatformDispatcher.instance.onError = _previousPlatformHandler;
    }
    _flutterHandler = null;
    _platformHandler = null;
  }

  Future<void> record(
    Object error,
    StackTrace? stack, {
    bool framework = false,
  }) {
    // Sanitize before awaiting so raw customer-bearing exceptions are never
    // retained by our initialization queue or handed to a provider.
    final category = safeCrashCategory(error, framework: framework);
    final safeStack = sanitizeCrashStack(stack);
    return _recordSanitized(category, safeStack);
  }

  Future<void> _recordSanitized(String category, StackTrace safeStack) async {
    final fingerprint = '$category\n$safeStack';
    if (_reported.length >= 20 || !_reported.add(fingerprint)) return;
    try {
      if (!await (_ready ?? Future.value(false))) return;
      await _sink
          .record(category, safeStack, fatal: true)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Never recursively report transport/plugin failures or print their data.
    }
  }
}

String safeCrashCategory(Object error, {bool framework = false}) {
  final String kind;
  if (error is FlutterError) {
    kind = 'FlutterError';
  } else if (error is RangeError) {
    kind = 'RangeError';
  } else if (error is ArgumentError) {
    kind = 'ArgumentError';
  } else if (error is StateError) {
    kind = 'StateError';
  } else if (error is TypeError) {
    kind = 'TypeError';
  } else if (error is FormatException) {
    kind = 'FormatException';
  } else if (error is TimeoutException) {
    kind = 'TimeoutException';
  } else if (error is PlatformException) {
    kind = 'PlatformException';
  } else {
    kind = 'UnhandledError';
  }
  return 'Workloop ${framework ? 'framework' : 'unhandled'} $kind';
}

final _dartCodeFrame = RegExp(
  r'^#\d+\s+[A-Za-z0-9_.$<> ,:=\[\]-]+\s+\((?:package:[a-z][a-z0-9_]*/[A-Za-z0-9_./-]+\.dart|dart:[a-z_][a-z0-9_./-]*):\d+(?::\d+)?\)$',
);
final _nativeDartFrame = RegExp(
  r'^#\d+ abs [a-fA-F0-9]+(?: virt [a-fA-F0-9]+)?(?: (?:_kDart(?:Isolate|Vm)SnapshotInstructions|_kDart(?:Isolate|Vm)SnapshotData)\+0x[a-fA-F0-9]+)?$',
);
final _buildId = RegExp(r"^build_id: '[a-fA-F0-9]{8,128}'$");

StackTrace sanitizeCrashStack(StackTrace? stack) {
  final frames = <String>[];
  // Real VM stack frames contain static code paths, never error descriptions.
  // Reject absolute paths, HTTP URLs, arbitrary text and unrecognized metadata.
  for (final raw in (stack?.toString() ?? '').split('\n').take(200)) {
    final line = raw.trim();
    if (line.length > 500) continue;
    if (_dartCodeFrame.hasMatch(line) ||
        _nativeDartFrame.hasMatch(line) ||
        _buildId.hasMatch(line)) {
      frames.add(line);
      if (frames.length >= 48) break;
    }
  }
  // Keep this nonempty: Crashlytics replaces an empty trace with its own current
  // stack, which would incorrectly point to this reporter instead of the failure.
  return StackTrace.fromString(
    frames.isEmpty ? '<stack unavailable>' : frames.join('\n'),
  );
}
