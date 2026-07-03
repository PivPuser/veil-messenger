import 'package:relay/relay.dart';

/// App-wide relay configuration.
///
/// Holds the relay address the app talks to and builds the right transport for
/// it: a Tor onion address uses [TorRelayClient] (IP-hidden); https / loopback
/// http use the direct [RelayClient]. Remote plain http is refused by default
/// because it leaks the client IP and metadata — enable [allowInsecure] only
/// for local development.
class RelayConfig {
  RelayConfig._();

  static final RelayConfig instance = RelayConfig._();

  Uri? baseUrl;
  bool allowInsecure = false;

  bool get isConfigured =>
      baseUrl != null &&
      RelayEndpoint.isUsable(baseUrl!.toString(), allowInsecure: allowInsecure);

  RelayScheme? get scheme =>
      baseUrl == null ? null : RelayEndpoint.classify(baseUrl!.toString());

  /// Builds a fresh transport for the configured relay, or null if unset or the
  /// address is not usable (invalid, or remote plain http without opt-in).
  RelayTransport? transport() {
    final Uri? url = baseUrl;
    if (url == null) return null;
    switch (RelayEndpoint.classify(url.toString())) {
      case RelayScheme.onion:
        return TorRelayClient(
          onionHost: url.host,
          onionPort: url.hasPort ? url.port : 80,
        );
      case RelayScheme.https:
      case RelayScheme.localhostHttp:
        return RelayClient(url);
      case RelayScheme.insecureHttp:
        return allowInsecure ? RelayClient(url) : null;
      case RelayScheme.invalid:
        return null;
    }
  }
}
