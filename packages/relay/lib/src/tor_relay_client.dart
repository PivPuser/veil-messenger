import 'dart:convert';
import 'dart:typed_data';

import 'relay_transport.dart';
import 'socks5.dart';

/// A [RelayTransport] that reaches the relay through a Tor SOCKS5 proxy.
///
/// The relay is expected to be published as a Tor onion service, so:
///   * the client's IP is never exposed to the relay (traffic exits inside Tor),
///   * the relay's IP is never exposed either, and
///   * the `.onion` address self-authenticates the relay.
///
/// Each request opens a fresh tunnel and speaks a tiny HTTP/1.0 exchange
/// (`Connection: close`), which keeps parsing trivial: read until EOF.
class TorRelayClient implements RelayTransport {
  TorRelayClient({
    required this.onionHost,
    this.onionPort = 80,
    this.torProxyHost = '127.0.0.1',
    this.torProxyPort = 9050,
    this.timeout = const Duration(seconds: 60),
  });

  /// The relay's onion address, e.g. `abcd…xyz.onion`.
  final String onionHost;
  final int onionPort;
  final String torProxyHost;
  final int torProxyPort;
  final Duration timeout;

  @override
  Future<void> send(String mailboxId, List<int> envelope) async {
    final _Response res = await _request(
      'POST',
      '/mailbox/$mailboxId',
      body: envelope,
    );
    if (res.statusCode != 200) {
      throw RelayException('send failed (${res.statusCode}): ${res.body}');
    }
  }

  @override
  Future<List<Uint8List>> fetch(String mailboxId) async {
    final _Response res = await _request('GET', '/mailbox/$mailboxId');
    if (res.statusCode != 200) {
      throw RelayException('fetch failed (${res.statusCode}): ${res.body}');
    }
    return parseMailboxMessages(res.body);
  }

  @override
  void close() {
    // Nothing to close: tunnels are opened per request.
  }

  Future<_Response> _request(
    String method,
    String path, {
    List<int>? body,
  }) async {
    final TunnelConnection conn = await Socks5.connect(
      proxyHost: torProxyHost,
      proxyPort: torProxyPort,
      destHost: onionHost,
      destPort: onionPort,
      timeout: timeout,
    );
    try {
      final StringBuffer head = StringBuffer()
        ..write('$method $path HTTP/1.0\r\n')
        ..write('Host: $onionHost\r\n')
        ..write('Connection: close\r\n');
      if (body != null) {
        head
          ..write('Content-Type: application/octet-stream\r\n')
          ..write('Content-Length: ${body.length}\r\n');
      }
      head.write('\r\n');

      conn.add(ascii.encode(head.toString()));
      if (body != null) conn.add(body);
      await conn.flush();

      final Uint8List raw = await conn.reader.readToEnd();
      return _parseResponse(raw);
    } finally {
      await conn.close();
    }
  }

  static _Response _parseResponse(Uint8List raw) {
    final int sep = _indexOfHeaderEnd(raw);
    if (sep < 0) {
      throw const RelayException('malformed HTTP response (no header end)');
    }
    final String headerText = latin1.decode(raw.sublist(0, sep));
    final Uint8List bodyBytes = raw.sublist(sep + 4);

    final String statusLine = headerText.split('\r\n').first;
    final List<String> parts = statusLine.split(' ');
    final int code = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    return _Response(code, utf8.decode(bodyBytes));
  }

  /// Finds the index of the `\r\n\r\n` that ends the HTTP headers.
  static int _indexOfHeaderEnd(Uint8List data) {
    for (int i = 0; i + 3 < data.length; i++) {
      if (data[i] == 0x0d &&
          data[i + 1] == 0x0a &&
          data[i + 2] == 0x0d &&
          data[i + 3] == 0x0a) {
        return i;
      }
    }
    return -1;
  }
}

class _Response {
  _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
