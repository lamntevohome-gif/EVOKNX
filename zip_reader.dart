import 'dart:io';
import 'dart:typed_data';

import 'crypto_lite.dart';

/// The password given to a [ZipReader] does not open the entry.
class ZipPasswordException implements Exception {
  const ZipPasswordException();
  @override
  String toString() => 'Sai mật khẩu.';
}

/// Minimal ZIP reader (stored + deflate), enough for ETS .knxproj files.
/// With a [password] it also opens WinZip AES (AES-128/192/256) entries,
/// the format ETS uses for password-protected projects.
class ZipReader {
  final Uint8List _b;
  final Uint8List? _pwd;
  final Map<String, _Entry> _entries = {};

  ZipReader(Uint8List bytes, {Uint8List? password})
      : _b = bytes,
        _pwd = password {
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
      // WinZip AES extra field (0x9901): strength and the real compression method.
      var strength = 0, realMethod = method;
      var x = p + 46 + nameLen;
      final xEnd = x + extraLen;
      while (x + 4 <= xEnd) {
        final id = bd.getUint16(x, Endian.little), sz = bd.getUint16(x + 2, Endian.little);
        if (id == 0x9901 && sz >= 7) {
          strength = _b[x + 8];
          realMethod = bd.getUint16(x + 9, Endian.little);
        }
        x += 4 + sz;
      }
      _entries[name] = _Entry(method, csize, local, (flags & 1) != 0, strength, realMethod);
      p += 46 + nameLen + extraLen + commentLen;
    }
  }

  Iterable<String> get names => _entries.keys;

  bool isEncrypted(String name) => _entries[name]?.encrypted ?? false;

  /// The entry's bytes, or null when missing, or encrypted and no usable
  /// password was given. Throws [ZipPasswordException] for a wrong password.
  Uint8List? read(String name) {
    final e = _entries[name];
    if (e == null) return null;
    if (e.encrypted && (_pwd == null || e.method != 99)) return null;
    final bd = ByteData.sublistView(_b);
    final nameLen = bd.getUint16(e.local + 26, Endian.little);
    final extraLen = bd.getUint16(e.local + 28, Endian.little);
    final start = e.local + 30 + nameLen + extraLen;
    var data = _b.sublist(start, start + e.csize);
    var method = e.method;
    if (e.encrypted) {
      data = _decryptAes(data, e.strength);
      method = e.realMethod;
    }
    if (method == 0) return data;
    if (method == 8) return Uint8List.fromList(ZLibCodec(raw: true).decode(data));
    throw FormatException('Kiểu nén ZIP chưa hỗ trợ ($method).');
  }

  /// WinZip AES: salt | 2-byte check | AES-CTR data | 10-byte HMAC-SHA1.
  Uint8List _decryptAes(Uint8List d, int strength) {
    final keyLen = switch (strength) { 1 => 16, 2 => 24, 3 => 32, _ => throw const FormatException('Kiểu mã hoá ZIP chưa hỗ trợ.') };
    final saltLen = keyLen ~/ 2;
    if (d.length < saltLen + 12) throw const FormatException('Dữ liệu mã hoá bị hỏng.');
    final salt = d.sublist(0, saltLen);
    final check = d.sublist(saltLen, saltLen + 2);
    final payload = d.sublist(saltLen + 2, d.length - 10);
    final auth = d.sublist(d.length - 10);
    final dk = pbkdf2(Sha1.new, _pwd!, salt, 1000, 2 * keyLen + 2);
    if (dk[2 * keyLen] != check[0] || dk[2 * keyLen + 1] != check[1]) throw const ZipPasswordException();
    final mac = Hmac(Sha1.new, dk.sublist(keyLen, 2 * keyLen)).mac(payload);
    for (var i = 0; i < 10; i++) {
      if (mac[i] != auth[i]) throw const ZipPasswordException();
    }
    final aes = Aes(dk.sublist(0, keyLen));
    final out = Uint8List(payload.length);
    final ctr = Uint8List(16), ks = Uint8List(16);
    for (var off = 0, n = 1; off < payload.length; off += 16, n++) {
      // little-endian block counter starting at 1
      var c = n;
      for (var i = 0; i < 16 && c > 0; i++) {
        ctr[i] = c & 0xFF;
        c >>= 8;
      }
      aes.encryptBlock(ctr, ks);
      final end = off + 16 > payload.length ? payload.length : off + 16;
      for (var i = off; i < end; i++) {
        out[i] = payload[i] ^ ks[i - off];
      }
    }
    return out;
  }
}

class _Entry {
  final int method, csize, local, strength, realMethod;
  final bool encrypted;
  _Entry(this.method, this.csize, this.local, this.encrypted, this.strength, this.realMethod);
}
