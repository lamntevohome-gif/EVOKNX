// Tests of the Home Assistant module against a fake HA server (WebSocket).
// Run: dart run tool/ha_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_config/knx_config.dart';

int failed = 0;
void check(bool ok, String name) {
  print('${ok ? 'OK  ' : 'FAIL'} $name');
  if (!ok) failed++;
}

class FakeHa {
  final String token = 'tok';
  late HttpServer server;
  final List<Map<String, dynamic>> calls = [];
  final Map<WebSocket, int> subs = {};
  final Map<String, Map<String, dynamic>> states = {
    'light.den1': {
      'entity_id': 'light.den1',
      'state': 'on',
      'attributes': {
        'friendly_name': 'Đèn 1',
        'brightness': 128,
        'supported_color_modes': ['brightness']
      }
    },
    'cover.rem1': {
      'entity_id': 'cover.rem1',
      'state': 'open',
      'attributes': {'friendly_name': 'Rèm 1', 'current_position': 100}
    },
    'climate.ac': {
      'entity_id': 'climate.ac',
      'state': 'cool',
      'attributes': {
        'friendly_name': 'Máy lạnh',
        'temperature': 25.0,
        'current_temperature': 27.5,
        'hvac_modes': ['off', 'cool', 'heat', 'fan_only', 'dry']
      },
    },
    'sensor.t': {
      'entity_id': 'sensor.t',
      'state': '23.4',
      'attributes': {'friendly_name': 'Nhiệt độ'}
    },
  };

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.uri.path == '/api/websocket') _serve(await WebSocketTransformer.upgrade(req));
    });
  }

  int get port => server.port;

  void _serve(WebSocket ws) {
    ws.add(jsonEncode({'type': 'auth_required', 'ha_version': '2025.1.0'}));
    var authed = false;
    ws.listen((raw) {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      if (!authed) {
        if (m['type'] == 'auth') {
          if (m['access_token'] == token) {
            authed = true;
            ws.add(jsonEncode({'type': 'auth_ok', 'ha_version': '2025.1.0'}));
          } else {
            ws.add(jsonEncode({'type': 'auth_invalid', 'message': 'Invalid access token'}));
          }
        }
        return;
      }
      final id = m['id'];
      void ok([Object? result]) => ws.add(jsonEncode({'id': id, 'type': 'result', 'success': true, 'result': result}));
      switch (m['type']) {
        case 'get_states':
          ok(states.values.toList());
        case 'subscribe_events':
          subs[ws] = id as int;
          ok();
        case 'ping':
          ws.add(jsonEncode({'id': id, 'type': 'pong'}));
        case 'call_service':
          calls.add(m);
          final target = (m['target'] as Map)['entity_id'] as String;
          if (!states.containsKey(target)) {
            ws.add(jsonEncode({
              'id': id,
              'type': 'result',
              'success': false,
              'error': {'code': 'not_found', 'message': 'Entity not found'}
            }));
            return;
          }
          _apply(m['domain'] as String, m['service'] as String, Map<String, dynamic>.from(m['service_data'] as Map), target);
          ok();
      }
    }, onDone: () => subs.remove(ws));
  }

  void _apply(String domain, String service, Map<String, dynamic> data, String id) {
    final s = states[id]!;
    final a = Map<String, dynamic>.from(s['attributes'] as Map);
    switch ('$domain.$service') {
      case 'light.turn_on':
        s['state'] = 'on';
        if (data['brightness_pct'] != null) a['brightness'] = ((data['brightness_pct'] as num) * 255 / 100).round();
      case 'light.turn_off':
        s['state'] = 'off';
      case 'cover.set_cover_position':
        a['current_position'] = data['position'];
        s['state'] = (data['position'] as num) > 0 ? 'open' : 'closed';
      case 'climate.set_temperature':
        a['temperature'] = (data['temperature'] as num).toDouble();
      case 'climate.set_hvac_mode':
        s['state'] = data['hvac_mode'];
      case 'climate.turn_off':
        s['state'] = 'off';
      case 'climate.turn_on':
        s['state'] = 'cool';
    }
    s['attributes'] = a;
    emit(id);
  }

  void emit(String id) {
    for (final e in subs.entries) {
      e.key.add(jsonEncode({
        'id': e.value,
        'type': 'event',
        'event': {
          'event_type': 'state_changed',
          'data': {'entity_id': id, 'new_state': states[id]}
        },
      }));
    }
  }

  Future<void> dropClients() async {
    for (final ws in subs.keys.toList()) {
      await ws.close();
    }
  }

  Future<void> stop() => server.close(force: true);
}

Future<bool> waitFor(bool Function() cond, {int ms = 4000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return cond();
}

Future<void> main() async {
  // ---- URL
  check(haWebSocketUrl('192.168.1.5') == 'ws://192.168.1.5:8123/api/websocket', 'url: bare IP gets port 8123');
  check(haWebSocketUrl('http://ha.local:8123/') == 'ws://ha.local:8123/api/websocket', 'url: http with port');
  check(haWebSocketUrl('https://x.ui.nabu.casa') == 'wss://x.ui.nabu.casa:443/api/websocket', 'url: https → wss 443');

  // ---- values
  HaEntity ent(String id, String state, [Map<String, dynamic> a = const {}]) => HaEntity(id, state, a);
  check(haStatusValue('brightness', ent('light.a', 'on', {'brightness': 128})) == 50, 'status: brightness 128/255 → 50 %');
  check(haStatusValue('brightness', ent('light.a', 'off')) == 0, 'status: light off → 0 %');
  check(haStatusValue('onoff', ent('switch.a', 'off')) == false && haStatusValue('onoff', ent('switch.a', 'on')) == true, 'status: on/off');
  check(haStatusValue('onoff', ent('light.a', 'unavailable')) == null, 'status: unavailable is ignored');
  check(haStatusValue('position', ent('cover.a', 'open', {'current_position': 70})) == 30, 'status: cover 70 (HA) → 30 % (KNX, 0 = open)');
  check(haStatusValue('mode', ent('climate.a', 'fan_only')) == 9 && haStatusValue('mode', ent('climate.a', 'cool')) == 3, 'status: hvac mode → card value');
  check(haStatusValue('sensor', ent('sensor.a', '23,5')) == 23.5, 'status: sensor number');
  final c1 = haCommand(ent('light.a', 'on'), 'brightness', 40)!;
  check(c1.domain == 'light' && c1.service == 'turn_on' && c1.data['brightness_pct'] == 40, 'command: brightness 40 → brightness_pct');
  check(haCommand(ent('light.a', 'on'), 'brightness', 0)!.service == 'turn_off', 'command: brightness 0 → turn_off');
  check(haCommand(ent('cover.a', 'open'), 'position', 30)!.data['position'] == 70, 'command: cover 30 % → position 70');
  check(haCommand(ent('cover.a', 'open'), 'move', true)!.service == 'close_cover' && haCommand(ent('cover.a', 'open'), 'move', false)!.service == 'open_cover',
      'command: up/down');
  check(haCommand(ent('climate.a', 'off'), 'mode', 3)!.data['hvac_mode'] == 'cool', 'command: mode 3 → cool');
  check(
      haCommand(
                  ent('climate.a', 'off', {
                    'hvac_modes': ['off', 'heat_cool']
                  }),
                  'mode',
                  0)!
              .data['hvac_mode'] ==
          'heat_cool',
      'command: auto → heat_cool when there is no auto');
  check(haCommand(ent('climate.a', 'off'), 'onoff', true)!.service == 'turn_on' && haCommand(ent('switch.a', 'on'), 'onoff', false)!.service == 'turn_off',
      'command: power');

  // ---- virtual addresses
  final doc = <String, dynamic>{'groupAddresses': <dynamic>[]};
  final light = ent('light.den1', 'on', {
    'friendly_name': 'Đèn 1',
    'brightness': 128,
    'supported_color_modes': ['brightness']
  });
  check(haSuggest(light).map((a) => a.key).join(',') == 'onoff,brightness', 'suggest: dimmable light');
  final added = addHaEntity(doc, light, ['onoff', 'brightness']);
  final addrs = added.map((g) => g['address']).join(' ');
  check(addrs == '32/1/1 32/1/101 32/1/2 32/1/102', 'addresses: 32/1/1 32/1/101 32/1/2 32/1/102 (got $addrs)');
  addHaEntity(doc, ent('cover.rem1', 'open', {'friendly_name': 'Rèm 1'}), ['position']);
  check((doc['groupAddresses'] as List).any((g) => g['address'] == '32/2/4'), 'addresses: second entity gets number 2');
  addHaEntity(doc, light, ['colortemp']);
  check((doc['groupAddresses'] as List).any((g) => g['address'] == '32/1/3'), 'addresses: an entity keeps its number');
  check(added.every((g) => g['dpt'] != null && isHaAddress(g)), 'addresses: have a DPT and the ha link');
  final ac = ent('climate.ac', 'cool', {'friendly_name': 'Máy lạnh'});
  addHaEntity(doc, ac, ['onoff', 'setpoint', 'current', 'mode']);
  addHaEntity(doc, ent('sensor.t', '23.4', {'friendly_name': 'Nhiệt độ'}), ['sensor']);

  // ---- removing an entity unlinks its cards
  doc['pages'] = [
    {
      'id': 'r1',
      'subpages': [
        {
          'id': 's1',
          'widgets': [
            {
              'id': 'w1',
              'type': 'switch',
              'bind': {'write': (doc['groupAddresses'] as List).firstWhere((g) => g['address'] == '32/1/1')['id'], 'status': 'zzz'}
            },
          ],
        },
      ],
    },
  ];
  check(haEntityUses(doc, 'light.den1') == 1, 'remove: counts the cards that use the entity');
  final copy = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
  check(removeHaEntity(copy, 'light.den1') == 1, 'remove: unlinks the card slot');
  check(!(copy['groupAddresses'] as List).any((g) => g['ha'] is Map && g['ha']['entity'] == 'light.den1'), 'remove: addresses gone');
  check((copy['groupAddresses'] as List).any((g) => g['ha'] is Map && g['ha']['entity'] == 'cover.rem1'), 'remove: other entities stay');

  // ---- an ETS import (even "replace") keeps the virtual addresses
  final etsDoc = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
  (etsDoc['groupAddresses'] as List).add({'id': 'ga_x', 'address': '1/1/1', 'name': 'x', 'dpt': '1.001'});
  final before = haAddresses(etsDoc).length;
  applyEts(etsDoc, EtsResult([EtsItem('2/2/2', 'y', '1.001')], 'p'), replace: true);
  check(haAddresses(etsDoc).length == before && !(etsDoc['groupAddresses'] as List).any((g) => g['address'] == '1/1/1'),
      'ETS replace: keeps virtual addresses, removes the missing KNX one');
  check(importStats(etsDoc, [EtsItem('2/2/2', 'y', '1.001')]).gone == 0, 'ETS stats: virtual addresses are not counted as removed');

  // ---- server: wrong token, right token
  final ha = FakeHa();
  await ha.start();
  final url = '127.0.0.1:${ha.port}';
  try {
    await haFetchEntities(url, 'sai');
    check(false, 'connect: wrong token is refused');
  } on HaException catch (e) {
    check(e.message.contains('Token'), 'connect: wrong token is refused (${e.message})');
  }
  final r = await haFetchEntities(url, 'tok');
  check(r.version == '2025.1.0' && r.entities.length == 4, 'connect: version and ${r.entities.length} entities');
  try {
    await haFetchEntities('127.0.0.1:1', 'tok');
    check(false, 'connect: nothing listening');
  } on HaException {
    check(true, 'connect: nothing listening gives an error');
  }

  // ---- bridge
  final got = <String, Object?>{};
  final bridge = HaBridge(url: url, token: 'tok', addresses: haAddresses(doc));
  bridge.onValue = (a, v) => got[a] = v;
  Json ga(String address) => (doc['groupAddresses'] as List).firstWhere((g) => g['address'] == address) as Json;
  check(await bridge.write(ga('32/1/1'), true) != null, 'bridge: write before connecting reports an error');
  await bridge.start();
  check(await waitFor(() => bridge.connected), 'bridge: connected');
  check(await waitFor(() => got['32/1/101'] == true && got['32/1/102'] == 50), 'bridge: initial state pushed (on, 50 %)');
  check(got['32/2/104'] == 0, 'bridge: cover open → 0 %');
  check(got['32/3/107'] == 25.0, 'bridge: setpoint 25 pushed');
  check(got['32/3/108'] == 27.5 && got['32/4/110'] == 23.4, 'bridge: room temperature and sensor pushed');

  check(await bridge.write(ga('32/1/1'), false) == null, 'bridge: write on/off');
  check(await waitFor(() => got['32/1/101'] == false), 'bridge: status follows (off)');
  check(ha.calls.last['domain'] == 'light' && ha.calls.last['service'] == 'turn_off' && (ha.calls.last['target'] as Map)['entity_id'] == 'light.den1',
      'bridge: sent light.turn_off to light.den1');
  check(await bridge.write(ga('32/1/2'), 40) == null, 'bridge: write brightness 40');
  check(await waitFor(() => got['32/1/102'] == 40), 'bridge: brightness status 40 %');
  check(await bridge.write(ga('32/2/4'), 30) == null, 'bridge: write cover position 30 %');
  check(ha.states['cover.rem1']!['attributes']['current_position'] == 70, 'bridge: HA received position 70');
  check(await waitFor(() => got['32/2/104'] == 30), 'bridge: cover status back as 30 %');
  // climate.ac is entity 3: power 1/101, setpoint 7/107, room 108, mode 9/109
  check(await bridge.write(ga('32/3/7'), 24.5) == null, 'bridge: write setpoint');
  check(await waitFor(() => got['32/3/107'] == 24.5), 'bridge: setpoint status 24.5');
  check(await bridge.write(ga('32/3/9'), 1) == null, 'bridge: write mode heat (1)');
  check(await waitFor(() => got['32/3/109'] == 1), 'bridge: mode status heat');
  check(await bridge.write(ga('32/3/1'), false) == null, 'bridge: power off');
  check(await waitFor(() => got['32/3/101'] == false), 'bridge: power status off');

  // ---- an unknown entity gives the HA error text
  final ghost = <String, dynamic>{
    'id': 'x',
    'address': '32/9/1',
    'name': 'ghost',
    'dpt': '1.001',
    'ha': {'entity': 'light.khong_co', 'attr': 'onoff', 'role': 'cmd'}
  };
  final err = await bridge.write(ghost, true);
  check(err != null && err.contains('not found'), 'bridge: error of HA is returned ($err)');

  // ---- reconnect
  got.clear();
  await ha.dropClients();
  check(await waitFor(() => !bridge.connected, ms: 1500), 'bridge: notices the lost connection');
  check(await waitFor(() => bridge.connected && got.isNotEmpty, ms: 6000), 'bridge: reconnects and pushes the states again');
  await bridge.stop();
  check(bridge.state == HaConnection.disconnected, 'bridge: stopped');
  await ha.stop();

  print(failed == 0 ? '\nHA tests: all passed' : '\nHA tests: $failed FAILED');
  exit(failed == 0 ? 0 : 1);
}
