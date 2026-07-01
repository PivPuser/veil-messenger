/// relay — store-and-forward transport for the anonymous messenger.
///
///   * [RelayServer]    — the "dumb" server that moves opaque envelopes.
///   * [RelayTransport] — interface for clients.
///   * [RelayClient]    — direct HTTP client (local/testing).
///   * [TorRelayClient] — client tunnelled through a Tor SOCKS proxy.
///   * [Mailbox]        — derives unlinkable one-time mailbox ids.
library relay;

export 'src/mailbox.dart' show Mailbox;
export 'src/relay_client.dart' show RelayClient;
export 'src/relay_server.dart' show RelayServer;
export 'src/relay_transport.dart'
    show RelayTransport, RelayException, parseMailboxMessages;
export 'src/socks5.dart' show Socks5, TunnelConnection, SocksException;
export 'src/tor_relay_client.dart' show TorRelayClient;
