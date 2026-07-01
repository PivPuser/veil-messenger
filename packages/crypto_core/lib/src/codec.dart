import 'dart:convert';
import 'dart:typed_data';

/// Tiny length-prefixed binary writer used for serializing key material and
/// session state. Byte strings are prefixed with an unsigned LEB128 varint
/// length so records are self-describing and forward-compatible.
class ByteWriter {
  final BytesBuilder _b = BytesBuilder();

  void byte(int v) => _b.addByte(v & 0xff);

  void u32(int v) {
    final ByteData d = ByteData(4)..setUint32(0, v, Endian.big);
    _b.add(d.buffer.asUint8List());
  }

  void _varint(int value) {
    int v = value;
    while (v >= 0x80) {
      _b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _b.addByte(v);
  }

  void bytes(List<int> v) {
    _varint(v.length);
    _b.add(v);
  }

  void boolean(bool v) => _b.addByte(v ? 1 : 0);

  void optionalBytes(List<int>? v) {
    if (v == null) {
      _b.addByte(0);
    } else {
      _b.addByte(1);
      bytes(v);
    }
  }

  void str(String s) => bytes(utf8.encode(s));

  Uint8List toBytes() => _b.toBytes();
}

/// Reader counterpart to [ByteWriter].
class ByteReader {
  ByteReader(this._data);

  final Uint8List _data;
  int _pos = 0;

  bool get atEnd => _pos >= _data.length;

  int byte() {
    _check(1);
    return _data[_pos++];
  }

  int u32() {
    _check(4);
    final int v = ByteData.sublistView(_data, _pos, _pos + 4).getUint32(0, Endian.big);
    _pos += 4;
    return v;
  }

  int _varint() {
    int shift = 0;
    int result = 0;
    while (true) {
      final int b = byte();
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) throw const FormatException('varint too long');
    }
    return result;
  }

  Uint8List bytes() {
    final int n = _varint();
    _check(n);
    final Uint8List out = Uint8List.fromList(_data.sublist(_pos, _pos + n));
    _pos += n;
    return out;
  }

  bool boolean() => byte() != 0;

  Uint8List? optionalBytes() => byte() == 0 ? null : bytes();

  String str() => utf8.decode(bytes());

  void _check(int n) {
    if (_pos + n > _data.length) {
      throw const FormatException('Unexpected end of serialized data.');
    }
  }
}
