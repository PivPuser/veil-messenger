import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Low-level cryptographic primitives used by the protocol layer.
///
/// This module intentionally wraps a vetted library (`package:cryptography`)
/// rather than implementing any primitive by hand. Do NOT replace these with
/// custom implementations — that is the single most common way privacy apps
/// get silently broken.
///
/// Primitives used:
///   * X25519               — Diffie-Hellman key agreement
///   * Ed25519              — digital signatures
///   * HKDF-SHA256          — key derivation
///   * HMAC-SHA256          — symmetric chain ratchet
///   * ChaCha20-Poly1305    — authenticated encryption (AEAD)
class Primitives {
  Primitives._();

  static final X25519 _x25519 = X25519();
  static final Ed25519 _ed25519 = Ed25519();
  static final Chacha20 _aead = Chacha20.poly1305Aead();

  /// AEAD authentication tag length in bytes (Poly1305).
  static const int aeadTagLength = 16;

  // ---------------------------------------------------------------------------
  // X25519 (Diffie-Hellman)
  // ---------------------------------------------------------------------------

  static Future<SimpleKeyPair> generateDhKeyPair() => _x25519.newKeyPair();

  /// Deterministic X25519 key pair from a 32-byte seed (tests / key backup).
  static Future<SimpleKeyPair> dhKeyPairFromSeed(List<int> seed) =>
      _x25519.newKeyPairFromSeed(seed);

  static Future<Uint8List> dhPublicBytes(SimpleKeyPair keyPair) async {
    final SimplePublicKey pk = await keyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  static SimplePublicKey dhPublicFromBytes(List<int> bytes) =>
      SimplePublicKey(List<int>.from(bytes), type: KeyPairType.x25519);

  /// The 32-byte private seed of an X25519 key pair (for serialization/backup).
  static Future<Uint8List> dhPrivateSeed(SimpleKeyPair keyPair) async {
    final SimpleKeyPairData data = await keyPair.extract();
    return Uint8List.fromList(data.bytes);
  }

  /// Raw Diffie-Hellman. Returns the 32-byte shared secret.
  static Future<Uint8List> dh(
    SimpleKeyPair ours,
    SimplePublicKey theirs,
  ) async {
    final SecretKey secret = await _x25519.sharedSecretKey(
      keyPair: ours,
      remotePublicKey: theirs,
    );
    return Uint8List.fromList(await secret.extractBytes());
  }

  // ---------------------------------------------------------------------------
  // Ed25519 (signatures)
  // ---------------------------------------------------------------------------

  static Future<SimpleKeyPair> generateSignKeyPair() => _ed25519.newKeyPair();

  static Future<SimpleKeyPair> signKeyPairFromSeed(List<int> seed) =>
      _ed25519.newKeyPairFromSeed(seed);

  static Future<Uint8List> signPublicBytes(SimpleKeyPair keyPair) async {
    final SimplePublicKey pk = await keyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  static SimplePublicKey signPublicFromBytes(List<int> bytes) =>
      SimplePublicKey(List<int>.from(bytes), type: KeyPairType.ed25519);

  /// The 32-byte private seed of an Ed25519 key pair (for serialization/backup).
  static Future<Uint8List> signPrivateSeed(SimpleKeyPair keyPair) async {
    final SimpleKeyPairData data = await keyPair.extract();
    return Uint8List.fromList(data.bytes);
  }

  static Future<Uint8List> sign(
    List<int> message,
    SimpleKeyPair keyPair,
  ) async {
    final Signature sig = await _ed25519.sign(message, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  static Future<bool> verify(
    List<int> message,
    List<int> signature,
    SimplePublicKey signer,
  ) {
    return _ed25519.verify(
      message,
      signature: Signature(signature, publicKey: signer),
    );
  }

  // ---------------------------------------------------------------------------
  // Key derivation
  // ---------------------------------------------------------------------------

  /// HKDF-SHA256. [salt] may be empty; [length] is the output size in bytes.
  static Future<Uint8List> hkdf({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) async {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: length);
    final SecretKey out = await hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: info,
    );
    return Uint8List.fromList(await out.extractBytes());
  }

  /// PBKDF2-HMAC-SHA256 — derives a key from a low-entropy passphrase.
  ///
  /// Used to protect the on-device key vault. A memory-hard KDF (Argon2id) is
  /// preferable and should replace this before release; PBKDF2 with a high
  /// iteration count is a reasonable, widely-available interim choice.
  static Future<Uint8List> pbkdf2({
    required List<int> password,
    required List<int> salt,
    int iterations = 210000,
    int bits = 256,
  }) async {
    final Pbkdf2 kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: bits,
    );
    final SecretKey key = await kdf.deriveKey(
      secretKey: SecretKey(password),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// HMAC-SHA256, used for the symmetric-key ratchet.
  static Future<Uint8List> hmacSha256(List<int> key, List<int> data) async {
    final Mac mac = await Hmac.sha256().calculateMac(
      data,
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(mac.bytes);
  }

  static Future<Uint8List> sha256(List<int> data) async {
    final Hash hash = await Sha256().hash(data);
    return Uint8List.fromList(hash.bytes);
  }

  // ---------------------------------------------------------------------------
  // AEAD (ChaCha20-Poly1305, 12-byte nonce)
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext]; returns `ciphertext || tag` (tag is 16 bytes).
  static Future<Uint8List> aeadEncrypt({
    required List<int> key,
    required List<int> nonce,
    required List<int> plaintext,
    required List<int> aad,
  }) async {
    final SecretBox box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final Uint8List out = Uint8List(box.cipherText.length + box.mac.bytes.length);
    out.setAll(0, box.cipherText);
    out.setAll(box.cipherText.length, box.mac.bytes);
    return out;
  }

  /// Decrypts `ciphertext || tag`. Throws if authentication fails.
  static Future<Uint8List> aeadDecrypt({
    required List<int> key,
    required List<int> nonce,
    required List<int> cipherWithTag,
    required List<int> aad,
  }) async {
    if (cipherWithTag.length < aeadTagLength) {
      throw const FormatException('Ciphertext shorter than the auth tag.');
    }
    final int split = cipherWithTag.length - aeadTagLength;
    final List<int> cipher = cipherWithTag.sublist(0, split);
    final List<int> tag = cipherWithTag.sublist(split);
    final List<int> clear = await _aead.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Cryptographically secure random bytes.
  static Uint8List randomBytes(int n) {
    final Random rng = Random.secure();
    final Uint8List out = Uint8List(n);
    for (int i = 0; i < n; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  /// Constant-time byte comparison (avoids timing side-channels on secrets).
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
