import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'relay_transport.dart';

/// Direct HTTP client for the [RelayServer].
///
/// This talks to the relay over a plain connection — fine for localhost and
/// tests. For real anonymity use [TorRelayClient], which tunnels through Tor so
/// the relay never learns the client's IP address.
class RelayClient implements RelayTransport {
  RelayClient(this.base, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final Uri base;
  final http.Client _http;

  @override
  Future<void> send(String mailboxId, List<int> envelope) async {
    final http.Response res = await _http.post(
      base.resolve('mailbox/$mailboxId'),
      body: envelope,
    );
    if (res.statusCode != 200) {
      throw RelayException('send failed (${res.statusCode}): ${res.body}');
    }
  }

  @override
  Future<List<Uint8List>> fetch(String mailboxId) async {
    final http.Response res =
        await _http.get(base.resolve('mailbox/$mailboxId'));
    if (res.statusCode != 200) {
      throw RelayException('fetch failed (${res.statusCode}): ${res.body}');
    }
    return parseMailboxMessages(res.body);
  }

  @override
  void close() => _http.close();
}
