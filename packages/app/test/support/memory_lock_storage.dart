import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';

/// In-memory [LockStorage] for widget tests. Avoids real dart:io file I/O,
/// which does not complete under `testWidgets`' fake-async clock.
class MemoryLockStorage implements LockStorage {
  final Map<String, Uint8List> _data = <String, Uint8List>{};
  bool wiped = false;

  @override
  Future<Uint8List?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Uint8List value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> wipeAll() async {
    _data.clear();
    wiped = true;
  }
}
