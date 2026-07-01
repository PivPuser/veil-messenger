import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:relay/relay.dart';

/// Smoke test against a REAL Tor daemon + onion relay.
///
/// Prerequisites:
///   1. Run Tor (it exposes a SOCKS proxy on 127.0.0.1:9050 by default).
///   2. Publish the relay as an onion service and note its xxxxx.onion address.
///
/// Usage:
///   ONION=xxxxx.onion dart run relay:tor_smoke
///   ONION=xxxxx.onion ONION_PORT=80 TOR_PORT=9050 dart run relay:tor_smoke
Future<void> main() async {
  final String? onion = Platform.environment['ONION'];
  if (onion == null || onion.isEmpty) {
    stderr.writeln('Set ONION=<address>.onion (the relay onion service).');
    exit(2);
  }
  final int onionPort =
      int.tryParse(Platform.environment['ONION_PORT'] ?? '') ?? 80;
  final int torPort = int.tryParse(Platform.environment['TOR_PORT'] ?? '') ?? 9050;

  final TorRelayClient client = TorRelayClient(
    onionHost: onion,
    onionPort: onionPort,
    torProxyPort: torPort,
  );

  const String mailbox = 'ab12cd34ab12cd34';
  final Uint8List payload =
      Uint8List.fromList(utf8.encode('tor smoke ${DateTime.now()}'));

  stdout.writeln('→ Tor SOCKS 127.0.0.1:$torPort  →  $onion:$onionPort');
  stdout.writeln('Depositing an envelope…');
  await client.send(mailbox, payload);

  stdout.writeln('Fetching it back…');
  final List<Uint8List> got = await client.fetch(mailbox);
  if (got.length == 1 && _equal(got.single, payload)) {
    stdout.writeln('OK — round-trip through Tor succeeded.');
  } else {
    stderr.writeln('MISMATCH — got ${got.length} envelope(s).');
    exit(1);
  }
  client.close();
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
