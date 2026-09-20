import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// No credentials are included in storage errors or diagnostics.
class SecureAuthStorageException implements Exception {
  const SecureAuthStorageException();
  @override
  String toString() => 'Secure sign-in storage is unavailable.';
}

/// Supabase's two persistence interfaces share one ordered native store.
/// The preferences contain only migration/sign-out markers after migration.
class WorkloopSecureAuthStorage {
  WorkloopSecureAuthStorage({
    required String supabaseUrl,
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? preferences,
  }) : sessionKey =
           'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
       _secure =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: false),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
             mOptions: MacOsOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           ),
       _preferences = preferences ?? SharedPreferences.getInstance {
    session = SecureSessionStorage(this);
    pkce = SecurePkceStorage(this);
  }

  static const pkceKey = 'supabase.auth.token-code-verifier';
  final String sessionKey;
  final FlutterSecureStorage _secure;
  final Future<SharedPreferences> Function() _preferences;
  late final SecureSessionStorage session;
  late final SecurePkceStorage pkce;
  SharedPreferences? _prefs;
  Future<void> _pending = Future<void>.value();
  bool _initialized = false;

  String get installationKey => '$sessionKey.secure-install.v1';
  String _removedKey(String key) => '$key.secure-removed.v1';
  Iterable<String> get _ownedKeys => [sessionKey, pkceKey];

  Future<T> _ordered<T>(Future<T> Function() operation) {
    final result = _pending.then((_) async {
      try {
        await _initialize();
        return await operation();
      } catch (_) {
        throw const SecureAuthStorageException();
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> initialize() => _ordered(() async {});

  Future<void> _writeVerified(String key, String value) async {
    await _secure.write(key: key, value: value);
    if (await _secure.read(key: key) != value) {
      throw const SecureAuthStorageException();
    }
  }

  Future<void> _deleteVerified(String key) async {
    await _secure.delete(key: key);
    if (await _secure.read(key: key) != null) {
      throw const SecureAuthStorageException();
    }
  }

  Future<void> _removeLegacy(String key) async {
    if (_prefs!.containsKey(key) && !await _prefs!.remove(key)) {
      throw const SecureAuthStorageException();
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _prefs ??= await _preferences();
    if (_prefs!.getBool(installationKey) != true) {
      // Keychain items can survive uninstall. Only this installation's legacy
      // preferences establish ownership on first use; never restore an old
      // install's account. Keep every legacy value until all writes verify.
      for (final key in _ownedKeys) {
        final legacy = _prefs!.getString(key);
        if (legacy != null && _prefs!.getBool(_removedKey(key)) != true) {
          await _writeVerified(key, legacy);
        } else {
          await _deleteVerified(key);
        }
      }
      if (!await _prefs!.setBool(installationKey, true)) {
        throw const SecureAuthStorageException();
      }
    }
    // A crash or failed preferences removal may happen after the installation
    // marker commits. Finish both migrations on retry, including an unused
    // PKCE verifier, without discarding the already migrated secure account.
    for (final key in _ownedKeys) {
      final legacy = _prefs!.getString(key);
      if (legacy == null) continue;
      if (_prefs!.getBool(_removedKey(key)) != true &&
          await _secure.read(key: key) == null) {
        await _writeVerified(key, legacy);
      }
      await _removeLegacy(key);
    }
    _initialized = true;
  }

  Future<String?> read(String key) => _ordered(() async {
    // A durable, non-secret sign-out marker also prevents resurrection if the
    // Keychain is temporarily unavailable during deletion.
    if (_prefs!.getBool(_removedKey(key)) == true) return null;
    final stored = await _secure.read(key: key);
    if (stored != null) {
      await _removeLegacy(key);
      return stored;
    }
    final legacy = _prefs!.getString(key);
    if (legacy == null) return null;
    await _writeVerified(key, legacy);
    await _removeLegacy(key);
    return legacy;
  });

  Future<void> write(String key, String value) => _ordered(() async {
    // Auth callbacks may replace an account without an intervening sign-out
    // (for example an external sign-in link). If persistence then fails, never
    // reopen the preceding account from an older secure value on next launch.
    if (!await _prefs!.setBool(_removedKey(key), true)) {
      throw const SecureAuthStorageException();
    }
    await _writeVerified(key, value);
    await _removeLegacy(key);
    if (!await _prefs!.remove(_removedKey(key))) {
      throw const SecureAuthStorageException();
    }
  });

  Future<void> remove(String key) => _ordered(() async {
    if (!await _prefs!.setBool(_removedKey(key), true)) {
      throw const SecureAuthStorageException();
    }
    await _removeLegacy(key);
    await _deleteVerified(key);
  });

  Future<void> clearSession() => _ordered(() async {
    for (final key in _ownedKeys) {
      if (!await _prefs!.setBool(_removedKey(key), true)) {
        throw const SecureAuthStorageException();
      }
      await _removeLegacy(key);
    }
    for (final key in _ownedKeys) {
      await _deleteVerified(key);
    }
  });
}

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage(this._store);
  final WorkloopSecureAuthStorage _store;
  @override
  Future<void> initialize() => _store.initialize();
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => _store.read(_store.sessionKey);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_store.sessionKey, persistSessionString);
  @override
  Future<void> removePersistedSession() => _store.remove(_store.sessionKey);
}

class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage(this._store);
  final WorkloopSecureAuthStorage _store;
  @override
  Future<String?> getItem({required String key}) => _store.read(key);
  @override
  Future<void> setItem({required String key, required String value}) =>
      _store.write(key, value);
  @override
  Future<void> removeItem({required String key}) => _store.remove(key);
}
