import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/services/vault_store.dart';

import 'support/memory_lock_storage.dart';

void main() {
  test('round-trips an identity encrypted at rest', () async {
    final MemoryLockStorage storage = MemoryLockStorage();
    final VaultStore store = VaultStore(storage);
    final key = Primitives.randomBytes(32);
    final Identity id = await Identity.generate();

    await store.saveIdentity(id, key);
    expect(await store.hasIdentity(), isTrue);

    final Identity? loaded = await store.loadIdentity(key);
    expect(loaded, isNotNull);
    expect(await loaded!.signPublicBytes(), equals(await id.signPublicBytes()));
    expect(await loaded.dhPublicBytes(), equals(await id.dhPublicBytes()));
  });

  test('a wrong master key cannot open the vault', () async {
    final VaultStore store = VaultStore(MemoryLockStorage());
    await store.saveIdentity(await Identity.generate(), Primitives.randomBytes(32));

    await expectLater(
      store.loadIdentity(Primitives.randomBytes(32)),
      throwsA(anything),
    );
  });

  test('wipe removes the stored identity', () async {
    final MemoryLockStorage storage = MemoryLockStorage();
    final VaultStore store = VaultStore(storage);
    final key = Primitives.randomBytes(32);
    await store.saveIdentity(await Identity.generate(), key);

    await storage.wipeAll();

    expect(await store.hasIdentity(), isFalse);
    expect(await store.loadIdentity(key), isNull);
  });
}
