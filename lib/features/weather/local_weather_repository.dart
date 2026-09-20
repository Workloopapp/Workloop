import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  rain,
  snow,
  fog,
  thunder,
  unknown,
}

WeatherCondition weatherCondition(String symbol) {
  if (symbol.contains('thunder')) return WeatherCondition.thunder;
  if (symbol.contains('snow') || symbol.contains('sleet')) {
    return WeatherCondition.snow;
  }
  if (symbol.contains('rain')) return WeatherCondition.rain;
  if (symbol.startsWith('clearsky')) return WeatherCondition.clear;
  if (symbol.startsWith('fair') || symbol.startsWith('partlycloudy')) {
    return WeatherCondition.partlyCloudy;
  }
  if (symbol.startsWith('cloudy')) return WeatherCondition.cloudy;
  if (symbol.startsWith('fog')) return WeatherCondition.fog;
  return WeatherCondition.unknown;
}

class WeatherArea {
  final double latitude;
  final double longitude;
  final String label;
  final DateTime expiresAt;
  WeatherArea(
    double latitude,
    double longitude,
    this.label, {
    DateTime? expiresAt,
  }) : latitude = double.parse(latitude.toStringAsFixed(2)),
       expiresAt =
           expiresAt ?? DateTime.now().toUtc().add(const Duration(days: 29)),
       longitude = double.parse(longitude.toStringAsFixed(2)) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const FormatException('Invalid weather area');
    }
  }
  String get key => '$latitude,$longitude';
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'label': label,
    'expiresAt': expiresAt.toIso8601String(),
  };
  factory WeatherArea.fromJson(Map<String, dynamic> json) => WeatherArea(
    (json['latitude'] as num).toDouble(),
    (json['longitude'] as num).toDouble(),
    json['label'] as String,
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
  );
}

class WeatherSelection {
  final bool useDevice;
  final WeatherArea? area;
  const WeatherSelection.off() : useDevice = false, area = null;
  const WeatherSelection.device() : useDevice = true, area = null;
  const WeatherSelection.manual(this.area) : useDevice = false;
  bool get enabled => useDevice || area != null;
  String get label => useDevice ? 'Near you' : area?.label ?? 'Local weather';
  Map<String, dynamic> toJson() => {
    'device': useDevice,
    'area': area?.toJson(),
  };
  factory WeatherSelection.fromJson(Map<String, dynamic> json) =>
      json['device'] == true
      ? const WeatherSelection.device()
      : json['area'] is Map
      ? WeatherSelection.manual(
          WeatherArea.fromJson(Map<String, dynamic>.from(json['area'] as Map)),
        )
      : const WeatherSelection.off();
}

class LocalWeatherReading {
  final double temperature;
  final String symbol;
  final DateTime validAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  const LocalWeatherReading({
    required this.temperature,
    required this.symbol,
    required this.validAt,
    required this.updatedAt,
    required this.expiresAt,
  });
  WeatherCondition get condition => weatherCondition(symbol);
  bool get night =>
      symbol.endsWith('_night') || symbol.endsWith('_polartwilight');
  bool isCurrent(DateTime now) =>
      !now.isBefore(validAt) &&
      now.difference(validAt) <= const Duration(minutes: 90) &&
      now.difference(updatedAt) <= const Duration(hours: 12);
  String get description => switch (condition) {
    WeatherCondition.clear => night ? 'Clear' : 'Sunny',
    WeatherCondition.partlyCloudy => 'Partly cloudy',
    WeatherCondition.cloudy => 'Cloudy',
    WeatherCondition.rain => 'Rain',
    WeatherCondition.snow => 'Snow or sleet',
    WeatherCondition.fog => 'Fog',
    WeatherCondition.thunder => 'Thunderstorms',
    WeatherCondition.unknown => 'Conditions unavailable',
  };
  factory LocalWeatherReading.fromJson(Map<String, dynamic> json) {
    final value = LocalWeatherReading(
      temperature: (json['temperature'] as num).toDouble(),
      symbol: json['symbol'] as String,
      validAt: DateTime.parse(json['validAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
    if (!value.temperature.isFinite ||
        value.temperature < -100 ||
        value.temperature > 65) {
      throw const FormatException('Invalid weather reading');
    }
    return value;
  }
}

class WeatherUnavailable implements Exception {
  final String message;
  const WeatherUnavailable(this.message);
}

abstract class WeatherLocationService {
  Future<WeatherArea> current({bool requestPermission = false});
}

class DeviceWeatherLocationService implements WeatherLocationService {
  @override
  Future<WeatherArea> current({bool requestPermission = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const WeatherUnavailable(
        'Location is turned off. Choose an area below or enable location in your phone settings.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const WeatherUnavailable(
        'Location access is unavailable. Choose an area below, or allow location in your phone settings.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 8),
      ),
    );
    if (DateTime.now().difference(position.timestamp) >
        const Duration(minutes: 10)) {
      throw const WeatherUnavailable(
        'Your current location is unavailable. Choose an area or try again.',
      );
    }
    return WeatherArea(position.latitude, position.longitude, 'Near you');
  }
}

abstract class WeatherPreferenceStore {
  Future<WeatherSelection> read(String userId);
  Future<void> write(String userId, WeatherSelection selection);
}

class LocalWeatherPreferenceStore implements WeatherPreferenceStore {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<WeatherSelection> read(String userId) async {
    try {
      final text = await _preferences.getString('workloop.weather.$userId');
      if (text == null) return const WeatherSelection.off();
      final json = jsonDecode(text) as Map<String, dynamic>;
      final selection = WeatherSelection.fromJson(json);
      // Google Places permits temporary coordinate caching for up to 30 days.
      // Expire the local manual-area copy; device location is never persisted.
      final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
      if (selection.area != null &&
          (savedAt == null ||
              DateTime.now().difference(savedAt) > const Duration(days: 29))) {
        await _preferences.remove('workloop.weather.$userId');
        return const WeatherSelection.off();
      }
      return selection;
    } catch (_) {
      return const WeatherSelection.off();
    }
  }

  @override
  Future<void> write(String userId, WeatherSelection selection) =>
      _preferences.setString(
        'workloop.weather.$userId',
        jsonEncode({
          ...selection.toJson(),
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
}

class LocalWeatherRepository {
  final Future<Map<String, dynamic>> Function(WeatherArea) fetch;
  final DateTime Function() now;
  final Map<String, LocalWeatherReading> _cache = {};
  final Map<String, Future<LocalWeatherReading>> _pending = {};
  LocalWeatherRepository({required this.fetch, DateTime Function()? now})
    : now = now ?? DateTime.now;
  factory LocalWeatherRepository.supabase(SupabaseClient client) =>
      LocalWeatherRepository(
        fetch: (area) async {
          final response = await client.functions
              .invoke(
                'local-weather',
                body: {'latitude': area.latitude, 'longitude': area.longitude},
              )
              .timeout(const Duration(seconds: 10));
          if (response.data is! Map) {
            throw const FormatException('Invalid weather response');
          }
          return Map<String, dynamic>.from(response.data as Map);
        },
      );
  Future<LocalWeatherReading> current(WeatherArea area) async {
    final saved = _cache[area.key];
    if (saved != null &&
        now().isBefore(saved.expiresAt) &&
        saved.isCurrent(now())) {
      return saved;
    }
    final pending = _pending[area.key];
    if (pending != null) return pending;
    final request = _load(area);
    _pending[area.key] = request;
    try {
      return await request;
    } finally {
      _pending.remove(area.key);
    }
  }

  Future<LocalWeatherReading> _load(WeatherArea area) async {
    final reading = LocalWeatherReading.fromJson(await fetch(area));
    if (!reading.isCurrent(now())) {
      throw const WeatherUnavailable(
        'Current weather is unavailable. Try again later.',
      );
    }
    if (_cache.length >= 8) _cache.remove(_cache.keys.first);
    _cache[area.key] = reading;
    return reading;
  }
}
