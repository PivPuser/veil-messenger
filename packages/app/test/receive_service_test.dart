import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay/relay.dart';
import 'package:veil/services/chat_service.dart';
import 'package:veil/services/receive_service.dart';

void main() {
  test('responder accepts an incoming chat and can reply', () async {
    final RelayServer relay = RelayServer();
    final Uri uri = await relay.start();
    addTearDown(relay.stop);

    final Identity bob = await Identity.generate();
    final PreKeys bobPreKeys = await PreKeys.generate(bob);
    final InviteKey invite = await InviteKey.create(bob, bobPreKeys);
    final String rv = Mailbox.toHex(invite.rendezvousId);

    final ReceiveService receive = ReceiveService.instance..clear();
    receive.register(rv, bobPreKeys);

    final RelayClient bobNet = RelayClient(uri);
    final RelayClient aliceNet = RelayClient(uri);
    addTearDown(() {
      bobNet.close();
      aliceNet.close();
    });

    final Identity alice = await Identity.generate();
    final ChatController aliceCtl = await ChatController.startFromInvite(
      me: alice,
      invite: invite,
      transport: aliceNet,
    );
    await aliceCtl.send('привет от Чел2');

    final ChatController? bobCtl = await receive.tryAccept(
      me: bob,
      rendezvousHex: rv,
      transport: bobNet,
    );
    expect(bobCtl, isNotNull);
    expect(
      bobCtl!.messages.where((m) => !m.outgoing).map((m) => m.text),
      contains('привет от Чел2'),
    );

    await bobCtl.send('привет от Чел1');
    await aliceCtl.poll();
    expect(
      aliceCtl.messages.where((m) => !m.outgoing).map((m) => m.text),
      contains('привет от Чел1'),
    );
  });

  test('rejects a second connection reusing the same one-time pre-key',
      () async {
    final RelayServer relay = RelayServer();
    final Uri uri = await relay.start();
    addTearDown(relay.stop);

    final Identity bob = await Identity.generate();
    final PreKeys bobPreKeys = await PreKeys.generate(bob);
    final InviteKey invite = await InviteKey.create(bob, bobPreKeys);
    final String rv = Mailbox.toHex(invite.rendezvousId);

    final ReceiveService receive = ReceiveService.instance..clear();
    receive.register(rv, bobPreKeys);

    final RelayClient bobNet = RelayClient(uri);
    final RelayClient a1Net = RelayClient(uri);
    final RelayClient a2Net = RelayClient(uri);
    addTearDown(() {
      bobNet.close();
      a1Net.close();
      a2Net.close();
    });

    // First party connects and is accepted.
    final ChatController c1 = await ChatController.startFromInvite(
      me: await Identity.generate(),
      invite: invite,
      transport: a1Net,
    );
    await c1.send('первый');
    expect(
      await receive.tryAccept(me: bob, rendezvousHex: rv, transport: bobNet),
      isNotNull,
    );

    // Second party reuses the SAME invite (same one-time pre-key).
    final ChatController c2 = await ChatController.startFromInvite(
      me: await Identity.generate(),
      invite: invite,
      transport: a2Net,
    );
    await c2.send('второй');

    // The responder must refuse the reused one-time pre-key.
    expect(
      await receive.tryAccept(me: bob, rendezvousHex: rv, transport: bobNet),
      isNull,
    );
  });
}
