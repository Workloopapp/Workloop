import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/weather/local_weather_greeting.dart';
import 'package:workloop/features/weather/local_weather_provider.dart';
import 'package:workloop/features/weather/local_weather_repository.dart';
import 'package:workloop/shared/repositories/address_search_repository.dart';

Map<String, dynamic> reading(
  DateTime now, {
  String symbol = 'rain',
  double temperature = 13,
}) => {
  'symbol': symbol,
  'temperature': temperature,
  'validAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
  'updatedAt': now.subtract(const Duration(minutes: 30)).toIso8601String(),
  'expiresAt': now.add(const Duration(minutes: 20)).toIso8601String(),
};

class MemoryWeatherStore implements WeatherPreferenceStore {
  final Map<String, WeatherSelection> selections = {};
  @override
  Future<WeatherSelection> read(String userId) async =>
      selections[userId] ?? const WeatherSelection.off();
  @override
  Future<void> write(String userId, WeatherSelection selection) async {
    selections[userId] = selection;
  }
}

class TestAddressSearch implements AddressSearchRepository {
  final resolved = Completer<ResolvedAddress>();
  @override
  Future<List<AddressPrediction>> autocomplete({
    required String input,
    required String sessionToken,
  }) async => [
    const AddressPrediction(
      placeId: 'test',
      primaryText: 'Chosen postcode',
      secondaryText: 'London',
      fullText: 'Chosen postcode, London',
    ),
  ];
  @override
  Future<ResolvedAddress> resolve({
    required String placeId,
    required String sessionToken,
  }) => resolved.future;
}

class TestLocation implements WeatherLocationService {
  final List<bool> requests = [];
  bool deny = false;
  @override
  Future<WeatherArea> current({bool requestPermission = false}) async {
    requests.add(requestPermission);
    if (deny) throw const WeatherUnavailable('Choose an area');
    return WeatherArea(51.5073, -.1288, 'Near you');
  }
}

void main() {
  test(
    'weather maps rain snow thunder fog and night without assuming sunshine',
    () {
      expect(weatherCondition('heavyrainandthunder'), WeatherCondition.thunder);
      expect(weatherCondition('lightsleetshowers_day'), WeatherCondition.snow);
      expect(weatherCondition('lightrainshowers_night'), WeatherCondition.rain);
      expect(weatherCondition('fog'), WeatherCondition.fog);
      expect(weatherCondition('something_new'), WeatherCondition.unknown);
      final value = LocalWeatherReading.fromJson(
        reading(DateTime.now(), symbol: 'clearsky_night'),
      );
      expect(value.night, isTrue);
      expect(value.description, 'Clear');
    },
  );
  test(
    'coordinates lose precise location before becoming a request or saved area',
    () {
      final area = WeatherArea(51.507351, -.127758, 'Near you');
      expect(area.toJson()['latitude'], 51.51);
      expect(area.toJson()['longitude'], -.13);
      expect(() => WeatherArea(91, 0, 'bad'), throwsFormatException);
      expect(() => WeatherArea(double.nan, 0, 'bad'), throwsFormatException);
    },
  );
  test('cache coalesces simultaneous requests and respects expiry', () async {
    var now = DateTime.utc(2026, 9, 5, 17);
    var calls = 0;
    final repo = LocalWeatherRepository(
      now: () => now,
      fetch: (_) async {
        calls++;
        return reading(now);
      },
    );
    final area = WeatherArea(52, 0, 'Area');
    await Future.wait([repo.current(area), repo.current(area)]);
    await repo.current(area);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 21));
    await repo.current(area);
    expect(calls, 2);
  });
  test('old and invalid data is not presented as current weather', () async {
    final now = DateTime.utc(2026, 9, 5, 17);
    final repo = LocalWeatherRepository(
      now: () => now,
      fetch: (_) async => reading(now.subtract(const Duration(hours: 4))),
    );
    await expectLater(
      repo.current(WeatherArea(52, 0, 'Area')),
      throwsA(isA<WeatherUnavailable>()),
    );
    expect(
      () => LocalWeatherReading.fromJson({...reading(now), 'temperature': 900}),
      throwsFormatException,
    );
  });
  test(
    'default off never asks for permission or fetches; manual fallback works after denial',
    () async {
      final store = MemoryWeatherStore();
      final location = TestLocation()..deny = true;
      var fetches = 0;
      final container = ProviderContainer(
        overrides: [
          weatherPreferenceStoreProvider.overrideWithValue(store),
          weatherLocationServiceProvider.overrideWithValue(location),
          localWeatherRepositoryProvider.overrideWithValue(
            LocalWeatherRepository(
              fetch: (_) async {
                fetches++;
                return reading(DateTime.now());
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = localWeatherProvider('owner');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      expect(location.requests, isEmpty);
      expect(fetches, 0);
      await container
          .read(provider.notifier)
          .select(const WeatherSelection.device());
      expect(location.requests, [true]);
      expect(container.read(provider).requireValue.message, 'Choose an area');
      await container
          .read(provider.notifier)
          .select(WeatherSelection.manual(WeatherArea(51, 0, 'Chosen area')));
      expect(
        container.read(provider).requireValue.reading?.description,
        'Rain',
      );
      expect(fetches, 1);
      expect(location.requests, [true]);
      expect(
        await store.read('another-owner'),
        isA<WeatherSelection>().having((v) => v.enabled, 'enabled', isFalse),
      );
    },
  );
  test(
    'late reply for an old area cannot overwrite a newly chosen area or off',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final container = ProviderContainer(
        overrides: [
          weatherPreferenceStoreProvider.overrideWithValue(
            MemoryWeatherStore(),
          ),
          localWeatherRepositoryProvider.overrideWithValue(
            LocalWeatherRepository(fetch: (_) => pending.future),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = localWeatherProvider('owner');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final loading = container
          .read(provider.notifier)
          .select(WeatherSelection.manual(WeatherArea(51, 0, 'Old area')));
      await Future<void>.delayed(Duration.zero);
      await container
          .read(provider.notifier)
          .select(const WeatherSelection.off());
      pending.complete(reading(DateTime.now()));
      await loading;
      expect(container.read(provider).requireValue.selection.enabled, isFalse);
      expect(container.read(provider).requireValue.reading, isNull);
    },
  );
  testWidgets(
    'disabled weather has a neutral marker and does not block greeting',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherUserIdProvider.overrideWith((ref) => Stream.value('owner')),
            weatherPreferenceStoreProvider.overrideWithValue(
              MemoryWeatherStore(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: WorkloopWeatherGreeting(greeting: 'Good evening, Alex'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Good evening, Alex'), findsOneWidget);
      expect(find.text('Local weather'), findsOneWidget);
      expect(find.byIcon(LucideIcons.mapPin), findsOneWidget);
      expect(find.textContaining('Sunny'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'expired manual coordinates are cleared without a weather request',
    () async {
      final store = MemoryWeatherStore();
      store.selections['owner'] = WeatherSelection.manual(
        WeatherArea(
          51,
          0,
          'Old area',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
      final container = ProviderContainer(
        overrides: [weatherPreferenceStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        localWeatherProvider('owner'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final result = await container.read(localWeatherProvider('owner').future);
      expect(result.selection.enabled, isFalse);
      expect(result.reading, isNull);
      expect(result.message, contains('Choose your weather area again'));
      expect((await store.read('owner')).enabled, isFalse);
    },
  );
  testWidgets(
    'weather details remain usable with large text and show source and age',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryWeatherStore();
      store.selections['owner'] = WeatherSelection.manual(
        WeatherArea(51, 0, 'Chosen area'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherUserIdProvider.overrideWith((ref) => Stream.value('owner')),
            weatherPreferenceStoreProvider.overrideWithValue(store),
            localWeatherRepositoryProvider.overrideWithValue(
              LocalWeatherRepository(
                fetch: (_) async => reading(DateTime.now()),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const Scaffold(
              body: WorkloopWeatherGreeting(greeting: 'Good evening, Alex'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('13° · Rain · Chosen area'), findsOneWidget);
      await tester.tap(find.text('Good evening, Alex'));
      await tester.pumpAndSettle();
      expect(find.text('Chosen area · Forecast for this hour'), findsOneWidget);
      expect(find.textContaining('Forecast updated'), findsOneWidget);
      expect(find.text('Weather: MET Norway'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'late area lookup cannot replace a newer use-my-location choice',
    (tester) async {
      final store = MemoryWeatherStore();
      final addresses = TestAddressSearch();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherUserIdProvider.overrideWith((ref) => Stream.value('owner')),
            weatherPreferenceStoreProvider.overrideWithValue(store),
            weatherLocationServiceProvider.overrideWithValue(TestLocation()),
            addressSearchRepositoryProvider.overrideWithValue(addresses),
            localWeatherRepositoryProvider.overrideWithValue(
              LocalWeatherRepository(
                fetch: (_) async => reading(DateTime.now()),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: WorkloopWeatherGreeting(greeting: 'Good evening'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Good evening'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'SW1A');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chosen postcode'));
      await tester.pump();
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      addresses.resolved.complete(
        const ResolvedAddress(
          formattedAddress: 'Chosen postcode',
          latitude: 52,
          longitude: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect((await store.read('owner')).useDevice, isTrue);
      expect(find.text('Near you · Forecast for this hour'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
