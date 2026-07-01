import 'dart:convert';
import 'dart:typed_data';

/// Common interface for anything that can carry opaque envelopes to/from the
/// relay. Implemented by [RelayClient] (direct HTTP, for local/testing) and
/// [TorRelayClient] (HTTP tunnelled through a Tor SOCKS proxy).
abstract interface class RelayTransport {
  /// Deposits an opaque [envelope] into [mailboxId].
  Future<void> send(String mailboxId, List<int> envelope);

  /// Fetches and clears all envelopes waiting in [mailboxId].
  Future<List<Uint8List>> fetch(String mailboxId);

  void close();
}

class RelayException implements Exception {
  const RelayException(this.message);
  final String message;
  @override
  String toString() => 'RelayException: $message';
}

/// Parses the relay's JSON response body (`{"messages": ["<base64>", ...]}`).
List<Uint8List> parseMailboxMessages(String jsonBody) {
  final Object? decoded = jsonDecode(jsonBody);
  if (decoded is! Map<String, dynamic> || decoded['messages'] is! List) {
    throw const RelayException('malformed relay response');
  }
  final List<dynamic> messages = decoded['messages'] as List<dynamic>;
  return <Uint8List>[
    for (final dynamic m in messages) base64.decode(m as String),
  ];
}
