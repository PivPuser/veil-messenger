import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// A minimal store-and-forward relay.
///
/// Design goals (this is the whole security story of the server):
///   * It stores opaque byte blobs keyed by an opaque mailbox id.
///   * It has NO concept of accounts, identities, contacts or plaintext.
///   * Storage is in-memory only — nothing is written to disk, so seizing the
///     machine yields no history. A production relay would add a short TTL and
///     size caps; this prototype keeps envelopes until fetched.
///   * On fetch, envelopes are handed over and immediately dropped.
///
/// HTTP API:
///   POST /mailbox/{id}   body = raw envelope bytes      -> 200
///   GET  /mailbox/{id}   -> {"messages": ["<base64>", ...]}  (and clears them)
class RelayServer {
  RelayServer({this.maxEnvelopesPerMailbox = 1000, this.maxEnvelopeBytes = 1 << 20});

  final int maxEnvelopesPerMailbox;
  final int maxEnvelopeBytes;

  final Map<String, List<Uint8List>> _inboxes = <String, List<Uint8List>>{};
  HttpServer? _server;

  /// Starts listening. Returns the base [Uri]. Use port 0 for an ephemeral port.
  Future<Uri> start({String host = '127.0.0.1', int port = 0}) async {
    final Handler handler = const Pipeline().addHandler(_handle);
    _server = await shelf_io.serve(handler, host, port);
    return Uri.parse('http://$host:${_server!.port}');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _inboxes.clear();
  }

  Future<Response> _handle(Request request) async {
    final List<String> segments = request.url.pathSegments;
    if (segments.length != 2 || segments[0] != 'mailbox') {
      return Response.notFound('');
    }
    final String id = segments[1];
    if (!_isValidMailboxId(id)) {
      return Response.badRequest(body: 'invalid mailbox id');
    }

    switch (request.method) {
      case 'POST':
        return _deposit(id, request);
      case 'GET':
        return _collect(id);
      default:
        return Response(HttpStatus.methodNotAllowed);
    }
  }

  Future<Response> _deposit(String id, Request request) async {
    final Uint8List body = await _readBody(request);
    if (body.isEmpty) {
      return Response.badRequest(body: 'empty envelope');
    }
    if (body.length > maxEnvelopeBytes) {
      return Response(HttpStatus.requestEntityTooLarge);
    }
    final List<Uint8List> box = _inboxes.putIfAbsent(id, () => <Uint8List>[]);
    if (box.length >= maxEnvelopesPerMailbox) {
      return Response(HttpStatus.insufficientStorage, body: 'mailbox full');
    }
    box.add(body);
    return Response.ok('');
  }

  Response _collect(String id) {
    final List<Uint8List>? box = _inboxes.remove(id);
    final List<String> encoded = <String>[
      for (final Uint8List env in box ?? const <Uint8List>[]) base64.encode(env),
    ];
    return Response.ok(
      jsonEncode(<String, dynamic>{'messages': encoded}),
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  static bool _isValidMailboxId(String id) {
    if (id.isEmpty || id.length > 128) return false;
    for (final int c in id.codeUnits) {
      final bool ok = (c >= 0x30 && c <= 0x39) || // 0-9
          (c >= 0x61 && c <= 0x66); // a-f
      if (!ok) return false;
    }
    return true;
  }

  static Future<Uint8List> _readBody(Request request) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in request.read()) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }
}
