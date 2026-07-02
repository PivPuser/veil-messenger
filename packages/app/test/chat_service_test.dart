import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay/relay.dart';
import 'package:veil/services/chat_service.dart';

void main() {
  test('two controllers exchange messages through a real relay', () async {
    final RelayServer relay = RelayServer();
    final Uri uri = await relay.start();
    addTearDown(relay.stop);

    // Чел1 (responder) publishes an invite.
    final Identity bob = await Identity.generate();
    final PreKeys bobPreKeys = await PreKeys.generate(bob);
    final InviteKey invite = await InviteKey.create(bob, bobPreKeys);

    // Чел2 (initiator) starts a chat from the invite.
    final Identity alice = await Identity.generate();
    final RelayClient aliceNet = RelayClient(uri);
    final RelayClient bobNet = RelayClient(uri);
    addTearDown(() {
      aliceNet.close();
      bobNet.close();
    });

    final ChatController aliceCtl = await ChatController.startFromInvite(
      me: alice,
      invite: invite,
      transport: aliceNet,
    );

    await aliceCtl.send('привет');

    // Чел1 receives the handshake from the rendezvous mailbox and accepts.
    final incoming =
        await bobNet.fetch(Mailbox.toHex(invite.rendezvousId));
    final accepted = await Session.acceptChat(
      me: bob,
      myPreKeys: bobPreKeys,
      firstMessage: incoming.single,
    );
    expect(utf8.decode(accepted.firstMessage), 'привет');

    final ChatController bobCtl = ChatController(
      session: accepted.session,
      transport: bobNet,
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

    // Bob -> Alice
    await bobCtl.send('здарова');
    // A corrupted envelope lands in the same mailbox; poll must skip it and
    // still deliver the real message.
    final String box = await Mailbox.id(
      accepted.session.mailboxSeed,
      Mailbox.responderToInitiator,
      0,
    );
    await bobNet.send(box, Uint8List.fromList(List<int>.filled(80, 0)));
    await aliceCtl.poll();
    expect(
      aliceCtl.messages.where((m) => !m.outgoing).map((m) => m.text),
      contains('здарова'),
    );

    // Alice -> Bob
    await aliceCtl.send('как сам?');
    await bobCtl.poll();
    expect(
      bobCtl.messages.where((m) => !m.outgoing).map((m) => m.text),
      contains('как сам?'),
    );
  });
}
