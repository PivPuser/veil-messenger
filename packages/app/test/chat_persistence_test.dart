import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay/relay.dart';
import 'package:veil/services/chat_service.dart';
import 'package:veil/services/chat_store.dart';

import 'support/memory_lock_storage.dart';

void main() {
  test('a chat survives seal + restore and keeps working', () async {
    final RelayServer relay = RelayServer();
    final Uri uri = await relay.start();
    addTearDown(relay.stop);

    final Identity bob = await Identity.generate();
    final PreKeys bobPreKeys = await PreKeys.generate(bob);
    final InviteKey invite = await InviteKey.create(bob, bobPreKeys);
    final Identity alice = await Identity.generate();

    final RelayClient aliceNet = RelayClient(uri);
    final RelayClient bobNet = RelayClient(uri);
    addTearDown(() {
      aliceNet.close();
      bobNet.close();
    });

    ChatController aliceCtl = await ChatController.startFromInvite(
      me: alice,
      invite: invite,
      transport: aliceNet,
    );
    await aliceCtl.send('первое');

    final incoming = await bobNet.fetch(Mailbox.toHex(invite.rendezvousId));
    final accepted = await Session.acceptChat(
      me: bob,
      myPreKeys: bobPreKeys,
      firstMessage: incoming.single,
    );
    final ChatController bobCtl = ChatController(
      session: accepted.session,
      transport: bobNet,
      sendDir: Mailbox.responderToInitiator,
      recvDir: Mailbox.initiatorToResponder,
    );

    // Persist Alice's chat encrypted, then restore it (simulating a restart).
    final ChatStore store = ChatStore(MemoryLockStorage());
    final Uint8List masterKey = Primitives.randomBytes(32);
    await store.saveChat(
      id: 'c1',
      title: 'bob',
      controller: aliceCtl,
      masterKey: masterKey,
    );

    final List<StoredChat> restored =
        await store.loadChats(masterKey, transport: aliceNet);
    expect(restored, hasLength(1));
    expect(restored.single.title, 'bob');
    aliceCtl = restored.single.controller;
    expect(aliceCtl.messages.map((m) => m.text), contains('первое'));

    // The restored session must keep working in both directions.
    await bobCtl.send('ответ');
    await aliceCtl.poll();
    expect(
      aliceCtl.messages.where((m) => !m.outgoing).map((m) => m.text),
      contains('ответ'),
    );

    await aliceCtl.send('второе');
    await bobCtl.poll();
    expect(
      bobCtl.messages.where((m) => !m.outgoing).map((m) => m.text),
      contains('второе'),
    );
  });

  test('the wrong master key cannot open stored chats', () async {
    final MemoryLockStorage storage = MemoryLockStorage();
    final ChatStore store = ChatStore(storage);
    final Uint8List key = Primitives.randomBytes(32);

    final Identity bob = await Identity.generate();
    final PreKeys pk = await PreKeys.generate(bob);
    final InviteKey invite = await InviteKey.create(bob, pk);
    final ChatController ctl = await ChatController.startFromInvite(
      me: await Identity.generate(),
      invite: invite,
    );
    await store.saveChat(id: 'c1', title: 'x', controller: ctl, masterKey: key);

    await expectLater(
      store.loadChats(Primitives.randomBytes(32)),
      throwsA(anything),
    );
  });
}
