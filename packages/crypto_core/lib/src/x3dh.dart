import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity.dart';
import 'invite.dart';
import 'primitives.dart';

/// Extended Triple Diffie-Hellman (X3DH) key agreement.
///
/// Roles in our "keys" model:
///   * Чел1 = "Bob"   — the RESPONDER, who published the invite / pre-key bundle.
///   * Чел2 = "Alice" — the INITIATOR, who pasted the key and starts the chat.
///
/// Both sides independently derive the same 32-byte shared secret `SK`, which
/// then seeds the Double Ratchet.
class X3dh {
  X3dh._();

  static const String _info = 'AnonMsg/X3DH/v1';

  /// 32 bytes of 0xFF prepended to the DH concatenation, for domain separation
  /// (per the X3DH specification, for the Curve25519 case).
  static Uint8List get _f => Uint8List(32)..fillRange(0, 32, 0xFF);

  static Future<Uint8List> _deriveSecret(List<int> ikm) {
    return Primitives.hkdf(
      ikm: ikm,
      salt: Uint8List(32),
      info: utf8.encode(_info),
      length: 32,
    );
  }

  /// INITIATOR side (Чел2). Verifies the invite, then derives `SK` and the
  /// public values that must be sent to the responder so it can derive the
  /// same `SK`.
  static Future<InitialHandshake> initiator({
    required Identity initiator,
    required InviteKey invite,
  }) async {
    if (!await invite.verify()) {
      throw StateError(
        'Invalid invite signature — refusing X3DH handshake.',
      );
    }

    final SimpleKeyPair ephemeral = await Primitives.generateDhKeyPair();
    final SimplePublicKey spkPub =
        Primitives.dhPublicFromBytes(invite.signedPreKeyPub);
    final SimplePublicKey ikBPub =
        Primitives.dhPublicFromBytes(invite.identityDhPub);

    // DH1 = DH(IK_A, SPK_B)
    // DH2 = DH(EK_A, IK_B)
    // DH3 = DH(EK_A, SPK_B)
    // DH4 = DH(EK_A, OPK_B)   (only if a one-time pre-key is present)
    final Uint8List dh1 = await Primitives.dh(initiator.dhKeyPair, spkPub);
    final Uint8List dh2 = await Primitives.dh(ephemeral, ikBPub);
    final Uint8List dh3 = await Primitives.dh(ephemeral, spkPub);

    final BytesBuilder ikm = BytesBuilder()
      ..add(_f)
      ..add(dh1)
      ..add(dh2)
      ..add(dh3);
    if (invite.hasOneTimePreKey) {
      final SimplePublicKey opkPub =
          Primitives.dhPublicFromBytes(invite.oneTimePreKeyPub!);
      ikm.add(await Primitives.dh(ephemeral, opkPub));
    }

    final Uint8List sk = await _deriveSecret(ikm.toBytes());

    return InitialHandshake(
      identitySignPub: await initiator.signPublicBytes(),
      identityDhPub: await initiator.dhPublicBytes(),
      identityDhSignature: await initiator.dhBindingSignature(),
      ephemeralPub: await Primitives.dhPublicBytes(ephemeral),
      usedOneTimeKey: invite.hasOneTimePreKey,
      sharedSecret: sk,
    );
  }

  /// RESPONDER side (Чел1). Recomputes `SK` from the initiator's public values
  /// and the responder's own private pre-keys.
  static Future<Uint8List> responderSharedSecret({
    required Identity responder,
    required SimpleKeyPair signedPreKey,
    SimpleKeyPair? oneTimePreKey,
    required Uint8List initiatorIdentityDhPub,
    required Uint8List initiatorEphemeralPub,
    required bool usedOneTimeKey,
  }) async {
    final SimplePublicKey ikAPub =
        Primitives.dhPublicFromBytes(initiatorIdentityDhPub);
    final SimplePublicKey ekAPub =
        Primitives.dhPublicFromBytes(initiatorEphemeralPub);

    // Mirror of the initiator's DHs (arguments swapped, same shared values):
    final Uint8List dh1 = await Primitives.dh(signedPreKey, ikAPub);
    final Uint8List dh2 = await Primitives.dh(responder.dhKeyPair, ekAPub);
    final Uint8List dh3 = await Primitives.dh(signedPreKey, ekAPub);

    final BytesBuilder ikm = BytesBuilder()
      ..add(_f)
      ..add(dh1)
      ..add(dh2)
      ..add(dh3);
    if (usedOneTimeKey) {
      if (oneTimePreKey == null) {
        throw StateError(
          'Handshake used a one-time pre-key that we no longer have.',
        );
      }
      ikm.add(await Primitives.dh(oneTimePreKey, ekAPub));
    }

    return _deriveSecret(ikm.toBytes());
  }
}

/// Result of the initiator's X3DH computation.
///
/// [sharedSecret] stays local (it seeds the ratchet). Everything else is public
/// and must accompany the first encrypted message so the responder can derive
/// the same secret.
class InitialHandshake {
  InitialHandshake({
    required this.identitySignPub,
    required this.identityDhPub,
    required this.identityDhSignature,
    required this.ephemeralPub,
    required this.usedOneTimeKey,
    required this.sharedSecret,
  });

  final Uint8List identitySignPub;
  final Uint8List identityDhPub;
  final Uint8List identityDhSignature; // binds identityDhPub to identitySignPub
  final Uint8List ephemeralPub;
  final bool usedOneTimeKey;
  final Uint8List sharedSecret;
}
