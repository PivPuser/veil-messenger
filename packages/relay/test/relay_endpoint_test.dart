import 'package:relay/relay.dart';
import 'package:test/test.dart';

void main() {
  group('RelayEndpoint.classify', () {
    test('recognizes onion, https, loopback and remote http', () {
      expect(RelayEndpoint.classify('http://abcd.onion'), RelayScheme.onion);
      expect(RelayEndpoint.classify('https://relay.example'), RelayScheme.https);
      expect(RelayEndpoint.classify('http://127.0.0.1:8080'),
          RelayScheme.localhostHttp);
      expect(RelayEndpoint.classify('http://localhost:9000'),
          RelayScheme.localhostHttp);
      expect(RelayEndpoint.classify('http://relay.example'),
          RelayScheme.insecureHttp);
      expect(RelayEndpoint.classify('nonsense'), RelayScheme.invalid);
    });
  });

  group('RelayEndpoint.isUsable', () {
    test('allows onion, https and loopback; blocks remote http by default', () {
      expect(RelayEndpoint.isUsable('http://abcd.onion'), isTrue);
      expect(RelayEndpoint.isUsable('https://relay.example'), isTrue);
      expect(RelayEndpoint.isUsable('http://127.0.0.1:8080'), isTrue);
      expect(RelayEndpoint.isUsable('http://relay.example'), isFalse);
    });

    test('allows remote http only with explicit insecure opt-in', () {
      expect(
        RelayEndpoint.isUsable('http://relay.example', allowInsecure: true),
        isTrue,
      );
    });
  });
}
