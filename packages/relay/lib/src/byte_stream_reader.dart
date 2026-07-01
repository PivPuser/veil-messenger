import 'dart:async';
import 'dart:typed_data';

/// Reads an exact number of bytes at a time from a byte [Stream].
///
/// A raw [Socket] delivers data in arbitrarily sized chunks, but protocols like
/// SOCKS5 need to consume precise byte counts and then hand the *same* stream
/// (with any leftover already-buffered bytes) to the next layer. This reader
/// owns a single subscription and buffers across chunk boundaries so those
/// layers can share one underlying stream safely.
class ByteStreamReader {
  ByteStreamReader(Stream<List<int>> stream) {
    _sub = stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  late final StreamSubscription<List<int>> _sub;
  final List<int> _buffer = <int>[];
  Completer<void>? _waiter;
  bool _done = false;
  Object? _error;

  void _onData(List<int> data) {
    _buffer.addAll(data);
    _wake();
  }

  void _onError(Object error, StackTrace stackTrace) {
    _error = error;
    _wake();
  }

  void _onDone() {
    _done = true;
    _wake();
  }

  void _wake() {
    final Completer<void>? waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> _wait() {
    _waiter ??= Completer<void>();
    return _waiter!.future;
  }

  /// Returns exactly [n] bytes, waiting as needed. Throws if the stream ends
  /// or errors before [n] bytes are available.
  Future<Uint8List> readExactly(int n) async {
    while (_buffer.length < n) {
      final Object? error = _error;
      if (error != null) throw error;
      if (_done) {
        throw StateError('stream closed after ${_buffer.length}/$n bytes');
      }
      await _wait();
    }
    final Uint8List out = Uint8List.fromList(_buffer.sublist(0, n));
    _buffer.removeRange(0, n);
    return out;
  }

  /// Returns whatever bytes are currently buffered (waiting for at least one),
  /// or `null` once the stream is exhausted. Useful for byte-pump/splice loops.
  Future<Uint8List?> readSome() async {
    while (_buffer.isEmpty) {
      final Object? error = _error;
      if (error != null) throw error;
      if (_done) return null;
      await _wait();
    }
    final Uint8List out = Uint8List.fromList(_buffer);
    _buffer.clear();
    return out;
  }

  /// Drains the stream to its end and returns all remaining bytes.
  Future<Uint8List> readToEnd() async {
    while (!_done) {
      final Object? error = _error;
      if (error != null) throw error;
      await _wait();
    }
    final Uint8List out = Uint8List.fromList(_buffer);
    _buffer.clear();
    return out;
  }

  Future<void> cancel() => _sub.cancel();
}
