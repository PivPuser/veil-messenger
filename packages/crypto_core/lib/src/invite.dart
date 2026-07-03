import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'identity.dart';
import 'primitives.dart';

/// The shareable "key" of the app — a contact invitation.
///
/// This is what Чел1 creates and hands to Чел2. It carries only PUBLIC data:
///   * Чел1's identity signing key (Ed25519)
///   * Чел1's identity DH key      (X25519)
///   * a signed pre-key            (X25519, signature by the identity key)
///   * a rendezvous id             (16 bytes) — the mailbox where Чел1 listens
///     for the first (handshake) message
///   * optionally, a one-time pre-key (X25519)
///
/// Wire form (bytes), then base64url with an `amk1:` prefix:
///
///   magic "AMK" (3) | version (1) | identitySignPub (32) | identityDhPub (32)
///   | signedPreKeyPub (32) | signedPreKeySignature (64)
///   | identityDhSignature (64) | rendezvousId (16)
///   | flags (1) [ | oneTimePreKeyPub (32) ] | checksum (4)
///
/// The checksum is the first 4 bytes of SHA-256 over everything before it. It
/// only guards against typos/truncation — integrity of the crypto material is
/// enforced by verifying the signatures ([verify]), NOT by the checksum.
class InviteKey {
  InviteKey({
    required this.identitySignPub,
    required this.identityDhPub,
    required this.signedPreKeyPub,
    required this.signedPreKeySignature,
    required this.identityDhSignature,
    required this.rendezvousId,
    required this.expiresAtMillis,
    this.oneTimePreKeyPub,
  });

  static const List<int> _magic = <int>[0x41, 0x4d, 0x4b]; // "AMK"
  static const int version = 1;
  static const String prefix = 'amk1:';
  static const int rendezvousLength = 16;
  static const int _checksumLength = 4;

  final Uint8List identitySignPub; // 32
  final Uint8List identityDhPub; // 32
  final Uint8List signedPreKeyPub; // 32
  final Uint8List signedPreKeySignature; // 64
  final Uint8List identityDhSignature; // 64 — binds identityDhPub + expiry
  final Uint8List rendezvousId; // 16
  final int expiresAtMillis; // millis since epoch; 0 = never expires
  final Uint8List? oneTimePreKeyPub; // 32 or null

  bool get hasOneTimePreKey => oneTimePreKeyPub != null;

  /// True if the invite has an expiry in the past.
  bool get isExpired =>
      expiresAtMillis != 0 &&
      DateTime.now().millisecondsSinceEpoch > expiresAtMillis;

  /// Builds an invite from a local identity and freshly generated pre-keys.
  /// A random [rendezvousId] is generated unless one is supplied. The invite
  /// expires after [validity] (pass [Duration.zero] for a non-expiring invite).
  static Future<InviteKey> create(
    Identity identity,
    PreKeys preKeys, {
    Uint8List? rendezvousId,
    Duration validity = const Duration(days: 7),
  }) async {
    final int expiresAtMillis = validity == Duration.zero
        ? 0
        : DateTime.now().add(validity).millisecondsSinceEpoch;
    return InviteKey(
      identitySignPub: await identity.signPublicBytes(),
      identityDhPub: await identity.dhPublicBytes(),
      signedPreKeyPub: await Primitives.dhPublicBytes(preKeys.signedPreKey),
      signedPreKeySignature: preKeys.signedPreKeySignature,
      identityDhSignature:
          await identity.inviteBindingSignature(expiresAtMillis),
      rendezvousId: rendezvousId ?? _randomBytes(rendezvousLength),
      expiresAtMillis: expiresAtMillis,
      oneTimePreKeyPub: preKeys.oneTimePreKey == null
          ? null
          : await Primitives.dhPublicBytes(preKeys.oneTimePreKey!),
    );
  }

  /// Serializes to the shareable `amk1:...` string.
  Future<String> encode() async {
    final BytesBuilder body = BytesBuilder();
    body.add(_magic);
    body.addByte(version);
    body.add(identitySignPub);
    body.add(identityDhPub);
    body.add(signedPreKeyPub);
    body.add(signedPreKeySignature);
    body.add(identityDhSignature);
    body.add(rendezvousId);
    final ByteData exp = ByteData(8)..setUint64(0, expiresAtMillis, Endian.big);
    body.add(exp.buffer.asUint8List());
    body.addByte(hasOneTimePreKey ? 1 : 0);
    if (hasOneTimePreKey) body.add(oneTimePreKeyPub!);

    final Uint8List bytes = body.toBytes();
    final Uint8List checksum =
        (await Primitives.sha256(bytes)).sublist(0, _checksumLength);
    final Uint8List full = Uint8List.fromList(<int>[...bytes, ...checksum]);
    return prefix + base64Url.encode(full).replaceAll('=', '');
  }

  /// Parses an `amk1:...` string. Throws [FormatException] on any problem.
  ///
  /// This verifies the framing and checksum only. Callers MUST additionally
  /// call [verifySignedPreKey] (the handshake does this automatically).
  static Future<InviteKey> decode(String key) async {
    final String trimmed = key.trim();
    if (!trimmed.startsWith(prefix)) {
      throw const FormatException('Not an invite key (missing "amk1:" prefix).');
    }
    String b64 = trimmed.substring(prefix.length);
    b64 = b64.padRight((b64.length + 3) & ~3, '='); // restore padding
    final Uint8List full;
    try {
      full = base64Url.decode(b64);
    } on FormatException {
      throw const FormatException('Invite key is not valid base64url.');
    }

    const int minLen = 3 +
        1 +
        32 +
        32 +
        32 +
        64 +
        64 +
        rendezvousLength +
        8 +
        1 +
        _checksumLength; // no one-time key
    if (full.length < minLen) {
      throw const FormatException('Invite key too short / corrupted.');
    }

    final Uint8List bytes = full.sublist(0, full.length - _checksumLength);
    final Uint8List checksum = full.sublist(full.length - _checksumLength);
    final Uint8List expected =
        (await Primitives.sha256(bytes)).sublist(0, _checksumLength);
    if (!Primitives.constantTimeEquals(checksum, expected)) {
      throw const FormatException('Invite key checksum mismatch (typo?).');
    }

    int offset = 0;
    Uint8List take(int n) {
      if (offset + n > bytes.length) {
        throw const FormatException('Invite key truncated.');
      }
      final Uint8List slice =
          Uint8List.fromList(bytes.sublist(offset, offset + n));
      offset += n;
      return slice;
    }

    final Uint8List magic = take(3);
    if (magic[0] != _magic[0] ||
        magic[1] != _magic[1] ||
        magic[2] != _magic[2]) {
      throw const FormatException('Bad invite magic bytes.');
    }
    final int ver = take(1)[0];
    if (ver != version) {
      throw FormatException('Unsupported invite version: $ver.');
    }
    final Uint8List signPub = take(32);
    final Uint8List dhPub = take(32);
    final Uint8List spkPub = take(32);
    final Uint8List spkSig = take(64);
    final Uint8List idDhSig = take(64);
    final Uint8List rendezvous = take(rendezvousLength);
    final int expiresAtMillis =
        ByteData.sublistView(take(8)).getUint64(0, Endian.big);
    final bool hasOpk = take(1)[0] == 1;
    final Uint8List? opk = hasOpk ? take(32) : null;

    return InviteKey(
      identitySignPub: signPub,
      identityDhPub: dhPub,
      signedPreKeyPub: spkPub,
      signedPreKeySignature: spkSig,
      identityDhSignature: idDhSig,
      rendezvousId: rendezvous,
      expiresAtMillis: expiresAtMillis,
      oneTimePreKeyPub: opk,
    );
  }

  /// Verifies that the signed pre-key was really signed by the identity key.
  Future<bool> verifySignedPreKey() {
    return Primitives.verify(
      signedPreKeyPub,
      signedPreKeySignature,
      Primitives.signPublicFromBytes(identitySignPub),
    );
  }

  /// Verifies that the identity DH key and the expiry are bound to the identity
  /// signing key (so neither can be swapped or the expiry extended).
  Future<bool> verifyIdentityBinding() {
    return Identity.verifyInviteBinding(
      signPub: identitySignPub,
      dhPub: identityDhPub,
      expiresAtMillis: expiresAtMillis,
      signature: identityDhSignature,
    );
  }

  /// Full validation of the invite: both signatures AND not expired. A failure
  /// means the invite is forged, tampered or stale — refuse it. The handshake
  /// calls this automatically.
  Future<bool> verify() async =>
      !isExpired &&
      await verifySignedPreKey() &&
      await verifyIdentityBinding();

  static Uint8List _randomBytes(int n) {
    final Random rng = Random.secure();
    final Uint8List out = Uint8List(n);
    for (int i = 0; i < n; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }
}
