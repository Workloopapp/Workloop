import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workloop/core/supabase/secure_auth_storage.dart';
import 'package:workloop/core/supabase/secure_session_recovery_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const sessionKey = 'sb-example-auth-token';
  const installKey = '$sessionKey.secure-install.v1';
  const session =
      '{"access_token":"fixture","refresh_token":"fixture-refresh"}';
  late Map<String, String> secure;
  late List<String> operations;
  String? failMethod;
  bool corruptWrite = false;
  Completer<void>? blockedWrite;
  WorkloopSecureAuthStorage create() =>
      WorkloopSecureAuthStorage(supabaseUrl: 'https://example.supabase.co');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = {};
    operations = [];
    failMethod = null;
    corruptWrite = false;
    blockedWrite = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          operations.add('${call.method}:$key');
          if (call.method == failMethod) {
            throw PlatformException(
              code: 'locked',
              message: 'private-value-never-forwarded',
            );
          }
          switch (call.method) {
            case 'read':
              return secure[key];
            case 'write':
              await blockedWrite?.future;
              if (!corruptWrite) secure[key] = args['value'] as String;
              return null;
            case 'delete':
              secure.remove(key);
              return null;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'migrates session and pending recovery code only after verified writes',
    () async {
      SharedPreferences.setMockInitialValues({
        sessionKey: session,
        WorkloopSecureAuthStorage.pkceKey: 'recovery-verifier',
        'workloop.theme': 'dark',
      });
      final store = create();
      await store.initialize();
      expect(await store.session.accessToken(), session);
      expect(
        await store.pkce.getItem(key: WorkloopSecureAuthStorage.pkceKey),
        'recovery-verifier',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(sessionKey), isFalse);
      expect(prefs.containsKey(WorkloopSecureAuthStorage.pkceKey), isFalse);
      expect(prefs.getString('workloop.theme'), 'dark');
      expect(operations.take(4), [
        'write:$sessionKey',
        'read:$sessionKey',
        'write:${WorkloopSecureAuthStorage.pkceKey}',
        'read:${WorkloopSecureAuthStorage.pkceKey}',
      ]);
    },
  );

  for (final failure in ['write', 'read', 'corrupt']) {
    test(
      '$failure failure retains legacy session and supports retry',
      () async {
        SharedPreferences.setMockInitialValues({sessionKey: session});
        failMethod = failure == 'corrupt' ? null : failure;
        corruptWrite = failure == 'corrupt';
        final store = create();
        await expectLater(
          store.initialize(),
          throwsA(isA<SecureAuthStorageException>()),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(sessionKey), session);
        expect(prefs.getBool(installKey), isNot(true));
        failMethod = null;
        corruptWrite = false;
        await store.initialize();
        expect(await store.session.accessToken(), session);
        expect(prefs.getString(sessionKey), isNull);
      },
    );
  }

  test('partial migration failure retains every legacy credential', () async {
    SharedPreferences.setMockInitialValues({sessionKey: session});
    // Session writes first; failure removing an old PKCE entry is later.
    failMethod = 'delete';
    final store = create();
    await expectLater(
      store.initialize(),
      throwsA(isA<SecureAuthStorageException>()),
    );
    expect(secure[sessionKey], session);
    expect(
      (await SharedPreferences.getInstance()).getString(sessionKey),
      session,
    );
    failMethod = null;
    await create().initialize();
    expect(await create().session.accessToken(), session);
  });

  test(
    'restart finishes PKCE cleanup interrupted after installation marker commit',
    () async {
      SharedPreferences.setMockInitialValues({
        installKey: true,
        WorkloopSecureAuthStorage.pkceKey: 'retained-recovery-verifier',
      });
      secure[sessionKey] = session;
      secure[WorkloopSecureAuthStorage.pkceKey] = 'retained-recovery-verifier';
      await create().initialize();
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          WorkloopSecureAuthStorage.pkceKey,
        ),
        isFalse,
      );
      expect(secure[sessionKey], session);
      expect(
        secure[WorkloopSecureAuthStorage.pkceKey],
        'retained-recovery-verifier',
      );
    },
  );

  test(
    'cleanup retry preserves legacy verifier while secure storage is locked',
    () async {
      SharedPreferences.setMockInitialValues({
        installKey: true,
        WorkloopSecureAuthStorage.pkceKey: 'retained-recovery-verifier',
      });
      secure[sessionKey] = session;
      secure[WorkloopSecureAuthStorage.pkceKey] = 'retained-recovery-verifier';
      failMethod = 'read';
      final store = create();
      await expectLater(
        store.initialize(),
        throwsA(isA<SecureAuthStorageException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          WorkloopSecureAuthStorage.pkceKey,
        ),
        'retained-recovery-verifier',
      );
      failMethod = null;
      await store.initialize();
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          WorkloopSecureAuthStorage.pkceKey,
        ),
        isFalse,
      );
      expect(await store.session.accessToken(), session);
    },
  );

  test(
    'reinstall never restores old Keychain account or recovery verifier',
    () async {
      secure[sessionKey] = session;
      secure[WorkloopSecureAuthStorage.pkceKey] = 'old-verifier';
      final store = create();
      await store.initialize();
      expect(await store.session.hasAccessToken(), isFalse);
      expect(secure, isEmpty);
    },
  );

  test(
    'existing secure account wins over stale legacy value after migration',
    () async {
      SharedPreferences.setMockInitialValues({
        installKey: true,
        sessionKey: 'old-account',
      });
      secure[sessionKey] = session;
      expect(await create().session.accessToken(), session);
      expect(
        (await SharedPreferences.getInstance()).containsKey(sessionKey),
        isFalse,
      );
    },
  );

  test('locked Keychain never reports a saved session as missing', () async {
    SharedPreferences.setMockInitialValues({installKey: true});
    secure[sessionKey] = session;
    failMethod = 'read';
    final store = create();
    await expectLater(
      store.session.hasAccessToken(),
      throwsA(isA<SecureAuthStorageException>()),
    );
    expect(secure[sessionKey], session);
    failMethod = null;
    expect(await store.session.accessToken(), session);
  });

  test(
    'logout removes session and PKCE without erasing other secure data',
    () async {
      final store = create();
      await store.session.persistSession(session);
      await store.pkce.setItem(
        key: WorkloopSecureAuthStorage.pkceKey,
        value: 'new-verifier',
      );
      secure['unrelated'] = 'unrelated';
      await store.clearSession();
      expect(secure, {'unrelated': 'unrelated'});
      expect(await create().session.accessToken(), isNull);
      expect(
        await create().pkce.getItem(key: WorkloopSecureAuthStorage.pkceKey),
        isNull,
      );
    },
  );

  test(
    'failed Keychain removal cannot resurrect a signed-out account on restart',
    () async {
      final store = create();
      await store.session.persistSession(session);
      failMethod = 'delete';
      await expectLater(
        store.clearSession(),
        throwsA(isA<SecureAuthStorageException>()),
      );
      expect(secure[sessionKey], session);
      expect(await create().session.accessToken(), isNull);
      failMethod = null;
      await store.session.persistSession('new-account');
      expect(await create().session.accessToken(), 'new-account');
    },
  );

  test(
    'failed direct account replacement cannot reopen the preceding account',
    () async {
      final store = create();
      await store.session.persistSession('preceding-account');
      failMethod = 'write';
      await expectLater(
        store.session.persistSession('next-account'),
        throwsA(isA<SecureAuthStorageException>()),
      );
      expect(secure[sessionKey], 'preceding-account');
      expect(await create().session.accessToken(), isNull);
      failMethod = null;
      await store.session.persistSession('next-account');
      expect(await create().session.accessToken(), 'next-account');
    },
  );

  test(
    'pending token refresh finishes before logout and cannot restore it late',
    () async {
      final store = create();
      await store.initialize();
      blockedWrite = Completer<void>();
      final write = store.session.persistSession(session);
      await Future<void>.delayed(Duration.zero);
      final logout = store.clearSession();
      blockedWrite!.complete();
      await Future.wait([write, logout]);
      expect(await store.session.hasAccessToken(), isFalse);
      expect(secure[sessionKey], isNull);
    },
  );

  test('new account write queued after logout is preserved', () async {
    final store = create();
    await store.session.persistSession(session);
    final logout = store.clearSession();
    final login = store.session.persistSession('new-account');
    await Future.wait([logout, login]);
    expect(await create().session.accessToken(), 'new-account');
  });

  testWidgets(
    'secure storage retry stays available without exposing error values',
    (tester) async {
      var retries = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        SecureSessionRecoveryScreen(
          onRetry: () {
            retries++;
            return pending.future;
          },
        ),
      );
      expect(find.textContaining('has not been removed'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retries, 1);
      expect(find.text('Please wait…'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
