import 'dart:io';
import 'dart:typed_data';

/// Minimal ZIP reader (stored + deflate), enough for ETS .knxproj files.
class ZipReader {
  final Uint8List _b;
  final Map<String, _Entry> _entries = {};

  ZipReader(Uint8List bytes) : _b = bytes {
    final bd = ByteData.sublistView(_b);
    var eocd = -1;
    for (var i = _b.length - 22; i >= 0 && i >= _b.length - 65557; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('Không phải file ZIP hợp lệ.');
    final count = bd.getUint16(eocd + 10, Endian.little);
    var p = bd.getUint32(eocd + 16, Endian.little);
    for (var n = 0; n < count; n++) {
      if (bd.getUint32(p, Endian.little) != 0x02014b50) break;
      final flags = bd.getUint16(p + 8, Endian.little);
      final method = bd.getUint16(p + 10, Endian.little);
      final csize = bd.getUint32(p + 20, Endian.little);
      final nameLen = bd.getUint16(p + 28, Endian.little);
      final extraLen = bd.getUint16(p + 30, Endian.little);
      final commentLen = bd.getUint16(p + 32, Endian.little);
      final local = bd.getUint32(p + 42, Endian.little);
      final name = String.fromCharCodes(_b.sublist(p + 46, p + 46 + nameLen)).replaceAll('\\', '/');
      _entries[name] = _Entry(method, csize, local, (flags & 1) != 0);
      p += 46 + nameLen + extraLen + commentLen;
    }
  }

  Iterable<String> get names => _entries.keys;

  bool isEncrypted(String name) => _entries[name]?.encrypted ?? false;

  Uint8List? read(String name) {
    final e = _entries[name];
    if (e == null || e.encrypted) return null;
    final bd = ByteData.sublistView(_b);
    final nameLen = bd.getUint16(e.local + 26, Endian.little);
    final extraLen = bd.getUint16(e.local + 28, Endian.little);
    final start = e.local + 30 + nameLen + extraLen;
    final data = _b.sublist(start, start + e.csize);
    if (e.method == 0) return data;
    if (e.method == 8) return Uint8List.fromList(ZLibCodec(raw: true).decode(data));
    throw FormatException('Kiểu nén ZIP chưa hỗ trợ ($e.method).');
  }
}

class _Entry {
  final int method, csize, local;
  final bool encrypted;
  _Entry(this.method, this.csize, this.local, this.encrypted);
}
