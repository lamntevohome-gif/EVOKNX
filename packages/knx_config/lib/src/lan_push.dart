import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_share.dart';
import 'project.dart';

/// Port the phone listens on while "Receive from computer" is on.
const int kPushPort = 47801;

/// UDP port the phone answers "who is there?" on, so the Editor can find it.
const int kDiscoveryPort = 47802;

const String _ask = 'EVOKNX-FIND';
const String _here = 'EVOKNX-HERE';

/// A phone found on the network (it has "Receive from computer" on).
class FoundApp {
  const FoundApp(this.name, this.ip, this.port);
  final String name, ip;
  final int port;
  String get address => '$ip:$port';
}

/// Called when a computer wants to send a configuration: shows the question on the phone and
/// returns true when it is accepted (the handler also keeps the configuration).
typedef OfferHandler = Future<bool> Function(String from, Json config);

/// The phone's side of "Transfer to App": a small HTTP server that takes a configuration pushed by the Editor, and an
/// UDP answer to the Editor's search. Nothing is kept unless the person accepts on the phone.
class LanReceiver {
  LanReceiver(this.onOffer, {String? name}) : name = name ?? _hostName();
  final OfferHandler onOffer;
  final String name;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  bool _busy = false;
  int port = 0;

  bool get running => _http != null;

  static String _hostName() {
    try {
      final h = Platform.localHostname.trim();
      if (h.isNotEmpty) return h;
    } catch (_) {}
    return 'Phone';
  }

  /// Starts listening. Returns an error message, or null when running.
  Future<String?> start() async {
    await stop();
    try {
      try {
        _http = await HttpServer.bind(InternetAddress.anyIPv4, kPushPort);
      } on SocketException {
        _http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
    } catch (e) {
      return 'Could not open the receiving port: $e';
    }
    port = _http!.port;
    _http!.listen(_handle, onError: (_) {});
    try {
      final u = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort, reuseAddress: true);
      _udp = u;
      u.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = u.receive();
        if (d == null || !isLocalAddress(d.address)) return;
        if (utf8.decode(d.data, allowMalformed: true).trim() != _ask) return;
        u.send(utf8.encode(jsonEncode({'t': _here, 'name': name, 'port': port})), d.address, d.port);
      });
    } catch (_) {
      // Searching is not available on this network: the Editor can still send to the address.
    }
    return null;
  }

  Future<void> stop() async {
    final h = _http, u = _udp;
    _http = null;
    _udp = null;
    u?.close();
    if (h != null) await h.close(force: true);
  }

  Future<void> _handle(HttpRequest r) async {
    final res = r.response;
    void json(int status, Object body) {
      res.statusCode = status;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
    }

    try {
      final from = r.connectionInfo?.remoteAddress;
      if (from == null || !isLocalAddress(from)) {
        json(403, {'error': 'Only accepted on the local network.'});
      } else if (r.uri.path == '/evoknx/ping') {
        json(200, {'app': 'evoknx-app', 'name': name});
      } else if (r.uri.path != '/evoknx/push' || r.method != 'POST') {
        json(404, {'error': 'Not found.'});
      } else if (r.contentLength > 40 * 1024 * 1024) {
        json(413, {'error': 'The configuration is too large.'});
      } else if (_busy) {
        json(409, {'error': 'The phone is already asking about another configuration.'});
      } else {
        Object? o;
        try {
          o = jsonDecode(await utf8.decoder.bind(r).join());
        } catch (_) {
          o = null;
        }
        final cfg = o is Map ? o['config'] : null;
        if (cfg is! Map || !isProject(cfg)) {
          json(400, {'error': 'The data is not an EvoKNX configuration.'});
        } else {
          _busy = true;
          try {
            final who = ((o as Map)['from'] ?? '').toString().trim();
            final ok = await onOffer(who.isEmpty ? from.address : who, cfg.cast<String, dynamic>());
            if (ok) {
              json(200, {'ok': true});
            } else {
              json(403, {'error': 'Declined on the phone.'});
            }
          } finally {
            _busy = false;
          }
        }
      }
    } catch (_) {
      try {
        res.statusCode = 500;
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }
}

/// The name of this computer, shown on the phone's question.
String thisComputerName() {
  try {
    final h = Platform.localHostname.trim();
    if (h.isNotEmpty) return h;
  } catch (_) {}
  return 'EvoKNX Editor';
}

/// Looks for phones that have "Receive from computer" on (UDP broadcast on the local network).
Future<List<FoundApp>> discoverApps({Duration wait = const Duration(milliseconds: 1500)}) async {
  final found = <String, FoundApp>{};
  RawDatagramSocket? s;
  try {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s = sock;
    sock.broadcastEnabled = true;
    sock.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = sock.receive();
      if (d == null) return;
      try {
        final o = jsonDecode(utf8.decode(d.data, allowMalformed: true));
        if (o is Map && o['t'] == _here) {
          final port = (o['port'] as num?)?.toInt();
          if (port != null) found['${d.address.address}:$port'] = FoundApp((o['name'] ?? 'Phone').toString(), d.address.address, port);
        }
      } catch (_) {}
    });
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    for (final a in await LanShareServer.listAddresses()) {
      final p = a.ip.split('.');
      if (p.length == 4) targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
    }
    final msg = utf8.encode(_ask);
    for (var i = 0; i < 2; i++) {
      for (final t in targets) {
        try {
          sock.send(msg, t, kDiscoveryPort);
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await Future<void>.delayed(wait);
  } catch (_) {
    // No search possible: the address can still be typed.
  } finally {
    s?.close();
  }
  return found.values.toList();
}

/// Sends [config] to the phone at [address] ("192.168.1.30" or "192.168.1.30:47801"). Waits for the answer on the
/// phone. Returns null when the phone accepted it, or an error message.
Future<String?> pushConfigToApp(String address, String from, Json config) async {
  var host = address.trim().replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), '');
  var port = kPushPort;
  final i = host.lastIndexOf(':');
  if (i > 0) {
    port = int.tryParse(host.substring(i + 1)) ?? kPushPort;
    host = host.substring(0, i);
  }
  if (host.isEmpty) return 'Enter the phone\'s address (shown in the App).';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await client.postUrl(Uri(scheme: 'http', host: host, port: port, path: '/evoknx/push'));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({'from': from, 'config': config})));
    final res = await req.close().timeout(const Duration(seconds: 90));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 200) return null;
    Object? o;
    try {
      o = jsonDecode(body);
    } catch (_) {
      o = null;
    }
    final msg = o is Map ? o['error'] : null;
    return msg is String ? msg : 'The phone replied with error ${res.statusCode}.';
  } on SocketException {
    return 'Could not connect to the phone. Check that "Receive from computer" is on in the App and both are on the same Wi-Fi.';
  } on TimeoutException {
    return 'No answer from the phone. Accept the question shown on the phone, or check the Wi-Fi.';
  } on HttpException catch (e) {
    return e.message;
  } finally {
    client.close(force: true);
  }
}
