// Named parameters can't be backed by private-field initializing formals
// (`this._x`), so we assign in the initializer list on purpose.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/foundation.dart';
import 'package:relay/relay.dart';

/// One message in a conversation.
class ChatMessage {
  ChatMessage({
    required this.text,
    required this.outgoing,
    required this.time,
  });

  final String text;
  final bool outgoing;
  final DateTime time;
}

/// Drives one 1:1 conversation: encrypts/decrypts with the [Session] and moves
/// envelopes through the relay using unlinkable one-time mailboxes.
///
/// This is the app-level mirror of the CLI demo's peer logic. It is transport-
/// agnostic: pass a [RelayTransport] (direct or Tor) to talk to a relay, or
/// null to run offline (messages are encrypted and shown but not delivered).
class ChatController extends ChangeNotifier {
  ChatController({
    required Session session,
    required String sendDir,
    required String recvDir,
    RelayTransport? transport,
    String? rendezvousId,
    List<ChatMessage>? initialMessages,
  })  : _session = session,
        _sendDir = sendDir,
        _recvDir = recvDir,
        _transport = transport,
        _rendezvousId = rendezvousId,
        messages = initialMessages ?? <ChatMessage>[];

  /// Builds the initiator (Чел2) side from a decoded invite. The first message
  /// carries the X3DH handshake and goes to the invite's rendezvous mailbox.
  static Future<ChatController> startFromInvite({
    required Identity me,
    required InviteKey invite,
    RelayTransport? transport,
  }) async {
    final Session session = await Session.startChat(me: me, invite: invite);
    return ChatController(
      session: session,
      transport: transport,
      sendDir: Mailbox.initiatorToResponder,
      recvDir: Mailbox.responderToInitiator,
      rendezvousId: Mailbox.toHex(invite.rendezvousId),
    );
  }

  final Session _session;
  final String _sendDir;
  final String _recvDir;
  final RelayTransport? _transport;
  String? _rendezvousId; // consumed by the initiator's first (handshake) send
  int _sendIndex = 0;
  int _recvIndex = 0;

  final List<ChatMessage> messages;

  bool get hasTransport => _transport != null;

  /// Encrypts and shows [text], then delivers it if a transport is configured.
  Future<void> send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final envelope = await _session.encrypt(utf8.encode(trimmed));
    messages.add(
      ChatMessage(text: trimmed, outgoing: true, time: DateTime.now()),
    );
    notifyListeners();

    final RelayTransport? transport = _transport;
    if (transport == null) return;

    final String mailbox;
    if (_rendezvousId != null) {
      mailbox = _rendezvousId!;
      _rendezvousId = null;
    } else {
      mailbox = await Mailbox.id(_session.mailboxSeed, _sendDir, _sendIndex++);
    }
    await transport.send(mailbox, envelope);
  }

  /// Fetches the next expected incoming mailbox and decrypts anything waiting.
  Future<void> poll() async {
    final RelayTransport? transport = _transport;
    if (transport == null) return;

    final String mailbox =
        await Mailbox.id(_session.mailboxSeed, _recvDir, _recvIndex);
    final envelopes = await transport.fetch(mailbox);
    bool changed = false;
    for (final envelope in envelopes) {
      try {
        final String text = utf8.decode(await _session.decrypt(envelope));
        _recvIndex++;
        messages.add(
          ChatMessage(text: text, outgoing: false, time: DateTime.now()),
        );
        changed = true;
      } catch (_) {
        // Skip a corrupted / undeliverable envelope. Decryption rolls the
        // ratchet back on failure, so this cannot desync the session.
      }
    }
    if (changed) notifyListeners();
  }

  /// Serializes the whole conversation (session ratchet state, mailbox
  /// counters, and message history). Contains secrets — persist only sealed
  /// (see [ChatStore]). The transport is NOT serialized; supply it on restore.
  Future<Map<String, dynamic>> toJson() async {
    return <String, dynamic>{
      'session': base64.encode(await _session.serialize()),
      'sendDir': _sendDir,
      'recvDir': _recvDir,
      'sendIndex': _sendIndex,
      'recvIndex': _recvIndex,
      'rendezvousId': _rendezvousId,
      'messages': <Map<String, dynamic>>[
        for (final ChatMessage m in messages)
          <String, dynamic>{
            't': m.text,
            'o': m.outgoing,
            'ms': m.time.millisecondsSinceEpoch,
          },
      ],
    };
  }

  static Future<ChatController> fromJson(
    Map<String, dynamic> json, {
    RelayTransport? transport,
  }) async {
    final Session session =
        await Session.deserialize(base64.decode(json['session'] as String));
    final ChatController controller = ChatController(
      session: session,
      transport: transport,
      sendDir: json['sendDir'] as String,
      recvDir: json['recvDir'] as String,
      rendezvousId: json['rendezvousId'] as String?,
      initialMessages: <ChatMessage>[
        for (final dynamic m in json['messages'] as List<dynamic>)
          ChatMessage(
            text: m['t'] as String,
            outgoing: m['o'] as bool,
            time: DateTime.fromMillisecondsSinceEpoch(m['ms'] as int),
          ),
      ],
    );
    controller._sendIndex = json['sendIndex'] as int;
    controller._recvIndex = json['recvIndex'] as int;
    return controller;
  }
}
