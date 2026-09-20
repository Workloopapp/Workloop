import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/shared/repositories/repository_schema_compatibility.dart';

void main() {
  group('repository schema compatibility', () {
    test('missing embedded relation retries the legacy query once', () async {
      var currentCalls = 0;
      var legacyCalls = 0;
      final cache = PostgrestSchemaCompatibilityCache();

      final result = await loadWithPostgrestSchemaFallback(
        objectName: 'appointment_items',
        compatibilityCache: cache,
        loadCurrent: () async {
          currentCalls++;
          throw const PostgrestException(
            code: 'PGRST200',
            message:
                "Could not find a relationship between 'appointments' and 'appointment_items' in the schema cache",
          );
        },
        loadLegacy: () async {
          legacyCalls++;
          return ['legacy appointment'];
        },
      );

      expect(result, ['legacy appointment']);
      expect(currentCalls, 1);
      expect(legacyCalls, 1);
    });

    test('missing add-on table can degrade to an empty catalog', () async {
      final cache = PostgrestSchemaCompatibilityCache();
      final result = await loadWithPostgrestSchemaFallback(
        objectName: 'service_add_ons',
        compatibilityCache: cache,
        loadCurrent: () async => throw const PostgrestException(
          code: 'PGRST205',
          message:
              "Could not find the table 'public.service_add_ons' in the schema cache",
        ),
        loadLegacy: () async => const <String>[],
      );

      expect(result, isEmpty);
    });

    test('permission and unrelated schema errors remain visible', () async {
      final cache = PostgrestSchemaCompatibilityCache();
      const permissionError = PostgrestException(
        code: '42501',
        message: 'permission denied for table appointment_items',
      );
      const unrelatedRelation = PostgrestException(
        code: 'PGRST200',
        message:
            "Could not find a relationship between 'appointments' and 'contacts'",
      );

      await expectLater(
        loadWithPostgrestSchemaFallback<void>(
          objectName: 'appointment_items',
          compatibilityCache: cache,
          loadCurrent: () async => throw permissionError,
          loadLegacy: () async {},
        ),
        throwsA(same(permissionError)),
      );
      await expectLater(
        loadWithPostgrestSchemaFallback<void>(
          objectName: 'appointment_items',
          compatibilityCache: cache,
          loadCurrent: () async => throw unrelatedRelation,
          loadLegacy: () async {},
        ),
        throwsA(same(unrelatedRelation)),
      );
    });

    test('concurrent callers share one missing-schema probe', () async {
      final cache = PostgrestSchemaCompatibilityCache();
      final releaseProbe = Completer<void>();
      var currentCalls = 0;
      var legacyCalls = 0;

      Future<String> load(int caller) => loadWithPostgrestSchemaFallback(
        objectName: 'appointment_items',
        compatibilityCache: cache,
        loadCurrent: () async {
          currentCalls++;
          await releaseProbe.future;
          throw const PostgrestException(
            code: 'PGRST200',
            message:
                "Could not find a relationship between 'appointments' and 'appointment_items' in the schema cache",
          );
        },
        loadLegacy: () async {
          legacyCalls++;
          return 'legacy-$caller';
        },
      );

      final first = load(1);
      final second = load(2);
      final third = load(3);
      await Future<void>.delayed(Duration.zero);
      expect(currentCalls, 1);

      releaseProbe.complete();
      expect(await Future.wait([first, second, third]), [
        'legacy-1',
        'legacy-2',
        'legacy-3',
      ]);
      expect(currentCalls, 1);
      expect(legacyCalls, 3);
    });

    test(
      'missing-schema decision expires so a deployed object is retried',
      () async {
        var now = DateTime(2026, 9, 1, 12);
        final cache = PostgrestSchemaCompatibilityCache(
          ttl: const Duration(minutes: 5),
          now: () => now,
        );
        var currentCalls = 0;

        Future<String> load() => loadWithPostgrestSchemaFallback(
          objectName: 'booking_request_items',
          compatibilityCache: cache,
          loadCurrent: () async {
            currentCalls++;
            if (currentCalls == 1) {
              throw const PostgrestException(
                code: 'PGRST200',
                message:
                    "Could not find a relationship between 'booking_requests' and 'booking_request_items' in the schema cache",
              );
            }
            return 'current';
          },
          loadLegacy: () async => 'legacy',
        );

        expect(await load(), 'legacy');
        expect(await load(), 'legacy');
        expect(currentCalls, 1);

        now = now.add(const Duration(minutes: 6));
        expect(await load(), 'current');
        expect(currentCalls, 2);
      },
    );
  });
}
