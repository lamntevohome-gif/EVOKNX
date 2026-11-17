import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:knx_core/knx_core.dart';

import 'crypto_lite.dart';
import 'ha.dart';
import 'lan_share.dart';
import 'project.dart';

/// The EvoKNX Box: a small always-on device (ESP32) that runs timers when the App is closed.
///
/// Who does what:
///   Editor   declares the box (Connections tab) and chooses, in the Schedulers tab, the 1-bit group addresses the timers may switch
///            (On/Off only). It also sends the box its settings.
///   Phone    makes, changes, switches on/off and deletes the timers (Settings > Schedulers) and sends them to the box with Save.
///   Box      keeps the timers in its own flash and runs them.
///
/// Stored in the project as
///   box: { added, name, host, wan, id, key, tz, bus: {mode: routing|tunnel, host, port}, extra: [ {ga: group address id, name} ] }

///
/// A timer (made on the phone) refers to a target: an address chosen in the Schedulers tab ("g:<address id>").
///   schedule   {id, kind: 'schedule', title, on, time: 'HH:MM', days: [1..7 (Monday = 1)], tg, act, val}
///   countdown  {id, kind: 'countdown', title, on, wtg, wval: 'on'|'off', amount, unit: s|m|h, secs, restart, tg, act, val}
/// The actions: on, off (switch, dimmer, 1-bit address), level (dimmer, [val] 0–100 %), up, down, pos (blind, [val] 0–100 %).
/// A schedule does the action at a time of day. A countdown starts when the watched target ([wtg]) becomes [wval]; after
/// [secs] seconds it does the action. Any other value of the watched address cancels it.

/// Port of the box's web API.
const int kBoxHttpPort = 80;

/// UDP port the box answers "who is there?" on.
const int kBoxDiscoveryPort = 47803;

const int kBoxMaxTimers = 64;
const int kBoxMaxSecs = 86400;

const String _boxAsk = 'EVOKNX-BOX?';
const String _boxHere = 'EVOKNX-BOX';

// ------------------------------------------------------------------ the box in the project

Json boxOf(Json doc) => jsonMap(doc['box']);

/// The box was added in the Connections tab.
bool boxAdded(Json doc) => boxOf(doc)['added'] == true;

String boxHost(Json doc) => (boxOf(doc)['host'] ?? '').toString().trim();

/// The box has an address: the phone shows the Schedulers tab.
bool boxDeclared(Json doc) => boxAdded(doc) && boxHost(doc).isNotEmpty;

/// The mode of the connection of the box to the bus: 'routing' (KNX IP Router) or 'tunnel' (KNX IP Interface).
String boxMode(Json box) => jsonMap(box['bus'])['mode'] == 'tunnel' ? 'tunnel' : 'routing';

List<Json> boxExtra(Json doc) => jsonList(boxOf(doc)['extra']);

/// What the phone needs of the box (without anything else of the project's box settings).
Json boxForApp(Json doc) {
  final b = boxOf(doc);
  if (!boxDeclared(doc)) return <String, dynamic>{};
  return {
    'added': true,
    'name': b['name'],
    'host': b['host'],
    'wan': b['wan'],
    'id': b['id'],
    'key': b['key'],
    'tz': b['tz'],
    'bus': b['bus'],
    'extra': b['extra'] ?? <Json>[],
  };
}

/// A new key for a box (32 capital hex digits). It is made by the Editor, given to the box once, and travels to the phones inside the
/// configuration; nobody types it.
String makeBoxKey([Random? rnd]) {
  final r = rnd ?? Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join().toUpperCase();
}

// ------------------------------------------------------------------ targets and actions

/// Something a timer can write to.
class BoxTarget {
  const BoxTarget(this.key, this.kind, this.label, this.where, this.bind);

  /// "c:<card id>" or "g:<address id>".
  final String key;

  /// 'switch', 'dimmer', 'blind' or 'bit' (an extra 1-bit address).
  final String kind;
  final String label, where;

  /// The group addresses it uses, by role: onoff, level, updown, pos, state (ids of the addresses).
  final Map<String, String> bind;

  String get title => where.isEmpty ? label : '$label · $where';
}

Json? _ga(Json doc, Object? id) {
  if (id == null) return null;
  for (final g in jsonList(doc['groupAddresses'])) {
    if (g['id'] == id) return g;
  }
  return null;
}

/// The addresses a timer can use: only the 1-bit addresses chosen in the Schedulers tab of the Editor (On/Off).
List<BoxTarget> boxTargets(Json doc) {
  if (!boxAdded(doc)) return const [];
  final out = <BoxTarget>[];
  for (final e in boxExtra(doc)) {
    final g = _ga(doc, e['ga']);
    if (g == null || isHaAddress(g) || dptMain((g['dpt'] ?? '').toString()) != 1) continue;
    final name = (e['name'] ?? '').toString().trim();
    out.add(
      BoxTarget('g:${g['id']}', 'bit', name.isEmpty ? (g['name'] ?? g['address']).toString() : name, '', {
        'onoff': g['id'] as String,
        'state': g['id'] as String,
      }),
    );
  }
  return out;
}

BoxTarget? boxTarget(Json doc, String? key) {
  if (key == null) return null;
  for (final t in boxTargets(doc)) {
    if (t.key == key) return t;
  }
  return null;
}

/// The actions the target offers (only those whose addresses are set on the card): (action, text).
List<(String, String)> boxActions(BoxTarget t) {
  final b = t.bind;
  return switch (t.kind) {
    'blind' => [
        if (b['updown'] != null) ...[('up', 'Open (up)'), ('down', 'Close (down)')],
        if (b['pos'] != null) ('pos', 'Position %'),
      ],
    'dimmer' => [
        if (b['onoff'] != null) ...[('on', 'On'), ('off', 'Off')],
        if (b['level'] != null) ('level', 'Brightness %'),
      ],
    _ => [
        if (b['onoff'] != null) ...[('on', 'On'), ('off', 'Off')],
      ],
  };
}

/// The action needs a number (percent).
bool boxNeedsValue(String act) => act == 'level' || act == 'pos';

/// A target the countdown can watch: it has an address that tells on/off.
bool boxCanWatch(BoxTarget t) => t.bind['state'] != null && t.kind != 'blind';

String _dptFor(Json ga, int main, String fallback) {
  final d = (ga['dpt'] ?? '').toString().trim();
  return dptMain(d) == main ? d : fallback;
}

int? _addr(Json? ga) {
  if (ga == null || isHaAddress(ga)) return null;
  final a = GroupAddress.tryParse((ga['address'] ?? '').toString());
  return a?.raw;
}

/// What an action writes: the address and the bytes of the bus. Null when it cannot be resolved (the card was removed, the address
/// is not set, the number is missing).
({Json ga, KnxPayload p})? boxWriteOf(Json doc, String? key, String? act, num? val) {
  final t = boxTarget(doc, key);
  if (t == null || act == null) return null;
  Json? g(String role) => _ga(doc, t.bind[role]);
  switch (act) {
    case 'on':
    case 'off':
      final ga = g('onoff');
      if (ga == null) return null;
      return (ga: ga, p: Dpt.encode(_dptFor(ga, 1, '1.001'), act == 'on' ? 1 : 0));
    case 'up':
    case 'down':
      final ga = g('updown');
      if (ga == null) return null;
      return (ga: ga, p: Dpt.encode(_dptFor(ga, 1, '1.001'), act == 'down' ? 1 : 0));
    case 'level':
    case 'pos':
      final ga = g(act == 'level' ? 'level' : 'pos');
      if (ga == null || val == null) return null;
      return (ga: ga, p: Dpt.encode(_dptFor(ga, 5, '5.001'), val.clamp(0, 100)));
  }
  return null;
}

/// The address and the bytes a countdown watches: the state of [key] becomes [on] (true) or off (false).
({Json ga, KnxPayload p})? boxWatchOf(Json doc, String? key, bool on) {
  final t = boxTarget(doc, key);
  if (t == null || !boxCanWatch(t)) return null;
  final ga = _ga(doc, t.bind['state']);
  if (ga == null) return null;
  return (ga: ga, p: Dpt.encode(_dptFor(ga, 1, '1.001'), on ? 1 : 0));
}

// ------------------------------------------------------------------ timers

Json makeBoxTimer(String kind) {
  if (kind == 'countdown') {
    return {
      'id': uid('tm_'),
      'kind': 'countdown',
      'title': '',
      'on': true,
      'wtg': null,
      'wval': 'on',
      'amount': 10,
      'unit': 'm',
      'secs': 600,
      'restart': true,
      'tg': null,
      'act': 'off',
      'val': null,
    };
  }
  return {
    'id': uid('tm_'),
    'kind': 'schedule',
    'title': '',
    'on': true,
    'time': '22:00',
    'days': [1, 2, 3, 4, 5, 6, 7],
    'tg': null,
    'act': 'off',
    'val': null,
  };
}

/// The seconds of "[amount] [unit]" (s, m or h).
int boxSeconds(num amount, String unit) => (amount * (unit == 'h' ? 3600 : (unit == 'm' ? 60 : 1))).round();

final RegExp _hhmm = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');

/// "22:30" as minutes of the day (1350), or null.
int? boxMinutes(String text) {
  final m = _hhmm.firstMatch(text.trim());
  return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

/// The days of a schedule (1 = Monday … 7 = Sunday).
List<int> jsonDays(Json t) => [
      for (final d in (t['days'] is List ? t['days'] as List : const []))
        if (d is num && d >= 1 && d <= 7) d.toInt(),
    ];

/// A name for the box's web page: short, one line.
String _label(Object? v) {
  final t = (v ?? '').toString().replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  return t.length > 40 ? t.substring(0, 40) : t;
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

bool _samePayload(KnxPayload a, KnxPayload b) => a.short == b.short && _hex(a.raw) == _hex(b.raw);

/// What is wrong with the timers (shown to the person before saving). The text starts with the name of the timer.
List<String> boxProblems(Json doc, List<Json> timers) {
  final out = <String>[];
  if (timers.length > kBoxMaxTimers) out.add('The box runs at most $kBoxMaxTimers timers; the others are not sent.');
  for (var i = 0; i < timers.length; i++) {
    final t = timers[i];
    final title = (t['title'] ?? '').toString().trim();
    final w = 'Timer ${i + 1}${title.isEmpty ? '' : ' “$title”'}: ';
    final act = (t['act'] ?? '').toString();
    final target = boxTarget(doc, t['tg']?.toString());
    if (t['tg'] == null || t['tg'] == '') {
      out.add('${w}choose what to control.');
    } else if (target == null) {
      out.add('${w}this card or address is not available for timers any more.');
    } else if (!boxActions(target).any((a) => a.$1 == act)) {
      out.add('${w}choose what to do.');
    } else if (boxNeedsValue(act) && (t['val'] is! num || (t['val'] as num) < 0 || (t['val'] as num) > 100)) {
      out.add('${w}enter a percent between 0 and 100.');
    }
    if (t['kind'] == 'countdown') {
      final secs = (t['secs'] as num?)?.toInt() ?? 0;
      if (secs < 1 || secs > kBoxMaxSecs) out.add('${w}the time must be between 1 second and 24 hours.');
      final wt = boxTarget(doc, t['wtg']?.toString());
      if (t['wtg'] == null || t['wtg'] == '') {
        out.add('${w}choose what to watch.');
      } else if (wt == null || !boxCanWatch(wt)) {
        out.add('${w}this card or address cannot be watched.');
      } else {
        final watch = boxWatchOf(doc, wt.key, t['wval'] != 'off');
        final write = boxWriteOf(doc, t['tg']?.toString(), act, t['val'] as num?);
        if (watch != null && write != null && watch.ga['id'] == write.ga['id'] && _samePayload(watch.p, write.p)) {
          out.add('${w}it writes the same value that starts it, so it would never end.');
        }
      }
    } else {
      if (boxMinutes((t['time'] ?? '').toString()) == null) out.add('${w}the time must look like 22:30.');
      if (jsonDays(t).isEmpty) out.add('${w}choose at least one day.');
    }
  }
  return out;
}

/// The timers as the box needs them: the addresses are numbers and the values are already the bytes of the bus, so the box needs no data
/// types. Only the timers that are switched on and have no problem are run; all of them are kept in "ui" so that the phone can read them
/// back as they were made.
Map<String, dynamic> boxTimersWire(Json doc, List<Json> timers) {
  final run = <Map<String, dynamic>>[];
  for (final t in timers) {
    if (run.length >= kBoxMaxTimers) break;
    if (t['on'] == false) continue;
    final target = boxTarget(doc, t['tg']?.toString());
    final write = boxWriteOf(doc, t['tg']?.toString(), t['act']?.toString(), t['val'] as num?);
    final to = _addr(write?.ga);
    if (target == null || write == null || to == null) continue;
    final base = <String, dynamic>{'id': t['id'], 'n': _label(t['title']), 'gn': _label(target.label)};
    if (t['kind'] == 'countdown') {
      final secs = (t['secs'] as num?)?.toInt() ?? 0;
      final wt = boxTarget(doc, t['wtg']?.toString());
      final watch = boxWatchOf(doc, t['wtg']?.toString(), t['wval'] != 'off');
      final wa = _addr(watch?.ga);
      if (wt == null || watch == null || wa == null || secs < 1 || secs > kBoxMaxSecs) continue;
      run.add({
        ...base,
        'wn': _label(wt.label),
        'k': 'c',
        'w': wa,
        'v': _hex(watch.p.raw),
        'vs': watch.p.short ? 1 : 0,
        's': secs,
        'r': t['restart'] == false ? 0 : 1,
        'g': to,
        'a': _hex(write.p.raw),
        'as': write.p.short ? 1 : 0,
      });
    } else {
      final m = boxMinutes((t['time'] ?? '').toString());
      final days = jsonDays(t);
      if (m == null || days.isEmpty) continue;
      run.add({...base, 'k': 's', 'm': m, 'd': days.fold<int>(0, (a, d) => a | (1 << (d - 1))), 'g': to, 'a': _hex(write.p.raw), 'as': write.p.short ? 1 : 0});
    }
  }
  final wire = <String, dynamic>{'v': 1, 'timers': run, 'ui': timers};
  wire['rev'] = boxRevision(wire);
  return wire;
}

/// A short fingerprint of the content (without the "rev" itself): the box keeps it, so the phone can tell whether the box has what it shows.
String boxRevision(Map<String, dynamic> wire) {
  final copy = Map<String, dynamic>.from(wire)..remove('rev');
  final h = Sha256()..update(Uint8List.fromList(utf8.encode(jsonEncode(copy))));
  return _hex(h.digest().sublist(0, 6));
}

/// The settings the Editor gives the box: name, time zone (minutes from UTC) and how it reaches the bus.
Map<String, dynamic> boxSettingsWire(Json doc, {int? tzMinutes}) {
  final box = boxOf(doc);
  final bus = jsonMap(box['bus']);
  return {
    'v': 1,
    'name': (box['name'] ?? '').toString().trim().isEmpty ? 'EvoKNX Box' : (box['name'] as String).trim(),
    'tz': tzMinutes ?? ((box['tz'] as num?)?.toInt() ?? DateTime.now().timeZoneOffset.inMinutes),
    'bus': boxMode(box) == 'tunnel'
        ? {'mode': 'tunnel', 'host': (bus['host'] ?? '').toString().trim(), 'port': (bus['port'] as num?)?.toInt() ?? 3671}
        : {'mode': 'routing'},
  };
}

/// What is wrong with the box settings of the project.
List<String> boxSettingsProblems(Json doc) {
  final out = <String>[];
  final box = boxOf(doc);
  if (boxHost(doc).isEmpty) out.add('Enter the address of the box.');
  if (boxMode(box) == 'tunnel' && (jsonMap(box['bus'])['host'] ?? '').toString().trim().isEmpty)
    out.add('Tunneling needs the address of the KNX IP interface.');
  return out;
}

// ------------------------------------------------------------------ signing

/// The signature the box expects: HMAC-SHA256 with the key, over the one-time number the box gave, the method, the path and the body.
/// The key itself never travels on the network.
String boxSign(String key, String nonce, String method, String path, String body) {
  final mac = Hmac(Sha256.new, Uint8List.fromList(utf8.encode(key.trim())));
  return _hex(mac.mac(Uint8List.fromList(utf8.encode('$nonce\n$method\n$path\n$body'))));
}

// ------------------------------------------------------------------ talking to the box

/// A box found on the network.
class FoundBox {
  const FoundBox(this.name, this.ip, this.port, this.id, this.fw, this.claimed);
  final String name, ip, id, fw;
  final int port;

  /// True when the box already has a key (it belongs to a project).
  final bool claimed;
  String get address => port == kBoxHttpPort ? ip : '$ip:$port';
}

/// Looks for boxes on the local network (UDP broadcast).
Future<List<FoundBox>> discoverBoxes({Duration wait = const Duration(milliseconds: 1500)}) async {
  final found = <String, FoundBox>{};
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
        if (o is Map && o['t'] == _boxHere) {
          final port = (o['port'] as num?)?.toInt() ?? kBoxHttpPort;
          final id = (o['id'] ?? d.address.address).toString();
          found[id] = FoundBox((o['name'] ?? 'EvoKNX Box').toString(), d.address.address, port, id, (o['fw'] ?? '').toString(), o['claimed'] == true);
        }
      } catch (_) {}
    });
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    for (final a in await LanShareServer.listAddresses()) {
      final p = a.ip.split('.');
      if (p.length == 4) targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
    }
    final msg = utf8.encode(_boxAsk);
    for (var i = 0; i < 2; i++) {
      for (final t in targets) {
        try {
          sock.send(msg, t, kBoxDiscoveryPort);
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

/// The answer of the box: [data] when it worked, [error] (a sentence for the person) when not. [unreachable] is true when nothing
/// answered (as opposed to the box answering with an error).
class BoxReply {
  const BoxReply.ok(this.data)
      : error = null,
        unreachable = false;
  const BoxReply.fail(this.error, {this.unreachable = false}) : data = null;
  final Json? data;
  final String? error;
  final bool unreachable;
  bool get ok => error == null;
}

/// Calls the box at [address] ("192.168.1.60" or "192.168.1.60:8080"). With [key] the call is signed.
Future<BoxReply> boxCall(
  String address,
  String method,
  String path, {
  String? key,
  Json? body,
  Duration connect = const Duration(seconds: 5),
  Duration wait = const Duration(seconds: 15),
}) async {
  var host = address.trim().replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), '');
  var port = kBoxHttpPort;
  final i = host.lastIndexOf(':');
  if (i > 0) {
    port = int.tryParse(host.substring(i + 1)) ?? kBoxHttpPort;
    host = host.substring(0, i);
  }
  if (host.isEmpty) return const BoxReply.fail('Enter the address of the box.', unreachable: true);
  final client = HttpClient()..connectionTimeout = connect;
  Future<(int, Json)> send(String m, String route, {Map<String, String> headers = const {}, String text = ''}) async {
    final req = await client.openUrl(m, Uri(scheme: 'http', host: host, port: port, path: route));
    headers.forEach(req.headers.set);
    if (text.isNotEmpty) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(text));
    }
    final res = await req.close().timeout(wait);
    final t = await res.transform(utf8.decoder).join();
    Object? o;
    try {
      o = jsonDecode(t);
    } catch (_) {
      o = null;
    }
    return (res.statusCode, o is Map ? o.cast<String, dynamic>() : <String, dynamic>{});
  }

  try {
    final text = body == null ? '' : jsonEncode(body);
    var headers = <String, String>{};
    if (key != null && key.isNotEmpty) {
      final (st, ch) = await send('GET', '/api/challenge');
      final nonce = ch['nonce'];
      if (st != 200 || nonce is! String) return const BoxReply.fail('The box did not answer like an EvoKNX Box. Check the address.');
      headers = {'X-Nonce': nonce, 'X-Sig': boxSign(key, nonce, method, path, text)};
    }
    final (status, o) = await send(method, path, headers: headers, text: text);
    if (status == 200) return BoxReply.ok(o);
    if (status == 401)
      return const BoxReply.fail(
        'The box does not accept this key. In the Editor, press Connect in Connections › EvoKNX Box, then send the configuration to the phone again.',
      );
    if (status == 429) return const BoxReply.fail('The box is busy or too many wrong keys were tried. Wait a minute and try again.');
    final msg = o['error'];
    return BoxReply.fail(msg is String ? msg : 'The box replied with error $status.');
  } on SocketException {
    return const BoxReply.fail('Could not connect to the box. Check the address, the power and the network cable.', unreachable: true);
  } on TimeoutException {
    return const BoxReply.fail('The box did not answer in time.', unreachable: true);
  } on HttpException catch (e) {
    return BoxReply.fail(e.message);
  } finally {
    client.close(force: true);
  }
}

/// Calls the box of [box] (see [boxForApp]): first on the home network, then on the external address. The first one that answers wins.
Future<BoxReply> boxCallVia(Json box, String method, String path, {Json? body}) async {
  final key = (box['key'] ?? '').toString();
  final lan = (box['host'] ?? '').toString().trim();
  final wan = (box['wan'] ?? '').toString().trim();
  if (lan.isEmpty && wan.isEmpty) return const BoxReply.fail('The box has no address. Send the configuration again from the Editor.', unreachable: true);
  BoxReply? last;
  for (final (address, quick) in [if (lan.isNotEmpty) (lan, true), if (wan.isNotEmpty) (wan, false)]) {
    last = await boxCall(
      address,
      method,
      path,
      key: key,
      body: body,
      connect: Duration(seconds: quick ? 2 : 6),
    );
    if (!last.unreachable) return last;
  }
  return const BoxReply.fail('No connection to the box. If its address changed, send the configuration again from the Editor.', unreachable: true);
}

/// Who is it, and has it a key (no key needed).
Future<BoxReply> boxInfo(String address) => boxCall(address, 'GET', '/api/info');

/// Gives the box its key (only a box that has none, and only from the home network).
Future<BoxReply> boxClaim(String address, String key) => boxCall(address, 'POST', '/api/claim', body: {'key': key});

/// The state of the box: bus connected, time, the fingerprint of the timers it has, countdowns running.
Future<BoxReply> boxStatus(Json box) => boxCallVia(box, 'GET', '/api/status');

/// The timers the box has: {timers (what it runs), ui (as the phone made them), rev}.
Future<BoxReply> boxConfig(Json box) => boxCallVia(box, 'GET', '/api/config');

/// Sends the timers [wire] (see [boxTimersWire]).
Future<BoxReply> boxPush(Json box, Map<String, dynamic> wire) => boxCallVia(box, 'POST', '/api/config', body: wire);

/// Sends the settings of the box (see [boxSettingsWire]).
Future<BoxReply> boxPushSettings(Json box, Map<String, dynamic> settings) => boxCallVia(box, 'POST', '/api/settings', body: settings);

/// Runs the timer [id] now (to test it); the box must already have it.
Future<BoxReply> boxRun(Json box, String id) => boxCallVia(box, 'POST', '/api/run', body: {'id': id});

/// The time of the box: the time server ([ntp]), synchronise now ([sync]), or set it by hand ([epoch], seconds since 1970).
Future<BoxReply> boxSetTime(Json box, {String? ntp, bool sync = false, int? epoch}) =>
    boxCallVia(box, 'POST', '/api/time', body: {if (ntp != null) 'ntp': ntp, if (sync) 'sync': true, if (epoch != null) 'set': epoch});

/// What the box did in the last 7 days: [{t, k, x}] (t = seconds since 1970, 0 when the clock was not set).
Future<BoxReply> boxLog(Json box) => boxCallVia(box, 'GET', '/api/log');
