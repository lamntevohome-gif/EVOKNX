import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';

import '../../state/project_controller.dart';
import 'model.dart';

/// What is being dragged onto the canvas.
class DragItem {
  final String kind; // palette | widget
  final String? type;
  final String? id;
  const DragItem.palette(String this.type) : kind = 'palette', id = null;
  const DragItem.widget(String this.id) : kind = 'widget', type = null;
}

/// Selection + editing commands for the Structure workspace.
/// All edits go through [ProjectController.mutate] (undo/redo, autosave) and
/// look objects up by id inside the callback, so they stay valid after undo.
class Designer extends ChangeNotifier {
  Designer(this.p);
  final ProjectController p;

  String view = 'room'; // overview | floor | room
  String? floorId, roomId, subId, widgetId;
  ({String? g, int x, int y})? cell;
  Json? clip;

  Json get doc => p.doc;

  // ------------------------------------------------------------ resolution

  Json? get floor {
    final fs = floorsOf(doc);
    if (fs.isEmpty) return null;
    final r = byId(jsonList(doc['pages']), roomId);
    return byId(fs, r?['floorId'] as String? ?? floorId) ?? fs.first;
  }

  Json? get room {
    final r = byId(jsonList(doc['pages']), roomId);
    if (r != null) return r;
    final f = floor;
    final rs = f == null ? <Json>[] : roomsOf(doc, f['id'] as String?);
    return rs.isEmpty ? null : rs.first;
  }

  Json? get sub {
    final r = room;
    if (r == null) return null;
    final ss = subsOf(r);
    return byId(ss, subId) ?? (ss.isEmpty ? null : ss.first);
  }

  Json? get widget {
    final s = sub;
    return s == null ? null : findWidget(s, widgetId);
  }

  void _n() => notifyListeners();

  // ------------------------------------------------------------ selection

  void overview() {
    view = 'overview';
    widgetId = null;
    cell = null;
    _n();
  }

  void selectFloor(String id) {
    view = 'floor';
    floorId = id;
    final rs = roomsOf(doc, id);
    roomId = rs.isEmpty ? null : rs.first['id'] as String?;
    subId = null;
    widgetId = null;
    cell = null;
    _n();
  }

  void selectRoom(String id) {
    view = 'room';
    roomId = id;
    floorId = byId(jsonList(doc['pages']), id)?['floorId'] as String?;
    subId = null;
    widgetId = null;
    cell = null;
    _n();
  }

  void selectSub(String roomId_, String id) {
    view = 'room';
    roomId = roomId_;
    floorId = byId(jsonList(doc['pages']), roomId_)?['floorId'] as String?;
    subId = id;
    widgetId = null;
    cell = null;
    _n();
  }

  void selectWidget(String? id) {
    widgetId = id;
    cell = null;
    if (id != null) view = 'room';
    _n();
  }

  void selectCell(String? g, int x, int y) {
    cell = (g: g, x: x, y: y);
    widgetId = null;
    view = 'room';
    _n();
  }

  void stepSub(int d) {
    final r = room;
    final s = sub;
    if (r == null || s == null) return;
    final ss = subsOf(r);
    final i = ss.indexWhere((x) => x['id'] == s['id']);
    final j = i + d;
    if (j < 0 || j >= ss.length) return;
    selectSub(r['id'] as String, ss[j]['id'] as String);
  }

  // ------------------------------------------------------------ structure edits

  void addFloor() {
    late Json f;
    p.mutate((d) {
      f = makeFloor('Tầng ${floorsOf(d).length + 1}');
      rawList(d, 'floors').add(f);
    });
    selectFloor(f['id'] as String);
  }

  void addRoom(String floorId_) {
    late Json r;
    p.mutate((d) {
      r = makeRoom('Phòng ${roomsOf(d, floorId_).length + 1}', floorId: floorId_);
      rawList(d, 'pages').add(r);
    });
    selectRoom(r['id'] as String);
  }

  void addSub() {
    final r = room, s = sub;
    if (r == null) return;
    final rid = r['id'];
    late Json n;
    p.mutate((d) {
      final rr = byId(jsonList(d['pages']), rid as String)!;
      n = makeSub('Trang ${subsOf(rr).length + 1}', cols: s == null ? 4 : cols(s), rows: s == null ? 12 : rows(s));
      rawList(rr, 'subpages').add(n);
    });
    selectSub(rid as String, n['id'] as String);
  }

  String? deleteSub() {
    final r = room, s = sub;
    if (r == null || s == null) return null;
    if (subsOf(r).length < 2) return 'Phòng cần ít nhất một trang.';
    final rid = r['id'] as String, sid = s['id'];
    p.mutate((d) => rawList(byId(jsonList(d['pages']), rid)!, 'subpages').removeWhere((x) => x is Map && x['id'] == sid));
    subId = null;
    widgetId = null;
    _n();
    return null;
  }

  void deleteRoom() {
    final r = room;
    if (r == null) return;
    final rid = r['id'];
    p.mutate((d) => rawList(d, 'pages').removeWhere((x) => x is Map && x['id'] == rid));
    roomId = null;
    subId = null;
    widgetId = null;
    _n();
  }

  String? deleteFloor(String id) {
    if (floorsOf(doc).length < 2) return 'Dự án cần ít nhất một tầng.';
    if (roomsOf(doc, id).isNotEmpty) return 'Tầng còn phòng. Hãy chuyển hoặc xoá các phòng trước.';
    p.mutate((d) => rawList(d, 'floors').removeWhere((x) => x is Map && x['id'] == id));
    overview();
    return null;
  }

  void moveInList(String listKey, String id, int dir, {String? roomForSubs}) {
    p.mutate((d) {
      final list = roomForSubs == null ? rawList(d, listKey) : rawList(byId(jsonList(d['pages']), roomForSubs)!, 'subpages');
      final i = list.indexWhere((x) => x is Map && x['id'] == id);
      final j = i + dir;
      if (i < 0 || j < 0 || j >= list.length) return;
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    });
  }

  /// Moves a room among the rooms of its floor.
  void moveRoom(String id, int dir) {
    p.mutate((d) {
      final list = rawList(d, 'pages');
      final r = list.firstWhere((x) => x is Map && x['id'] == id) as Map;
      final same = [
        for (var k = 0; k < list.length; k++)
          if ((list[k] as Map)['floorId'] == r['floorId']) k,
      ];
      final pos_ = same.indexOf(list.indexOf(r));
      final to = pos_ + dir;
      if (to < 0 || to >= same.length) return;
      final a = same[pos_], b = same[to];
      final t = list[a];
      list[a] = list[b];
      list[b] = t;
    });
  }

  // ------------------------------------------------------------ widget edits

  /// Edits the selected subpage (looked up again inside the mutation).
  void editSub(void Function(Json sub) fn, {String? coalesce}) {
    final r = room, s = sub;
    if (r == null || s == null) return;
    final rid = r['id'] as String, sid = s['id'] as String;
    p.mutate((d) {
      final ss = byId(subsOf(byId(jsonList(d['pages']), rid)!), sid);
      if (ss != null) fn(ss);
    }, coalesce: coalesce);
  }

  void editWidget(String id, void Function(Json w) fn, {String? coalesce}) => editSub((s) {
    final w = findWidget(s, id);
    if (w != null) fn(w);
  }, coalesce: coalesce);

  Json? _box(Json s, String? g) => g == null ? s : findWidget(s, g);

  ({int x, int y, int w, int h, bool ok})? footprint(DragItem it, String? g, int x, int y) {
    final s = sub;
    if (s == null) return null;
    final box = _box(s, g);
    if (box == null) return null;
    final c = cols(box);
    if (it.kind == 'widget') {
      final w = findWidget(s, it.id);
      if (w == null) return null;
      final ww = min(pi(w, 'w'), c), hh = g == null ? pi(w, 'h') : min(pi(w, 'h'), rows(box));
      final xx = min(x, c - ww);
      final nested = g != null && (w['type'] == 'group' || w['id'] == g);
      return (x: xx, y: y, w: ww, h: hh, ok: !nested && isFree(box, xx, y, ww, hh, w['id'] as String?));
    }
    final t = kWidgetTypes[it.type]!;
    final ww = min(t.w, c - x), hh = g == null ? t.h : min(t.h, rows(box) - y);
    return (x: x, y: y, w: ww, h: hh, ok: !(g != null && it.type == 'group') && ww > 0 && isFree(box, x, y, ww, hh));
  }

  /// Drops [it] on cell (x, y) of box [g] (null = page). Returns an error.
  String? drop(DragItem it, String? g, int x, int y) {
    final s = sub;
    if (s == null) return 'Hãy chọn một phòng trước.';
    final box = _box(s, g);
    if (box == null) return null;
    if (it.kind == 'palette') {
      if (g != null && it.type == 'group') return 'Không thể đặt khung lưới bên trong khung lưới khác.';
      final sp = placeAt(box, it.type!, x, y);
      if (sp == null) return 'Không đủ chỗ ở vị trí này.';
      late Json nw;
      editSub((ss) {
        final b = _box(ss, g)!;
        final h = g == null ? sp.h : min(sp.h, rows(b) - y);
        nw = makeWidget(it.type!, sp.x, sp.y, sp.w, h);
        rawList(b, 'widgets').add(nw);
      });
      selectWidget(nw['id'] as String);
      return null;
    }
    final fp = footprint(it, g, x, y);
    if (fp == null) return null;
    if (!fp.ok) {
      final w = findWidget(s, it.id);
      if (g != null && w?['type'] == 'group') return 'Không thể đặt khung lưới bên trong khung lưới khác.';
      return 'Vị trí này đã có thành phần khác.';
    }
    final id = it.id!;
    editSub((ss) {
      final w = findWidget(ss, id);
      final src = containerOf(ss, id);
      final dst = _box(ss, g);
      if (w == null || src == null || dst == null) return;
      if (!identical(src, dst) && src['id'] != dst['id']) {
        rawList(src, 'widgets').removeWhere((o) => o is Map && o['id'] == id);
        rawList(dst, 'widgets').add(w);
      }
      w['pos'] = {'x': fp.x, 'y': fp.y, 'w': fp.w, 'h': fp.h};
    });
    selectWidget(id);
    return null;
  }

  /// Adds a component at the selected cell, or at the first free spot.
  String? addWidget(String type) {
    if (room == null) {
      final f = floor;
      if (f == null) return 'Hãy thêm tầng trước.';
      addRoom(f['id'] as String);
    }
    final s = sub!;
    final c = cell;
    if (c != null) {
      final box = _box(s, c.g);
      if (box == null) return null;
      if (c.g != null && type == 'group') return 'Không thể đặt khung lưới bên trong khung lưới khác.';
      final sp = placeAt(box, type, c.x, c.y);
      if (sp == null || (c.g == null && sp.y + sp.h > rows(box))) return 'Ô đã chọn không đủ chỗ cho thành phần này. Hãy chọn ô khác.';
      return drop(DragItem.palette(type), c.g, c.x, c.y);
    }
    final t = kWidgetTypes[type]!;
    final f = findFree(s, t.w, t.h);
    late Json nw;
    editSub((ss) {
      nw = makeWidget(type, f.x, f.y, min(t.w, cols(ss)), t.h);
      rawList(ss, 'widgets').add(nw);
    });
    selectWidget(nw['id'] as String);
    return null;
  }

  void deleteWidget() {
    final id = widgetId;
    if (id == null) return;
    editSub((s) => removeWidget(s, id));
    widgetId = null;
    _n();
  }

  String? copy() {
    final w = widget;
    if (w == null) return null;
    clip = deepCopy(w);
    _n();
    return 'Đã sao chép “${w['label'] ?? ''}”. Chọn một ô trống rồi bấm Dán (Ctrl+V).';
  }

  String? paste() {
    final cp = clip;
    final s = sub;
    if (cp == null) return null;
    if (s == null) return 'Hãy mở một phòng trước khi dán.';
    final c = cell;
    final box = c == null ? s : _box(s, c.g);
    if (box == null) return null;
    if (c?.g != null && cp['type'] == 'group') return 'Không thể dán khung lưới vào bên trong khung lưới khác.';
    final nw = cloneWidget(cp);
    final ww = min(pi(nw, 'w'), cols(box));
    final hh = c?.g != null ? min(pi(nw, 'h'), rows(box)) : pi(nw, 'h');
    int x, y;
    if (c != null) {
      x = max(0, min(c.x, cols(box) - ww));
      y = c.y;
      if (!isFree(box, x, y, ww, hh)) return 'Ô đã chọn không đủ chỗ cho thành phần này.';
    } else {
      final f = findFree(box, ww, hh);
      x = f.x;
      y = f.y;
    }
    nw['pos'] = {'x': x, 'y': y, 'w': ww, 'h': hh};
    final g = c?.g;
    editSub((ss) => rawList(_box(ss, g)!, 'widgets').add(nw));
    selectWidget(nw['id'] as String);
    return 'Đã dán “${nw['label'] ?? ''}”.';
  }

  /// Re-packs widgets after the column count shrinks.
  static void repackCols(Json box, int n) {
    final old = cols(box);
    jsonMap(box['layout'])['columns'] = n;
    if (n >= old) return;
    final ws = jsonList(box['widgets'])..sort((a, b) => pi(a, 'y') != pi(b, 'y') ? pi(a, 'y') - pi(b, 'y') : pi(a, 'x') - pi(b, 'x'));
    final tmp = <String, dynamic>{
      'layout': {'columns': n},
      'widgets': <Json>[],
    };
    for (final w in ws) {
      final ww = min(pi(w, 'w'), n), hh = pi(w, 'h');
      var x = min(pi(w, 'x'), n - ww), y = pi(w, 'y');
      if (!isFree(tmp, x, y, ww, hh)) {
        final f = findFree(tmp, ww, hh);
        x = f.x;
        y = f.y;
      }
      w['pos'] = {'x': x, 'y': y, 'w': ww, 'h': hh};
      (tmp['widgets'] as List).add(w);
    }
  }
}
