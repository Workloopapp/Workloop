import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WorkloopAppearance { system, light, dark }

extension WorkloopAppearancePresentation on WorkloopAppearance {
  String get label => switch (this) {
    WorkloopAppearance.system => 'System',
    WorkloopAppearance.light => 'Light',
    WorkloopAppearance.dark => 'Dark',
  };

  String get description => switch (this) {
    WorkloopAppearance.system => 'Follow your phone automatically',
    WorkloopAppearance.light => 'Warm paper with dark text',
    WorkloopAppearance.dark => 'Deep charcoal with warm, light text',
  };

  ThemeMode get themeMode => switch (this) {
    WorkloopAppearance.system => ThemeMode.system,
    WorkloopAppearance.light => ThemeMode.light,
    WorkloopAppearance.dark => ThemeMode.dark,
  };
}

final themeModeStoreProvider = Provider<ThemeModeStore>(
  (_) => SharedPreferencesThemeModeStore(),
);

final workloopAppearanceProvider =
    AsyncNotifierProvider<WorkloopAppearanceNotifier, WorkloopAppearance>(
      WorkloopAppearanceNotifier.new,
    );

abstract class ThemeModeStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

class WorkloopAppearanceNotifier extends AsyncNotifier<WorkloopAppearance> {
  static const storageKey = 'workloop.appearance';

  @override
  Future<WorkloopAppearance> build() async {
    String? stored;
    try {
      stored = await ref.read(themeModeStoreProvider).read(storageKey);
    } catch (_) {
      return WorkloopAppearance.system;
    }
    return WorkloopAppearance.values.firstWhere(
      (appearance) => appearance.name == stored,
      orElse: () => WorkloopAppearance.system,
    );
  }

  Future<void> setAppearance(WorkloopAppearance appearance) async {
    final previous = state;
    state = AsyncData(appearance);
    try {
      await ref.read(themeModeStoreProvider).write(storageKey, appearance.name);
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
