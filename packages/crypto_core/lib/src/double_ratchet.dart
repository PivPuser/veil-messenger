import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'codec.dart';
import 'primitives.dart';

/// Header prepended (in the clear, but authenticated) to every ratchet message.
///
/// Fixed 40-byte layout: dhPub (32) | pn (uint32 BE) | n (uint32 BE).
class RatchetHeader {
  RatchetHeader({required this.dhPub, required this.pn, required this.n});

  final Uint8List dhPub; // sender's current ratchet public key
  final int pn; // number of messages in the previous sending chain
  final int n; // message number in the current sending chain

  static const int byteLength = 40;

  Uint8List toBytes() {
    final Uint8List out = Uint8List(byteLength);
    out.setAll(0, dhPub);
    final ByteData bd = ByteData.sublistView(out);
    bd.setUint32(32, pn, Endian.big);
    bd.setUint32(36, n, Endian.big);
    return out;
  }

  static RatchetHeader fromBytes(Uint8List bytes) {
    if (bytes.length < byteLength) {
      throw const FormatException('Ratchet header truncated.');
    }
    final ByteData bd = ByteData.sublistView(bytes);
    return RatchetHeader(
      dhPub: Uint8List.fromList(bytes.sublist(0, 32)),
      pn: bd.getUint32(32, Endian.big),
      n: bd.getUint32(36, Endian.big),
    );
  }
}

/// The Double Ratchet (Signal's algorithm), providing per-message forward
/// secrecy and post-compromise security.
///
/// Two ratchets are combined:
///   * a Diffie-Hellman ratchet that advances whenever a new peer ratchet key
///     is seen, and
///   * a symmetric-key (HMAC) ratchet for each sending/receiving chain.
///
/// Out-of-order and dropped messages are handled by caching skipped message
/// keys, bounded by [maxSkip] to prevent a denial-of-service via huge gaps.
class DoubleRatchet {
  DoubleRatchet._({
    required SimpleKeyPair dhs,
    required Uint8List dhsPub,
  })  : _dhs = dhs,
        _dhsPub = dhsPub;

  // Domain-separation labels. MUST be identical on both peers.
  static const String _rootInfo = 'AnonMsg/DR/root/v1';
  static const String _msgInfo = 'AnonMsg/DR/msg/v1';

  /// Upper bound on how many messages may be skipped (out-of-order/dropped)
  /// before we refuse, to bound memory use and prevent a DoS via huge gaps.
  static const int maxSkip = 1000;

  SimpleKeyPair _dhs; // our current ratchet key pair (DHs)
  Uint8List _dhsPub; // cached public part of _dhs
  Uint8List? _dhr; // peer's current ratchet public key (DHr)
  late Uint8List _rk; // root key (RK)
  Uint8List? _cks; // sending chain key (CKs)
  Uint8List? _ckr; // receiving chain key (CKr)
  int _ns = 0; // messages sent in current chain
  int _nr = 0; // messages received in current chain
  int _pn = 0; // messages sent in previous chain

  /// Skipped message keys, keyed by "<hex(dhPub)>:<n>".
  final Map<String, Uint8List> _skipped = <String, Uint8List>{};

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initiator side (Чел2 / Alice). She already knows the responder's signed
  /// pre-key public value, which is used as the initial DHr.
  static Future<DoubleRatchet> initAlice({
    required Uint8List sharedSecret,
    required Uint8List responderSignedPreKeyPub,
  }) async {
    final SimpleKeyPair dhs = await Primitives.generateDhKeyPair();
    final DoubleRatchet dr = DoubleRatchet._(
      dhs: dhs,
      dhsPub: await Primitives.dhPublicBytes(dhs),
    );
    dr._dhr = Uint8List.fromList(responderSignedPreKeyPub);
    final Uint8List dhOut = await Primitives.dh(
      dhs,
      Primitives.dhPublicFromBytes(responderSignedPreKeyPub),
    );
    final (Uint8List rk, Uint8List cks) = await dr._kdfRk(sharedSecret, dhOut);
    dr._rk = rk;
    dr._cks = cks;
    return dr;
  }

  /// Responder side (Чел1 / Bob). His signed pre-key KEY PAIR is the initial
  /// DHs; DHr is unknown until his first received message.
  static Future<DoubleRatchet> initBob({
    required Uint8List sharedSecret,
    required SimpleKeyPair signedPreKey,
  }) async {
    final DoubleRatchet dr = DoubleRatchet._(
      dhs: signedPreKey,
      dhsPub: await Primitives.dhPublicBytes(signedPreKey),
    );
    dr._rk = Uint8List.fromList(sharedSecret);
    return dr;
  }

  // ---------------------------------------------------------------------------
  // Serialization (persist the full ratchet state; store only inside a vault)
  // ---------------------------------------------------------------------------

  Future<Uint8List> serialize() async {
    final ByteWriter w = ByteWriter()
      ..bytes(await Primitives.dhPrivateSeed(_dhs))
      ..bytes(_dhsPub)
      ..optionalBytes(_dhr)
      ..bytes(_rk)
      ..optionalBytes(_cks)
      ..optionalBytes(_ckr)
      ..u32(_ns)
      ..u32(_nr)
      ..u32(_pn)
      ..u32(_skipped.length);
    _skipped.forEach((String k, Uint8List v) {
      w
        ..str(k)
        ..bytes(v);
    });
    return w.toBytes();
  }

  static Future<DoubleRatchet> deserialize(Uint8List data) async {
    final ByteReader r = ByteReader(data);
    final Uint8List dhsSeed = r.bytes();
    final SimpleKeyPair dhs = await Primitives.dhKeyPairFromSeed(dhsSeed);
    final DoubleRatchet dr = DoubleRatchet._(dhs: dhs, dhsPub: r.bytes());
    dr._dhr = r.optionalBytes();
    dr._rk = r.bytes();
    dr._cks = r.optionalBytes();
    dr._ckr = r.optionalBytes();
    dr._ns = r.u32();
    dr._nr = r.u32();
    dr._pn = r.u32();
    final int skippedCount = r.u32();
    for (int i = 0; i < skippedCount; i++) {
      final String key = r.str();
      dr._skipped[key] = r.bytes();
    }
    return dr;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext]; returns `header || ciphertext || tag`.
  Future<Uint8List> encrypt(List<int> plaintext) async {
    if (_cks == null) {
      throw StateError(
        'Cannot send yet: no sending chain. The responder must receive the '
        "initiator's first message before it can reply.",
      );
    }
    final (Uint8List cks, Uint8List mk) = await _kdfCk(_cks!);
    _cks = cks;

    final RatchetHeader header =
        RatchetHeader(dhPub: _dhsPub, pn: _pn, n: _ns);
    _ns += 1;

    final Uint8List headerBytes = header.toBytes();
    final (Uint8List key, Uint8List nonce) = await _messageKeys(mk);
    final Uint8List cipher = await Primitives.aeadEncrypt(
      key: key,
      nonce: nonce,
      plaintext: plaintext,
      aad: headerBytes,
    );
    return Uint8List.fromList(<int>[...headerBytes, ...cipher]);
  }

  /// Decrypts a `header || ciphertext || tag` message.
  Future<Uint8List> decrypt(Uint8List message) async {
    if (message.length < RatchetHeader.byteLength) {
      throw const FormatException('Ratchet message too short.');
    }
    final Uint8List headerBytes =
        Uint8List.fromList(message.sublist(0, RatchetHeader.byteLength));
    final Uint8List cipher =
        Uint8List.fromList(message.sublist(RatchetHeader.byteLength));
    final RatchetHeader header = RatchetHeader.fromBytes(headerBytes);

    final Uint8List? fromSkipped =
        await _trySkippedKeys(header, headerBytes, cipher);
    if (fromSkipped != null) return fromSkipped;

    if (_dhr == null || !Primitives.constantTimeEquals(header.dhPub, _dhr!)) {
      await _skipMessageKeys(header.pn); // finish the old receiving chain
      await _dhRatchet(header);
    }
    await _skipMessageKeys(header.n); // skip within the current chain

    final (Uint8List ckr, Uint8List mk) = await _kdfCk(_ckr!);
    _ckr = ckr;
    _nr += 1;

    final (Uint8List key, Uint8List nonce) = await _messageKeys(mk);
    return Primitives.aeadDecrypt(
      key: key,
      nonce: nonce,
      cipherWithTag: cipher,
      aad: headerBytes,
    );
  }

  // ---------------------------------------------------------------------------
  // Ratchet internals
  // ---------------------------------------------------------------------------

  /// Root KDF: (RK, dhOut) -> (RK', chainKey). RK is the HKDF salt.
  Future<(Uint8List, Uint8List)> _kdfRk(
    Uint8List rk,
    Uint8List dhOut,
  ) async {
    final Uint8List out = await Primitives.hkdf(
      ikm: dhOut,
      salt: rk,
      info: utf8.encode(_rootInfo),
      length: 64,
    );
    return (
      Uint8List.fromList(out.sublist(0, 32)),
      Uint8List.fromList(out.sublist(32, 64)),
    );
  }

  /// Chain KDF: CK -> (CK', messageKey), via HMAC with fixed constants.
  Future<(Uint8List, Uint8List)> _kdfCk(Uint8List ck) async {
    final Uint8List mk = await Primitives.hmacSha256(ck, const <int>[0x01]);
    final Uint8List nextCk = await Primitives.hmacSha256(ck, const <int>[0x02]);
    return (nextCk, mk);
  }

  /// Derives the AEAD key (32) + nonce (12) from a one-time message key.
  Future<(Uint8List, Uint8List)> _messageKeys(Uint8List mk) async {
    final Uint8List out = await Primitives.hkdf(
      ikm: mk,
      salt: Uint8List(32),
      info: utf8.encode(_msgInfo),
      length: 44,
    );
    return (
      Uint8List.fromList(out.sublist(0, 32)),
      Uint8List.fromList(out.sublist(32, 44)),
    );
  }

  Future<void> _dhRatchet(RatchetHeader header) async {
    _pn = _ns;
    _ns = 0;
    _nr = 0;
    _dhr = Uint8List.fromList(header.dhPub);

    Uint8List dhOut = await Primitives.dh(
      _dhs,
      Primitives.dhPublicFromBytes(_dhr!),
    );
    final (Uint8List rk1, Uint8List ckr) = await _kdfRk(_rk, dhOut);
    _rk = rk1;
    _ckr = ckr;

    _dhs = await Primitives.generateDhKeyPair();
    _dhsPub = await Primitives.dhPublicBytes(_dhs);

    dhOut = await Primitives.dh(_dhs, Primitives.dhPublicFromBytes(_dhr!));
    final (Uint8List rk2, Uint8List cks) = await _kdfRk(_rk, dhOut);
    _rk = rk2;
    _cks = cks;
  }

  Future<void> _skipMessageKeys(int until) async {
    if (_nr + maxSkip < until) {
      throw StateError(
        'Refusing to skip more than $maxSkip messages (possible DoS).',
      );
    }
    if (_ckr != null) {
      while (_nr < until) {
        final (Uint8List ckr, Uint8List mk) = await _kdfCk(_ckr!);
        _ckr = ckr;
        _skipped[_skipKey(_dhr!, _nr)] = mk;
        _nr += 1;
      }
    }
  }

  Future<Uint8List?> _trySkippedKeys(
    RatchetHeader header,
    Uint8List headerBytes,
    Uint8List cipher,
  ) async {
    final String k = _skipKey(header.dhPub, header.n);
    final Uint8List? mk = _skipped.remove(k);
    if (mk == null) return null;
    final (Uint8List key, Uint8List nonce) = await _messageKeys(mk);
    return Primitives.aeadDecrypt(
      key: key,
      nonce: nonce,
      cipherWithTag: cipher,
      aad: headerBytes,
    );
  }

  String _skipKey(Uint8List dhPub, int n) {
    final StringBuffer sb = StringBuffer();
    for (final int b in dhPub) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    sb.write(':');
    sb.write(n);
    return sb.toString();
  }
}
