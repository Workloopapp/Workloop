import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';

void main() {
  test(
    'invalid-account cleanup cannot sign out a new account after push wait',
    () async {
      final client = _SwitchableClient();
      final pending = Completer<void>();
      final repository = AuthRepository(
        client,
        beforeSignOut: () => pending.future,
      );
      final operation = repository.signOutLocal(expectedUserId: 'owner-a');
      client.auth.userId = 'owner-b';
      pending.complete();
      await operation;
      expect(client.auth.userId, 'owner-b');
      expect(client.auth.signOutCalls, 0);
    },
  );

  test(
    'stale cleanup skips its hook while matching account still signs out',
    () async {
      final client = _SwitchableClient();
      var cleanupCalls = 0;
      final repository = AuthRepository(
        client,
        beforeSignOut: () async {
          cleanupCalls++;
        },
      );
      await repository.signOutLocal(expectedUserId: 'previous-owner');
      expect(cleanupCalls, 0);
      expect(client.auth.signOutCalls, 0);
      await repository.signOutLocal(expectedUserId: 'owner-a');
      expect(cleanupCalls, 1);
      expect(client.auth.signOutCalls, 1);
    },
  );

  for (final localOnly in [false, true]) {
    test(
      '${localOnly ? 'local' : 'standard'} sign-out reaches SDK when push cleanup hangs',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        final cleanup = Completer<void>();
        final signedOut = client.auth.onAuthStateChange.firstWhere(
          (state) => state.event == AuthChangeEvent.signedOut,
        );
        final events = <AuthChangeEvent>[];
        final subscription = client.auth.onAuthStateChange.listen(
          (state) => events.add(state.event),
        );
        final repository = AuthRepository(
          client,
          beforeSignOut: () => cleanup.future,
        );
        var completed = false;
        final operation =
            (localOnly ? repository.signOutLocal() : repository.signOut()).then(
              (_) => completed = true,
            );
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(completed, isFalse);
        expect(events, isNot(contains(AuthChangeEvent.signedOut)));
        await Future<void>.delayed(const Duration(seconds: 1));
        await operation.timeout(const Duration(seconds: 3));
        expect(completed, isTrue);
        // Auth event delivery is asynchronous even after signOut completes.
        final signedOutState = await signedOut.timeout(
          const Duration(seconds: 3),
        );
        expect(signedOutState.event, AuthChangeEvent.signedOut);
        // A late failed request must not become an uncaught asynchronous error.
        cleanup.completeError(StateError('offline'));
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        await client.dispose();
      },
    );
  }

  test('offline push cleanup does not prevent SDK sign-out', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final events = <AuthChangeEvent>[];
    final subscription = client.auth.onAuthStateChange.listen(
      (state) => events.add(state.event),
    );
    final repository = AuthRepository(
      client,
      beforeSignOut: () async => throw StateError('network unavailable'),
    );
    await repository.signOutLocal();
    await Future<void>.delayed(Duration.zero);
    expect(events, contains(AuthChangeEvent.signedOut));
    await subscription.cancel();
    await client.dispose();
  });
}

class _SwitchableAuth implements GoTrueClient {
  String? userId = 'owner-a';
  int signOutCalls = 0;
  @override
  User? get currentUser => userId == null
      ? null
      : User(
          id: userId!,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-09-05T00:00:00Z',
        );
  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    signOutCalls++;
    userId = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SwitchableClient implements SupabaseClient {
  @override
  final _SwitchableAuth auth = _SwitchableAuth();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
