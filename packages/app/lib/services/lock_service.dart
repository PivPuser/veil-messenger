import 'dart:io';

import 'package:crypto_core/crypto_core.dart';

import 'file_lock_storage.dart';

/// Holds the app's [AppLock], backed by file storage. Initialized once at
/// startup with the app data directory.
class LockService {
  LockService._();

  static final LockService instance = LockService._();

  AppLock? _lock;

  AppLock get lock {
    final AppLock? current = _lock;
    if (current == null) {
      throw StateError('LockService.initWith must be called before use');
    }
    return current;
  }

  void initWith(Directory dataDir) {
    initWithStorage(FileLockStorage(dataDir));
  }

  /// Escape hatch for tests / custom backends.
  void initWithStorage(LockStorage storage) {
    _lock = AppLock(storage);
  }
}
