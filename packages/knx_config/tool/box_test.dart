// Test of the box model, the wire format, the signing and the client (pure Dart). Run: dart run tool/box_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_config/knx_config.dart';
import 'package:knx_config/src/crypto_lite.dart';

int _fail = 0, _pass = 0;
void check(bool ok, String name) {
  if (ok) {
    _pass++;
  } else {
    _fail++;
    print('FAIL: $name');
  }
}

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Future<void> main() async {
  // HMAC-SHA256, RFC 4231 test cases 1 and 2 (the firmware uses the same function of mbedtls).
  final m1 = Hmac(Sha256.new, Uint8List.fromList(List.filled(20, 0x0b))).mac(Uint8List.fromList(utf8.encode('Hi There')));
  check(hex(m1) == 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7', 'HMAC RFC4231 #1');
  final m2 = Hmac(Sha256.new, Uint8List.fromList(utf8.encode('Jefe'))).mac(Uint8List.fromList(utf8.encode('what do ya want for nothing?')));
  check(hex(m2) == '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843', 'HMAC RFC4231 #2');
  final key = makeBoxKey();
  check(RegExp(r'^[0-9A-F]{32}$').hasMatch(key) && key != makeBoxKey(), 'key form $key');
  check(boxSign('AB', 'n', 'GET', '/a', '') != boxSign('AB', 'n2', 'GET', '/a', ''), 'signature depends on the nonce');

  // The project: a box, cards and extra addresses.
  final doc = newProject('Villa');
  doc['groupAddresses'] = [
    {'id': 'ga_sw', 'address': '1/1/5', 'name': 'WC light', 'dpt': '1.001'},
    {'id': 'ga_sws', 'address': '1/1/6', 'name': 'WC light status', 'dpt': '1.001'},
    {'id': 'ga_dim', 'address': '2/0/1', 'name': 'Dim on/off', 'dpt': '1.001'},
    {'id': 'ga_lvl', 'address': '2/0/2', 'name': 'Dim level', 'dpt': '5.001'},
    {'id': 'ga_ud', 'address': '3/0/1', 'name': 'Blind move', 'dpt': '1.008'},
    {'id': 'ga_pos', 'address': '3/0/2', 'name': 'Blind pos', 'dpt': '5.001'},
    {'id': 'ga_x', 'address': '4/0/1', 'name': 'Pump', 'dpt': '1.001'},
    {'id': 'ga_num', 'address': '4/0/2', 'name': 'Temp', 'dpt': '9.001'},
  ];
  final pages = jsonList(doc['pages']);
  final room = pages.isNotEmpty ? pages.first : (<String, dynamic>{'id': 'p1', 'title': 'Home', 'subpages': <dynamic>[]});
  if (pages.isEmpty) doc['pages'] = [room];
  var subs = jsonList(room['subpages']);
  if (subs.isEmpty) {
    room['subpages'] = [
      <String, dynamic>{'id': 's1', 'title': 'Main', 'widgets': <dynamic>[]}
    ];
    subs = jsonList(room['subpages']);
  }
  room['title'] = 'Living';
  subs.first['widgets'] = [
    {
      'id': 'w_sw',
      'type': 'switch',
      'label': 'WC',
      'bind': {'write': 'ga_sw', 'status': 'ga_sws'}
    },
    {
      'id': 'w_dim',
      'type': 'dimmer',
      'label': 'Lamp',
      'bind': {'write': 'ga_dim', 'value': 'ga_lvl'}
    },
    {
      'id': 'w_bl',
      'type': 'blind',
      'label': 'Blind',
      'bind': {'upDown': 'ga_ud', 'position': 'ga_pos'}
    },
    {
      'id': 'w_val',
      'type': 'value',
      'label': 'Temp',
      'bind': {'value': 'ga_num'}
    },
  ];
  check(boxTargets(doc).isEmpty && !boxDeclared(doc), 'no box, no targets');
  doc['box'] = {
    'added': true,
    'name': 'Villa box',
    'host': '',
    'key': key,
    'bus': {'mode': 'routing'},
    'extra': [
      {'ga': 'ga_x', 'name': 'Pump'},
      {'ga': 'ga_sw', 'name': ''},
      {'ga': 'ga_num', 'name': 'Not a bit'},
      {'ga': 'gone', 'name': 'Removed'},
    ],
  };
  check(!boxDeclared(doc) && boxForApp(doc).isEmpty, 'a box without an address is not declared');
  (doc['box'] as Map)['host'] = '192.168.1.60';
  check(boxDeclared(doc) && boxForApp(doc)['key'] == key, 'declared');
  final ts = boxTargets(doc);
  check(ts.map((e) => e.key).join(',') == 'g:ga_x,g:ga_sw', 'only the chosen 1-bit addresses: ${ts.map((e) => e.key)}');
  check(ts[0].title == 'Pump' && ts[1].title == 'WC light', 'titles');
  check(boxActions(ts[0]).map((e) => e.$1).join(',') == 'on,off' && boxCanWatch(ts[0]), 'actions, watch');
  final off = boxWriteOf(doc, 'g:ga_x', 'off', null)!;
  check(off.ga['id'] == 'ga_x' && off.p.short && off.p.shortValue == 0, 'off');
  check(boxWriteOf(doc, 'c:w_sw', 'off', null) == null, 'a card is not a target');
  check(boxWatchOf(doc, 'g:ga_x', true)!.ga['id'] == 'ga_x', 'watched on its own address');

  // Timers.
  final sch = makeBoxTimer('schedule')
    ..['title'] = 'Night off'
    ..['tg'] = 'g:ga_sw'
    ..['act'] = 'off'
    ..['time'] = '22:30'
    ..['days'] = [1, 2, 3, 4, 5];
  final lamp = makeBoxTimer('schedule')
    ..['tg'] = 'g:ga_x'
    ..['act'] = 'on'
    ..['time'] = '6:05'
    ..['days'] = [6, 7];
  final cd = makeBoxTimer('countdown')
    ..['title'] = 'Pump auto off'
    ..['wtg'] = 'g:ga_x'
    ..['wval'] = 'on'
    ..['amount'] = 10
    ..['unit'] = 'm'
    ..['secs'] = 600
    ..['tg'] = 'g:ga_x'
    ..['act'] = 'off';
  final timers = [sch, lamp, cd];
  check(boxProblems(doc, timers).isEmpty, 'no problems: ${boxProblems(doc, timers)}');
  final w = boxTimersWire(doc, timers);
  final t = (w['timers'] as List).cast<Map>();
  check(t.length == 3, 'three timers on the wire');
  check(t[0]['k'] == 's' && t[0]['m'] == 22 * 60 + 30 && t[0]['d'] == 0x1F && t[0]['g'] == (1 << 11 | 1 << 8 | 5) && t[0]['a'] == '00' && t[0]['as'] == 1,
      'schedule: ${t[0]}');
  check(t[0]['n'] == 'Night off' && t[0]['gn'] == 'WC light', 'names for the web page');
  check(t[1]['m'] == 6 * 60 + 5 && t[1]['d'] == 0x60 && t[1]['g'] == (4 << 11 | 1) && t[1]['a'] == '01' && t[1]['as'] == 1, 'weekend on: ${t[1]}');
  check(t[2]['k'] == 'c' && t[2]['w'] == t[2]['g'] && t[2]['v'] == '01' && t[2]['vs'] == 1 && t[2]['s'] == 600 && t[2]['a'] == '00' && t[2]['r'] == 1,
      'countdown: ${t[2]}');
  check((w['ui'] as List).length == 3 && (w['rev'] as String).length == 12, 'ui blob and rev');
  check(boxTimersWire(doc, timers)['rev'] == w['rev'], 'the fingerprint is stable');
  sch['act'] = 'on';
  check(boxTimersWire(doc, timers)['rev'] != w['rev'], 'the fingerprint changes');
  sch['act'] = 'off';
  lamp['on'] = false;
  final w2 = boxTimersWire(doc, timers);
  check((w2['timers'] as List).length == 2 && (w2['ui'] as List).length == 3, 'a timer that is off is kept for the phone but not run');
  lamp['on'] = true;

  // Settings.
  var st = boxSettingsWire(doc, tzMinutes: 420);
  check(st['name'] == 'Villa box' && st['tz'] == 420 && (st['bus'] as Map)['mode'] == 'routing', 'settings');
  (doc['box'] as Map)['bus'] = {'mode': 'tunnel', 'host': '', 'port': 3671};
  check(boxSettingsProblems(doc).any((e) => e.contains('interface')), 'tunnel needs the interface address');
  (doc['box'] as Map)['bus'] = {'mode': 'tunnel', 'host': '192.168.1.50', 'port': 3671};
  st = boxSettingsWire(doc, tzMinutes: 420);
  check((st['bus'] as Map)['host'] == '192.168.1.50' && (st['bus'] as Map)['port'] == 3671, 'tunnel settings');

  // Problems.
  cd['act'] = 'on';
  check(boxProblems(doc, timers).any((e) => e.contains('never end')), 'a countdown that restarts itself is refused');
  cd['act'] = 'off';
  cd['secs'] = 0;
  check(boxProblems(doc, timers).any((e) => e.contains('between 1 second')), 'time of a countdown');
  cd['secs'] = 600;
  sch['time'] = '25:00';
  check(boxProblems(doc, timers).any((e) => e.contains('22:30')), 'bad time');
  check((boxTimersWire(doc, timers)['timers'] as List).length == 2, 'a timer with a problem is not run');
  sch['time'] = '22:30';
  lamp['tg'] = 'g:gone';
  check(boxProblems(doc, timers).any((e) => e.contains('not available')), 'removed card');
  lamp['tg'] = 'g:ga_x';

  // What the phone gets.
  final app = exportProject(doc);
  final ab = jsonMap(app['box']);
  check(ab['key'] == key && ab['host'] == '192.168.1.60' && (ab['extra'] as List).length == 4, 'the App configuration has the box');
  (doc['box'] as Map)['host'] = '';
  check(!exportProject(doc).containsKey('box'), 'no address, no box in the App configuration');
  (doc['box'] as Map)['host'] = '192.168.1.60';

  // The client against a small server that checks the signature like the box does.
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  String? lastNonce;
  String? received;
  srv.listen((r) async {
    final body = await utf8.decoder.bind(r).join();
    void out(int st, Object o) {
      r.response.statusCode = st;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(o));
      r.response.close();
    }

    if (r.uri.path == '/api/info') return out(200, {'app': 'evoknx-box', 'claimed': true});
    if (r.uri.path == '/api/claim') {
      received = body;
      return out(200, {'ok': true});
    }
    if (r.uri.path == '/api/challenge') {
      lastNonce = 'nonce${DateTime.now().microsecondsSinceEpoch}';
      return out(200, {'nonce': lastNonce});
    }
    final ok = r.headers.value('X-Nonce') == lastNonce && r.headers.value('X-Sig') == boxSign(key, lastNonce ?? '', r.method, r.uri.path, body);
    lastNonce = null;
    if (!ok) return out(401, {'error': 'bad signature'});
    if (r.uri.path == '/api/config' && r.method == 'POST') received = body;
    out(200, {'ok': true, 'echo': r.uri.path});
  });
  final addr = '127.0.0.1:${srv.port}';
  check((await boxInfo(addr)).ok, 'info without key');
  check((await boxClaim(addr, key)).ok && jsonDecode(received!)['key'] == key, 'claim sends the key');
  final box = <String, dynamic>{'host': addr, 'wan': '', 'key': key};
  check((await boxStatus(box)).ok, 'signed GET');
  final bad = await boxStatus({...box, 'key': 'AAAA'});
  check(!bad.ok && !bad.unreachable && bad.error!.contains('does not accept this key'), 'wrong key: ${bad.error}');
  final push = await boxPush(box, w);
  check(push.ok && jsonDecode(received!)['rev'] == w['rev'], 'signed push of the timers');
  check((await boxPushSettings(box, st)).ok, 'signed settings');
  check((await boxRun(box, 'tm_x')).ok, 'signed run');
  check((await boxSetTime(box, sync: true)).ok, 'signed time');
  final down = await boxStatus({'host': '127.0.0.1:1', 'wan': '', 'key': key});
  check(!down.ok && down.unreachable && down.error!.contains('No connection'), 'no box: ${down.error}');
  final viaWan = await boxStatus({'host': '127.0.0.1:1', 'wan': addr, 'key': key});
  check(viaWan.ok, 'the external address is used when the home one does not answer');
  final noFallback = await boxStatus({'host': addr, 'wan': addr, 'key': 'BAD'});
  check(!noFallback.ok && !noFallback.unreachable, 'an answer (even an error) stops the fallback');
  await srv.close(force: true);

  print('$_pass passed, $_fail failed');
  if (_fail > 0) exit(1);
}
