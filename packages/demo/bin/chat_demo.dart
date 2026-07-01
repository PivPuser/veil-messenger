import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:relay/relay.dart';

/// End-to-end walkthrough of the "keys" flow over the store-and-forward relay.
///
/// Run from packages/demo:  dart run
Future<void> main() async {
  _title('0. Запускаем релей (in-memory, без логов)');
  final RelayServer relayServer = RelayServer();
  final Uri relayUri = await relayServer.start();
  print('Релей поднят: $relayUri');
  print('Сервер увидит ТОЛЬКО зашифрованные конверты в одноразовых ящиках.\n');

  // --- Чел1 (responder) creates a key -----------------------------------
  _title('1. Чел1 создаёт ключ и отдаёт его Чел2');
  final Identity bob = await Identity.generate();
  final PreKeys bobPreKeys = await PreKeys.generate(bob);
  final InviteKey invite = await InviteKey.create(bob, bobPreKeys);
  final String inviteString = await invite.encode();
  final String rendezvous = Mailbox.toHex(invite.rendezvousId);
  print('Ключ (это Чел1 пересылает Чел2 любым способом):');
  print('  $inviteString');
  print('Внутри ключа зашит адрес рандеву (mailbox): $rendezvous\n');

  // --- Чел2 (initiator) pastes the key ----------------------------------
  _title('2. Чел2 вводит ключ и подключается');
  final Identity alice = await Identity.generate();
  final InviteKey parsed = await InviteKey.decode(inviteString);
  final Session aliceSession = await Session.startChat(me: alice, invite: parsed);

  final RelayClient aliceNet = RelayClient(relayUri);
  final RelayClient bobNet = RelayClient(relayUri);

  // Чел2 sends the very first (handshake) message to the rendezvous mailbox.
  final Uint8List firstEnvelope =
      await aliceSession.encrypt(utf8.encode('Привет, это Чел2 🙂'));
  await aliceNet.send(rendezvous, firstEnvelope);
  _relayView(rendezvous, firstEnvelope);

  // Чел1 polls the rendezvous mailbox and accepts the chat.
  final List<Uint8List> incoming = await bobNet.fetch(rendezvous);
  final ({Session session, Uint8List firstMessage}) accepted =
      await Session.acceptChat(
    me: bob,
    myPreKeys: bobPreKeys,
    firstMessage: incoming.single,
  );
  final Session bobSession = accepted.session;
  print('  Чел1 расшифровал: "${utf8.decode(accepted.firstMessage)}"\n');

  // Confirm both sides derived the same (private) mailbox space.
  final bool seedsMatch = _bytesEqual(
    aliceSession.mailboxSeed,
    bobSession.mailboxSeed,
  );
  print('Общий mailbox-seed совпал у обоих: $seedsMatch '
      '(значит, дальше адреса ящиков они считают одинаково)\n');

  // --- Ongoing conversation over derived one-time mailboxes -------------
  _title('3. Обычная переписка через одноразовые ящики');
  final _Peer alicePeer = _Peer(
    name: 'Чел2',
    session: aliceSession,
    net: aliceNet,
    seed: aliceSession.mailboxSeed,
    sendDir: Mailbox.initiatorToResponder,
    recvDir: Mailbox.responderToInitiator,
  );
  final _Peer bobPeer = _Peer(
    name: 'Чел1',
    session: bobSession,
    net: bobNet,
    seed: bobSession.mailboxSeed,
    sendDir: Mailbox.responderToInitiator,
    recvDir: Mailbox.initiatorToResponder,
  );

  await bobPeer.send('О, здарова, Чел2! Ключ сработал.');
  await alicePeer.receiveAll();

  await alicePeer.send('Ага, вижу. Никаких телефонов и аккаунтов 👌');
  await bobPeer.receiveAll();

  await bobPeer.send('И сервер не знает, что мы вообще общаемся.');
  await alicePeer.receiveAll();

  // --- Out-of-order delivery over the transport -------------------------
  _title('4. Доставка не по порядку (сеть — штука ненадёжная)');
  final Uint8List m1 = await alicePeer.pack('сообщение №1');
  final Uint8List m2 = await alicePeer.pack('сообщение №2');
  final Uint8List m3 = await alicePeer.pack('сообщение №3');
  // Deposit into their (in-order) mailboxes, but let Чел1 read 3,1,2.
  final String box1 = await alicePeer.nextSendBox();
  await aliceNet.send(box1, m1);
  final String box2 = await alicePeer.nextSendBox();
  await aliceNet.send(box2, m2);
  final String box3 = await alicePeer.nextSendBox();
  await aliceNet.send(box3, m3);
  print('  Чел2 отправил 3 сообщения. Читаем в порядке 3 → 1 → 2:');
  await bobPeer.receiveFrom(box3);
  await bobPeer.receiveFrom(box1);
  await bobPeer.receiveFrom(box2);

  _title('Готово');
  print('Полный цикл отработал: ключ → X3DH → Double Ratchet → релей.');
  print('Никакого открытого текста и никакой привязки к личности сервер не видел.');

  aliceNet.close();
  bobNet.close();
  await relayServer.stop();
}

/// A peer's transport-side bookkeeping: which mailbox index to use next.
class _Peer {
  _Peer({
    required this.name,
    required this.session,
    required this.net,
    required this.seed,
    required this.sendDir,
    required this.recvDir,
  });

  final String name;
  final Session session;
  final RelayClient net;
  final Uint8List seed;
  final String sendDir;
  final String recvDir;
  int _sendIdx = 0;
  int _recvIdx = 0;

  Future<void> send(String text) async {
    final Uint8List envelope = await session.encrypt(utf8.encode(text));
    final String box = await Mailbox.id(seed, sendDir, _sendIdx++);
    await net.send(box, envelope);
    print('  [$name → релей] "$text"');
    _relayView(box, envelope);
  }

  Future<void> receiveAll() async {
    final String box = await Mailbox.id(seed, recvDir, _recvIdx);
    final List<Uint8List> envelopes = await net.fetch(box);
    for (final Uint8List env in envelopes) {
      final String text = utf8.decode(await session.decrypt(env));
      _recvIdx++;
      print('  [$name] расшифровал: "$text"');
    }
  }

  // Helpers for the out-of-order demonstration.

  Future<Uint8List> pack(String text) =>
      session.encrypt(utf8.encode(text)).then(Uint8List.fromList);

  Future<String> nextSendBox() => Mailbox.id(seed, sendDir, _sendIdx++);

  Future<void> receiveFrom(String box) async {
    final List<Uint8List> envelopes = await net.fetch(box);
    for (final Uint8List env in envelopes) {
      final String text = utf8.decode(await session.decrypt(env));
      _recvIdx++;
      print('    [$name] расшифровал: "$text"');
    }
  }
}

void _relayView(String mailboxId, Uint8List envelope) {
  final String head = Mailbox.toHex(
    envelope.sublist(0, envelope.length < 8 ? envelope.length : 8),
  );
  print('    (сервер видит) ящик=${mailboxId.substring(0, 12)}…  '
      'конверт=$head… (${envelope.length} байт шифротекста)');
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _title(String text) {
  print('── $text ${'─' * (60 - text.length).clamp(0, 60)}');
}
