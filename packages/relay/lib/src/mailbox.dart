import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';

/// Derives one-time mailbox ids from a session's shared [Session.mailboxSeed].
///
/// The point: the relay must never see a stable address that can be linked to a
/// user or that reveals two addresses belong to the same conversation. Both
/// peers can compute the same id for message `index` in a given `direction`
/// (there are two directions, one per sender), but a third party who does not
/// know the seed only sees uncorrelated 16-byte values, each used once.
class Mailbox {
  Mailbox._();

  /// Direction label for messages the initiator (Чел2) sends to the responder.
  static const String initiatorToResponder = 'a2b';

  /// Direction label for messages the responder (Чел1) sends to the initiator.
  static const String responderToInitiator = 'b2a';

  static const int _idLength = 16;

  /// Mailbox id (hex) for the `index`-th message in `direction`.
  static Future<String> id(
    Uint8List seed,
    String direction,
    int index,
  ) async {
    final Uint8List raw = await Primitives.hkdf(
      ikm: seed,
      salt: Uint8List(32),
      info: utf8.encode('AnonMsg/mailbox/$direction/$index'),
      length: _idLength,
    );
    return toHex(raw);
  }

  static String toHex(List<int> bytes) {
    final StringBuffer sb = StringBuffer();
    for (final int b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
