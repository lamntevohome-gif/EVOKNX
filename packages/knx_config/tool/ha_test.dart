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
    'remote.tv': {
      'entity_id': 'remote.tv',
      'state': 'on',
      'attributes': {'friendly_name': 'TV remote'}
    },
    'media_player.avr': {
      'entity_id': 'media_player.avr',
      'state': 'on',
      'attributes': {
        'friendly_name': 'AV receiver',
        'source_list': ['HDMI 1', 'HDMI 2'],
        'sound_mode_list': ['Movie', 'Music']
      }
    },
    'media_player.nows': {
      'entity_id': 'media_player.nows',
      'state': 'playing',
      'attributes': {'friendly_name': 'No thumbnail command', 'entity_picture': '/api/media_player_proxy/media_player.nows?token=x&cache=1'}
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
        'friendly_name': 'Air conditioner',
        'temperature': 25.0,
        'current_temperature': 27.5,
        'hvac_modes': ['off', 'cool', 'heat', 'fan_only', 'dry']
      },
    },
    'sensor.t': {
      'entity_id': 'sensor.t',
      'state': '23.4',
      'attributes': {'friendly_name': 'Temperature'}
    },
  };

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.uri.path == '/api/websocket') {
        _serve(await WebSocketTransformer.upgrade(req));
      } else if (req.uri.path.startsWith('/api/media_player_proxy/')) {
        // The picture of a player: with the login of Home Assistant, or with the token of the address.
        final good = req.headers.value('authorization') == 'Bearer $token' || req.uri.queryParameters['token'] == 'x';
        if (good) {
          req.response.add([9, 8, 7]);
        } else {
          req.response.statusCode = 401;
        }
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
  }

  int get port => server.port;

  /// How many times a client logged in (right or wrong).
  int authCount = 0;

  void _serve(WebSocket ws) {
    ws.add(jsonEncode({'type': 'auth_required', 'ha_version': '2025.1.0'}));
    var authed = false;
    ws.listen((raw) {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      if (!authed) {
        if (m['type'] == 'auth') {
          authCount++;
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
        case 'media_player_thumbnail':
          if (m['entity_id'] == 'media_player.nows' || !(m['entity_id'] as String).startsWith('media_player.')) {
            ws.add(jsonEncode({
              'id': id,
              'type': 'result',
              'success': false,
              'error': {'code': 'unknown_command', 'message': 'Unknown command.'}
            }));
            break;
          }
          ok({
            'content_type': 'image/png',
            'content': base64Encode([1, 2, 3, 4])
          });
        case 'get_services':
          ok({
            'light': {
              'turn_on': {
                'name': 'Turn on',
                'description': 'Turn on a light.',
                'fields': {
                  'brightness_pct': {
                    'name': 'Brightness',
                    'description': 'Brightness in percent.',
                    'required': false,
                    'selector': {
                      'number': {'min': 0, 'max': 100, 'unit_of_measurement': '%'}
                    },
                    'example': 47
                  },
                  'advanced_fields': {
                    'collapsed': true,
                    'fields': {
                      'transition': {
                        'selector': {
                          'number': {'min': 0, 'max': 300}
                        },
                        'required': true
                      }
                    }
                  },
                  'flash': {
                    'selector': {
                      'select': {
                        'options': ['short', 'long']
                      }
                    }
                  },
                  'color_name': {
                    'selector': {'text': null}
                  },
                  'color_temp_kelvin': {
                    'selector': {
                      'color_temp': {'unit': 'kelvin', 'min': 2000, 'max': 6500}
                    }
                  },
                  'rgb_color': {
                    'selector': {'color_rgb': null},
                    'example': [255, 100, 100]
                  },
                  'hs_color': {
                    'description': 'Color in hue/sat format. A list of two integers. Hue is 0-360 and Sat is 0-100.',
                    'selector': {'object': null},
                    'example': [300, 70]
                  },
                  'white': {
                    'selector': {
                      'constant': {'value': true, 'label': 'Enabled'}
                    }
                  }
                }
              },
              'turn_off': {}
            },
            'remote': {'send_command': {}},
            'media_player': {'select_source': {}, 'volume_set': {}},
          });
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

  final mp = ent('media_player.tv', 'playing', {'volume_level': 0.35, 'is_volume_muted': false});
  check(haStatusValue('volume', mp) == 35 && haStatusValue('mute', mp) == false && haStatusValue('playing', mp) == true && haStatusValue('onoff', mp) == true,
      'status: media player volume, mute, playing, power');
  check(haStatusValue('onoff', ent('media_player.a', 'standby')) == false, 'status: media player standby counts as off');
  check(haCommand(mp, 'volume', 50)!.data['volume_level'] == 0.5 && haCommand(mp, 'mute', true)!.data['is_volume_muted'] == true,
      'command: media player volume and mute');
  check(
      haCommand(mp, 'playpause', 1)!.service == 'media_play_pause' &&
          haCommand(mp, 'next', 1)!.service == 'media_next_track' &&
          haCommand(mp, 'prev', 1)!.service == 'media_previous_track' &&
          haCommand(mp, 'mstop', 1)!.service == 'media_stop',
      'command: media player buttons');
  check(haCommand(mp, 'onoff', true)!.domain == 'media_player' && haCommand(ent('automation.a', 'on'), 'scene', 1)!.service == 'trigger',
      'command: media player power, automation trigger');

  // ---- virtual addresses. The Editor no longer makes them (a card follows an entity directly), but a project made with
  // the old Extensions tab still has them and the bridge still runs them: they are made here by hand.
  final doc = <String, dynamic>{'groupAddresses': <dynamic>[]};
  var seq = 0;
  List<Json> addVirtual(HaEntity e, List<String> keys) {
    final out = <Json>[];
    for (final key in keys) {
      final a = haAttr(key)!;
      for (final role in ['cmd', 'status']) {
        if (role == 'cmd' ? !a.cmd : (!a.status || const ['scene', 'script', 'automation'].contains(e.domain))) continue;
        seq++;
        final g = <String, dynamic>{
          'id': 'ga_t$seq',
          'address': '40/${seq ~/ 200}/${seq % 200 + 1}',
          'name': '${e.id} · ${a.label} ($role)',
          'dpt': a.dpt,
          'ha': {'entity': e.id, 'attr': key, 'role': role},
        };
        (doc['groupAddresses'] as List).add(g);
        out.add(g);
      }
    }
    return out;
  }

  final light = ent('light.den1', 'on', {
    'friendly_name': 'Đèn 1',
    'brightness': 128,
    'supported_color_modes': ['brightness']
  });
  final added = addVirtual(light, ['onoff', 'brightness']);
  check(added.length == 4 && added.every((g) => g['dpt'] != null && isHaAddress(g)),
      'virtual addresses: a dimmable light has a command and a status for each function');
  addVirtual(ent('cover.rem1', 'open', {'friendly_name': 'Rèm 1'}), ['position']);
  addVirtual(light, ['colortemp']);
  addVirtual(ent('climate.ac', 'cool', {'friendly_name': 'Air conditioner'}), ['onoff', 'setpoint', 'current', 'mode']);
  addVirtual(ent('sensor.t', '23.4', {'friendly_name': 'Temperature'}), ['sensor']);
  addVirtual(ent('light.den2', 'on', {'friendly_name': 'Đèn 2', 'brightness': 1}), ['onoff']);
  addVirtual(ent('switch.quat', 'on', {'friendly_name': 'Fan'}), ['onoff']);
  addVirtual(ent('cover.rem2', 'open', {'friendly_name': 'Rèm 2'}), ['move', 'stop']);
  addVirtual(ent('media_player.tv', 'playing', {'friendly_name': 'TV'}), ['onoff', 'playpause', 'volume', 'mute', 'playing']);

  // ---- a card follows an entity of Home Assistant (nothing is added to the project)
  final cdoc = newProject('c');
  final cw = makeWidget('switch', 0, 0);
  cw['bind'] = {'write': 'ga_x', 'status': 'ga_y'};
  check(setCardEntity(cw, 'light.den1') == null && cardEntity(cw) == 'light.den1' && cw['source'] == 'ha' && jsonMap(cw['bind']).isEmpty,
      'card entity: a switch takes a light and forgets its KNX addresses');
  check(jsonList(cdoc["groupAddresses"]).isEmpty, "card entity: nothing is added to the project");
  check(setCardEntity(makeWidget('switch', 0, 0), 'sensor.t') != null && setCardEntity(makeWidget('switch', 0, 0), 'oops') != null,
      'card entity: a sensor does not fit a switch; a wrong name is refused');
  final cv = makeWidget('value', 0, 0);
  check(setCardEntity(cv, 'sensor.temp') == null, 'card entity: a value card takes a sensor');
  final cs = makeWidget('scene', 0, 0);
  check(setCardEntity(cs, 'scene.movie') == null, 'card entity: a scene card takes a scene');
  final cw2 = makeWidget('switch', 0, 0);
  setCardEntity(cw2, 'light.den1');
  (((cdoc['pages'] as List)
    ..add({
      'id': 'rc',
      'title': 'R',
      'subpages': [
        {
          'id': 'sc',
          'title': 'P',
          'widgets': [cw, cw2, cv, cs]
        }
      ]
    })));
  final ce = cardEntities(cdoc);
  check(ce.binds[cw['id']]!['write'] != null && ce.binds[cw['id']]!['status'] != null && ce.binds[cw['id']]!['write'] == ce.binds[cw2['id']]!['write'],
      'card entity: two cards that follow one entity share its addresses');
  check(
      ce.binds[cs['id']]!.length == 1 &&
          ce.binds[cv['id']]!.keys.single == 'status' &&
          ce.gas.length == 4 &&
          ce.gas.every((g) => g['ha'] is Map && g['ha']['card'] == true),
      'card entity: a scene has a command address, a value a status address; four addresses in all');
  check(ce.gas.map((g) => g['address']).toSet().length == 4 && ce.gas.every((g) => g['address'].toString().startsWith('1000/')),
      'card entity: the addresses are different and in the reserved main group');
  applyCardEntities(cdoc);
  applyCardEntities(cdoc);
  check(jsonList(cdoc['groupAddresses']).length == 4 && jsonMap(cw['bind'])['write'] != null && isHaAddress(jsonList(cdoc['groupAddresses']).first),
      'card entity: applying twice gives the same result');
  check(haAddresses(cdoc).length == 4, 'card entity: the bridge gets the addresses of the cards');
  // dimmer, blind and air conditioner
  final fdocW = newProject('f');
  final dmW = makeWidget('dimmer', 0, 0),
      dm2W = makeWidget('dimmer', 0, 0),
      shW = makeWidget('shutter', 0, 0),
      sh2W = makeWidget('shutter', 0, 0),
      acW = makeWidget('ac', 0, 0);
  dm2W['features'] = {'tw': true};
  sh2W['showStop'] = false;
  check(
      setCardEntity(dmW, 'light.lamp') == null &&
          setCardEntity(dm2W, 'light.lamp') == null &&
          setCardEntity(shW, 'cover.blind') == null &&
          setCardEntity(sh2W, 'cover.blind') == null &&
          setCardEntity(acW, 'climate.ac') == null,
      'card entity: a dimmer takes a light, a blind a cover, an air conditioner a climate');
  check(setCardEntity(makeWidget('dimmer', 0, 0), 'cover.blind') != null && setCardEntity(makeWidget('ac', 0, 0), 'light.lamp') != null,
      'card entity: the wrong kind of entity is refused');
  (((fdocW['pages'] as List)
    ..add({
      'id': 'rf',
      'title': 'F',
      'subpages': [
        {
          'id': 'sf',
          'title': 'P',
          'widgets': [dmW, dm2W, shW, sh2W, acW]
        }
      ]
    })));
  final feW = cardEntities(fdocW);
  check(feW.binds[dmW['id']]!.keys.join(',') == 'write,value,status', 'dimmer: on/off, brightness and its status (${feW.binds[dmW['id']]!.keys})');
  check(feW.binds[dm2W['id']]!.keys.join(',') == 'write,value,status,ctWrite,ctStatus' && feW.binds[dm2W['id']]!['write'] == feW.binds[dmW['id']]!['write'],
      'dimmer: with color temperature two more fields; the addresses are shared');
  check(feW.binds[shW['id']]!.keys.join(',') == 'upDown,stop,position,status' && feW.binds[sh2W['id']]!.keys.join(',') == 'upDown,position,status',
      'blind: up/down, stop, position and status (stop only when the card shows it)');
  check(feW.binds[acW['id']]!.keys.join(',') == 'power,powerSt,setpoint,setpointSt,current,mode,modeSt',
      'air conditioner: power, setpoint, room temperature and mode with their statuses');
  final usedW = {for (final g in feW.gas) g['ha']['attr'] + '/' + g['ha']['role']};
  check(
      usedW.containsAll(
          ['brightness/cmd', 'brightness/status', 'colortemp/cmd', 'move/cmd', 'stop/cmd', 'position/status', 'setpoint/cmd', 'current/status', 'mode/status']),
      'card entity: the addresses follow the right functions ($usedW)');
  check(feW.gas.every((g) => haAttr(g['ha']['attr']) != null && g['dpt'] == haAttr(g['ha']['attr'])!.dpt),
      'card entity: each address has the DPT of its function');
  final sw = makeWidget('switch', 0, 0);
  sw['bind'] = {'write': 'ga_x', 'status': 'ga_y'};
  check(switchCardSource(sw, 'ha') && jsonMap(sw['bind']).isEmpty && cardIsHa(sw) && sw['source'] == 'ha', 'card source: HA forgets the KNX addresses at once');
  check(!switchCardSource(sw, 'ha'), 'card source: nothing changes when the source is the same');
  setCardEntity(sw, 'light.den1');
  check(switchCardSource(sw, 'knx') && cardEntity(sw).isEmpty && sw['source'] == null && !cardIsHa(sw), 'card source: KNX forgets the entity');

  // ---- a value card takes a binary sensor; the entity of any card
  final vbin = makeWidget('value', 0, 0);
  check(setCardEntity(vbin, 'binary_sensor.door') == null && setCardEntity(makeWidget('value', 0, 0), 'light.x') != null,
      'value card: a binary sensor is taken, a light is not');
  final vdoc = newProject('v');
  (((vdoc['pages'] as List)
    ..add({
      'id': 'rv',
      'title': 'R',
      'subpages': [
        {
          'id': 'sv',
          'title': 'P',
          'widgets': [vbin]
        }
      ]
    })));
  final vce = cardEntities(vdoc);
  check(
      vce.gas.length == 1 &&
          vce.gas.single['ha']['attr'] == 'binary' &&
          vce.gas.single['dpt'] == '1.001' &&
          vce.binds[vbin['id']]!['status'] == vce.gas.single['id'],
      'value card: a binary sensor gives an on/off status address');
  check(
      widgetEntity(vbin) == 'binary_sensor.door' &&
          widgetEntity(makeWidget('media', 0, 0)) == '' &&
          widgetEntity({
                'type': 'media',
                'media': {'entity': ' media_player.a '}
              }) ==
              'media_player.a' &&
          widgetEntity({
                'type': 'remote',
                'remote': {'entity': 'remote.tv'}
              }) ==
              'remote.tv',
      'widgetEntity: the entity of a card, a media player card and a remote card');
  // ---- the remote control card
  final rcard = makeWidget('remote', 0, 0);
  check(remoteProblem(rcard) == 'choose the remote.' && remoteCall(rcard, 'up') == null, 'remote card: it needs a remote');
  rcard['remote'] = {
    'entity': 'remote.tv',
    'preset': 'Samsung TV',
    'device': 'TV',
    'keys': {'ok': 'KEY_OK'}
  };
  final rup = remoteCall(rcard, 'up')!, rok = remoteCall(rcard, 'ok')!;
  check(
      rup.service == 'remote.send_command' &&
          rup.entity == 'remote.tv' &&
          rup.data['command'] == 'KEY_UP' &&
          rup.data['device'] == 'TV' &&
          rok.data['command'] == 'KEY_OK',
      'remote card: the names of the platform, the ones typed on the card win, the device is sent');
  rcard['remote'] = {'entity': 'remote.tv', 'preset': 'Apple TV'};
  check(
      remoteCall(rcard, 'mute') == null &&
          remoteCall(rcard, 'ok')!.data['command'] == 'select' &&
          !remoteCall(rcard, 'ok')!.data.containsKey('device') &&
          remoteProblem(rcard) == null,
      'remote card: a key without a name is left out; no device when none is set');
  check(
      kRemotePresets.values.every((p) => p.keys.every((k) => kRemoteKeys.any((x) => x.$1 == k))) && kRemotePresets['Android TV']!.length == kRemoteKeys.length,
      'remote card: the presets only use known keys');

  // ---- push button commands for a media player and a remote
  final btSonos = HaEntity('media_player.sonos', 'playing', {
    'supported_features': 4 | 16 | 32 | 1 | 2048,
    'source_list': ['TV', 'Line In']
  });
  final btKeys = haCommandsFor(btSonos).map((c) => c.key).toList();
  check(
    btKeys.contains('volume_set') &&
        btKeys.contains('next') &&
        btKeys.contains('select_source') &&
        btKeys.contains('pause') &&
        !btKeys.contains('seek') &&
        !btKeys.contains('play_media') &&
        !btKeys.contains('select_sound_mode'),
    'commands: only those that the player supports ($btKeys)',
  );
  check(
      haCommandsFor(btSonos, all: true).length == kMediaCommands.length && haCommandsFor(HaEntity('media_player.x', 'on', {})).length == kMediaCommands.length,
      'commands: all of them when the features are not listed or "all" is on');
  final btVol = haCommandByKey('media_player', 'volume_set')!;
  check(
    haCommandData(btVol, {'volume_level': '35'}).$1!['volume_level'] == 0.35 &&
        haCommandData(btVol, {}).$2 != null &&
        haCommandData(btVol, {'volume_level': '150'}).$2 != null &&
        haCommandData(btVol, {'volume_level': 'abc'}).$2 != null,
    'commands: the volume in % becomes 0–1; a missing, wrong or out of range value is refused',
  );
  check(haCommandData(haCommandByKey('media_player', 'select_source')!, {'source': ' HDMI 2 '}).$1!['source'] == 'HDMI 2',
      'commands: the text is sent as it is (trimmed)');
  final btPm = haCommandData(haCommandByKey('media_player', 'play_media')!, {'media_content_id': 'x://y'}).$1!;
  check(btPm['media_content_id'] == 'x://y' && btPm['media_content_type'] == 'music', 'commands: a choice with an initial value');
  check(
      haCommandData(haCommandByKey('media_player', 'mute')!, {}).$1!['is_volume_muted'] == true &&
          haCommandData(haCommandByKey('media_player', 'unmute')!, {}).$1!['is_volume_muted'] == false,
      'commands: mute and unmute');
  check(haParamSuggestions(btSonos, haCommandByKey('media_player', 'select_source')!.params.first).join(',') == 'TV,Line In',
      'commands: the sources of the player are suggested');
  final btSend = haCommandData(haCommandByKey('remote', 'send_command')!, {'command': 'DPAD_UP', 'num_repeats': '3', 'hold_secs': '0,5', 'device': ''}).$1!;
  check(
      btSend['command'] == 'DPAD_UP' &&
          btSend['num_repeats'] == 3 &&
          btSend['hold_secs'] == 0.5 &&
          !btSend.containsKey('device') &&
          !btSend.containsKey('delay_secs'),
      'remote: command, repeats and hold time; empty fields are left out');
  check(
    haCommandsFor(HaEntity('remote.a', 'on', {
          'activity_list': ['TV']
        })).any((c) => c.key == 'start_activity') &&
        !haCommandsFor(HaEntity('remote.b', 'on', {'supported_features': 0})).any((c) => c.key == 'start_activity'),
    'remote: activities only when the remote has them',
  );
  final btn = makeWidget('button', 0, 0);
  check(setCardEntity(btn, 'media_player.sonos') == null && haDirect(btn) && haButtonProblem(btn) == 'choose the command.',
      'button: a media player is taken; the command must be chosen');
  setButtonCommand(btn, 'select_source');
  check(haButtonProblem(btn)!.startsWith('fill in') && haButtonCall(btn) == null, 'button: a missing parameter is reported');
  setButtonParam(btn, 'source', 'TV');
  final btCall = haButtonCall(btn)!;
  check(
      btCall.service == 'media_player.select_source' && btCall.entity == 'media_player.sonos' && btCall.data['source'] == 'TV' && haButtonProblem(btn) == null,
      'button: the service call');
  final btDoc = newProject('b');
  (((btDoc['pages'] as List)
    ..add({
      'id': 'rb',
      'title': 'R',
      'subpages': [
        {
          'id': 'sb',
          'title': 'P',
          'widgets': [btn]
        }
      ]
    })));
  check(cardEntities(btDoc).gas.isEmpty && cardEntities(btDoc).binds.isEmpty, 'button: a direct button makes no address');
  setCardEntity(btn, 'remote.tv');
  check(haDirect(btn) && jsonMap(btn['ha'])['action'] == null, 'button: another entity forgets the command');
  setCardEntity(btn, 'light.lamp');
  check(!haDirect(btn), 'button: a light is not a direct button (it uses an address)');
  final btScene = makeWidget('scene', 0, 0);
  check(setCardEntity(btScene, 'media_player.sonos') != null, 'scene card: a media player is refused');

  // ---- the media player card
  final mpm = HaMedia(HaEntity('media_player.sonos', 'playing', {
    'media_title': 'Song',
    'media_artist': 'Artist',
    'media_album_name': 'Album',
    'media_duration': 225,
    'media_position': 80,
    'media_position_updated_at': '2025-01-01T10:00:00+00:00',
    'volume_level': 0.4,
    'is_volume_muted': false,
    'supported_features': 4 | 16 | 32,
    'entity_picture': '/api/media_player_proxy/media_player.sonos?token=x&cache=1',
  }));
  check(mpm.title == 'Song' && mpm.subtitle == 'Artist · Album' && mpm.duration == 225 && mpm.volume == 0.4 && mpm.picture.contains('cache=1'),
      'media: title, artist and album, duration, volume, cover');
  check(mpm.position(DateTime.utc(2025, 1, 1, 10, 0, 3)) == 83, 'media: the position runs while playing');
  check(mpm.position(DateTime.utc(2025, 1, 1, 10, 10)) == 225, 'media: the position stops at the end of the track');
  final pausedM = HaMedia(HaEntity('media_player.sonos', 'paused', {'media_position': 80, 'media_position_updated_at': '2025-01-01T10:00:00+00:00'}));
  check(pausedM.position(DateTime.utc(2025, 1, 1, 11)) == 80 && pausedM.paused && !pausedM.playing, 'media: a paused player keeps its position');
  check(mpm.supports(HaMedia.featVolumeSet) && mpm.supports(HaMedia.featNext) && !mpm.supports(HaMedia.featSeek), 'media: features from supported_features');
  check(pausedM.supports(HaMedia.featSeek) && HaMedia(HaEntity('media_player.x', 'unavailable', {})).available == false,
      'media: a player that lists no features has them all; unavailable');
  check(mediaTime(83) == '1:23' && mediaTime(3725) == '1:02:05' && mediaTime(null) == '–:––', 'media: time text');
  final mdoc = newProject('x');
  check(!haNeeded(mdoc), 'haNeeded: nothing needs Home Assistant');
  check(
      !haAdded(mdoc) &&
          haAdded({
            'ha': {'added': true}
          }) &&
          haAdded({
            'ha': {'url': '10.0.0.1:8123'}
          }) &&
          haAdded({
            'ha': {'enabled': true}
          }) &&
          !haAdded({'ha': {}}),
      'haAdded: a connection was added, or set up before');
  (mdoc['pages'] as List).add({
    'id': 'rm',
    'title': 'Room',
    'subpages': [
      {
        'id': 'sp',
        'title': 'Page',
        'widgets': [makeWidget('media', 0, 0)],
      },
    ],
  });
  check(haNeeded(mdoc) && makeWidget('media', 0, 0)['media']['entity'] == '', 'haNeeded: a media player card needs it');

  // ---- text commands: the text written to the address is the command
  final tvs = ent('media_player.avr', 'on', {
    'source_list': ['HDMI 1', 'HDMI 2'],
    'sound_mode_list': ['Movie']
  });
  final rem = ent('remote.tv', 'on', {'friendly_name': 'TV remote'});
  final cmd = haCommand(rem, 'cmdtext', 'DPAD_UP')!;
  check(cmd.domain == 'remote' && cmd.service == 'send_command' && cmd.data['command'] == 'DPAD_UP', 'send command: the text is the command');
  check(haCommand(tvs, 'srctext', ' HDMI 2 ')!.data['source'] == 'HDMI 2' && haCommand(tvs, 'soundtext', 'Movie')!.service == 'select_sound_mode',
      'source and sound mode: the text');
  check(haCommand(rem, 'acttext', 'Watch TV')!.data['activity'] == 'Watch TV' && identical(haCommand(rem, 'cmdtext', '  '), HaCall.none),
      'activity; an empty text does nothing');
  check(haCommand(rem, 'onoff', true)!.domain == 'remote' && haCommand(rem, 'onoff', false)!.service == 'turn_off', 'remote on/off');
  check(haAttr('cmdtext')!.dpt == '16.000' && !haAttr('cmdtext')!.status, 'text commands are text addresses without a status');
  addVirtual(rem, ['onoff', 'cmdtext']);
  addVirtual(tvs, ['srctext', 'soundtext']);

  String addr(String entity, String attr, String role) {
    for (final g in doc['groupAddresses'] as List) {
      final h = g['ha'];
      if (h is Map && h['entity'] == entity && h['attr'] == attr && h['role'] == role) return g['address'] as String;
    }
    return '';
  }

  Json ga(String address) => (doc['groupAddresses'] as List).firstWhere((g) => g['address'] == address) as Json;

  // ---- scene, script, automation: 1 bit like a light
  final sc = ent('scene.chieu_phim', 'scening', {'friendly_name': 'Chiếu phim'});
  final sr = ent('script.tiep_khach', 'off', {'friendly_name': 'Tiếp khách'});
  final au = ent('automation.movie', 'on', {'friendly_name': 'Movie'});
  check(haAttr('onoff')!.dpt == '1.001', 'scene/script/automation: DPT 1.001');
  check(haCommand(sc, 'onoff', true)!.service == 'turn_on' && haCommand(sc, 'onoff', true)!.domain == 'scene' && haCommand(sc, 'onoff', false)!.isNone,
      'scene: 1 activates, 0 does nothing');
  check(haCommand(sr, 'onoff', true)!.service == 'turn_on' && haCommand(sr, 'onoff', false)!.service == 'turn_off', 'script: 1 runs, 0 stops');
  check(haCommand(au, 'onoff', true)!.service == 'trigger' && haCommand(au, 'onoff', false)!.isNone, 'automation: 1 triggers, 0 does nothing');
  final aSc = addVirtual(sc, ['onoff']), aSr = addVirtual(sr, ['onoff']), aAu = addVirtual(au, ['onoff']);
  check(aSc.length == 1 && aSc.first['ha']['role'] == 'cmd' && aSr.length == 1 && aAu.length == 1,
      'scene, script, automation: only a command address, no status');
  check(aSc.first['dpt'] == '1.001', 'scene: DPT 1.001');

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
    check(e.message.contains('token'), 'connect: wrong token is refused (${e.message})');
  }
  final r = await haFetchEntities(url, 'tok');
  check(r.version == '2025.1.0' && r.entities.length == 7, 'connect: version and ${r.entities.length} entities');
  // The services (for the suggestions of a script)
  final sess = await HaSession.open(url, 'tok');
  final svc = await sess.getServices();
  check(svc['light']!.join(',') == 'turn_off,turn_on' && svc['remote']!.contains('send_command') && svc.length == 3,
      'services: domains with their services ($svc)');
  final cover = await sess.getThumbnail('media_player.avr');
  check(cover != null && cover.join(',') == '1,2,3,4', 'thumbnail: the cover image of a media player ($cover)');
  final info = await sess.getServiceInfo();
  final on = info['light']!['turn_on']!;
  check(
      on.description == 'Turn on a light.' &&
          on.fields.map((f) => f.key).join(',') == 'brightness_pct,transition,flash,color_name,color_temp_kelvin,rgb_color,hs_color,white',
      'service fields: a section is flattened (${on.fields.map((f) => f.key)})');
  final bp = on.fields.firstWhere((f) => f.key == 'brightness_pct');
  check(bp.type == 'number' && bp.sample == 47 && !bp.required && bp.description == 'Brightness in percent.', 'service fields: number with an example');
  check(bp.min == 0 && bp.max == 100 && bp.unit == '%', 'service fields: range and unit');
  String specOf(String k) => on.fields.firstWhere((f) => f.key == k).spec;
  check(bp.spec == '0–100 %' && specOf('transition') == '0–300', 'spec: a number shows its range and unit');
  check(specOf('color_temp_kelvin') == '2000–6500 kelvin', 'spec: color temperature shows its range and unit (${specOf('color_temp_kelvin')})');
  check(specOf('rgb_color') == 'R, G, B: 0–255' && specOf('hs_color') == 'e.g. [300,70]' && specOf('white') == 'fixed: true' && specOf('color_name') == 'text',
      'spec: color formats, an example, a fixed value, text');
  check(specOf('flash') == '' && on.fields.firstWhere((f) => f.key == 'hs_color').brief == 'Color in hue/sat format.',
      'spec: a choice has none; the brief is the first sentence');
  check(on.fields.firstWhere((f) => f.key == 'color_temp_kelvin').sample == 2000 && on.fields.firstWhere((f) => f.key == 'white').sample == true,
      'service fields: color temperature starts at its minimum, a fixed value is its value');
  check(on.fields.firstWhere((f) => f.key == 'flash').options.map((o) => o.$1).join(',') == 'short,long', 'service fields: options of a select');
  check(on.fields.firstWhere((f) => f.key == 'transition').required && on.fields.firstWhere((f) => f.key == 'transition').sample == 0,
      'service fields: required, a number starts at its minimum');
  check(on.fields.firstWhere((f) => f.key == 'flash').sample == 'short' && on.fields.firstWhere((f) => f.key == 'color_name').sample == '',
      'service fields: a select starts at its first option, a text is empty');
  await sess.close();
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
  check(await bridge.write(ga(addr('light.den1', 'onoff', 'cmd')), true) != null, 'bridge: write before connecting reports an error');
  await bridge.start();
  check(await waitFor(() => bridge.connected), 'bridge: connected');
  check(await waitFor(() => got[addr('light.den1', 'onoff', 'status')] == true && got[addr('light.den1', 'brightness', 'status')] == 50),
      'bridge: initial state pushed (on, 50 %)');
  check(got[addr('cover.rem1', 'position', 'status')] == 0, 'bridge: cover open → 0 %');
  check(got[addr('climate.ac', 'setpoint', 'status')] == 25.0, 'bridge: setpoint 25 pushed');
  check(
      got[addr('climate.ac', 'current', 'status')] == 27.5 && got[addr('sensor.t', 'sensor', 'status')] == 23.4, 'bridge: room temperature and sensor pushed');

  check(await bridge.write(ga(addr('light.den1', 'onoff', 'cmd')), false) == null, 'bridge: write on/off');
  check(await waitFor(() => got[addr('light.den1', 'onoff', 'status')] == false), 'bridge: status follows (off)');
  check(ha.calls.last['domain'] == 'light' && ha.calls.last['service'] == 'turn_off' && (ha.calls.last['target'] as Map)['entity_id'] == 'light.den1',
      'bridge: sent light.turn_off to light.den1');
  check(await bridge.write(ga(addr('remote.tv', 'cmdtext', 'cmd')), 'DPAD_UP') == null, 'bridge: write a text command');
  check(
      ha.calls.last['domain'] == 'remote' &&
          ha.calls.last['service'] == 'send_command' &&
          (ha.calls.last['service_data'] as Map)['command'] == 'DPAD_UP' &&
          (ha.calls.last['target'] as Map)['entity_id'] == 'remote.tv',
      'bridge: sent remote.send_command with the text to remote.tv');
  check(await bridge.write(ga(addr('media_player.avr', 'srctext', 'cmd')), 'HDMI 2') == null, 'bridge: write a text source');
  check(
      ha.calls.last['service'] == 'select_source' && (ha.calls.last['service_data'] as Map)['source'] == 'HDMI 2', 'bridge: sent select_source with the text');
  // a refused token is not tried again; entities that Home Assistant does not have are known
  final authBefore = ha.authCount;
  final bad = HaBridge(url: url, token: 'wrong', addresses: const []);
  await bad.start();
  await Future<void>.delayed(const Duration(milliseconds: 2600));
  check(bad.state == HaConnection.failed && (bad.error ?? '').contains('token') && ha.authCount - authBefore == 1,
      'bridge: a refused token is tried once, not again (${ha.authCount - authBefore} tries, ${bad.state})');
  await bad.start();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  check(ha.authCount - authBefore == 2, 'bridge: it tries again when it is started again');
  await bad.stop();
  final gone = HaBridge(url: url, token: 'tok', addresses: [
    {
      'id': 'g1',
      'address': '1000/0/1',
      'dpt': '1.001',
      'ha': {'entity': 'light.gone', 'attr': 'onoff', 'role': 'cmd'}
    },
    {
      'id': 'g2',
      'address': '1000/0/2',
      'dpt': '1.001',
      'ha': {'entity': 'cover.rem1', 'attr': 'move', 'role': 'cmd'}
    },
  ]);
  await gone.start();
  for (var i = 0; i < 40 && !gone.connected; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  check(gone.connected && gone.missingEntities.length == 1 && gone.missingEntities.first == 'light.gone',
      'bridge: the entities that Home Assistant does not have (${gone.missingEntities})');
  await gone.stop();
  final cv1 = await bridge.thumbnail('media_player.avr');
  check(cv1 != null && cv1.join(',') == '1,2,3,4', 'bridge: the cover comes by WebSocket ($cv1)');
  final cv2 = await bridge.thumbnail('media_player.nows');
  check(cv2 != null && cv2.join(',') == '9,8,7', 'bridge: the cover comes over HTTP when the WebSocket command fails ($cv2)');
  check(await bridge.thumbnail('light.den1') == null, 'bridge: no cover for an entity without a picture');
  check(await bridge.write(ga(addr('light.den1', 'brightness', 'cmd')), 40) == null, 'bridge: write brightness 40');
  check(await waitFor(() => got[addr('light.den1', 'brightness', 'status')] == 40), 'bridge: brightness status 40 %');
  check(await bridge.write(ga(addr('cover.rem1', 'position', 'cmd')), 30) == null, 'bridge: write cover position 30 %');
  check(ha.states['cover.rem1']!['attributes']['current_position'] == 70, 'bridge: HA received position 70');
  check(await waitFor(() => got[addr('cover.rem1', 'position', 'status')] == 30), 'bridge: cover status back as 30 %');
  check(await bridge.write(ga(addr('climate.ac', 'setpoint', 'cmd')), 24.5) == null, 'bridge: write setpoint');
  check(await waitFor(() => got[addr('climate.ac', 'setpoint', 'status')] == 24.5), 'bridge: setpoint status 24.5');
  check(await bridge.write(ga(addr('climate.ac', 'mode', 'cmd')), 1) == null, 'bridge: write mode heat (1)');
  check(await waitFor(() => got[addr('climate.ac', 'mode', 'status')] == 1), 'bridge: mode status heat');
  check(await bridge.write(ga(addr('climate.ac', 'onoff', 'cmd')), false) == null, 'bridge: power off');
  check(await waitFor(() => got[addr('climate.ac', 'onoff', 'status')] == false), 'bridge: power status off');

  // ---- an unknown entity gives the HA error text
  final ghost = <String, dynamic>{
    'id': 'x',
    'address': '49/9/1',
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
