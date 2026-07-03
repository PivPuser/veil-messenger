/// How a relay address should be treated, from a metadata-privacy standpoint.
enum RelayScheme {
  /// A Tor onion service — IP-hidden and self-authenticating. Preferred.
  onion,

  /// https:// — transport-encrypted; the operator still sees IP + metadata.
  https,

  /// Plain http to localhost/loopback — fine for development only.
  localhostHttp,

  /// Plain http to a remote host — leaks IP and metadata in the clear. Blocked
  /// unless the caller explicitly opts into insecure mode (dev/testing).
  insecureHttp,

  /// Not a usable relay URL.
  invalid,
}

/// Pure classification of a relay URL. No Flutter/IO — unit-testable.
class RelayEndpoint {
  RelayEndpoint._();

  static const Set<String> _loopbackHosts = <String>{
    '127.0.0.1',
    'localhost',
    '::1',
  };

  static RelayScheme classify(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return RelayScheme.invalid;

    if (uri.host.toLowerCase().endsWith('.onion')) return RelayScheme.onion;

    switch (uri.scheme.toLowerCase()) {
      case 'https':
        return RelayScheme.https;
      case 'http':
        return _loopbackHosts.contains(uri.host.toLowerCase())
            ? RelayScheme.localhostHttp
            : RelayScheme.insecureHttp;
      default:
        return RelayScheme.invalid;
    }
  }

  /// Whether this URL may be used given [allowInsecure] (a dev/testing flag).
  /// Onion, https and loopback http are allowed; remote plain http (which leaks
  /// IP + metadata) only when insecure mode is explicitly enabled.
  static bool isUsable(String raw, {bool allowInsecure = false}) {
    switch (classify(raw)) {
      case RelayScheme.onion:
      case RelayScheme.https:
      case RelayScheme.localhostHttp:
        return true;
      case RelayScheme.insecureHttp:
        return allowInsecure;
      case RelayScheme.invalid:
        return false;
    }
  }
}
