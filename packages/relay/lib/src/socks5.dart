import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'byte_stream_reader.dart';

/// A minimal SOCKS5 client — enough to reach a service through Tor.
///
/// Tor exposes a SOCKS5 proxy (default 127.0.0.1:9050). Crucially, we send the
/// destination as a DOMAIN NAME (ATYP = 0x03) rather than resolving it locally,
/// because `.onion` names are not DNS-resolvable and must be handed to Tor to
/// resolve inside the network. No authentication is used (Tor's SOCKS port
/// accepts "no auth").
///
/// Only the subset we need is implemented: greeting with the no-auth method and
/// a single CONNECT command. See RFC 1928.
class Socks5 {
  Socks5._();

  static const int _version = 0x05;
  static const int _cmdConnect = 0x01;
  static const int _noAuth = 0x00;
  static const int _atypIpv4 = 0x01;
  static const int _atypDomain = 0x03;
  static const int _atypIpv6 = 0x04;

  /// Opens a TCP tunnel to [destHost]:[destPort] via the SOCKS5 proxy at
  /// [proxyHost]:[proxyPort]. Returns a [TunnelConnection] wrapping the socket
  /// and its buffered reader (any bytes the proxy already sent are preserved).
  static Future<TunnelConnection> connect({
    required String proxyHost,
    required int proxyPort,
    required String destHost,
    required int destPort,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final Socket socket =
        await Socket.connect(proxyHost, proxyPort, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final ByteStreamReader reader = ByteStreamReader(socket);

    try {
      // Greeting: VER, NMETHODS=1, METHODS=[no-auth].
      socket.add(<int>[_version, 0x01, _noAuth]);
      await socket.flush();
      final Uint8List methodReply = await reader.readExactly(2);
      if (methodReply[0] != _version || methodReply[1] != _noAuth) {
        throw SocksException(
          'proxy rejected no-auth (ver=${methodReply[0]}, method=${methodReply[1]})',
        );
      }

      // CONNECT request with a domain-name destination.
      final Uint8List host = Uint8List.fromList(destHost.codeUnits);
      if (host.length > 255) {
        throw SocksException('destination host too long: $destHost');
      }
      final BytesBuilder request = BytesBuilder()
        ..add(<int>[_version, _cmdConnect, 0x00, _atypDomain, host.length])
        ..add(host)
        ..add(<int>[(destPort >> 8) & 0xff, destPort & 0xff]);
      socket.add(request.toBytes());
      await socket.flush();

      // Reply: VER, REP, RSV, ATYP, BND.ADDR, BND.PORT.
      final Uint8List head = await reader.readExactly(4);
      if (head[0] != _version) {
        throw SocksException('bad SOCKS version in reply: ${head[0]}');
      }
      if (head[1] != 0x00) {
        throw SocksException(_replyMessage(head[1]));
      }
      final int addrLen = switch (head[3]) {
        _atypIpv4 => 4,
        _atypIpv6 => 16,
        _atypDomain => (await reader.readExactly(1))[0],
        _ => throw SocksException('unknown ATYP in reply: ${head[3]}'),
      };
      await reader.readExactly(addrLen + 2); // discard BND.ADDR + BND.PORT

      return TunnelConnection(socket, reader);
    } catch (_) {
      await reader.cancel();
      socket.destroy();
      rethrow;
    }
  }

  static String _replyMessage(int code) {
    const Map<int, String> messages = <int, String>{
      0x01: 'general SOCKS server failure',
      0x02: 'connection not allowed by ruleset',
      0x03: 'network unreachable',
      0x04: 'host unreachable',
      0x05: 'connection refused',
      0x06: 'TTL expired',
      0x07: 'command not supported',
      0x08: 'address type not supported',
    };
    return 'SOCKS connect failed: ${messages[code] ?? 'code $code'}';
  }
}

/// An established SOCKS5 tunnel: the raw [socket] plus a [ByteStreamReader] that
/// already owns the socket's read stream.
class TunnelConnection {
  TunnelConnection(this.socket, this.reader);

  final Socket socket;
  final ByteStreamReader reader;

  void add(List<int> bytes) => socket.add(bytes);
  Future<void> flush() => socket.flush();

  Future<void> close() async {
    await reader.cancel();
    socket.destroy();
  }
}

class SocksException implements Exception {
  SocksException(this.message);
  final String message;
  @override
  String toString() => 'SocksException: $message';
}
