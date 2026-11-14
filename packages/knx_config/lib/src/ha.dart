import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'project.dart';

// ======================================================================
// Home Assistant (HA)
//
// A card follows an entity of HA directly (see card_entity.dart): the App and the Editor give it virtual group
// addresses (main group 1000) when they run, nothing is stored in the project. Projects made with the old Extensions
// tab keep their virtual addresses (a group address with an "ha" entry): they are still read and sent to HA here.
// ======================================================================

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
  HaAttr('onoff', 'On/Off', '1.001'),
  HaAttr('brightness', 'Brightness', '5.001'),
  HaAttr('colortemp', 'Color temperature', '7.600'),
  HaAttr('position', 'Blind position', '5.001'),
  HaAttr('move', 'Blind up/down', '1.008', status: false),
  HaAttr('stop', 'Blind stop', '1.007', status: false),
  HaAttr('setpoint', 'Setpoint', '9.001'),
  HaAttr('current', 'Room temperature', '9.001', cmd: false),
  HaAttr('mode', 'Mode', '20.105'),
  HaAttr('sensor', 'Sensor value', '9.001', cmd: false),
  HaAttr('binary', 'Status (on/off)', '1.001', cmd: false),
  HaAttr('scene', 'Activate', '17.001', status: false),
  HaAttr('playpause', 'Play/Pause', '1.001', status: false),
  HaAttr('mstop', 'Stop playback', '1.001', status: false),
  HaAttr('prev', 'Previous track', '1.001', status: false),
  HaAttr('next', 'Next track', '1.001', status: false),
  HaAttr('volume', 'Volume', '5.001'),
  HaAttr('mute', 'Mute', '1.001'),
  HaAttr('playing', 'Playing', '1.001', cmd: false),
  // Text commands: the text written to the address is the command (a text address, DPT 16). They are sent to
  // Home Assistant as written, so they are not limited to the 14 characters of the bus.
  HaAttr('cmdtext', 'Send command (text)', '16.000', status: false),
  HaAttr('srctext', 'Select source / HDMI (text)', '16.000', status: false),
  HaAttr('soundtext', 'Select sound mode (text)', '16.000', status: false),
  HaAttr('acttext', 'Start activity (text)', '16.000', status: false),
];

HaAttr? haAttr(String key) {
  for (final a in kHaAttrs) {
    if (a.key == key) return a;
  }
  return null;
}

/// A field (a parameter) of a Home Assistant service, as Home Assistant describes it.
class HaField {
  HaField(this.key, {this.name = '', this.description = '', this.required = false, this.type = '', this.example, this.sample, this.selector = const {}});
  final String key, name, description;
  final bool required;

  /// The kind of value: number, boolean, text, select, color_rgb… (from the selector), or ''.
  final String type;
  final Object? example;

  /// A value to start from when the field is added: the default, the example, or one that fits the type.
  final Object? sample;

  /// What the selector says about the value (min, max, unit_of_measurement, options…).
  final Map<String, dynamic> selector;

  num? get min => selector['min'] is num ? selector['min'] as num : null;
  num? get max => selector['max'] is num ? selector['max'] as num : null;
  String get unit => (selector['unit_of_measurement'] ?? selector['unit'] ?? '').toString();

  static String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// What the value looks like, for the label of the field: its range and unit, the format of a color,
  /// or an example. Empty when there is nothing to say (a choice, an on/off).
  String get spec {
    switch (type) {
      case 'number':
      case 'color_temp':
        if (min == null && max == null) return unit;
        return '${min == null ? '' : _n(min!)}–${max == null ? '' : _n(max!)}${unit.isEmpty ? '' : ' $unit'}';
      case 'color_rgb':
        return 'R, G, B: 0–255';
      case 'constant':
        return 'fixed: ${selector['value']}';
      case 'text':
        return 'text';
      case 'select':
      case 'boolean':
        return '';
    }
    return example == null ? '' : 'e.g. ${jsonEncode(example)}';
  }

  /// The first sentence of the description, short.
  String get brief {
    final d = description.trim();
    if (d.isEmpty) return '';
    final dot = d.indexOf('. ');
    final first = dot > 0 ? d.substring(0, dot + 1) : d;
    return first.length > 110 ? '${first.substring(0, 107)}…' : first;
  }

  /// The choices of a select: (value, label).
  List<(String, String)> get options {
    final o = selector['options'];
    if (o is! List) return const [];
    return [
      for (final x in o)
        if (x is Map) ((x['value'] ?? '').toString(), (x['label'] ?? x['value'] ?? '').toString()) else (x.toString(), x.toString()),
    ];
  }

  /// Value of a field of Home Assistant's description (a section with more fields is flattened by the caller).
  factory HaField.fromJson(String key, Map<String, dynamic> m) {
    final sel = m['selector'];
    var type = '';
    Map<String, dynamic> selData = const {};
    if (sel is Map && sel.isNotEmpty) {
      type = sel.keys.first.toString();
      final d = sel.values.first;
      if (d is Map) selData = Map<String, dynamic>.from(d);
    }
    Object? sample = m['default'];
    sample ??= m['example'] is num || m['example'] is bool || m['example'] is String ? m['example'] : null;
    if (sample == null) {
      switch (type) {
        case 'number':
          sample = selData['min'] ?? 0;
        case 'color_temp':
          sample = selData['min'] ?? 2700;
        case 'constant':
          sample = selData['value'] ?? true;
        case 'boolean':
          sample = true;
        case 'select':
          final o = selData['options'];
          if (o is List && o.isNotEmpty) sample = o.first is Map ? (o.first as Map)['value'] : o.first;
        case 'color_rgb':
          sample = [255, 255, 255];
        case 'text':
          sample = '';
      }
    }
    return HaField(
      key,
      name: (m['name'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      required: m['required'] == true,
      type: type,
      example: m['example'],
      sample: sample ?? '',
      selector: selData,
    );
  }
}

/// A service of Home Assistant with its fields.
class HaService {
  HaService(this.key, {this.name = '', this.description = '', this.fields = const []});
  final String key, name, description;
  final List<HaField> fields;

  factory HaService.fromJson(String key, Map<String, dynamic> m) {
    final out = <HaField>[];
    void read(Object? fields) {
      if (fields is! Map) return;
      fields.forEach((k, v) {
        if (v is! Map) return;
        // A section groups more fields.
        if (v['fields'] is Map) {
          read(v['fields']);
        } else {
          out.add(HaField.fromJson(k.toString(), Map<String, dynamic>.from(v)));
        }
      });
    }

    read(m['fields']);
    return HaService(key, name: (m['name'] ?? '').toString(), description: (m['description'] ?? '').toString(), fields: out);
  }
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

  /// The attributes that are saved with the entities (what is needed to choose an entity and to suggest its functions).
  static const keptAttributes = [
    'friendly_name',
    'supported_color_modes',
    'brightness',
    'hvac_modes',
    'source_list',
    'sound_mode_list',
    'activity_list',
    'supported_features',
    'device_class',
    'unit_of_measurement',
  ];

  Map<String, dynamic> toJson() => {
    'entity_id': id,
    'state': state,
    'attributes': {
      for (final k in keptAttributes)
        if (attributes.containsKey(k)) k: attributes[k],
    },
  };

  List<String> get hvacModes => [for (final x in (attributes['hvac_modes'] as List? ?? const [])) x.toString()];
}

/// The HA virtual addresses of a project.
List<Json> haAddresses(Json doc) => [
  for (final g in jsonList(doc['groupAddresses']))
    if (isHaAddress(g)) g,
];

/// Connection settings of the project: {enabled, url, token}.
Json haSettings(Json doc) => jsonMap(doc['ha']);

/// Whether the project has a Home Assistant connection (added with "Add connection", or set up in an older version).
bool haAdded(Json doc) {
  final h = haSettings(doc);
  return h['added'] == true || h['enabled'] == true || (h['url'] ?? '').toString().trim().isNotEmpty || (h['token'] ?? '').toString().trim().isNotEmpty;
}

// ======================================================================
// Values between the cards (KNX-style values) and HA
// ======================================================================

/// A service call for HA.
class HaCall {
  const HaCall(this.domain, this.service, [this.data = const {}]);

  /// Nothing to send (for example "off" of a scene).
  static const HaCall none = HaCall('', '');
  bool get isNone => domain.isEmpty;
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
      // Scene, script, automation: a 1-bit trigger. 1 starts it, 0 only stops a script.
      if (d == 'scene') return on ? const HaCall('scene', 'turn_on') : HaCall.none;
      if (d == 'automation') return on ? const HaCall('automation', 'trigger') : HaCall.none;
      if (d == 'script') return HaCall('script', on ? 'turn_on' : 'turn_off');
      final dom = const ['light', 'switch', 'fan', 'input_boolean', 'climate', 'automation', 'cover', 'media_player', 'remote'].contains(d)
          ? d
          : 'homeassistant';
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
      if (d == 'automation') return const HaCall('automation', 'trigger');
      return HaCall(d == 'script' ? 'script' : 'scene', 'turn_on');
    case 'playpause':
      return const HaCall('media_player', 'media_play_pause');
    case 'mstop':
      return const HaCall('media_player', 'media_stop');
    case 'prev':
      return const HaCall('media_player', 'media_previous_track');
    case 'next':
      return const HaCall('media_player', 'media_next_track');
    case 'volume':
      return HaCall('media_player', 'volume_set', {'volume_level': ((n ?? 0).clamp(0, 100)) / 100});
    case 'mute':
      return HaCall('media_player', 'volume_mute', {'is_volume_muted': (n ?? 0) != 0});
    // The text is the command; an empty text does nothing.
    case 'cmdtext':
      final t = value.toString().trim();
      return t.isEmpty ? HaCall.none : HaCall('remote', 'send_command', {'command': t});
    case 'srctext':
      final t = value.toString().trim();
      return t.isEmpty ? HaCall.none : HaCall('media_player', 'select_source', {'source': t});
    case 'soundtext':
      final t = value.toString().trim();
      return t.isEmpty ? HaCall.none : HaCall('media_player', 'select_sound_mode', {'sound_mode': t});
    case 'acttext':
      final t = value.toString().trim();
      return t.isEmpty ? HaCall.none : HaCall('remote', 'turn_on', {'activity': t});
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
      if (e.domain == 'media_player') return s != 'off' && s != 'standby';
      return e.domain == 'cover' ? s != 'closed' : s != 'off';
    case 'playing':
      return s == 'playing';
    case 'volume':
      final v = e.attributes['volume_level'];
      return v is num ? (v * 100).round() : null;
    case 'mute':
      return e.attributes['is_volume_muted'] == true;
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
  HaException(this.message, {this.auth = false});
  final String message;

  /// Home Assistant refused the token (trying again with the same token is useless).
  final bool auth;
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
      throw HaException('Could not connect to Home Assistant (timed out). Check the address and the network.');
    } catch (e) {
      throw HaException('Could not connect to Home Assistant. Check the address, port and network. ($e)');
    }
    final s = HaSession._(ws);
    ws.listen(s._onData, onDone: s._onDone, onError: (_) => s._onDone(), cancelOnError: true);
    try {
      final hello = await s._next(timeout);
      if (hello['type'] != 'auth_required') throw HaException('The server is not Home Assistant.');
      s.version = hello['ha_version']?.toString();
      ws.add(jsonEncode({'type': 'auth', 'access_token': token}));
      final r = await s._next(timeout);
      if (r['type'] == 'auth_invalid') throw HaException('The token is wrong or has been revoked.', auth: true);
      if (r['type'] != 'auth_ok') throw HaException('Home Assistant did not accept the login.', auth: true);
      s._authed = true;
      return s;
    } catch (e) {
      await s.close();
      if (e is HaException) rethrow;
      if (e is TimeoutException) throw HaException('Home Assistant did not respond.');
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
      if (!c.isCompleted) c.completeError(HaException('Home Assistant connection lost.'));
    }
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(HaException('Home Assistant connection lost.'));
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
      throw HaException('Home Assistant did not respond.');
    }
    if (r['success'] == false) {
      final err = r['error'];
      throw HaException(err is Map ? (err['message'] ?? 'Error from Home Assistant').toString() : 'Error from Home Assistant');
    }
    return r['result'];
  }

  Future<List<HaEntity>> getStates() async {
    final r = await call({'type': 'get_states'}, timeout: const Duration(seconds: 20));
    return [for (final x in (r as List? ?? const [])) HaEntity.fromJson(Map<String, dynamic>.from(x as Map))];
  }

  /// The cover image of a media player (the one Home Assistant shows), or null when it has none.
  Future<Uint8List?> getThumbnail(String entityId) async {
    final r = await call({'type': 'media_player_thumbnail', 'entity_id': entityId}, timeout: const Duration(seconds: 15));
    if (r is Map && r['content'] is String) {
      try {
        return base64Decode(r['content'] as String);
      } catch (_) {}
    }
    return null;
  }

  /// The services of Home Assistant: each domain with its services and their fields (for suggestions).
  Future<Map<String, Map<String, HaService>>> getServiceInfo() async {
    final r = await call({'type': 'get_services'}, timeout: const Duration(seconds: 20));
    final out = <String, Map<String, HaService>>{};
    if (r is Map) {
      r.forEach((d, v) {
        if (v is! Map) return;
        out[d.toString()] = {
          for (final e in v.entries)
            e.key.toString(): HaService.fromJson(e.key.toString(), e.value is Map ? Map<String, dynamic>.from(e.value as Map) : const {}),
        };
      });
    }
    return out;
  }

  /// The services of Home Assistant: each domain with the names of its services.
  Future<Map<String, List<String>>> getServices() async {
    final info = await getServiceInfo();
    return {for (final e in info.entries) e.key: (e.value.keys.toList()..sort())};
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

  /// Calls any service ("light.turn_on") with its data; [entityId] may be empty.
  Future<void> callServiceRaw(String domain, String service, Json data, String entityId) async {
    await call({
      'type': 'call_service',
      'domain': domain,
      'service': service,
      'service_data': data,
      if (entityId.isNotEmpty) 'target': {'entity_id': entityId},
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

  /// The last known state of an entity (null when Home Assistant did not tell).
  HaEntity? entity(String id) => _entities[id];

  final StreamController<HaEntity> _changes = StreamController<HaEntity>.broadcast();

  /// Every entity whose state changes (and all of them when the connection is made), for the cards that show one.
  Stream<HaEntity> get entityChanges => _changes.stream;

  /// The cover image of a media player, or null. First the WebSocket command of Home Assistant; when the version of
  /// Home Assistant does not have it (or it gives nothing) the picture of the entity is fetched over HTTP.
  Future<Uint8List?> thumbnail(String entityId) async {
    final s = _session;
    if (s == null || !connected) return null;
    try {
      final b = await s.getThumbnail(entityId);
      if (b != null && b.isNotEmpty) return b;
    } catch (_) {}
    final e = _entities[entityId];
    if (e == null) return null;
    final base = haHttpUri(url, '/');
    for (final k in const ['entity_picture_local', 'entity_picture']) {
      final pic = (e.attributes[k] ?? '').toString().trim();
      if (pic.isEmpty) continue;
      final u = pic.startsWith('http') ? Uri.tryParse(pic) : haHttpUri(url, pic);
      if (u == null) continue;
      // The token of Home Assistant only goes to Home Assistant.
      final b = await haFetchImage(u, token: u.host == base.host && u.port == base.port ? token : null);
      if (b != null) return b;
    }
    return null;
  }

  /// A new number each time the bridge is started or stopped, so that an old loop never goes on (a stop and a quick
  /// start would otherwise leave two loops).
  int _gen = 0;

  /// Home Assistant refused the token: the bridge does not try again until it is started again.
  bool _refused = false;

  /// The entities that addresses refer to and that Home Assistant does not have (known after the connection is made).
  Set<String> missingEntities = {};

  Future<void> start() async {
    if (!_stopped) return;
    _stopped = false;
    _refused = false;
    final g = ++_gen;
    unawaited(_loop(g));
  }

  void _set(HaConnection s, [String? err]) {
    state = s;
    error = err;
    onState?.call();
  }

  Future<void> _loop(int g) async {
    var wait = 1;
    while (!_stopped && g == _gen) {
      _set(HaConnection.connecting);
      try {
        final s = await HaSession.open(url, token);
        _session = s;
        await s.subscribeStates(_changed);
        final known = <String>{};
        for (final e in await s.getStates()) {
          known.add(e.id);
          _entities[e.id] = e;
          _push(e);
          _changes.add(e);
        }
        missingEntities = {
          for (final a in addresses)
            if ((jsonMap(a['ha'])['entity'] ?? '').toString().isNotEmpty && !known.contains(jsonMap(a['ha'])['entity'].toString()))
              jsonMap(a['ha'])['entity'].toString(),
        };
        wait = 1;
        _set(HaConnection.connected);
        await s.closed;
        if (!_stopped && g == _gen) _set(HaConnection.failed, 'Home Assistant connection lost. Retrying…');
      } on HaException catch (e) {
        if (g != _gen) break;
        if (e.auth) {
          // The token is refused: stop (trying again could get this address blocked by Home Assistant).
          _refused = true;
          _stopped = true;
          _set(HaConnection.failed, '${e.message} Check it in the Connections tab.');
          break;
        }
        _set(HaConnection.failed, e.message);
      } catch (e) {
        _set(HaConnection.failed, '$e');
      }
      _session = null;
      if (_stopped || g != _gen) break;
      await Future<void>.delayed(Duration(seconds: wait));
      wait = (wait * 2).clamp(1, 30);
    }
    if (_stopped && !_refused && g == _gen) _set(HaConnection.disconnected);
  }

  void _changed(HaEntity e) {
    _entities[e.id] = e;
    _push(e);
    _changes.add(e);
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
  /// Calls a Home Assistant service ("light.turn_on") for a script. An error text, or null.
  Future<String?> callRaw(String service, String entity, Json data) async {
    final s = _session;
    if (s == null || !connected) return 'Could not connect to Home Assistant.';
    final i = service.indexOf('.');
    if (i <= 0) return 'The service “$service” is not valid, use the form domain.service.';
    try {
      await s.callServiceRaw(service.substring(0, i), service.substring(i + 1), data, entity);
      return null;
    } on HaException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> write(Json ga, Object value) async {
    final s = _session;
    if (s == null || !connected) return 'Could not connect to Home Assistant.';
    final h = jsonMap(ga['ha']);
    final id = (h['entity'] ?? '').toString();
    final e = _entities[id] ?? HaEntity(id, '', const {});
    final call = haCommand(e, (h['attr'] ?? '').toString(), value);
    if (call != null && call.isNone) return null;
    if (call == null) return 'Could not send the command “${ga['name'] ?? ga['address']}” to Home Assistant.';
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
    _gen++;
    final s = _session;
    _session = null;
    await s?.close();
    _set(HaConnection.disconnected);
  }
}

/// An address of Home Assistant over HTTP (for example "/api/media_player_proxy/…"), made from the address that is
/// set in the project.
Uri haHttpUri(String url, String path) {
  final ws = Uri.parse(haWebSocketUrl(url));
  return Uri(scheme: ws.scheme == 'wss' ? 'https' : 'http', host: ws.host, port: ws.hasPort ? ws.port : null).resolve(path);
}

/// Downloads an image (at most 6 MB). With a [token] it is sent as the login of Home Assistant. Null when it fails.
Future<Uint8List?> haFetchImage(Uri uri, {String? token}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..badCertificateCallback = (_, __, ___) => true;
  try {
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(const Duration(seconds: 15))) {
      out.add(chunk);
      if (out.length > 6 * 1024 * 1024) return null;
    }
    final b = out.takeBytes();
    return b.isEmpty ? null : b;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
