import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/shared/repositories/push_token_repository.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late PushTokenRepository repository;
  late List<Map<String, dynamic>> calls;

  setUp(() async {
    calls = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/rest/v1/rpc/register_push_token');
      calls.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode('token-row-id'));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'public-fixture-key',
    );
    repository = PushTokenRepository(client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('iOS registration transmits the explicit signing environment', () async {
    final id = await repository.register(
      workspaceId: 'workspace',
      token: 'ios-token',
      platform: 'ios',
      appBuild: '10',
      apnsEnvironment: 'production',
    );
    expect(id, 'token-row-id');
    expect(calls.single['p_apns_environment'], 'production');
    expect(calls.single['p_app_build'], '10');
  });

  test('Android registration sends no APNs environment', () async {
    await repository.register(
      workspaceId: 'workspace',
      token: 'fcm-token',
      platform: 'android',
      appBuild: '10',
    );
    expect(calls.single.containsKey('p_apns_environment'), isTrue);
    expect(calls.single['p_apns_environment'], isNull);
  });

  test(
    'unknown iOS environment and Android APNs claims fail before network',
    () async {
      await expectLater(
        repository.register(
          workspaceId: 'workspace',
          token: 'ios-token',
          platform: 'ios',
          appBuild: '10',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.register(
          workspaceId: 'workspace',
          token: 'android-token',
          platform: 'android',
          appBuild: '10',
          apnsEnvironment: 'sandbox',
        ),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );
}
