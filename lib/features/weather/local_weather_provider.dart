import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/repositories/supabase_client_provider.dart';
import 'local_weather_repository.dart';

final weatherUserIdProvider = StreamProvider<String?>((ref) async* {
  // Isolated previews/tests may deliberately run without a configured backend.
  SupabaseClient client;
  try {
    client = ref.watch(supabaseClientProvider);
  } catch (_) {
    yield null;
    return;
  }
  yield client.auth.currentUser?.id;
  yield* client.auth.onAuthStateChange
      .map((event) => event.session?.user.id)
      .distinct();
});
final weatherLocationServiceProvider = Provider<WeatherLocationService>(
  (ref) => DeviceWeatherLocationService(),
);
final weatherPreferenceStoreProvider = Provider<WeatherPreferenceStore>(
  (ref) => LocalWeatherPreferenceStore(),
);
final localWeatherRepositoryProvider = Provider<LocalWeatherRepository>(
  (ref) => LocalWeatherRepository.supabase(ref.watch(supabaseClientProvider)),
);

class LocalWeatherState {
  final WeatherSelection selection;
  final LocalWeatherReading? reading;
  final String? message;
  final bool busy;
  const LocalWeatherState({
    this.selection = const WeatherSelection.off(),
    this.reading,
    this.message,
    this.busy = false,
  });
}

final localWeatherProvider = AsyncNotifierProvider.autoDispose
    .family<LocalWeatherNotifier, LocalWeatherState, String>(
      LocalWeatherNotifier.new,
    );

class LocalWeatherNotifier extends AsyncNotifier<LocalWeatherState> {
  LocalWeatherNotifier(this.userId);
  final String userId;
  int _generation = 0;
  WeatherArea? _deviceArea;
  DateTime? _locatedAt;

  @override
  Future<LocalWeatherState> build() async {
    final selection = await ref
        .read(weatherPreferenceStoreProvider)
        .read(userId);
    if (!ref.mounted) return const LocalWeatherState();
    return _load(selection);
  }

  Future<LocalWeatherState> _load(
    WeatherSelection selection, {
    bool requestPermission = false,
  }) async {
    if (!selection.enabled) return LocalWeatherState(selection: selection);
    try {
      if (selection.area != null &&
          DateTime.now().isAfter(selection.area!.expiresAt)) {
        await ref
            .read(weatherPreferenceStoreProvider)
            .write(userId, const WeatherSelection.off());
        return const LocalWeatherState(
          message:
              'Choose your weather area again to keep its location up to date.',
        );
      }
      var area = selection.area;
      if (selection.useDevice) {
        if (_deviceArea == null ||
            _locatedAt == null ||
            requestPermission ||
            DateTime.now().difference(_locatedAt!) >
                const Duration(minutes: 5)) {
          _deviceArea = await ref
              .read(weatherLocationServiceProvider)
              .current(requestPermission: requestPermission)
              .timeout(const Duration(seconds: 12));
          _locatedAt = DateTime.now();
        }
        area = _deviceArea;
      }
      if (!ref.mounted || area == null) {
        return LocalWeatherState(selection: selection);
      }
      final reading = await ref
          .read(localWeatherRepositoryProvider)
          .current(area);
      return LocalWeatherState(selection: selection, reading: reading);
    } on WeatherUnavailable catch (error) {
      return LocalWeatherState(selection: selection, message: error.message);
    } catch (_) {
      return LocalWeatherState(
        selection: selection,
        message:
            'Weather is unavailable right now. Your bookings and other work are unaffected.',
      );
    }
  }

  Future<void> refresh() async {
    final previous = state.asData?.value;
    if (previous == null || previous.busy || !previous.selection.enabled) {
      return;
    }
    final generation = ++_generation;
    state = AsyncData(
      LocalWeatherState(
        selection: previous.selection,
        reading: previous.reading,
        busy: true,
      ),
    );
    final next = await _load(previous.selection);
    if (ref.mounted && generation == _generation) state = AsyncData(next);
  }

  Future<void> select(WeatherSelection selection) async {
    final generation = ++_generation;
    // Clear the previous area immediately; its weather must never label a new area.
    state = AsyncData(LocalWeatherState(selection: selection, busy: true));
    try {
      await ref.read(weatherPreferenceStoreProvider).write(userId, selection);
      if (!ref.mounted || generation != _generation) return;
      final next = await _load(
        selection,
        requestPermission: selection.useDevice,
      );
      if (ref.mounted && generation == _generation) state = AsyncData(next);
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = AsyncData(
          LocalWeatherState(
            selection: selection,
            message: 'Could not save the weather preference. Try again.',
          ),
        );
      }
    }
  }
}
