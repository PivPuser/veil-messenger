import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:relay/relay.dart';
import 'package:relay/src/byte_stream_reader.dart';
import 'package:test/test.dart';

void main() {
  group('TorRelayClient over a mock SOCKS5 proxy', () {
    late RelayServer relay;
    late Uri relayUri;
    late ServerSocket socks;
    late TorRelayClient client;

    setUp(() async {
      relay = RelayServer();
      relayUri = await relay.start();
      // A stand-in for Tor: speaks SOCKS5, then splices to the real relay.
      socks = await _startMockSocks(
        upstreamHost: relayUri.host,
        upstreamPort: relayUri.port,
      );
      client = TorRelayClient(
        onionHost: 'exampleexampleexampleexampleex.onion', // ignored by mock
        onionPort: 80,
        torProxyHost: '127.0.0.1',
        torProxyPort: socks.port,
      );
    });

    tearDown(() async {
      client.close();
      await socks.close();
      await relay.stop();
    });

    test('send + fetch round-trips through the tunnel', () async {
      final Uint8List envelope = Uint8List.fromList(<int>[10, 20, 30, 40]);
      await client.send('deadbeef', envelope);

      final List<Uint8List> fetched = await client.fetch('deadbeef');
      expect(fetched, hasLength(1));
      expect(fetched.single, equals(envelope));
    });

    test('fetch clears the mailbox through the tunnel', () async {
      await client.send('abc123', Uint8List.fromList(<int>[7]));
      expect(await client.fetch('abc123'), hasLength(1));
      expect(await client.fetch('abc123'), isEmpty);
    });

    test('surfaces a SOCKS failure reply as an exception', () async {
      final ServerSocket rejecting = await _startRejectingSocks();
      addTearDown(() => rejecting.close());
      final TorRelayClient bad = TorRelayClient(
        onionHost: 'nope.onion',
        torProxyHost: '127.0.0.1',
        torProxyPort: rejecting.port,
      );
      await expectLater(
        bad.fetch('0000'),
        throwsA(isA<SocksException>()),
      );
    });
  });
}

/// Minimal SOCKS5 proxy for tests: completes the no-auth CONNECT handshake,
/// then blindly splices the client to a fixed upstream (the real relay),
/// ignoring the requested destination the way a captive proxy would.
Future<ServerSocket> _startMockSocks({
  required String upstreamHost,
  required int upstreamPort,
}) async {
  final ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((Socket client) async {
    final ByteStreamReader reader = ByteStreamReader(client);
    try {
      // Greeting: VER, NMETHODS, METHODS…
      final Uint8List greeting = await reader.readExactly(2);
      await reader.readExactly(greeting[1]); // consume method list
      client.add(<int>[0x05, 0x00]); // choose no-auth
      await client.flush();

      // CONNECT: VER, CMD, RSV, ATYP, then address + port.
      final Uint8List req = await reader.readExactly(4);
      switch (req[3]) {
        case 0x01:
          await reader.readExactly(4);
        case 0x04:
          await reader.readExactly(16);
        case 0x03:
          final Uint8List len = await reader.readExactly(1);
          await reader.readExactly(len[0]);
      }
      await reader.readExactly(2); // port
      client.add(<int>[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]); // success
      await client.flush();

      // Splice to the fixed upstream relay.
      final Socket upstream = await Socket.connect(upstreamHost, upstreamPort);
      unawaited(_pump(reader, upstream));
      upstream.listen(
        client.add,
        onDone: () async {
          await client.flush();
          await client.close();
        },
        onError: (_) => client.destroy(),
      );
    } catch (_) {
      client.destroy();
    }
  });
  return server;
}

Future<void> _pump(ByteStreamReader from, Socket to) async {
  while (true) {
    final Uint8List? chunk = await from.readSome();
    if (chunk == null) break;
    to.add(chunk);
    await to.flush();
  }
  await to.close();
}

/// A SOCKS5 proxy that accepts the greeting but rejects the CONNECT.
Future<ServerSocket> _startRejectingSocks() async {
  final ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((Socket client) async {
    final ByteStreamReader reader = ByteStreamReader(client);
    try {
      final Uint8List greeting = await reader.readExactly(2);
      await reader.readExactly(greeting[1]);
      client.add(<int>[0x05, 0x00]);
      await client.flush();
      final Uint8List req = await reader.readExactly(4);
      switch (req[3]) {
        case 0x01:
          await reader.readExactly(4);
        case 0x04:
          await reader.readExactly(16);
        case 0x03:
          final Uint8List len = await reader.readExactly(1);
          await reader.readExactly(len[0]);
      }
      await reader.readExactly(2);
      // REP = 0x05 (connection refused).
      client.add(<int>[0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await client.flush();
      await client.close();
    } catch (_) {
      client.destroy();
    }
  });
  return server;
}
