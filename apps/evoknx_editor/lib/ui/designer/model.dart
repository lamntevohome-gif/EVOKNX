import 'package:knx_config/knx_config.dart';

/// Helpers to read and edit the project JSON from the designer.
/// Lists returned by [rawList] are the real lists inside the document, so
/// adding/removing items edits the project.
List<dynamic> rawList(Json m, String key) {
  final v = m[key];
  if (v is List) return v;
  final l = <dynamic>[];
  m[key] = l;
  return l;
}

Json pos(Json w) => jsonMap(w['pos']);
int pi(Json w, String k) => (pos(w)[k] as num?)?.toInt() ?? 0;
Json layout(Json box) => jsonMap(box['layout']);
int cols(Json box) => (layout(box)['columns'] as num?)?.toInt() ?? 4;
int rows(Json box) => (layout(box)['rows'] as num?)?.toInt() ?? 12;

Json? byId(List<Json> l, String? id) {
  if (id == null) return null;
  for (final x in l) {
    if (x['id'] == id) return x;
  }
  return null;
}

List<Json> floorsOf(Json d) => jsonList(d['floors']);
List<Json> roomsOf(Json d, [String? floorId]) => jsonList(d['pages']).where((r) => floorId == null || r['floorId'] == floorId).toList();
List<Json> subsOf(Json room) => jsonList(room['subpages']);

/// Finds a widget by id inside a subpage, including group children.
Json? findWidget(Json sub, String? id) {
  if (id == null) return null;
  for (final w in jsonList(sub['widgets'])) {
    if (w['id'] == id) return w;
    if (w['type'] == 'group') {
      for (final c in jsonList(w['widgets'])) {
        if (c['id'] == id) return c;
      }
    }
  }
  return null;
}

/// Box (subpage or group widget) that directly contains widget [id].
Json? containerOf(Json sub, String id) {
  for (final w in jsonList(sub['widgets'])) {
    if (w['id'] == id) return sub;
  }
  for (final w in jsonList(sub['widgets'])) {
    if (w['type'] == 'group' && jsonList(w['widgets']).any((c) => c['id'] == id)) return w;
  }
  return null;
}

void removeWidget(Json sub, String id) {
  final box = containerOf(sub, id);
  if (box == null) return;
  rawList(box, 'widgets').removeWhere((x) => x is Map && x['id'] == id);
}

/// Places a new widget of [type] at (x, y), shrinking its width to fit.
({int x, int y, int w, int h})? placeAt(Json box, String type, int x, int y) {
  final t = kWidgetTypes[type]!;
  for (var w = (t.w < cols(box) - x ? t.w : cols(box) - x); w >= 1; w--) {
    if (isFree(box, x, y, w, t.h)) return (x: x, y: y, w: w, h: t.h);
  }
  return null;
}

Json deepCopy(Json m) => jsonMap(_copy(m));
Object? _copy(Object? v) {
  if (v is Map) return v.map((k, e) => MapEntry(k.toString(), _copy(e)));
  if (v is List) return v.map(_copy).toList();
  return v;
}

/// Clone with fresh ids (also for group children).
Json cloneWidget(Json w) {
  final c = deepCopy(w);
  c['id'] = uid('w_');
  if (c['type'] == 'group') {
    for (final k in rawList(c, 'widgets')) {
      if (k is Map) k['id'] = uid('w_');
    }
  }
  return c;
}

// ------------------------------------------------------------- font sizes

class FsDef {
  final String key, name;
  final int def, min, max;
  const FsDef(this.key, this.name, this.def, this.min, this.max);
}

const kFs = {
  'labelSize': FsDef('labelSize', 'Tên hiển thị', 15, 11, 26),
  'iconSize': FsDef('iconSize', 'Biểu tượng', 24, 16, 48),
  'stateSize': FsDef('stateSize', 'Trạng thái', 12, 9, 20),
  'valueSize': FsDef('valueSize', 'Giá trị', 28, 16, 44),
  'btnIcon': FsDef('btnIcon', 'Biểu tượng nút', 16, 12, 30),
  'acBtn': FsDef('acBtn', 'Nút + / −', 20, 14, 36),
  'acMode': FsDef('acMode', 'Nút chế độ', 16, 12, 28),
};

double fs(Json w, String key) {
  final d = kFs[key]!;
  final v = (jsonMap(w['text'])[key] as num?)?.toInt();
  return (v != null && v >= d.min && v <= d.max ? v : d.def).toDouble();
}

List<String> fsKeysFor(String type) => switch (type) {
  'group' => const ['labelSize'],
  'value' => const ['labelSize', 'iconSize', 'valueSize'],
  'webview' => const ['labelSize', 'iconSize'],
  'shutter' => const ['labelSize', 'iconSize', 'stateSize', 'btnIcon'],
  'ac' => const ['labelSize', 'iconSize', 'valueSize', 'stateSize', 'acBtn', 'acMode'],
  _ => const ['labelSize', 'iconSize', 'stateSize'],
};

// ------------------------------------------------------------- app theme sizes

class TfsDef {
  final String key, name;
  final int def, min, max;
  const TfsDef(this.key, this.name, this.def, this.min, this.max);
}

const kTfs = [
  TfsDef('titleSize', 'Tiêu đề phòng', 23, 16, 36),
  TfsDef('roomBar', 'Thanh chọn phòng', 13, 11, 20),
  TfsDef('pageTitle', 'Tên trang', 13, 10, 24),
  TfsDef('floorBar', 'Thanh chọn tầng', 12, 9, 18),
  TfsDef('crumb', 'Dòng tầng (Tầng 1 ›)', 13, 10, 20),
];

double tfs(Json doc, String key) {
  final d = kTfs.firstWhere((x) => x.key == key);
  final v = (jsonMap(doc['theme'])[key] as num?)?.toInt();
  return (v != null && v >= d.min && v <= d.max ? v : d.def).toDouble();
}

// ------------------------------------------------------------- issues

class Issue {
  final bool error;
  final String text;
  final String? roomId, subId, widgetId;
  const Issue(this.error, this.text, {this.roomId, this.subId, this.widgetId});
}

List<Issue> computeIssues(Json d) {
  final out = <Issue>[];
  final gas = jsonList(d['groupAddresses']);
  Json? ga(String? id) => byId(gas, id);
  if (jsonList(d['pages']).isEmpty) out.add(const Issue(false, 'Dự án chưa có phòng nào.'));
  for (final r in jsonList(d['pages'])) {
    for (final s in subsOf(r)) {
      final all = <(Json, Json)>[];
      for (final w in jsonList(s['widgets'])) {
        all.add((w, s));
        if (w['type'] == 'group') {
          for (final c in jsonList(w['widgets'])) {
            all.add((c, w));
          }
        }
      }
      if (all.isEmpty) out.add(Issue(false, '${r['title']} / ${s['title']}: trang chưa có thành phần.', roomId: r['id'], subId: s['id']));
      for (final (w, box) in all) {
        final t = kWidgetTypes[w['type']];
        if (t == null) continue;
        final name = '“${(w['label'] ?? t.name)}”';
        final where = '${r['title']}: ';
        final rws = rows(box);
        if (pi(w, 'y') + pi(w, 'h') > rws) {
          out.add(Issue(false, '$where$name nằm ngoài màn hình.', roomId: r['id'], subId: s['id'], widgetId: w['id']));
        }
        final b = jsonMap(w['bind']);
        for (final sl in slotsFor(w)) {
          final id = b[sl.key] as String?;
          if (id == null) {
            if (sl.required) out.add(Issue(true, '$where$name thiếu ${sl.label.toLowerCase()}.', roomId: r['id'], subId: s['id'], widgetId: w['id']));
            continue;
          }
          final g = ga(id);
          if (g == null) {
            out.add(Issue(true, '$where$name: địa chỉ của ô ${sl.label.toLowerCase()} đã bị xoá.', roomId: r['id'], subId: s['id'], widgetId: w['id']));
          } else if (!slotAccepts(sl, g)) {
            out.add(Issue(true, '$where$name: DPT ${g['dpt']} không hợp với ô ${sl.label.toLowerCase()}.', roomId: r['id'], subId: s['id'], widgetId: w['id']));
          }
        }
        if ((w['type'] == 'link' || w['type'] == 'webview') && !RegExp(r'^https?://\S+').hasMatch((w['url'] ?? '').toString())) {
          out.add(Issue(true, '$where$name chưa có địa chỉ web hợp lệ.', roomId: r['id'], subId: s['id'], widgetId: w['id']));
        }
      }
    }
  }
  for (final c in jsonList(d['connections'])) {
    if ((c['host'] ?? '').toString().trim().isEmpty) out.add(Issue(true, 'Kết nối “${c['name']}” chưa có địa chỉ IP.'));
  }
  return out;
}
