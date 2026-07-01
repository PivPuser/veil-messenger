import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'codec.dart';
import 'primitives.dart';

/// A user's long-term cryptographic identity.
///
/// There is deliberately NO phone number, e-mail or username. The identity IS
/// the key material, generated locally and never leaving the device in the
/// clear. Two long-term key pairs are held:
///
///   * [signKeyPair] (Ed25519) — the stable public identity. Signs pre-keys and
///     (later) safety numbers so a peer can detect key substitution.
///   * [dhKeyPair]   (X25519)  — used inside the X3DH key agreement.
class Identity {
  Identity({required this.signKeyPair, required this.dhKeyPair});

  final SimpleKeyPair signKeyPair; // Ed25519
  final SimpleKeyPair dhKeyPair; // X25519

  static Future<Identity> generate() async {
    return Identity(
      signKeyPair: await Primitives.generateSignKeyPair(),
      dhKeyPair: await Primitives.generateDhKeyPair(),
    );
  }

  /// Deterministic identity from two 32-byte seeds. Intended for tests and,
  /// later, for deriving both key pairs from a single backed-up recovery seed.
  static Future<Identity> fromSeeds({
    required List<int> signSeed,
    required List<int> dhSeed,
  }) async {
    return Identity(
      signKeyPair: await Primitives.signKeyPairFromSeed(signSeed),
      dhKeyPair: await Primitives.dhKeyPairFromSeed(dhSeed),
    );
  }

  Future<Uint8List> signPublicBytes() =>
      Primitives.signPublicBytes(signKeyPair);

  Future<Uint8List> dhPublicBytes() => Primitives.dhPublicBytes(dhKeyPair);

  /// Serializes the PRIVATE key material. Store only inside an encrypted vault
  /// (see [SecretVault]) — never in the clear.
  Future<Uint8List> serialize() async {
    final ByteWriter w = ByteWriter()
      ..bytes(await Primitives.signPrivateSeed(signKeyPair))
      ..bytes(await Primitives.dhPrivateSeed(dhKeyPair));
    return w.toBytes();
  }

  static Future<Identity> deserialize(Uint8List data) async {
    final ByteReader r = ByteReader(data);
    final Uint8List signSeed = r.bytes();
    final Uint8List dhSeed = r.bytes();
    return Identity.fromSeeds(signSeed: signSeed, dhSeed: dhSeed);
  }
}

/// A signed pre-key plus an optional one-time pre-key.
///
/// In our "keys" model, Чел1 (the responder, "Bob") generates these and
/// publishes their PUBLIC parts inside the invite key. The PRIVATE parts stay
/// on Чел1's device until Чел2 consumes the invite and starts the session.
///
/// The signed pre-key doubles as the responder's initial Double Ratchet public
/// key, so no extra key needs to be transmitted to bootstrap the ratchet.
class PreKeys {
  PreKeys({
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.oneTimePreKey,
  });

  final SimpleKeyPair signedPreKey; // X25519; its public part is signed
  final Uint8List signedPreKeySignature; // Ed25519 sig over SPK public bytes
  final SimpleKeyPair? oneTimePreKey; // X25519; single use, optional

  /// Generates a fresh signed pre-key (signed by [identity]'s Ed25519 key) and,
  /// by default, one one-time pre-key.
  ///
  /// NOTE: a one-time pre-key must only ever be used for a SINGLE handshake.
  /// The transport/relay layer is responsible for handing out and then
  /// discarding one-time keys; this class only generates them.
  static Future<PreKeys> generate(
    Identity identity, {
    bool withOneTimeKey = true,
  }) async {
    final SimpleKeyPair spk = await Primitives.generateDhKeyPair();
    final Uint8List spkPublic = await Primitives.dhPublicBytes(spk);
    final Uint8List signature =
        await Primitives.sign(spkPublic, identity.signKeyPair);
    return PreKeys(
      signedPreKey: spk,
      signedPreKeySignature: signature,
      oneTimePreKey:
          withOneTimeKey ? await Primitives.generateDhKeyPair() : null,
    );
  }

  /// Serializes the PRIVATE pre-key material. Store only inside a vault.
  Future<Uint8List> serialize() async {
    final ByteWriter w = ByteWriter()
      ..bytes(await Primitives.dhPrivateSeed(signedPreKey))
      ..bytes(signedPreKeySignature)
      ..optionalBytes(oneTimePreKey == null
          ? null
          : await Primitives.dhPrivateSeed(oneTimePreKey!));
    return w.toBytes();
  }

  static Future<PreKeys> deserialize(Uint8List data) async {
    final ByteReader r = ByteReader(data);
    final Uint8List spkSeed = r.bytes();
    final Uint8List signature = r.bytes();
    final Uint8List? opkSeed = r.optionalBytes();
    return PreKeys(
      signedPreKey: await Primitives.dhKeyPairFromSeed(spkSeed),
      signedPreKeySignature: signature,
      oneTimePreKey:
          opkSeed == null ? null : await Primitives.dhKeyPairFromSeed(opkSeed),
    );
  }
}
