import 'dart:io';

import 'package:crypto_core/crypto_core.dart';

import 'file_lock_storage.dart';
import 'vault_store.dart';

/// Holds the app's [AppLock] and the shared [LockStorage] it lives in
/// (the same storage the encrypted identity vault uses).
class LockService {
  LockService._();

  static final LockService instance = LockService._();

  AppLock? _lock;
  LockStorage? _storage;

  AppLock get lock {
    final AppLock? current = _lock;
    if (current == null) {
      throw StateError('LockService.initWith must be called before use');
    }
    return current;
  }

  LockStorage get storage {
    final LockStorage? current = _storage;
    if (current == null) {
      throw StateError('LockService.initWith must be called before use');
    }
    return current;
  }

  VaultStore get vaultStore => VaultStore(storage);

  void initWith(Directory dataDir) {
    initWithStorage(FileLockStorage(dataDir));
  }

  /// Escape hatch for tests / custom backends.
  void initWithStorage(LockStorage storage) {
    _storage = storage;
    _lock = AppLock(storage);
  }
}
