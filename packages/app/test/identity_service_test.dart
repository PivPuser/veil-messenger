import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil/services/identity_service.dart';
import 'package:veil/services/vault_store.dart';

import 'support/memory_lock_storage.dart';

void main() {
  test('configured identity persists across a simulated restart', () async {
    final VaultStore store = VaultStore(MemoryLockStorage());
    final key = Primitives.randomBytes(32);

    IdentityService.instance.reset();
    IdentityService.instance.configure(store: store, masterKey: key);
    final Identity first = await IdentityService.instance.identity();

    // "Restart": drop memory, reconfigure with the same store + key.
    IdentityService.instance.reset();
    IdentityService.instance.configure(store: store, masterKey: key);
    final Identity again = await IdentityService.instance.identity();

    expect(await again.signPublicBytes(),
        equals(await first.signPublicBytes()));
  });

  test('reset clears the in-memory identity', () async {
    IdentityService.instance.reset(); // ephemeral fallback (not configured)
    final Identity first = await IdentityService.instance.identity();

    IdentityService.instance.reset();
    final Identity second = await IdentityService.instance.identity();

    expect(await second.signPublicBytes(),
        isNot(equals(await first.signPublicBytes())));
  });
}
