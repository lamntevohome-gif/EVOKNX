import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'project.dart';

// ======================================================================
// Home Assistant (HA): virtual group addresses
//
// An HA entity is wired to cards through VIRTUAL group addresses in main
// group 32. KNX main groups only go up to 31, so these can never collide
// with a real address, and they never go to the bus: the App sends them to
// HA instead. Per entity number m and attribute number k:
//   command address  32/m/k          status address  32/m/(100+k)
// ======================================================================

/// Main group of the virtual HA addresses (outside the KNX range 0–31).
const int kHaMainGroup = 32;

/// True when [ga] is a virtual address linked to an HA entity.
bool isHaAddress(Json ga) => ga['ha'] is Map;

/// One thing of an HA entity a card can use.
class HaAttr {
  const HaAttr(this.key, this.label, this.dpt, {this.cmd = true, this.status = true});
  final String key, label, dpt;

  /// Can be written (a command address) / can be read (a status address).
  final bool cmd, status;
}

const List<HaAttr> kHaAttrs = [
  HaAttr('onoff', 'Bật/tắt', '1.001'),
  HaAttr('brightness', 'Độ sáng', '5.001'),
  HaAttr('colortemp', 'Nhiệt độ màu', '7.600'),
  HaAttr('position', 'Vị trí rèm', '5.001'),
  HaAttr('move', 'Rèm lên/xuống', '1.008', status: false),
  HaAttr('stop', 'Rèm dừng', '1.007', status: false),
  HaAttr('setpoint', 'Nhiệt độ cài đặt', '9.001'),
  HaAttr('current', 'Nhiệt độ phòng', '9.001', cmd: false),
  HaAttr('mode', 'Chế độ', '20.105'),
  HaAttr('sensor', 'Giá trị cảm biến', '9.001', cmd: false),
  HaAttr('binary', 'Trạng thái (bật/tắt)', '1.001', cmd: false),
  HaAttr('scene', 'Kích hoạt', '17.001', status: false),
];

HaAttr? haAttr(String key) {
  for (final a in kHaAttrs) {
    if (a.key == key) return a;
  }
  return null;
}

/// An entity as listed by HA.
class HaEntity {
  HaEntity(this.id, this.state, this.attributes);
  final String id, state;
  final Map<String, dynamic> attributes;

  String get domain => id.split('.').first;
  String get name => (attributes['friendly_name'] ?? id).toString();

  factory HaEntity.fromJson(Map<String, dynamic> m) =>
      HaEntity((m['entity_id'] ?? '').toString(), (m['state'] ?? '').toString(), Map<String, dynamic>.from((m['attributes'] as Map?) ?? const {}));

  List<String> get hvacModes => [for (final x in (attributes['hvac_modes'] as List? ?? const [])) x.toString()];
}

/// What can be done with an entity, in the order they are offered.
List<HaAttr> haSuggest(HaEntity e) {
  List<HaAttr> pick(List<String> keys) => [for (final k in keys) haAttr(k)!];
  switch (e.domain) {
    case 'light':
      final modes = [for (final x in (e.attributes['supported_color_modes'] as List? ?? const [])) x.toString()];
      final dim = modes.any((m) => m != 'onoff') || e.attributes.containsKey('brightness');
      return pick(['onoff', if (dim) 'brightness', if (modes.contains('color_temp')) 'colortemp']);
    case 'switch':
    case 'input_boolean':
    case 'fan':
    case 'automation':
      return pick(['onoff']);
    case 'cover':
      return pick(['move', 'stop', 'position']);
    case 'climate':
      return pick(['onoff', 'setpoint', 'current', 'mode']);
    case 'sensor':
      return pick(['sensor']);
    case 'binary_sensor':
      return pick(['binary']);
    case 'scene':
    case 'script':
      return pick(['scene']);
  }
  return const [];
}

/// Adds the virtual addresses of [e] for the attributes [attrKeys] to the
/// project (both a command and a status address where the attribute has
/// them). Returns the new address entries. An entity keeps its number m.
List<Json> addHaEntity(Json doc, HaEntity e, List<String> attrKeys) {
  final gas = (doc['groupAddresses'] = List<dynamic>.from(doc['groupAddresses'] as List? ?? const []));
  // The number of this entity, or the next free one.
  var m = 0;
  for (final g in gas) {
    final h = (g as Map)['ha'];
    if (h is Map && h['entity'] == e.id) {
      m = int.tryParse(g['address'].toString().split('/')[1]) ?? 0;
    }
  }
  if (m == 0) {
    var top = 0;
    for (final g in gas) {
      if ((g as Map)['ha'] is Map) top = [top, int.tryParse(g['address'].toString().split('/')[1]) ?? 0].reduce((a, b) => a > b ? a : b);
    }
    m = top + 1;
  }
  final out = <Json>[];
  for (final key in attrKeys) {
    final a = haAttr(key);
    if (a == null) continue;
    final k = kHaAttrs.indexOf(a) + 1;
    for (final role in ['cmd', 'status']) {
      if ((role == 'cmd' && !a.cmd) || (role == 'status' && !a.status)) continue;
      final addr = '$kHaMainGroup/$m/${role == 'cmd' ? k : 100 + k}';
      if (gas.any((g) => (g as Map)['address'] == addr)) continue;
      final ga = <String, dynamic>{
        'id': uid('ga_'),
        'address': addr,
        'name': '${e.name} · ${a.label}${role == 'cmd' ? ' (lệnh)' : ' (trạng thái)'}',
        'dpt': a.dpt,
        'ha': {'entity': e.id, 'attr': key, 'role': role},
      };
      gas.add(ga);
      out.add(ga);
    }
  }
  return out;
}

/// Removes every virtual address of [entityId] and unlinks them from the
/// cards. Returns how many card slots were unlinked.
int removeHaEntity(Json doc, String entityId) {
  final gas = jsonList(doc['groupAddresses']);
  final gone = <Object?>{
    for (final g in gas)
      if (g['ha'] is Map && g['ha']['entity'] == entityId) g['id']
  };
  if (gone.isEmpty) return 0;
  var unlinked = 0;
  for (final w in allWidgets(doc)) {
    final b = jsonMap(w['bind']);
    b.removeWhere((k, v) {
      final hit = gone.contains(v);
      if (hit) unlinked++;
      return hit;
    });
    w['bind'] = b;
  }
  doc['groupAddresses'] = [
    for (final g in gas)
      if (!gone.contains(g['id'])) g
  ];
  return unlinked;
}

/// How many card slots use the virtual addresses of [entityId].
int haEntityUses(Json doc, String entityId) {
  final ids = <Object?>{
    for (final g in jsonList(doc['groupAddresses']))
      if (g['ha'] is Map && g['ha']['entity'] == entityId) g['id']
  };
  var n = 0;
  for (final w in allWidgets(doc)) {
    for (final v in jsonMap(w['bind']).values) {
      if (ids.contains(v)) n++;
    }
  }
  return n;
}

/// The HA virtual addresses of a project.
List<Json> haAddresses(Json doc) => [
      for (final g in jsonList(doc['groupAddresses']))
        if (isHaAddress(g)) g
    ];

/// Connection settings of the project: {enabled, url, token}.
Json haSettings(Json doc) => jsonMap(doc['ha']);

// ======================================================================
// Values between the cards (KNX-style values) and HA
// ======================================================================

/// A service call for HA.
class HaCall {
  const HaCall(this.domain, this.service, [this.data = const {}]);
  final String domain, service;
  final Map<String, dynamic> data;
}

const Map<String, String> _modeToHa = {'auto': 'auto', 'cool': 'cool', 'heat': 'heat', 'fan': 'fan_only', 'dry': 'dry'};

/// The call that sets [attr] of [e] to [value] (the value as a card sends it).
HaCall? haCommand(HaEntity e, String attr, Object value) {
  final d = e.domain;
  final n = value is bool ? (value ? 1 : 0) : (value is num ? value : num.tryParse(value.toString().replaceAll(',', '.')));
  switch (attr) {
    case 'onoff':
      final on = (n ?? 0) != 0;
      final dom = const ['light', 'switch', 'fan', 'input_boolean', 'climate', 'automation', 'cover'].contains(d) ? d : 'homeassistant';
      if (dom == 'cover') return HaCall('cover', on ? 'open_cover' : 'close_cover');
      return HaCall(dom, on ? 'turn_on' : 'turn_off');
    case 'brightness':
      final pct = (n ?? 0).round().clamp(0, 100);
      return pct == 0 ? const HaCall('light', 'turn_off') : HaCall('light', 'turn_on', {'brightness_pct': pct});
    case 'colortemp':
      return HaCall('light', 'turn_on', {'color_temp_kelvin': (n ?? 0).round()});
    case 'position':
      // KNX: 0 % = open. HA: 100 = open.
      return HaCall('cover', 'set_cover_position', {'position': 100 - (n ?? 0).round().clamp(0, 100)});
    case 'move':
      return HaCall('cover', (n ?? 0) != 0 ? 'close_cover' : 'open_cover');
    case 'stop':
      return const HaCall('cover', 'stop_cover');
    case 'setpoint':
      return HaCall('climate', 'set_temperature', {'temperature': (n ?? 20).toDouble()});
    case 'mode':
      String? key;
      for (final m in kAcModes) {
        if (m.value == n) key = m.key;
      }
      if (key == null) return null;
      var mode = _modeToHa[key]!;
      final modes = e.hvacModes;
      if (key == 'auto' && !modes.contains('auto') && modes.contains('heat_cool')) mode = 'heat_cool';
      return HaCall('climate', 'set_hvac_mode', {'hvac_mode': mode});
    case 'scene':
      return HaCall(d == 'script' ? 'script' : 'scene', 'turn_on');
  }
  return null;
}

/// The value of [attr] in the state of an entity, as a card expects it
/// (bool for on/off, numbers otherwise), or null when it does not apply.
Object? haStatusValue(String attr, HaEntity e) {
  final s = e.state;
  if (s == 'unavailable' || s == 'unknown') return null;
  switch (attr) {
    case 'onoff':
      return e.domain == 'cover' ? s != 'closed' : s != 'off';
    case 'binary':
      return s == 'on';
    case 'brightness':
      if (s == 'off') return 0;
      final b = e.attributes['brightness'];
      return b is num ? (b * 100 / 255).round() : null;
    case 'colortemp':
      final k = e.attributes['color_temp_kelvin'];
      return k is num ? k.round() : null;
    case 'position':
      final p = e.attributes['current_position'];
      return p is num ? 100 - p.round() : null;
    case 'setpoint':
      final t = e.attributes['temperature'];
      return t is num ? t.toDouble() : null;
    case 'current':
      final t = e.attributes['current_temperature'];
      return t is num ? t.toDouble() : null;
    case 'mode':
      for (final m in kAcModes) {
        final ha = _modeToHa[m.key];
        if (s == ha || (m.key == 'auto' && s == 'heat_cool')) return m.value;
      }
      return null;
    case 'sensor':
      return num.tryParse(s.replaceAll(',', '.'));
  }
  return null;
}

// ======================================================================
// WebSocket connection
// ======================================================================

class HaException implements Exception {
  HaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// "192.168.1.5:8123", "http://ha.local:8123", "https://x.ui.nabu.casa" →
/// the WebSocket URL of HA.
String haWebSocketUrl(String base) {
  var u = base.trim();
  if (!u.contains('://')) u = 'http://$u';
  final uri = Uri.parse(u);
  final secure = uri.scheme == 'https' || uri.scheme == 'wss';
  final port = uri.hasPort ? uri.port : (secure ? 443 : 8123);
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  return '${secure ? 'wss' : 'ws'}://${uri.host}:$port$path/api/websocket';
}

/// One authenticated WebSocket session with HA.
class HaSession {
  HaSession._(this._ws);
  final WebSocket _ws;
  String? version;
  int _id = 0;
  bool _authed = false;
  final List<Completer<Map<String, dynamic>>> _handshake = [];
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<int, void Function(Map<String, dynamic> event)> _subs = {};
  final Completer<void> _closed = Completer<void>();

  /// Completes when the connection is gone.
  Future<void> get closed => _closed.future;

  static Future<HaSession> open(String url, String token, {Duration timeout = const Duration(seconds: 8)}) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (_, __, ___) => true;
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(haWebSocketUrl(url), customClient: client).timeout(timeout);
    } on TimeoutException {
      throw HaException('Không kết nối được Home Assistant (quá thời gian chờ). Kiểm tra địa chỉ và mạng.');
    } catch (e) {
      throw HaException('Không kết nối được Home Assistant. Kiểm tra địa chỉ, cổng và mạng. ($e)');
    }
    final s = HaSession._(ws);
    ws.listen(s._onData, onDone: s._onDone, onError: (_) => s._onDone(), cancelOnError: true);
    try {
      final hello = await s._next(timeout);
      if (hello['type'] != 'auth_required') throw HaException('Máy chủ không phải Home Assistant.');
      s.version = hello['ha_version']?.toString();
      ws.add(jsonEncode({'type': 'auth', 'access_token': token}));
      final r = await s._next(timeout);
      if (r['type'] == 'auth_invalid') throw HaException('Token không đúng hoặc đã bị thu hồi.');
      if (r['type'] != 'auth_ok') throw HaException('Home Assistant không chấp nhận đăng nhập.');
      s._authed = true;
      return s;
    } catch (e) {
      await s.close();
      if (e is HaException) rethrow;
      if (e is TimeoutException) throw HaException('Home Assistant không trả lời.');
      throw HaException('$e');
    }
  }

  Future<Map<String, dynamic>> _next(Duration timeout) {
    final c = Completer<Map<String, dynamic>>();
    _handshake.add(c);
    return c.future.timeout(timeout);
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    if (!_authed) {
      if (_handshake.isNotEmpty) _handshake.removeAt(0).complete(m);
      return;
    }
    final id = m['id'];
    switch (m['type']) {
      case 'result':
      case 'pong':
        _pending.remove(id)?.complete(m);
      case 'event':
        _subs[id]?.call(Map<String, dynamic>.from((m['event'] as Map?) ?? const {}));
    }
  }

  void _onDone() {
    for (final c in _handshake) {
      if (!c.isCompleted) c.completeError(HaException('Mất kết nối Home Assistant.'));
    }
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(HaException('Mất kết nối Home Assistant.'));
    }
    _pending.clear();
    if (!_closed.isCompleted) _closed.complete();
  }

  /// Sends a command and waits for its result.
  Future<dynamic> call(Map<String, dynamic> msg, {Duration timeout = const Duration(seconds: 10)}) async {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws.add(jsonEncode({...msg, 'id': id}));
    final Map<String, dynamic> r;
    try {
      r = await c.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw HaException('Home Assistant không trả lời.');
    }
    if (r['success'] == false) {
      final err = r['error'];
      throw HaException(err is Map ? (err['message'] ?? 'Lỗi từ Home Assistant').toString() : 'Lỗi từ Home Assistant');
    }
    return r['result'];
  }

  Future<List<HaEntity>> getStates() async {
    final r = await call({'type': 'get_states'}, timeout: const Duration(seconds: 20));
    return [for (final x in (r as List? ?? const [])) HaEntity.fromJson(Map<String, dynamic>.from(x as Map))];
  }

  /// Subscribes to state changes of all entities.
  Future<void> subscribeStates(void Function(HaEntity e) onChange) async {
    final id = _id + 1;
    _subs[id] = (event) {
      final data = event['data'];
      if (data is Map && data['new_state'] is Map) onChange(HaEntity.fromJson(Map<String, dynamic>.from(data['new_state'] as Map)));
    };
    await call({'type': 'subscribe_events', 'event_type': 'state_changed'});
  }

  Future<void> callService(HaCall c, String entityId) async {
    await call({
      'type': 'call_service',
      'domain': c.domain,
      'service': c.service,
      'service_data': c.data,
      'target': {'entity_id': entityId},
    });
  }

  Future<void> close() async {
    try {
      await _ws.close();
    } catch (_) {}
    _onDone();
  }
}

/// Connects, lists the entities and closes (the Editor's "thử kết nối" and
/// the entity list).
Future<({String? version, List<HaEntity> entities})> haFetchEntities(String url, String token) async {
  final s = await HaSession.open(url, token);
  try {
    return (version: s.version, entities: await s.getStates());
  } finally {
    await s.close();
  }
}

enum HaConnection { disconnected, connecting, connected, failed }

/// The App's / Editor's link to HA: keeps a session open (reconnecting after
/// a failure), pushes status values to [onValue] as if they were telegrams of
/// the virtual addresses, and writes commands.
class HaBridge {
  HaBridge({required this.url, required this.token, required this.addresses});
  final String url, token;

  /// The virtual address entries of the project (see [haAddresses]).
  final List<Json> addresses;

  /// (virtual address, value) for every status that arrives.
  void Function(String address, Object? value)? onValue;

  /// The connection state changed.
  void Function()? onState;

  HaConnection state = HaConnection.disconnected;
  String? error;
  HaSession? _session;
  bool _stopped = true;
  final Map<String, HaEntity> _entities = {};

  bool get connected => state == HaConnection.connected;

  Future<void> start() async {
    if (!_stopped) return;
    _stopped = false;
    unawaited(_loop());
  }

  void _set(HaConnection s, [String? err]) {
    state = s;
    error = err;
    onState?.call();
  }

  Future<void> _loop() async {
    var wait = 1;
    while (!_stopped) {
      _set(HaConnection.connecting);
      try {
        final s = await HaSession.open(url, token);
        _session = s;
        await s.subscribeStates(_changed);
        for (final e in await s.getStates()) {
          _entities[e.id] = e;
          _push(e);
        }
        wait = 1;
        _set(HaConnection.connected);
        await s.closed;
        if (!_stopped) _set(HaConnection.failed, 'Mất kết nối Home Assistant. Đang thử lại…');
      } on HaException catch (e) {
        _set(HaConnection.failed, e.message);
      } catch (e) {
        _set(HaConnection.failed, '$e');
      }
      _session = null;
      if (_stopped) break;
      await Future<void>.delayed(Duration(seconds: wait));
      wait = (wait * 2).clamp(1, 30);
    }
    if (_stopped) _set(HaConnection.disconnected);
  }

  void _changed(HaEntity e) {
    _entities[e.id] = e;
    _push(e);
  }

  void _push(HaEntity e) {
    for (final g in addresses) {
      final h = jsonMap(g['ha']);
      if (h['entity'] != e.id || h['role'] != 'status') continue;
      final v = haStatusValue((h['attr'] ?? '').toString(), e);
      if (v != null) onValue?.call(g['address'].toString(), v);
    }
  }

  /// Writes a card's value to the entity of the virtual address [ga].
  Future<String?> write(Json ga, Object value) async {
    final s = _session;
    if (s == null || !connected) return 'Chưa kết nối được Home Assistant.';
    final h = jsonMap(ga['ha']);
    final id = (h['entity'] ?? '').toString();
    final e = _entities[id] ?? HaEntity(id, '', const {});
    final call = haCommand(e, (h['attr'] ?? '').toString(), value);
    if (call == null) return 'Không gửi được lệnh “${ga['name'] ?? ga['address']}” tới Home Assistant.';
    try {
      await s.callService(call, id);
      return null;
    } on HaException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> stop() async {
    _stopped = true;
    final s = _session;
    _session = null;
    await s?.close();
    _set(HaConnection.disconnected);
  }
}
