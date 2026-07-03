import 'dart:io';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/services/file_lock_storage.dart';

void main() {
  test('AppLock over real files: unlock works and wipe deletes everything',
      () async {
    final Directory dir = await Directory.systemTemp.createTemp('veil_test_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final FileLockStorage storage = FileLockStorage(dir);
    final AppLock lock = AppLock(storage, kdfMemory: 256, kdfIterations: 1);

    await lock.enable(password: '1234', passwordLength: 4);
    // A stand-in for the real data vault, to prove the wipe removes it too.
    await storage.write('identity.vault', Uint8List.fromList(<int>[1, 2, 3]));
    expect(await lock.isEnabled(), isTrue);

    // Wrong once (warns), then correct (unlocks + resets).
    await expectLater(
        lock.unlock('0000'), throwsA(isA<WrongPasswordException>()));
    expect(await lock.unlock('1234'), hasLength(32));

    // Two wrong in a row -> everything is wiped.
    await expectLater(
        lock.unlock('0000'), throwsA(isA<WrongPasswordException>()));
    await expectLater(
        lock.unlock('9999'), throwsA(isA<DataWipedException>()));

    expect(await storage.read('identity.vault'), isNull);
    expect(await lock.isEnabled(), isFalse);
  });
}
