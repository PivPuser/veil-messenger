import 'dart:typed_data';

import 'package:relay/relay.dart';
import 'package:test/test.dart';

void main() {
  group('RelayServer + RelayClient', () {
    late RelayServer server;
    late RelayClient client;

    setUp(() async {
      server = RelayServer();
      final Uri uri = await server.start();
      client = RelayClient(uri);
    });

    tearDown(() async {
      client.close();
      await server.stop();
    });

    test('stores and forwards an envelope', () async {
      final envelope = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      await client.send('deadbeef', envelope);

      final fetched = await client.fetch('deadbeef');
      expect(fetched, hasLength(1));
      expect(fetched.single, equals(envelope));
    });

    test('fetch clears the mailbox (no-logs behaviour)', () async {
      await client.send('abc123', Uint8List.fromList(<int>[9]));
      expect(await client.fetch('abc123'), hasLength(1));
      // Second fetch must be empty — the relay keeps nothing.
      expect(await client.fetch('abc123'), isEmpty);
    });

    test('preserves order of multiple envelopes', () async {
      await client.send('cafe', Uint8List.fromList(<int>[1]));
      await client.send('cafe', Uint8List.fromList(<int>[2]));
      await client.send('cafe', Uint8List.fromList(<int>[3]));

      final fetched = await client.fetch('cafe');
      expect(fetched.map((e) => e.single), equals(<int>[1, 2, 3]));
    });

    test('unknown mailbox yields nothing', () async {
      expect(await client.fetch('0000'), isEmpty);
    });
  });

  group('Mailbox id derivation', () {
    final Uint8List seed = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('is deterministic for the same seed/direction/index', () async {
      final a = await Mailbox.id(seed, Mailbox.initiatorToResponder, 0);
      final b = await Mailbox.id(seed, Mailbox.initiatorToResponder, 0);
      expect(a, equals(b));
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('differs by index and by direction', () async {
      final i0 = await Mailbox.id(seed, Mailbox.initiatorToResponder, 0);
      final i1 = await Mailbox.id(seed, Mailbox.initiatorToResponder, 1);
      final r0 = await Mailbox.id(seed, Mailbox.responderToInitiator, 0);
      expect(i0, isNot(equals(i1)));
      expect(i0, isNot(equals(r0)));
    });

    test('differs for a different seed', () async {
      final other = Uint8List.fromList(List<int>.filled(32, 7));
      final a = await Mailbox.id(seed, Mailbox.initiatorToResponder, 0);
      final b = await Mailbox.id(other, Mailbox.initiatorToResponder, 0);
      expect(a, isNot(equals(b)));
    });
  });
}
