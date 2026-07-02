import 'dart:convert';
import 'dart:typed_data';

import 'codec.dart';
import 'double_ratchet.dart';
import 'identity.dart';
import 'invite.dart';
import 'primitives.dart';
import 'x3dh.dart';

/// A high-level end-to-end encrypted 1:1 session.
///
/// Ties together X3DH (initial key agreement) and the Double Ratchet (ongoing
/// message encryption) and handles the small amount of framing needed so the
/// responder can bootstrap from the initiator's very first message.
///
/// Wire framing produced by [encrypt]:
///   type (1) | [initial handshake preamble] | ratchet message
///     type 0x01 = initial   : preamble = identitySignPub(32) identityDhPub(32)
///                             ephemeralPub(32) identityDhSignature(64) flags(1)
///     type 0x02 = subsequent : no preamble
class Session {
  Session._(this._ratchet, this._pendingHandshake, this.mailboxSeed);

  static const int _typeInitial = 0x01;
  static const int _typeNormal = 0x02;
  static const int _preambleLength = 32 + 32 + 32 + 64 + 1;

  final DoubleRatchet _ratchet;
  InitialHandshake? _pendingHandshake; // non-null until the first message sent

  /// A 32-byte secret, identical on both peers, derived from the X3DH secret.
  /// The transport layer uses it to derive unlinkable one-time mailbox ids so
  /// the relay never sees a stable address tied to an identity. It is NOT the
  /// ratchet seed and cannot be used to decrypt messages.
  final Uint8List mailboxSeed;

  static Future<Uint8List> _deriveMailboxSeed(List<int> sharedSecret) {
    return Primitives.hkdf(
      ikm: sharedSecret,
      salt: Uint8List(32),
      info: utf8.encode('AnonMsg/mailbox-root/v1'),
      length: 32,
    );
  }

  /// INITIATOR (Чел2): pastes [invite] and starts a chat with Чел1.
  /// The returned session's first [encrypt] output carries the handshake.
  static Future<Session> startChat({
    required Identity me,
    required InviteKey invite,
  }) async {
    final InitialHandshake hs =
        await X3dh.initiator(initiator: me, invite: invite);
    final DoubleRatchet ratchet = await DoubleRatchet.initAlice(
      sharedSecret: hs.sharedSecret,
      responderSignedPreKeyPub: invite.signedPreKeyPub,
    );
    return Session._(ratchet, hs, await _deriveMailboxSeed(hs.sharedSecret));
  }

  /// RESPONDER (Чел1): accepts an incoming first message that a peer produced
  /// via [startChat]. Returns the established session AND the decrypted first
  /// plaintext.
  ///
  /// [myPreKeys] MUST be the same pre-keys that were published in the invite
  /// the initiator used. The relay layer is responsible for looking up which
  /// pre-keys (especially which one-time key) correspond to this handshake.
  static Future<({Session session, Uint8List firstMessage})> acceptChat({
    required Identity me,
    required PreKeys myPreKeys,
    required Uint8List firstMessage,
  }) async {
    if (firstMessage.isEmpty || firstMessage[0] != _typeInitial) {
      throw const FormatException('Expected an initial handshake message.');
    }
    if (firstMessage.length < 1 + _preambleLength) {
      throw const FormatException('Initial message truncated.');
    }

    int offset = 1;
    Uint8List take(int n) {
      final Uint8List slice =
          Uint8List.fromList(firstMessage.sublist(offset, offset + n));
      offset += n;
      return slice;
    }

    final Uint8List initiatorSignPub = take(32);
    final Uint8List initiatorDhPub = take(32);
    final Uint8List initiatorEphemeralPub = take(32);
    final Uint8List initiatorDhSignature = take(64);
    final bool usedOneTimeKey = firstMessage[offset] == 1;
    offset += 1;
    final Uint8List ratchetBody = Uint8List.fromList(firstMessage.sublist(offset));

    // Bind the initiator's Ed25519 identity to the X25519 key used below, so
    // authenticating the identity (safety number) authenticates the channel.
    if (!await Identity.verifyDhBinding(
      signPub: initiatorSignPub,
      dhPub: initiatorDhPub,
      signature: initiatorDhSignature,
    )) {
      throw StateError('Initiator identity binding is invalid — refusing.');
    }

    final Uint8List sharedSecret = await X3dh.responderSharedSecret(
      responder: me,
      signedPreKey: myPreKeys.signedPreKey,
      oneTimePreKey: usedOneTimeKey ? myPreKeys.oneTimePreKey : null,
      initiatorIdentityDhPub: initiatorDhPub,
      initiatorEphemeralPub: initiatorEphemeralPub,
      usedOneTimeKey: usedOneTimeKey,
    );

    final DoubleRatchet ratchet = await DoubleRatchet.initBob(
      sharedSecret: sharedSecret,
      signedPreKey: myPreKeys.signedPreKey,
    );

    final Session session =
        Session._(ratchet, null, await _deriveMailboxSeed(sharedSecret));
    final Uint8List plaintext = await ratchet.decrypt(ratchetBody);
    return (session: session, firstMessage: plaintext);
  }

  /// Encrypts an outgoing message.
  Future<Uint8List> encrypt(List<int> plaintext) async {
    final Uint8List body = await _ratchet.encrypt(plaintext);
    final InitialHandshake? hs = _pendingHandshake;
    if (hs != null) {
      _pendingHandshake = null;
      final BytesBuilder b = BytesBuilder()
        ..addByte(_typeInitial)
        ..add(hs.identitySignPub)
        ..add(hs.identityDhPub)
        ..add(hs.ephemeralPub)
        ..add(hs.identityDhSignature)
        ..addByte(hs.usedOneTimeKey ? 1 : 0)
        ..add(body);
      return b.toBytes();
    }
    return Uint8List.fromList(<int>[_typeNormal, ...body]);
  }

  /// Decrypts an incoming message (any type after the first handshake).
  Future<Uint8List> decrypt(Uint8List message) async {
    if (message.isEmpty) {
      throw const FormatException('Empty message.');
    }
    final int type = message[0];
    switch (type) {
      case _typeNormal:
        return _ratchet.decrypt(Uint8List.fromList(message.sublist(1)));
      case _typeInitial:
        if (message.length < 1 + _preambleLength) {
          throw const FormatException('Initial message truncated.');
        }
        final Uint8List body =
            Uint8List.fromList(message.sublist(1 + _preambleLength));
        return _ratchet.decrypt(body);
      default:
        throw FormatException('Unknown message type: $type.');
    }
  }

  /// Serializes the full session (ratchet state, mailbox seed, and any not-yet
  /// sent handshake). Contains secrets — store only inside a [SecretVault].
  Future<Uint8List> serialize() async {
    final ByteWriter w = ByteWriter()
      ..bytes(mailboxSeed)
      ..bytes(await _ratchet.serialize());
    final InitialHandshake? hs = _pendingHandshake;
    if (hs == null) {
      w.boolean(false);
    } else {
      w
        ..boolean(true)
        ..bytes(hs.identitySignPub)
        ..bytes(hs.identityDhPub)
        ..bytes(hs.identityDhSignature)
        ..bytes(hs.ephemeralPub)
        ..boolean(hs.usedOneTimeKey)
        ..bytes(hs.sharedSecret);
    }
    return w.toBytes();
  }

  static Future<Session> deserialize(Uint8List data) async {
    final ByteReader r = ByteReader(data);
    final Uint8List seed = r.bytes();
    final DoubleRatchet ratchet = await DoubleRatchet.deserialize(r.bytes());
    InitialHandshake? hs;
    if (r.boolean()) {
      hs = InitialHandshake(
        identitySignPub: r.bytes(),
        identityDhPub: r.bytes(),
        identityDhSignature: r.bytes(),
        ephemeralPub: r.bytes(),
        usedOneTimeKey: r.boolean(),
        sharedSecret: r.bytes(),
      );
    }
    return Session._(ratchet, hs, seed);
  }
}
