import 'dart:io';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';

/// File-backed [LockStorage]. All app data lives in a single directory so the
/// panic [wipeAll] can delete it wholesale — the encrypted vault, the lock
/// metadata, everything.
class FileLockStorage implements LockStorage {
  FileLockStorage(this.dataDir);

  final Directory dataDir;

  File _file(String key) {
    if (key.contains('/') || key.contains(r'\') || key.contains('..')) {
      throw ArgumentError('unsafe storage key: $key');
    }
    return File('${dataDir.path}${Platform.pathSeparator}$key');
  }

  @override
  Future<Uint8List?> read(String key) async {
    final File file = _file(key);
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    await dataDir.create(recursive: true);
    await _file(key).writeAsBytes(value, flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final File file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> wipeAll() async {
    if (await dataDir.exists()) {
      await dataDir.delete(recursive: true);
    }
    await dataDir.create(recursive: true);
  }
}
