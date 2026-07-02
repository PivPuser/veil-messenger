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
///     machine yields no history.
///   * On fetch, envelopes are handed over and immediately dropped.
///
/// Denial-of-service bounds:
///   * [maxEnvelopeBytes] / [maxEnvelopesPerMailbox] cap a single mailbox.
///   * [maxMailboxes] caps the total number of mailboxes; creating one past the
///     cap evicts the oldest (so an attacker POSTing to endless random ids
///     can't exhaust memory).
///   * [messageTtl] expires envelopes; a throttled lazy sweep drops them.
///
/// HTTP API:
///   POST /mailbox/{id}   body = raw envelope bytes      -> 200
///   GET  /mailbox/{id}   -> {"messages": ["<base64>", ...]}  (and clears them)
class RelayServer {
  RelayServer({
    this.maxEnvelopesPerMailbox = 1000,
    this.maxEnvelopeBytes = 1 << 20,
    this.maxMailboxes = 100000,
    this.messageTtl = const Duration(days: 7),
    this.sweepInterval = const Duration(minutes: 1),
  });

  final int maxEnvelopesPerMailbox;
  final int maxEnvelopeBytes;
  final int maxMailboxes;
  final Duration messageTtl;
  final Duration sweepInterval;

  // Insertion-ordered, so the first key is the oldest mailbox.
  final Map<String, _Mailbox> _inboxes = <String, _Mailbox>{};
  DateTime _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);
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

    _sweepIfDue();

    _Mailbox? box = _inboxes[id];
    if (box == null) {
      if (_inboxes.length >= maxMailboxes) {
        _evictOldest();
      }
      box = _Mailbox();
      _inboxes[id] = box;
    }
    if (box.envelopes.length >= maxEnvelopesPerMailbox) {
      return Response(HttpStatus.insufficientStorage, body: 'mailbox full');
    }
    box.envelopes.add(body);
    return Response.ok('');
  }

  Response _collect(String id) {
    _sweepIfDue();
    final _Mailbox? box = _inboxes.remove(id);
    final List<String> encoded = <String>[
      for (final Uint8List env in box?.envelopes ?? const <Uint8List>[])
        base64.encode(env),
    ];
    return Response.ok(
      jsonEncode(<String, dynamic>{'messages': encoded}),
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  void _evictOldest() {
    if (_inboxes.isEmpty) return;
    _inboxes.remove(_inboxes.keys.first);
  }

  void _sweepIfDue() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastSweep) < sweepInterval) return;
    _lastSweep = now;
    _inboxes.removeWhere(
      (_, _Mailbox box) => now.difference(box.createdAt) > messageTtl,
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

class _Mailbox {
  _Mailbox() : createdAt = DateTime.now();

  final List<Uint8List> envelopes = <Uint8List>[];
  final DateTime createdAt;
}
