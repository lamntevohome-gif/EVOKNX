// EVOKNX project document (JSON). The document is kept as a plain
// Map<String, dynamic> so that files written by the web editor and the
// Windows editor stay 100% compatible. Helpers below give typed access.
import 'dart:math';

import 'package:knx_core/knx_core.dart';

import 'ets_import.dart';

typedef Json = Map<String, dynamic>;

const int kSchemaVersion = 4;
final Random _rnd = Random();

String uid(String prefix) => '$prefix${List.generate(6, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rnd.nextInt(36)]).join()}';
String gaId(String address) => 'ga_${address.replaceAll('/', '_')}';

List<Json> jsonList(Object? v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Json>[];
Json jsonMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

// ------------------------------------------------------------ widget types

class SlotDef {
  final String key;
  final String label;
  final List<int> dpts;
  final bool required;
  final bool recommended;
  const SlotDef(this.key, this.label, this.dpts, {this.required = false, this.recommended = false});
}

class WidgetTypeDef {
  final String type;
  final String name;
  final String icon;
  final int w;
  final int h;
  final List<SlotDef> slots;
  const WidgetTypeDef(this.type, this.name, this.icon, this.w, this.h, this.slots);
}

const Map<String, WidgetTypeDef> kWidgetTypes = {
  'switch': WidgetTypeDef('switch', 'Công tắc', 'bulb', 2, 2, [
    SlotDef('write', 'Địa chỉ ghi', [1], required: true),
    SlotDef('status', 'Địa chỉ trạng thái', [1], recommended: true),
  ]),
  'dimmer': WidgetTypeDef('dimmer', 'Đèn dim', 'sun', 2, 2, [
    SlotDef('write', 'Bật/tắt', [1]),
    SlotDef('value', 'Giá trị độ sáng', [5], required: true),
    SlotDef('status', 'Trạng thái độ sáng', [5], recommended: true),
  ]),
  'value': WidgetTypeDef('value', 'Giá trị', 'thermo', 2, 2, [
    SlotDef('status', 'Địa chỉ trạng thái', [5, 6, 7, 8, 9, 12, 13, 14], required: true),
  ]),
  'button': WidgetTypeDef('button', 'Nút nhấn', 'button', 2, 2, [
    SlotDef('write', 'Địa chỉ ghi', [1, 5, 17], required: true),
  ]),
  'shutter': WidgetTypeDef('shutter', 'Rèm', 'blind', 2, 2, [
    SlotDef('upDown', 'Lên/xuống', [1], required: true),
    SlotDef('stop', 'Dừng', [1]),
    SlotDef('position', 'Vị trí', [5]),
    SlotDef('status', 'Trạng thái vị trí', [5], recommended: true),
  ]),
  'scene': WidgetTypeDef('scene', 'Cảnh', 'star', 2, 2, [
    SlotDef('write', 'Địa chỉ ghi', [1, 5, 17, 18], required: true),
  ]),
  'link': WidgetTypeDef('link', 'Mở trang web', 'link', 2, 2, []),
  'webview': WidgetTypeDef('webview', 'Trang web nhúng', 'globe', 2, 2, []),
  'ac': WidgetTypeDef('ac', 'Máy lạnh', 'snow', 2, 2, [
    SlotDef('power', 'Bật/tắt', [1], required: true),
    SlotDef('powerSt', 'Trạng thái bật/tắt', [1], recommended: true),
    SlotDef('setpoint', 'Nhiệt độ cài đặt', [9], required: true),
    SlotDef('setpointSt', 'Trạng thái nhiệt độ cài đặt', [9], recommended: true),
    SlotDef('current', 'Nhiệt độ phòng', [9]),
    SlotDef('mode', 'Chế độ', [20, 5]),
    SlotDef('modeSt', 'Trạng thái chế độ', [20, 5]),
  ]),
  'camera': WidgetTypeDef('camera', 'Camera', 'camera', 2, 2, []),
  'group': WidgetTypeDef('group', 'Khung lưới', 'layout', 2, 2, []),
};

class AcMode {
  final String key, name, icon;
  final int value;
  const AcMode(this.key, this.name, this.icon, this.value);
}

/// Stream address of a camera widget, e.g. rtsp://user:pass@192.168.1.64:554/path.
/// [hidePass] replaces the password with ***.
String cameraUrl(Json cam, {bool hidePass = false}) {
  final proto = cam['protocol'] == 'http' ? 'http' : 'rtsp';
  final host = (cam['host'] ?? '').toString().trim();
  if (host.isEmpty) return '';
  final port = (cam['port'] as num?)?.toInt();
  var path = (cam['path'] ?? '').toString().trim();
  if (path.isNotEmpty && !path.startsWith('/')) path = '/$path';
  final user = (cam['user'] ?? '').toString();
  final pass = (cam['pass'] ?? '').toString();
  final auth = user.isEmpty ? '' : '${Uri.encodeComponent(user)}${pass.isEmpty ? '' : ':${hidePass ? '***' : Uri.encodeComponent(pass)}'}@';
  final defPort = proto == 'http' ? 80 : 554;
  return '$proto://$auth$host${port == null || port == defPort ? '' : ':$port'}$path';
}

/// Value card in "state" style (Kiểu đầy đủ): rows of
/// {v: value, text, icon, color, alarm}. Older value cards have no style and
/// keep showing a number.
bool isStateValue(Json w) => w['type'] == 'value' && w['valueStyle'] == 'state';

/// The state row matching [value] (a number; true/false count as 1/0).
Json? valueState(Json w, Object? value) {
  num? n;
  if (value is bool) n = value ? 1 : 0;
  if (value is num) n = value;
  if (value is String) n = num.tryParse(value.replaceAll(',', '.'));
  if (n == null) return null;
  for (final r in jsonList(w['states'])) {
    final v = num.tryParse((r['v'] ?? '').toString().replaceAll(',', '.'));
    if (v != null && v == n) return r;
  }
  return null;
}

/// Value a scene card sends. Older projects stored a scene number (1–64)
/// and sent number − 1; that value is kept for them.
String sceneSendValue(Json w) {
  final v = w['sendValue'];
  if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  final n = (w['sceneNumber'] as num?)?.toInt();
  return n == null ? '0' : '${n - 1}';
}

/// Fan speed levels of an AC: 'auto' (optional) then '1'…'N'.
/// Default values follow DPT 5.010 (0 = auto, 1…N = speed).
List<String> acFanLevels(Json ac) {
  final f = jsonMap(ac['fan']);
  final n = ((f['levels'] as num?) ?? 3).toInt().clamp(2, 5);
  return [if (f['auto'] != false) 'auto', for (var i = 1; i <= n; i++) '$i'];
}

num acFanValue(Json ac, String level) {
  final v = jsonMap(jsonMap(ac['fan'])['values'])[level];
  if (v is num) return v;
  return level == 'auto' ? 0 : int.parse(level);
}

const List<AcMode> kAcModes = [
  AcMode('auto', 'Tự động', 'acauto', 0),
  AcMode('cool', 'Làm lạnh', 'snow', 3),
  AcMode('heat', 'Sưởi', 'flame', 1),
  AcMode('fan', 'Quạt', 'fan', 9),
  AcMode('dry', 'Hút ẩm', 'drop', 14),
];

/// Slots of a widget, including dynamic ones (dimmer features, shutter
/// options, AC per-mode addresses). Mirrors the web editor.
List<SlotDef> slotsFor(Json w) {
  final t = kWidgetTypes[w['type']];
  final base = t?.slots ?? const <SlotDef>[];
  switch (w['type']) {
    case 'shutter':
      var out = w['showStop'] == false ? base.where((s) => s.key != 'stop').toList() : List<SlotDef>.from(base);
      final ctrl = (w['shCtrl'] ?? 'buttons') as String;
      if (ctrl == 'slider') out = out.where((s) => s.key != 'upDown' && s.key != 'stop').toList();
      if (ctrl != 'buttons') out = out.map((s) => s.key == 'position' ? SlotDef(s.key, s.label, s.dpts, required: true) : s).toList();
      if (w['shStyle'] == 'curtain') out = out.map((s) => s.key == 'upDown' ? SlotDef('upDown', 'Mở/đóng', s.dpts, required: s.required) : s).toList();
      return out;
    case 'dimmer':
      final f = jsonMap(w['features']);
      return [
        ...base,
        if (f['tw'] == true) ...const [
          SlotDef('ctWrite', 'Nhiệt độ màu', [7], required: true),
          SlotDef('ctStatus', 'Trạng thái nhiệt độ màu', [7], recommended: true)
        ],
        if (f['rgb'] == true) ...const [
          SlotDef('rgbWrite', 'Màu RGB', [232, 251], required: true),
          SlotDef('rgbStatus', 'Trạng thái màu RGB', [232, 251], recommended: true)
        ],
      ];
    case 'ac':
      final ac = jsonMap(w['ac']);
      final fanSlots = jsonMap(ac['fan'])['enabled'] == true
          ? const [
              SlotDef('fan', 'Tốc độ quạt', [5, 20], required: true),
              SlotDef('fanSt', 'Trạng thái tốc độ quạt', [5, 20], recommended: true)
            ]
          : const <SlotDef>[];
      if (ac['modeAddr'] != 'separate') return [...base, ...fanSlots];
      final modes = jsonMap(ac['modes']);
      final names = jsonMap(ac['names']);
      final extra = <SlotDef>[];
      for (final m in kAcModes) {
        final on = modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat';
        if (!on) continue;
        final n = (names[m.key] as String?)?.trim().isNotEmpty == true ? names[m.key] as String : m.name;
        extra.add(SlotDef('mode_${m.key}', 'Chế độ $n', const [1], required: true));
        extra.add(SlotDef('modeSt_${m.key}', 'Trạng thái $n', const [1]));
      }
      return [...base.where((s) => s.key != 'mode' && s.key != 'modeSt'), ...extra, ...fanSlots];
  }
  return base;
}

bool slotAccepts(SlotDef slot, Json ga) {
  final m = dptMain(ga['dpt'] as String?);
  return m == null || slot.dpts.contains(m);
}

// ------------------------------------------------------------ factories

Json makeSub(String title, {int cols = 4, int rows = 12}) => {
      'id': uid('sub_'),
      'title': title,
      'layout': {'type': 'grid', 'columns': cols, 'rows': rows},
      'widgets': <Json>[],
    };

Json makeRoom(String title, {String icon = 'sofa', String? floorId}) => {
      'id': uid('page_'),
      'title': title,
      'icon': icon,
      'floorId': floorId,
      'subpages': [makeSub('Trang 1')],
    };

Json makeFloor(String title, {String icon = 'stairs'}) => {'id': uid('fl_'), 'title': title, 'icon': icon, 'rows': 12, 'cols': 4};

Json makeWidget(String type, int x, int y, [int? w, int? h]) {
  final t = kWidgetTypes[type]!;
  final wd = <String, dynamic>{
    'id': uid('w_'),
    'type': type,
    'label': t.name,
    'icon': t.icon,
    'pos': {'x': x, 'y': y, 'w': w ?? t.w, 'h': h ?? t.h},
    'bind': <String, dynamic>{},
  };
  if (type == 'dimmer') {
    wd['features'] = {'tw': false, 'rgb': false};
    wd['tw'] = {'min': 2700, 'max': 6500};
  }
  if (type == 'switch' || type == 'dimmer') {
    wd['style'] = {'colorOn': '#EE9B2A', 'colorOff': '#8A938F', 'textOn': 'Đang bật', 'textOff': 'Đang tắt'};
  }
  if (type == 'value') wd['format'] = {'unit': '', 'decimals': 1};
  if (type == 'button') wd['sendValue'] = '1';
  if (type == 'scene') wd['sendValue'] = '0';
  if (type == 'link') {
    wd['url'] = '';
    wd['openIn'] = 'inApp';
  }
  if (type == 'webview') {
    wd['url'] = '';
    wd['web'] = {'showHeader': true, 'interactive': true, 'fullscreen': true, 'refresh': 0};
  }
  if (type == 'ac') {
    wd['ac'] = {
      'min': 16,
      'max': 30,
      'step': 0.5,
      'showCur': true,
      'modes': {'auto': true, 'cool': true, 'heat': false, 'fan': true, 'dry': true},
      'values': {'auto': 0, 'cool': 3, 'heat': 1, 'fan': 9, 'dry': 14},
    };
  }
  if (type == 'scene') {
    wd['popup'] = {'enabled': true, 'text': 'Đã bật cảnh {tên}', 'blur': 8, 'size': 20, 'seconds': 2};
  }
  if (type == 'camera') {
    wd['cam'] = {'protocol': 'rtsp', 'host': '', 'port': 554, 'path': '/Streaming/Channels/101', 'user': 'admin', 'pass': '', 'view': 'live'};
  }
  if (type == 'group') {
    wd['layout'] = {'type': 'grid', 'columns': min(w ?? t.w, 6), 'rows': min(h ?? t.h, 6)};
    wd['widgets'] = <Json>[];
    wd['gstyle'] = 'card';
    wd['showTitle'] = true;
  }
  return wd;
}

Json newProject(String name) {
  final f = makeFloor('Tầng 1');
  return {
    'schemaVersion': kSchemaVersion,
    'gridRows': 12,
    'devices': {'mobile': true, 'tabletP': false, 'tabletL': false},
    'activeDev': 'mobile',
    'project': {'id': uid('p_'), 'name': name.trim().isEmpty ? 'Dự án mới' : name.trim(), 'revision': 0, 'updatedAt': null},
    'connections': [
      {'id': 'main', 'name': 'Trong nhà', 'type': 'tunneling', 'host': '192.168.1.50', 'port': 3671, 'natMode': false}
    ],
    'groupAddresses': <Json>[],
    'theme': {'mode': 'light', 'accent': '#1E7F57', 'colorOn': '#EE9B2A', 'colorOff': '#8A938F'},
    'menu': {'style': 'grid', 'items': <String>[]},
    'floors': [f],
    'pages': <Json>[],
    'icons': <Json>[],
  };
}

// ------------------------------------------------------------ migration

bool isProject(Object? o) {
  if (o is! Map) return false;
  final v = o['schemaVersion'];
  return v is int && v >= 1 && v <= kSchemaVersion && o['pages'] is List && o['groupAddresses'] is List && o['project'] is Map && o['connections'] is List;
}

/// Upgrades any older document (v1–v3, web or desktop) to the current schema.
Json migrate(Json o) {
  final pages = jsonList(o['pages']);
  for (final r in pages) {
    if (r['subpages'] is! List) {
      r['subpages'] = [
        {
          'id': uid('sub_'),
          'title': 'Trang 1',
          'layout': r['layout'] ?? {'type': 'grid', 'columns': 4},
          'widgets': r['widgets'] ?? <Json>[]
        }
      ];
      r.remove('layout');
      r.remove('widgets');
    }
    if ((r['subpages'] as List).isEmpty) (r['subpages'] as List).add(makeSub('Trang 1'));
  }
  o['pages'] = pages;
  o['icons'] ??= <Json>[];
  final conns = jsonList(o['connections']);
  for (var i = 0; i < conns.length; i++) {
    conns[i]['name'] ??= i == 0 ? 'Trong nhà' : 'Kết nối ${i + 1}';
    conns[i]['id'] ??= uid('conn_');
  }
  o['connections'] = conns;
  var floors = jsonList(o['floors']);
  if (floors.isEmpty) floors = [makeFloor('Tầng 1')];
  o['floors'] = floors;
  for (final r in pages) {
    if (!floors.any((f) => f['id'] == r['floorId'])) r['floorId'] = floors.first['id'];
  }
  if (o['gridRows'] != 12) {
    for (final r in pages) {
      for (final s in jsonList(r['subpages'])) {
        for (final w in jsonList(s['widgets'])) {
          final p = jsonMap(w['pos']);
          p['y'] = (p['y'] as num? ?? 0) * 2;
          p['h'] = (p['h'] as num? ?? 1) * 2;
        }
      }
    }
    o['gridRows'] = 12;
  }
  o['devices'] ??= {'mobile': true, 'tabletP': false, 'tabletL': false};
  if (!const ['mobile', 'tabletP', 'tabletL'].contains(o['activeDev'])) o['activeDev'] = 'mobile';
  o['schemaVersion'] = kSchemaVersion;
  return o;
}

// ------------------------------------------------------------ queries

Iterable<Json> allSubpages(Json doc) sync* {
  for (final r in jsonList(doc['pages'])) {
    yield* jsonList(r['subpages']);
  }
}

/// All widgets including children of grid groups.
Iterable<Json> allWidgets(Json doc) sync* {
  for (final s in allSubpages(doc)) {
    for (final w in jsonList(s['widgets'])) {
      yield w;
      if (w['type'] == 'group') yield* jsonList(w['widgets']);
    }
  }
}

Map<String, int> gaUsage(Json doc) {
  final used = <String, int>{};
  for (final w in allWidgets(doc)) {
    for (final id in jsonMap(w['bind']).values) {
      if (id is String) used[id] = (used[id] ?? 0) + 1;
    }
  }
  return used;
}

int gaSortKey(String a) {
  final p = a.split('/').map((e) => int.tryParse(e) ?? 0).toList();
  return p.length == 3 ? (p[0] << 16) | (p[1] << 8) | p[2] : (p[0] << 16) | p.last;
}

// ------------------------------------------------------------ ETS import

class ImportStats {
  final int fresh, both, gone, links, edited;
  const ImportStats(this.fresh, this.both, this.gone, this.links, this.edited);
}

ImportStats importStats(Json doc, List<EtsItem> items) {
  final inFile = items.map((i) => i.address).toSet();
  final gas = jsonList(doc['groupAddresses']);
  final cur = gas.map((g) => g['address'] as String).toSet();
  final fresh = items.where((i) => !cur.contains(i.address)).length;
  final gone = gas.where((g) => !inFile.contains(g['address'])).map((g) => g['id']).toSet();
  var links = 0;
  for (final w in allWidgets(doc)) {
    for (final id in jsonMap(w['bind']).values) {
      if (gone.contains(id)) links++;
    }
  }
  final edited = gas.where((g) => g['nameEdited'] == true && inFile.contains(g['address'])).length;
  return ImportStats(fresh, items.length - fresh, gone.length, links, edited);
}

class ImportResult {
  final int added, updated, removed, unlinked;
  const ImportResult(this.added, this.updated, this.removed, this.unlinked);
}

/// Applies ETS items. [replace] removes addresses missing from the file.
ImportResult applyEts(Json doc, EtsResult ets, {bool replace = false, bool keepEditedNames = true}) {
  final gas = jsonList(doc['groupAddresses']);
  var added = 0, updated = 0, removed = 0, unlinked = 0;
  final byAddr = {for (final g in gas) g['address'] as String: g};
  for (final it in ets.items) {
    final ex = byAddr[it.address];
    if (ex != null) {
      if (it.name.isNotEmpty && !(keepEditedNames && ex['nameEdited'] == true)) ex['name'] = it.name;
      if (it.dpt.isNotEmpty) ex['dpt'] = it.dpt;
      updated++;
    } else {
      final g = {'id': gaId(it.address), 'address': it.address, 'name': it.name, 'dpt': it.dpt};
      gas.add(g);
      byAddr[it.address] = g;
      added++;
    }
  }
  if (replace) {
    final inFile = ets.items.map((i) => i.address).toSet();
    final gone = gas.where((g) => !inFile.contains(g['address'])).map((g) => g['id']).toSet();
    removed = gone.length;
    gas.removeWhere((g) => gone.contains(g['id']));
    for (final w in allWidgets(doc)) {
      final b = jsonMap(w['bind']);
      b.removeWhere((k, v) {
        final hit = gone.contains(v);
        if (hit) unlinked++;
        return hit;
      });
      w['bind'] = b;
    }
  }
  doc['groupAddresses'] = gas;
  final p = jsonMap(doc['project']);
  if (ets.projectName.isNotEmpty && (p['name'] == null || p['name'] == 'Dự án mới')) p['name'] = ets.projectName;
  return ImportResult(added, updated, removed, unlinked);
}

// ------------------------------------------------------------ grid / devices

bool isFree(Json box, int x, int y, int w, int h, [String? except]) {
  final cols = (jsonMap(box['layout'])['columns'] as num?)?.toInt() ?? 4;
  if (x < 0 || y < 0 || x + w > cols) return false;
  for (final o in jsonList(box['widgets'])) {
    if (o['id'] == except) continue;
    final p = jsonMap(o['pos']);
    final ox = (p['x'] as num).toInt(), oy = (p['y'] as num).toInt(), ow = (p['w'] as num).toInt(), oh = (p['h'] as num).toInt();
    if (x < ox + ow && x + w > ox && y < oy + oh && y + h > oy) return false;
  }
  return true;
}

({int x, int y}) findFree(Json box, int w, int h) {
  final cols = (jsonMap(box['layout'])['columns'] as num?)?.toInt() ?? 4;
  final ww = min(w, cols);
  for (var y = 0; y < 400; y++) {
    for (var x = 0; x + ww <= cols; x++) {
      if (isFree(box, x, y, ww, h)) return (x: x, y: y);
    }
  }
  return (x: 0, y: 0);
}

/// First free spot for a [w] × [h] card that fits inside [maxRows] rows,
/// or null when the page (or frame) has no room left.
({int x, int y})? findFreeWithin(Json box, int w, int h, int maxRows) {
  final cols = (jsonMap(box['layout'])['columns'] as num?)?.toInt() ?? 4;
  final ww = min(w, cols);
  for (var y = 0; y + h <= maxRows; y++) {
    for (var x = 0; x + ww <= cols; x++) {
      if (isFree(box, x, y, ww, h)) return (x: x, y: y);
    }
  }
  return null;
}

const Map<String, List<int>> kDeviceDefaults = {
  'mobile': [12, 4],
  'tabletP': [16, 6],
  'tabletL': [10, 8]
};

/// Exports a normalized copy with layouts for every enabled device.
Json exportProject(Json doc) {
  final out = migrate(Json.from(_deepCopy(doc) as Map));
  final devs = jsonMap(out['devices']);
  for (final d in ['mobile', 'tabletP', 'tabletL'].where((d) => d == 'mobile' || devs[d] == true)) {
    _swapDevice(out, d);
  }
  _swapDevice(out, 'mobile');
  for (final s in allSubpages(out)) {
    final lb = jsonMap(s['layoutBy']);
    final l = jsonMap(s['layout']);
    lb['mobile'] = {'columns': l['columns'], 'rows': l['rows']};
    s['layoutBy'] = lb;
    for (final w in jsonList(s['widgets'])) {
      final pb = jsonMap(w['posBy']);
      pb['mobile'] = Map<String, dynamic>.from(jsonMap(w['pos']));
      w['posBy'] = pb;
    }
  }
  out['activeDev'] = 'mobile';
  return out;
}

Object? _deepCopy(Object? v) {
  if (v is Map) return v.map((k, e) => MapEntry(k.toString(), _deepCopy(e)));
  if (v is List) return v.map(_deepCopy).toList();
  return v;
}

/// Switches the active device layout of [proj] (mobile, tabletP, tabletL).
void swapDevice(Json proj, String nd) => _swapDevice(proj, nd);

void _swapDevice(Json proj, String nd) {
  final cur = (proj['activeDev'] as String?) ?? 'mobile';
  if (cur == nd) return;
  for (final s in allSubpages(proj)) {
    final lb = jsonMap(s['layoutBy']);
    final l = jsonMap(s['layout']);
    lb[cur] = {'columns': l['columns'], 'rows': l['rows']};
    s['layoutBy'] = lb;
    final nl = jsonMap(lb[nd]);
    final def = kDeviceDefaults[nd]!;
    l['columns'] = nl['columns'] ?? def[1];
    l['rows'] = nl['rows'] ?? def[0];
    final need = <Json>[];
    for (final w in jsonList(s['widgets'])) {
      final pb = jsonMap(w['posBy']);
      pb[cur] = Map<String, dynamic>.from(jsonMap(w['pos']));
      w['posBy'] = pb;
      if (pb[nd] != null) {
        w['pos'] = Map<String, dynamic>.from(jsonMap(pb[nd]));
      } else {
        need.add(w);
      }
    }
    if (need.isNotEmpty) {
      final src = need.every((w) => jsonMap(w['posBy'])['mobile'] != null) ? 'mobile' : cur;
      final needIds = need.map((w) => w['id']).toSet();
      final placed = jsonList(s['widgets']).where((w) => !needIds.contains(w['id'])).toList();
      final tmp = <String, dynamic>{'layout': l, 'widgets': placed};
      Json sp(Json w) => jsonMap(jsonMap(w['posBy'])[src] ?? w['pos']);
      need.sort((a, b) {
        final pa = sp(a), pbb = sp(b);
        final c = (pa['y'] as num).compareTo(pbb['y'] as num);
        return c != 0 ? c : (pa['x'] as num).compareTo(pbb['x'] as num);
      });
      for (final w in need) {
        final o = sp(w);
        final ww = min((o['w'] as num).toInt(), (l['columns'] as num).toInt());
        final hh = (o['h'] as num).toInt();
        final f = findFree(tmp, ww, hh);
        w['pos'] = {'x': f.x, 'y': f.y, 'w': ww, 'h': hh};
        placed.add(w);
      }
    }
  }
  proj['activeDev'] = nd;
}
