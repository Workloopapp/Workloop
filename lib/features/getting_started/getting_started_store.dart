import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef GettingStartedScope = ({String userId, String workspaceId});

class GettingStartedProgress {
  final int nextStep;
  final bool pendingIntroduction;
  final bool completed;

  const GettingStartedProgress({
    this.nextStep = 0,
    this.pendingIntroduction = false,
    this.completed = false,
  });

  factory GettingStartedProgress.fromJson(Map<String, dynamic> value) =>
      GettingStartedProgress(
        nextStep: ((value['nextStep'] as num?)?.toInt() ?? 0).clamp(0, 4),
        pendingIntroduction: value['pendingIntroduction'] == true,
        completed: value['completed'] == true,
      );

  Map<String, dynamic> toJson() => {
    'nextStep': nextStep,
    'pendingIntroduction': pendingIntroduction,
    'completed': completed,
  };
}

abstract class GettingStartedStore {
  Future<GettingStartedProgress> read(GettingStartedScope scope);
  Future<void> write(
    GettingStartedScope scope,
    GettingStartedProgress progress,
  );

  /// Called only after a new workspace was saved and the owner chooses to enter.
  Future<void> prepareIntroduction(GettingStartedScope scope) =>
      write(scope, const GettingStartedProgress(pendingIntroduction: true));
}

class LocalGettingStartedStore extends GettingStartedStore {
  final SharedPreferencesAsync _preferences;
  final Map<GettingStartedScope, GettingStartedProgress> _cached = {};
  Future<void> _pendingWrite = Future<void>.value();

  LocalGettingStartedStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  String _key(GettingStartedScope scope) =>
      'workloop.getting-started.v1.${scope.userId}.${scope.workspaceId}';

  @override
  Future<GettingStartedProgress> read(GettingStartedScope scope) async {
    if (_cached[scope] case final progress?) return progress;
    var stored = const GettingStartedProgress();
    try {
      final value = await _preferences.getString(_key(scope));
      if (value != null) {
        stored = GettingStartedProgress.fromJson(
          Map<String, dynamic>.from(jsonDecode(value) as Map),
        );
      }
    } catch (_) {
      // This optional guide must never block access to the real workspace.
    }
    return _cached.putIfAbsent(scope, () => stored);
  }

  @override
  Future<void> write(
    GettingStartedScope scope,
    GettingStartedProgress progress,
  ) {
    _cached[scope] = progress;
    final encoded = jsonEncode(progress.toJson());
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await _preferences.setString(_key(scope), encoded);
      } catch (_) {
        // Keep progress for this session if device preferences are unavailable.
      }
    });
    return _pendingWrite;
  }
}

final gettingStartedStoreProvider = Provider<GettingStartedStore>(
  (_) => LocalGettingStartedStore(),
);
