import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:test/test.dart';

/// In-memory [LockStorage] whose [wipeAll] just clears the map and records that
/// it happened, so tests can assert the panic wipe fired.
class _MemStorage implements LockStorage {
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

void main() {
  group('AppLock', () {
    test('enable then unlock with the correct password returns the same key',
        () async {
      final storage = _MemStorage();
      final lock = AppLock(storage, kdfMemory: 256, kdfIterations: 1);
      final Uint8List keyFromEnable =
          await lock.enable(password: '1234', passwordLength: 4);

      expect(await lock.isEnabled(), isTrue);
      expect(await lock.passwordLength(), 4);

      final Uint8List keyFromUnlock = await lock.unlock('1234');
      expect(keyFromUnlock, equals(keyFromEnable));
      expect(storage.wiped, isFalse);
    });

    test('one wrong password warns but does not wipe', () async {
      final storage = _MemStorage();
      final lock = AppLock(storage, kdfMemory: 256, kdfIterations: 1);
      await lock.enable(password: '123456', passwordLength: 6);

      await expectLater(
        lock.unlock('000000'),
        throwsA(isA<WrongPasswordException>()
            .having((e) => e.remainingAttempts, 'remaining', 1)),
      );
      expect(storage.wiped, isFalse);
      expect(await lock.remainingAttempts(), 1);
    });

    test('two wrong passwords wipe all data', () async {
      final storage = _MemStorage();
      final lock = AppLock(storage, kdfMemory: 256, kdfIterations: 1);
      await lock.enable(password: '1234', passwordLength: 4);

      await expectLater(
          lock.unlock('0000'), throwsA(isA<WrongPasswordException>()));
      await expectLater(
          lock.unlock('9999'), throwsA(isA<DataWipedException>()));

      expect(storage.wiped, isTrue);
      expect(await lock.isEnabled(), isFalse);
    });

    test('a correct password resets the counter', () async {
      final storage = _MemStorage();
      final lock = AppLock(storage, kdfMemory: 256, kdfIterations: 1);
      await lock.enable(password: '1234', passwordLength: 4);

      await expectLater(
          lock.unlock('0000'), throwsA(isA<WrongPasswordException>()));
      await lock.unlock('1234'); // correct -> resets
      expect(await lock.remainingAttempts(), 2);

      // A single wrong attempt now should NOT wipe (counter was reset).
      await expectLater(
          lock.unlock('0000'), throwsA(isA<WrongPasswordException>()));
      expect(storage.wiped, isFalse);
    });

    test('the attempt counter survives an app "restart"', () async {
      final storage = _MemStorage();
      await AppLock(storage, kdfMemory: 256, kdfIterations: 1).enable(password: '1234', passwordLength: 4);

      // First wrong attempt on one AppLock instance.
      await expectLater(
          AppLock(storage, kdfMemory: 256, kdfIterations: 1).unlock('0000'),
          throwsA(isA<WrongPasswordException>()));

      // A fresh AppLock over the same storage (simulating a relaunch): the
      // second wrong attempt must still trigger the wipe.
      await expectLater(
          AppLock(storage, kdfMemory: 256, kdfIterations: 1).unlock('1111'),
          throwsA(isA<DataWipedException>()));
      expect(storage.wiped, isTrue);
    });

    test('the panic button wipes immediately', () async {
      final storage = _MemStorage();
      final lock = AppLock(storage, kdfMemory: 256, kdfIterations: 1);
      await lock.enable(password: '123456789012', passwordLength: 12);

      await lock.wipe();
      expect(storage.wiped, isTrue);
    });

    test('rejects a password whose length does not match the choice', () async {
      final lock = AppLock(_MemStorage(), kdfMemory: 256, kdfIterations: 1);
      await expectLater(
        lock.enable(password: '123', passwordLength: 4),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        lock.enable(password: '1234', passwordLength: 5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('disable removes the lock', () async {
      final storage = _MemStorage();
      final lock = AppLock(storage, kdfMemory: 256, kdfIterations: 1);
      await lock.enable(password: '1234', passwordLength: 4);
      await lock.disable();
      expect(await lock.isEnabled(), isFalse);
    });
  });
}
