import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';

import 'vault_store.dart';

/// Holds the user's long-term [Identity].
///
/// When [configure] has supplied a [VaultStore] and master key, the identity is
/// loaded from (or created in) the encrypted vault and survives restarts. If it
/// has not been configured (e.g. in isolated widget tests), it falls back to an
/// ephemeral in-memory identity so screens still work.
///
/// On a panic wipe, call [reset] to drop the in-memory identity and master key.
class IdentityService {
  IdentityService._();

  static final IdentityService instance = IdentityService._();

  VaultStore? _store;
  Uint8List? _masterKey;
  Identity? _identity;

  void configure({required VaultStore store, required Uint8List masterKey}) {
    _store = store;
    _masterKey = masterKey;
  }

  Future<Identity> identity() async {
    final Identity? cached = _identity;
    if (cached != null) return cached;

    final VaultStore? store = _store;
    final Uint8List? key = _masterKey;
    if (store != null && key != null) {
      _identity = await store.loadIdentity(key) ?? await _createAndSave(store, key);
    } else {
      // Ephemeral fallback (tests / not-yet-configured).
      _identity = await Identity.generate();
    }
    return _identity!;
  }

  Future<Identity> _createAndSave(VaultStore store, Uint8List key) async {
    final Identity identity = await Identity.generate();
    await store.saveIdentity(identity, key);
    return identity;
  }

  /// Clears in-memory secrets (call after a wipe or on lock).
  void reset() {
    _identity = null;
    _masterKey = null;
  }
}
