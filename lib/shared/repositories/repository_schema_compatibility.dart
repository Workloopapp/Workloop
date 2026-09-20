import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

const postgrestSchemaCompatibilityTtl = Duration(minutes: 5);

final _defaultPostgrestSchemaCompatibilityCache =
    PostgrestSchemaCompatibilityCache();

class PostgrestSchemaCompatibilityCache {
  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, _PostgrestSchemaObjectState> _objects = {};

  PostgrestSchemaCompatibilityCache({
    this.ttl = postgrestSchemaCompatibilityTtl,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  Future<T> load<T>({
    required String objectName,
    required Future<T> Function() loadCurrent,
    required Future<T> Function() loadLegacy,
  }) async {
    final key = objectName.trim().toLowerCase();
    final state = _objects.putIfAbsent(key, _PostgrestSchemaObjectState.new);
    final now = _now();

    if (state.expiresAt?.isAfter(now) ?? false) {
      return state.currentSchemaAvailable ? loadCurrent() : loadLegacy();
    }

    final inFlight = state.probe;
    if (inFlight != null) {
      final result = await inFlight;
      if (result.error case final error?) {
        Error.throwWithStackTrace(error, result.stackTrace!);
      }
      return result.currentSchemaAvailable! ? loadCurrent() : loadLegacy();
    }

    final probe = Completer<_PostgrestSchemaProbeResult>();
    state.probe = probe.future;
    try {
      final result = await loadCurrent();
      _settle(state, currentSchemaAvailable: true);
      probe.complete(const _PostgrestSchemaProbeResult.available(true));
      return result;
    } on PostgrestException catch (error, stackTrace) {
      if (!isMissingPostgrestSchemaObject(error, objectName)) {
        state.probe = null;
        probe.complete(_PostgrestSchemaProbeResult.error(error, stackTrace));
        rethrow;
      }
      _settle(state, currentSchemaAvailable: false);
      probe.complete(const _PostgrestSchemaProbeResult.available(false));
      return loadLegacy();
    } catch (error, stackTrace) {
      state.probe = null;
      probe.complete(_PostgrestSchemaProbeResult.error(error, stackTrace));
      rethrow;
    }
  }

  void clear() => _objects.clear();

  void _settle(
    _PostgrestSchemaObjectState state, {
    required bool currentSchemaAvailable,
  }) {
    state
      ..currentSchemaAvailable = currentSchemaAvailable
      ..expiresAt = _now().add(ttl)
      ..probe = null;
  }
}

class _PostgrestSchemaObjectState {
  bool currentSchemaAvailable = true;
  DateTime? expiresAt;
  Future<_PostgrestSchemaProbeResult>? probe;
}

class _PostgrestSchemaProbeResult {
  final bool? currentSchemaAvailable;
  final Object? error;
  final StackTrace? stackTrace;

  const _PostgrestSchemaProbeResult.available(this.currentSchemaAvailable)
    : error = null,
      stackTrace = null;

  const _PostgrestSchemaProbeResult.error(this.error, this.stackTrace)
    : currentSchemaAvailable = null;
}

/// True only when PostgREST reports that [objectName] is absent from its
/// schema/relationship cache. Permission, connectivity and query errors must
/// continue to surface rather than silently falling back.
bool isMissingPostgrestSchemaObject(
  PostgrestException error,
  String objectName,
) {
  final code = error.code?.toUpperCase();
  if (code != 'PGRST200' && code != 'PGRST205' && code != '42P01') {
    return false;
  }
  final description = [
    error.message,
    error.details?.toString() ?? '',
    error.hint?.toString() ?? '',
  ].join(' ').toLowerCase();
  return description.contains(objectName.toLowerCase());
}

Future<T> loadWithPostgrestSchemaFallback<T>({
  required String objectName,
  required Future<T> Function() loadCurrent,
  required Future<T> Function() loadLegacy,
  PostgrestSchemaCompatibilityCache? compatibilityCache,
}) => (compatibilityCache ?? _defaultPostgrestSchemaCompatibilityCache).load(
  objectName: objectName,
  loadCurrent: loadCurrent,
  loadLegacy: loadLegacy,
);
