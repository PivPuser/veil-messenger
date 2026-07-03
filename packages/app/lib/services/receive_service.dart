import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:relay/relay.dart';

import 'chat_service.dart';

class _Pending {
  _Pending(this.preKeys);

  final PreKeys preKeys;
  bool oneTimeConsumed = false;
}

/// Responder (Чел1) side: holds the private pre-keys published in the invites
/// this device created, and accepts incoming handshakes at their rendezvous
/// mailboxes.
///
/// Enforces ONE-TIME pre-key use: once a chat has been accepted at a rendezvous,
/// a second handshake that reuses the same one-time pre-key is refused. That
/// preserves the initial-message forward secrecy an OPK provides and closes the
/// "invite replayed by a second party reusing the OPK" hole.
class ReceiveService {
  ReceiveService._();

  static final ReceiveService instance = ReceiveService._();

  final Map<String, _Pending> _pending = <String, _Pending>{};

  /// Registers the pre-keys published in an invite so handshakes arriving at
  /// [rendezvousHex] can be accepted. Called when an invite is created.
  void register(String rendezvousHex, PreKeys preKeys) {
    _pending[rendezvousHex] = _Pending(preKeys);
  }

  bool get hasPending => _pending.isNotEmpty;

  Iterable<String> get rendezvousIds => _pending.keys.toList(growable: false);

  /// Fetches [rendezvousHex] and accepts the first valid handshake, returning a
  /// ready [ChatController] (with the first message), or null if there was
  /// nothing acceptable.
  Future<ChatController?> tryAccept({
    required Identity me,
    required String rendezvousHex,
    required RelayTransport transport,
  }) async {
    final _Pending? pending = _pending[rendezvousHex];
    if (pending == null) return null;

    final List<Uint8List> envelopes = await transport.fetch(rendezvousHex);
    for (final Uint8List envelope in envelopes) {
      // After the first accept, drop the one-time key so any reuse of it is
      // rejected by acceptChat (it will see usedOneTimeKey but have no OPK).
      final PreKeys keys = pending.oneTimeConsumed
          ? PreKeys(
              signedPreKey: pending.preKeys.signedPreKey,
              signedPreKeySignature: pending.preKeys.signedPreKeySignature,
            )
          : pending.preKeys;
      try {
        final ({Session session, Uint8List firstMessage}) accepted =
            await Session.acceptChat(
          me: me,
          myPreKeys: keys,
          firstMessage: envelope,
        );
        pending.oneTimeConsumed = true;
        return ChatController(
          session: accepted.session,
          transport: transport,
          sendDir: Mailbox.responderToInitiator,
          recvDir: Mailbox.initiatorToResponder,
          initialMessages: <ChatMessage>[
            ChatMessage(
              text: utf8.decode(accepted.firstMessage),
              outgoing: false,
              time: DateTime.now(),
            ),
          ],
        );
      } catch (_) {
        // Garbage, a foreign handshake, or a rejected one-time-key reuse.
        continue;
      }
    }
    return null;
  }

  void clear() => _pending.clear();
}
