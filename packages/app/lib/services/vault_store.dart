import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';

/// Persists the user's [Identity] encrypted at rest.
///
/// The identity is serialized and sealed with [SecretVault] under a 32-byte
/// master key, then written through a [LockStorage] (the same directory the
/// panic wipe clears). At-rest protection is only as strong as the master key:
/// with the passcode lock on, the key is derived from the passcode; without it,
/// see the note in the vault wiring (a keystore-backed key is the H2 follow-up).
class VaultStore {
  VaultStore(this._storage);

  final LockStorage _storage;

  static const String _identityKey = 'identity.vault';

  Future<bool> hasIdentity() async =>
      (await _storage.read(_identityKey)) != null;

  Future<void> saveIdentity(Identity identity, Uint8List masterKey) async {
    final Uint8List sealed = await SecretVault.seal(
      masterKey: masterKey,
      plaintext: await identity.serialize(),
    );
    await _storage.write(_identityKey, sealed);
  }

  /// Loads the stored identity, or null if none exists. Throws if [masterKey]
  /// is wrong (AEAD authentication failure).
  Future<Identity?> loadIdentity(Uint8List masterKey) async {
    final Uint8List? blob = await _storage.read(_identityKey);
    if (blob == null) return null;
    final Uint8List opened =
        await SecretVault.open(masterKey: masterKey, blob: blob);
    return Identity.deserialize(opened);
  }
}
