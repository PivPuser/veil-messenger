import 'dart:convert';
import 'dart:typed_data';

import 'codec.dart';
import 'secret_vault.dart';

/// Persistent storage the lock relies on. The Flutter layer backs this with
/// real files; tests use an in-memory map. [wipeAll] must irreversibly destroy
/// ALL application data — it is the panic wipe.
abstract interface class LockStorage {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List value);
  Future<void> delete(String key);
  Future<void> wipeAll();
}

/// Thrown when the password is wrong but the wipe threshold hasn't been reached.
class WrongPasswordException implements Exception {
  const WrongPasswordException(this.remainingAttempts);
  final int remainingAttempts;
  @override
  String toString() =>
      'WrongPasswordException(remaining: $remainingAttempts)';
}

/// Thrown after the final wrong attempt, once all data has been wiped.
class DataWipedException implements Exception {
  const DataWipedException();
  @override
  String toString() => 'DataWipedException: all app data was wiped';
}

/// A passphrase lock with a panic-wipe policy.
///
/// Enabling derives a 32-byte master key from the user's password (PBKDF2, via
/// [SecretVault]) and stores a small verifier so the password can be checked at
/// unlock time. After [defaultMaxAttempts] consecutive wrong passwords, every
/// bit of app data is wiped.
///
/// The attempt counter is persisted BEFORE each check, so force-quitting the
/// app between attempts cannot reset it — the wipe policy can't be dodged.
class AppLock {
  AppLock(this._storage, {this.kdfIterations = 210000});

  final LockStorage _storage;

  /// PBKDF2 iteration count used when enabling the lock. Stored in the lock
  /// metadata so unlocking always uses the same value the key was derived with
  /// (and so the cost can be raised in future versions without breaking old
  /// vaults). Tests may lower it for speed.
  final int kdfIterations;

  static const String _metaKey = 'lock.meta';

  /// Wipe threshold requested for this app: two wrong passwords wipe all data.
  static const int defaultMaxAttempts = 2;

  /// Allowed password lengths the user can pick when enabling the lock.
  static const List<int> allowedLengths = <int>[4, 6, 12];

  Future<bool> isEnabled() async => (await _loadMeta()) != null;

  Future<int?> passwordLength() async => (await _loadMeta())?.passwordLength;

  /// How many attempts remain before a wipe.
  Future<int> remainingAttempts() async {
    final _LockMeta? meta = await _loadMeta();
    if (meta == null) return 0;
    return (meta.maxAttempts - meta.failedAttempts).clamp(0, meta.maxAttempts);
  }

  /// Enables the lock. Returns the derived master key — use it to (re)seal the
  /// real data vault so that only this password can open it.
  Future<Uint8List> enable({
    required String password,
    required int passwordLength,
    int maxAttempts = defaultMaxAttempts,
  }) async {
    if (!allowedLengths.contains(passwordLength)) {
      throw ArgumentError('password length must be one of $allowedLengths');
    }
    if (password.length != passwordLength) {
      throw ArgumentError('password must be exactly $passwordLength characters');
    }
    final Uint8List salt = SecretVault.newSalt();
    final Uint8List key = await SecretVault.deriveKey(
      passphrase: password,
      salt: salt,
      iterations: kdfIterations,
    );
    final Uint8List verifier = await SecretVault.seal(
      masterKey: key,
      plaintext: utf8.encode('veil-lock-verifier-v1'),
    );
    await _saveMeta(_LockMeta(
      salt: salt,
      verifier: verifier,
      passwordLength: passwordLength,
      maxAttempts: maxAttempts,
      failedAttempts: 0,
      iterations: kdfIterations,
    ));
    return key;
  }

  /// Disables the lock. Call only while already unlocked.
  Future<void> disable() => _storage.delete(_metaKey);

  /// Verifies [password]. On success, resets the counter and returns the master
  /// key. On failure, increments the persisted counter and either throws
  /// [WrongPasswordException] or — once the limit is reached — wipes all data
  /// and throws [DataWipedException].
  Future<Uint8List> unlock(String password) async {
    final _LockMeta? meta = await _loadMeta();
    if (meta == null) {
      throw StateError('lock is not enabled');
    }

    // Persist the attempt up-front: killing the app now still counts it.
    meta.failedAttempts += 1;
    await _saveMeta(meta);

    final Uint8List key = await SecretVault.deriveKey(
      passphrase: password,
      salt: meta.salt,
      iterations: meta.iterations,
    );
    bool correct;
    try {
      await SecretVault.open(masterKey: key, blob: meta.verifier);
      correct = true;
    } catch (_) {
      correct = false;
    }

    if (correct) {
      meta.failedAttempts = 0;
      await _saveMeta(meta);
      return key;
    }

    if (meta.failedAttempts >= meta.maxAttempts) {
      await _storage.wipeAll();
      throw const DataWipedException();
    }
    throw WrongPasswordException(meta.maxAttempts - meta.failedAttempts);
  }

  /// The explicit "delete data" button on the lock screen — wipes everything.
  Future<void> wipe() => _storage.wipeAll();

  Future<_LockMeta?> _loadMeta() async {
    final Uint8List? raw = await _storage.read(_metaKey);
    if (raw == null) return null;
    return _LockMeta.deserialize(raw);
  }

  Future<void> _saveMeta(_LockMeta meta) =>
      _storage.write(_metaKey, meta.serialize());
}

class _LockMeta {
  _LockMeta({
    required this.salt,
    required this.verifier,
    required this.passwordLength,
    required this.maxAttempts,
    required this.failedAttempts,
    required this.iterations,
  });

  final Uint8List salt;
  final Uint8List verifier;
  final int passwordLength;
  final int maxAttempts;
  int failedAttempts;
  final int iterations;

  Uint8List serialize() {
    final ByteWriter w = ByteWriter()
      ..bytes(salt)
      ..bytes(verifier)
      ..u32(passwordLength)
      ..u32(maxAttempts)
      ..u32(failedAttempts)
      ..u32(iterations);
    return w.toBytes();
  }

  static _LockMeta deserialize(Uint8List data) {
    final ByteReader r = ByteReader(data);
    return _LockMeta(
      salt: r.bytes(),
      verifier: r.bytes(),
      passwordLength: r.u32(),
      maxAttempts: r.u32(),
      failedAttempts: r.u32(),
      iterations: r.u32(),
    );
  }
}
