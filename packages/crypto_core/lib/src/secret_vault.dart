import 'dart:convert';
import 'dart:typed_data';

import 'primitives.dart';

/// Encrypts blobs at rest under a 32-byte master key (AEAD: ChaCha20-Poly1305).
///
/// This is the portable part of on-device key storage. The master key itself
/// should live in the platform keystore (Android Keystore / iOS Keychain) via
/// the Flutter layer, or be derived from a user passphrase with [deriveKey].
/// Serialized [Identity]/[Session] material must ONLY ever be persisted through
/// this vault, never in the clear.
///
/// Blob layout: version (1) | nonce (12) | ciphertext+tag.
class SecretVault {
  SecretVault._();

  static const int _version = 1;
  static const int _nonceLength = 12;
  static const List<int> _aad = <int>[_version];

  static Future<Uint8List> seal({
    required Uint8List masterKey,
    required List<int> plaintext,
  }) async {
    _requireKey(masterKey);
    final Uint8List nonce = Primitives.randomBytes(_nonceLength);
    final Uint8List cipher = await Primitives.aeadEncrypt(
      key: masterKey,
      nonce: nonce,
      plaintext: plaintext,
      aad: _aad,
    );
    return Uint8List.fromList(<int>[_version, ...nonce, ...cipher]);
  }

  /// Decrypts a sealed blob. Throws if the key is wrong or the blob is tampered.
  static Future<Uint8List> open({
    required Uint8List masterKey,
    required Uint8List blob,
  }) async {
    _requireKey(masterKey);
    if (blob.isEmpty || blob[0] != _version) {
      throw const FormatException('Unsupported or missing vault version.');
    }
    if (blob.length < 1 + _nonceLength + Primitives.aeadTagLength) {
      throw const FormatException('Vault blob too short.');
    }
    final List<int> nonce = blob.sublist(1, 1 + _nonceLength);
    final List<int> cipher = blob.sublist(1 + _nonceLength);
    return Primitives.aeadDecrypt(
      key: masterKey,
      nonce: nonce,
      cipherWithTag: cipher,
      aad: _aad,
    );
  }

  /// Derives a 32-byte master key from a passphrase and salt. Persist the salt
  /// (it is not secret) alongside the vault so the key can be re-derived.
  static Future<Uint8List> deriveKey({
    required String passphrase,
    required Uint8List salt,
    int iterations = 210000,
  }) {
    return Primitives.pbkdf2(
      password: utf8.encode(passphrase),
      salt: salt,
      iterations: iterations,
      bits: 256,
    );
  }

  /// Derives a 32-byte master key from a passphrase with Argon2id (memory-hard).
  /// Preferred over [deriveKey] for low-entropy PINs. On mobile, add
  /// `cryptography_flutter` so this runs natively at production memory sizes.
  static Future<Uint8List> deriveKeyArgon2id({
    required String passphrase,
    required Uint8List salt,
    int memory = 19456,
    int iterations = 2,
    int parallelism = 1,
  }) {
    return Primitives.argon2id(
      password: utf8.encode(passphrase),
      salt: salt,
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      bits: 256,
    );
  }

  /// A fresh random salt for [deriveKey].
  static Uint8List newSalt() => Primitives.randomBytes(16);

  static void _requireKey(Uint8List masterKey) {
    if (masterKey.length != 32) {
      throw ArgumentError('master key must be 32 bytes');
    }
  }
}
