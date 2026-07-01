import 'dart:typed_data';

import 'primitives.dart';

/// A human-verifiable "safety number" for two identities, à la Signal.
///
/// X3DH gives implicit authentication (each side proves it holds its identity
/// key), but it cannot tell a user that the key really belongs to the human
/// they think they're talking to — that's what a man-in-the-middle exploits.
/// Both peers compute the same 60-digit number from their two identity signing
/// keys and compare it out-of-band (read it aloud, scan a QR). A mismatch means
/// someone is intercepting.
///
/// Each identity is reduced to a 30-digit fingerprint by iterated hashing (to
/// raise the cost of any second-preimage search); the two fingerprints are then
/// concatenated in a fixed order so both sides produce an identical string.
class SafetyNumber {
  SafetyNumber._();

  static const int _iterations = 5200;

  /// Computes the shared safety number from both identity signing public keys.
  static Future<String> compute({
    required Uint8List localSignPub,
    required Uint8List remoteSignPub,
  }) async {
    final String local = await _fingerprint(localSignPub);
    final String remote = await _fingerprint(remoteSignPub);
    // Order deterministically so both peers concatenate the halves identically.
    final bool localFirst = _compareBytes(localSignPub, remoteSignPub) <= 0;
    return localFirst ? '$local$remote' : '$remote$local';
  }

  /// Groups a safety number into blocks of 5 digits for display.
  static String formatForDisplay(String number) {
    final List<String> groups = <String>[];
    for (int i = 0; i < number.length; i += 5) {
      groups.add(number.substring(i, (i + 5).clamp(0, number.length)));
    }
    return groups.join(' ');
  }

  static Future<String> _fingerprint(Uint8List publicKey) async {
    Uint8List hash = Uint8List.fromList(publicKey);
    for (int i = 0; i < _iterations; i++) {
      hash = await Primitives.sha256(
        Uint8List.fromList(<int>[...hash, ...publicKey]),
      );
    }
    // 30 bytes -> six groups of five bytes -> six 5-digit chunks = 30 digits.
    final StringBuffer sb = StringBuffer();
    for (int group = 0; group < 6; group++) {
      int value = 0;
      for (int j = 0; j < 5; j++) {
        value = (value << 8) | hash[group * 5 + j];
      }
      sb.write((value % 100000).toString().padLeft(5, '0'));
    }
    return sb.toString();
  }

  static int _compareBytes(List<int> a, List<int> b) {
    final int n = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}
