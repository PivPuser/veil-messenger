import 'dart:io';

import 'package:relay/relay.dart';

/// Runnable entry point for the relay.
///
/// Usage:
///   dart run relay:relay_server            # 127.0.0.1:8080
///   HOST=0.0.0.0 PORT=9000 dart run relay:relay_server
Future<void> main() async {
  final String host = Platform.environment['HOST'] ?? '127.0.0.1';
  final int port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  final RelayServer server = RelayServer();
  final Uri uri = await server.start(host: host, port: port);
  stdout.writeln('Relay listening on $uri  (in-memory, no logs)');
  stdout.writeln('Press Ctrl+C to stop.');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nShutting down…');
    await server.stop();
    exit(0);
  });
}
