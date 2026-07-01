import 'package:relay/relay.dart';

/// App-wide relay configuration.
///
/// Holds the base URL of the relay the app talks to. In production this points
/// at a Tor onion service (and would build a [TorRelayClient]); for now it is a
/// plain URL the user sets in settings. Null means "no relay configured".
class RelayConfig {
  RelayConfig._();

  static final RelayConfig instance = RelayConfig._();

  Uri? baseUrl;

  bool get isConfigured => baseUrl != null;

  /// Builds a fresh transport for the configured relay, or null if unset.
  RelayTransport? transport() =>
      baseUrl == null ? null : RelayClient(baseUrl!);
}
