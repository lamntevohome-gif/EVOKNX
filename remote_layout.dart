import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:evoknx_ui/evoknx_ui.dart' show AppPalette, RemoteKeyFace, Text, iconWidget, liftOf, remoteDefaultIconWidget;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icon_picker.dart';
import 'props.dart' show ColorPicker;

/// Opens the window where the keys of a remote control card are arranged (dragged to a cell, one or several at a time),
/// and where their size, background, color, corner radius and icon are set.
Future<void> showRemoteLayout(BuildContext context, Designer d, String widgetId) => showDialog<void>(
  context: context,
  builder: (_) => _RemoteLayoutDialog(d: d, id: widgetId),
);

class _RemoteLayoutDialog extends StatefulWidget {
  const _RemoteLayoutDialog({required this.d, required this.id});
  final Designer d;
  final String id;

  @override
  State<_RemoteLayoutDialog> createState() => _RemoteLayoutDialogState();
}

class _RemoteLayoutDialogState extends State<_RemoteLayoutDialog> {
  /// The keys that are selected (the last one clicked is [_sel]; the settings below the grid show its values).
  final Set<String> _sels = {};
  String? _sel;

  /// The key that is being dragged, where the pointer is (in the grid) and where it was pressed.
  String? _drag;
  Offset _pos = Offset.zero, _start = Offset.zero;
  bool _moved = false;

  /// A press on a key of a group that was not dragged makes that key the only one selected.
  bool _collapse = false;

  Designer get d => widget.d;

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    d.addListener(_refresh);
    d.p.addListener(_refresh);
  }

  @override
  void dispose() {
    d.removeListener(_refresh);
    d.p.removeListener(_refresh);
    super.dispose();
  }

  Json? _card() => allWidgets(d.doc).where((x) => x['id'] == widget.id).firstOrNull;

  /// Changes the card wherever it is in the project (the page that is open does not matter).
  void _edit(void Function(Json w) fn, {String? coalesce}) {
    if (_card() == null) return;
    try {
      d.p.mutate((doc) {
        final x = allWidgets(doc).where((e) => e['id'] == widget.id).firstOrNull;
        if (x != null) fn(x);
      }, coalesce: coalesce);
    } catch (e) {
      if (mounted) toast(context, 'Could not change the card: $e');
    }
    if (mounted) setState(() {});
  }

  Json _remote(Json x) => jsonMap(x['remote']);

  /// Sets (or, with null, removes) the value of every selected key in the map [key] of the settings of the card.
  void _map(String key, Object? v, {String? coalesce}) {
    final ids = _sels.toList();
    _edit((x) {
      final o = _remote(x);
      final m = jsonMap(o[key]);
      for (final id in ids) {
        if (v == null) {
          m.remove(id);
        } else {
          m[id] = v;
        }
      }
      o[key] = m;
      x['remote'] = o;
    }, coalesce: coalesce == null ? null : 'r$coalesce-${widget.id}-${ids.join(',')}');
  }

  void _setScale(int pct) => _map('scale', pct == 100 ? null : pct, coalesce: 'scale');
  void _setBgSize(int pct) => _map('bgsize', pct >= 100 ? null : pct, coalesce: 'bgsize');
  void _setRadius(int? r) => _map('kradius', r, coalesce: 'radius');
  void _setBg(String mode) => _map('kbg', mode == 'default' ? null : mode);
  void _setColor(String? hex) => _map('kcolor', hex);

  void _setSpan(int cw, int rh) {
    final ids = _sels.toList();
    _edit((x) {
      final o = _remote(x);
      final m = jsonMap(o['span']);
      for (final id in ids) {
        final dflt = kRemoteSpan[id] ?? (1, 1);
        if (cw == dflt.$1 && rh == dflt.$2) {
          m.remove(id);
        } else {
          m[id] = <String, dynamic>{'w': cw, 'h': rh};
        }
      }
      o['span'] = m;
      x['remote'] = o;
    });
  }

  /// The icon of the selected keys: a custom button keeps it in its own entry, the others in remote.icons.
  void _setIcon(String? key) {
    final ids = _sels.where((e) => e != 'dpad' && e != 'touchpad').toList();
    _edit((x) {
      final o = _remote(x);
      final cu = remoteCustom(x);
      final m = jsonMap(o['icons']);
      for (final id in ids) {
        final i = cu.indexWhere((e) => e['id'] == id);
        if (i >= 0) {
          final e = Map<String, dynamic>.from(cu[i]);
          if (key == null) {
            e.remove('icon');
          } else {
            e['icon'] = key;
          }
          cu[i] = e;
        } else if (key == null) {
          m.remove(id);
        } else {
          m[id] = key;
        }
      }
      o['custom'] = cu;
      o['icons'] = m;
      x['remote'] = o;
    });
  }

  String? _iconOf(Json w, String part) {
    final e = remoteCustom(w).where((x) => x['id'] == part).firstOrNull;
    if (e != null) {
      final k = (e['icon'] ?? '').toString();
      return k.isEmpty ? null : k;
    }
    return remoteKeyIcon(w, part);
  }

  void _setSize(String key, int v) => _edit((x) {
    final o = _remote(x);
    o[key] = v;
    x['remote'] = o;
  });

  void _setHide(String part, bool hide) => _edit((x) {
    final o = _remote(x);
    final m = jsonMap(o['hide']);
    m[part] = hide;
    o['hide'] = m;
    x['remote'] = o;
  });

  void _setCustom(String cid, String field, String v) => _edit((x) {
    final o = _remote(x);
    final list = jsonList(o['custom']);
    for (final it in list) {
      if (it['id'] == cid) it[field] = v.trim();
    }
    o['custom'] = list;
    x['remote'] = o;
  }, coalesce: 'rc-${widget.id}-$cid-$field');

  void _addCustom() => _edit((x) {
    final o = _remote(x);
    final list = jsonList(o['custom']);
    list.add(<String, dynamic>{'id': uid('rc_'), 'label': 'Button ${list.length + 1}', 'icon': '', 'cmd': ''});
    o['custom'] = list;
    x['remote'] = o;
  });

  void _delCustom(Iterable<String> cids) {
    final gone = cids.toSet();
    if (gone.isEmpty) return;
    _sels.removeAll(gone);
    if (_sel != null && gone.contains(_sel)) _sel = _sels.firstOrNull;
    _edit((x) {
      final o = _remote(x);
      o['custom'] = [
        for (final it in jsonList(o['custom']))
          if (!gone.contains(it['id'])) it,
      ];
      for (final m in ['layout', 'hide', 'values', 'span', 'scale', 'kbg', 'kcolor', 'bgsize', 'kradius', 'icons']) {
        final mm = jsonMap(o[m]);
        for (final g in gone) {
          mm.remove(g);
        }
        o[m] = mm;
      }
      final b = jsonMap(x['bind']);
      for (final g in gone) {
        b.remove('rk_$g');
      }
      x['bind'] = b;
      x['remote'] = o;
    });
  }

  void _apply(Map<String, (int, int)> pos) => _edit((x) {
    final o = _remote(x);
    o['layout'] = {
      for (final e in pos.entries) e.key: {'c': e.value.$1, 'r': e.value.$2},
    };
    x['remote'] = o;
  });

  /// Where every key would be if [item] went to the cell ([c], [r]): a free place, or a swap with one key of the same size.
  /// Null when there is no room there.
  Map<String, (int, int)>? _plan(Json w, RemoteItem item, int c, int r) {
    final items = remoteItems(w);
    final cols = remoteCols(w);
    c = c.clamp(0, cols - item.cw);
    r = r < 0 ? 0 : r;
    final hit = [
      for (final o in items)
        if (o.id != item.id && c < o.c + o.cw && o.c < c + item.cw && r < o.r + o.rh && o.r < r + item.rh) o,
    ];
    final pos = {for (final o in items) o.id: (o.c, o.r)};
    if (hit.isEmpty) {
      pos[item.id] = (c, r);
    } else if (hit.length == 1 && hit.first.cw == item.cw && hit.first.rh == item.rh) {
      pos[hit.first.id] = (item.c, item.r);
      pos[item.id] = (hit.first.c, hit.first.r);
    } else {
      return null;
    }
    return pos;
  }

  /// The selected keys all moved by ([dc], [dr]) cells: only when they stay in the grid and on free cells.
  Map<String, (int, int)>? _planGroup(Json w, List<RemoteItem> group, int dc, int dr, int rows) {
    final items = remoteItems(w);
    final cols = remoteCols(w);
    final ids = {for (final g in group) g.id};
    for (final g in group) {
      if (g.c + dc < 0 || g.c + g.cw + dc > cols || g.r + dr < 0 || g.r + g.rh + dr > rows) return null;
    }
    for (final g in group) {
      for (final o in items) {
        if (ids.contains(o.id)) continue;
        if (g.c + dc < o.c + o.cw && o.c < g.c + g.cw + dc && g.r + dr < o.r + o.rh && o.r < g.r + g.rh + dr) return null;
      }
    }
    return {for (final o in items) o.id: ids.contains(o.id) ? (o.c + dc, o.r + dr) : (o.c, o.r)};
  }

  bool get _modifier => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isMetaPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final screen = MediaQuery.sizeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([d, d.p]),
      builder: (context, _) {
        final w = _card();
        if (w == null) return const SizedBox.shrink();
        final items = remoteItems(w);
        final cols = remoteCols(w);
        final rows = remoteRowCount(w, items);
        // The panel of the keys has a fixed size: more columns or rows only make more, smaller cells.
        const gridW = 340.0, gridH = 430.0, keyW = 290.0, sideW = 235.0, customW = 250.0;
        final dialogW = (gridW + keyW + sideW + customW + 60 + 48 + 8).clamp(0.0, screen.width - 48).toDouble();
        final bodyH = (screen.height - 48 - 130).clamp(300.0, 600.0).toDouble();
        final cellW = gridW / cols;
        final cellH = gridH / rows;
        final th = jsonMap(d.doc['theme']);
        final pal = AppPalette.of(d.previewTheme ?? (th['mode'] ?? 'light').toString()).copyWith(
          tileOpacity: ((th['cardOpacity'] as num?) ?? 100).toDouble().clamp(0, 100) / 100,
          edgeOpacity: ((th['cardEdge'] as num?) ?? 100).toDouble().clamp(0, 100) / 100,
          radius: ((th['cardRadius'] as num?) ?? 12).toDouble().clamp(0, 32).toDouble(),
          border: ((th['cardBorder'] as num?) ?? 1).toDouble().clamp(0, 4).toDouble(),
          lift: liftOf(((th['btnRaise'] as num?) ?? 60).toDouble().clamp(0, 100)),
        );
        String nameOf(String part) {
          for (final e in kRemoteElements) {
            if (e.$1 == part) return e.$2;
          }
          for (final x in remoteCustom(w)) {
            if (x['id'] == part) return (x['label'] ?? '').toString().isEmpty ? 'Custom button' : (x['label'] ?? '').toString();
          }
          return part;
        }

        // A key that is hidden or deleted leaves the selection.
        final shown = {for (final i in items) i.id};
        _sels.removeWhere((e) => !shown.contains(e));
        if (_sel != null && !_sels.contains(_sel)) _sel = _sels.firstOrNull;
        final dragging = _drag == null ? null : items.where((x) => x.id == _drag).firstOrNull;
        final group = dragging != null && _sels.length > 1 && _sels.contains(dragging.id)
            ? [
                for (final i in items)
                  if (_sels.contains(i.id)) i,
              ]
            : <RemoteItem>[];

        // Where the dragged key (or keys) would land, and whether it can.
        final delta = _pos - _start;
        final dc = (delta.dx / cellW).round(), dr = (delta.dy / cellH).round();
        Map<String, (int, int)>? plan;
        if (dragging != null && _moved) {
          plan = group.isNotEmpty
              ? _planGroup(w, group, dc, dr, rows)
              : _plan(w, dragging, (dragging.c + dc).clamp(0, cols - dragging.cw), (dragging.r + dr).clamp(0, rows - dragging.rh));
        }
        final moving = group.isNotEmpty ? group : [if (dragging != null) dragging];

        final grid = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            final p = e.localPosition;
            final hit = items
                .where((x) => p.dx >= x.c * cellW && p.dx < (x.c + x.cw) * cellW && p.dy >= x.r * cellH && p.dy < (x.r + x.rh) * cellH)
                .firstOrNull;
            setState(() {
              _moved = false;
              _start = p;
              _pos = p;
              _collapse = false;
              _drag = null;
              if (hit == null) {
                if (!_modifier) {
                  _sels.clear();
                  _sel = null;
                }
              } else if (_modifier) {
                if (!_sels.remove(hit.id)) {
                  _sels.add(hit.id);
                  _sel = hit.id;
                } else {
                  _sel = _sels.firstOrNull;
                }
              } else if (_sels.contains(hit.id) && _sels.length > 1) {
                _sel = hit.id;
                _drag = hit.id;
                _collapse = true;
              } else {
                _sels
                  ..clear()
                  ..add(hit.id);
                _sel = hit.id;
                _drag = hit.id;
              }
            });
          },
          onPointerMove: (e) {
            if (_drag == null) return;
            setState(() {
              _pos = e.localPosition;
              if ((_pos - _start).distance > 6) _moved = true;
            });
          },
          onPointerUp: (_) {
            final p = plan;
            if (dragging != null && _moved) {
              if (p != null) {
                _apply(p);
              } else {
                toast(context, 'Not enough room there.');
              }
            } else if (_collapse && dragging != null) {
              _sels
                ..clear()
                ..add(dragging.id);
              _sel = dragging.id;
            }
            setState(() {
              _drag = null;
              _moved = false;
              _collapse = false;
            });
          },
          onPointerCancel: (_) => setState(() {
            _drag = null;
            _moved = false;
            _collapse = false;
          }),
          child: MouseRegion(
            cursor: _drag != null ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
            child: Container(
              width: gridW,
              height: gridH,
              decoration: BoxDecoration(
                color: c.paper,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Stack(
                children: [
                  for (var gx = 0; gx < cols; gx++)
                    for (var gy = 0; gy < rows; gy++)
                      Positioned(
                        left: gx * cellW,
                        top: gy * cellH,
                        width: cellW,
                        height: cellH,
                        child: DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: c.line.withAlpha(120), width: 0.5)),
                        ),
                      ),
                  // The places the dragged keys would take.
                  if (_moved)
                    for (final m in moving)
                      Positioned(
                        left: (plan?[m.id]?.$1 ?? m.c + dc) * cellW,
                        top: (plan?[m.id]?.$2 ?? m.r + dr) * cellH,
                        width: m.cw * cellW,
                        height: m.rh * cellH,
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: (plan != null ? c.accent : c.danger).withAlpha(40),
                            border: Border.all(color: plan != null ? c.accent : c.danger, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  for (final it in items)
                    Positioned(
                      left: it.c * cellW,
                      top: it.r * cellH,
                      width: it.cw * cellW,
                      height: it.rh * cellH,
                      child: _face(c, w, pal, it, opacity: _moved && moving.any((m) => m.id == it.id) ? 0.3 : 1, selected: _sels.contains(it.id)),
                    ),
                  if (_moved)
                    for (final m in moving)
                      Positioned(
                        left: m.c * cellW + delta.dx,
                        top: m.r * cellH + delta.dy,
                        width: m.cw * cellW,
                        height: m.rh * cellH,
                        child: IgnorePointer(child: _face(c, w, pal, m, opacity: 0.85, selected: true)),
                      ),
                ],
              ),
            ),
          ),
        );

        final sel = _sel;
        final many = _sels.length > 1;
        final selItems = [
          for (final i in items)
            if (_sels.contains(i.id)) i,
        ];
        final onlyPad = selItems.isNotEmpty && selItems.every((i) => i.id == 'touchpad');
        final noRadius = selItems.isNotEmpty && selItems.every((i) => i.id == 'dpad');
        final hasIcon = selItems.any((i) => i.id != 'dpad' && i.id != 'touchpad');
        final customSel = [
          for (final i in selItems)
            if (remoteCustom(w).any((x) => x['id'] == i.id)) i.id,
        ];
        Widget title(String t) => Text(
          t,
          style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600, color: c.ink),
        );

        Widget numberRow(int value, int min, int max, ValueChanged<int> onChanged, {String unit = '%'}) => Row(
          children: [
            Expanded(
              child: Slider(
                value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
                min: min.toDouble(),
                max: max.toDouble(),
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
            SyncedField(
              value: '$value',
              number: true,
              width: 58,
              center: true,
              onChanged: (t) {
                final n = int.tryParse(t.trim());
                if (n != null) onChanged(n.clamp(min, max));
              },
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(fontSize: kUiText, color: c.muted),
            ),
          ],
        );

        final keyPanel = SizedBox(
          width: keyW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sel == null)
                Text('Click a key. Ctrl or Shift + click selects several.', style: TextStyle(fontSize: 12.5, color: c.muted))
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        many ? '${_sels.length} keys selected' : nameOf(sel),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                      ),
                    ),
                    if (customSel.isNotEmpty)
                      EvoButton(label: 'Delete', icon: Icons.delete_outline, danger: true, small: true, onPressed: () => _delCustom(customSel)),
                  ],
                ),
                if (!onlyPad) ...[const SizedBox(height: 8), title('Icon size'), numberRow(remoteScale(w, sel), 40, 300, _setScale)],
                title('Size of the button (cells)'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'Width',
                      style: TextStyle(fontSize: kUiText, color: c.muted),
                    ),
                    const SizedBox(width: 8),
                    _Step(value: remoteSpan(w, sel).$1, min: 1, max: cols, onChanged: (v) => _setSpan(v, remoteSpan(w, sel).$2)),
                    const SizedBox(width: 22),
                    Text(
                      'Height',
                      style: TextStyle(fontSize: kUiText, color: c.muted),
                    ),
                    const SizedBox(width: 8),
                    _Step(value: remoteSpan(w, sel).$2, min: 1, max: 8, onChanged: (v) => _setSpan(remoteSpan(w, sel).$1, v)),
                  ],
                ),
                const SizedBox(height: 10),
                title('Background'),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Seg<String>(
                    items: const [('default', 'Default'), ('outline', 'Border only'), ('transparent', 'Transparent')],
                    value: remoteKeyBg(w, sel),
                    onChanged: _setBg,
                  ),
                ),
                if (remoteKeyBg(w, sel) != 'transparent') ...[
                  const SizedBox(height: 8),
                  title('Background size'),
                  numberRow(remoteBgSize(w, sel), 40, 100, _setBgSize),
                  if (!noRadius) ...[
                    title('Border radius'),
                    numberRow(remoteKeyRadius(w, sel)?.round() ?? (pal.radius * 0.5).round(), 0, 60, _setRadius, unit: 'px'),
                  ],
                  title(remoteKeyBg(w, sel) == 'outline' ? 'Border color' : 'Color'),
                  const SizedBox(height: 6),
                  ColorPicker(value: remoteKeyColor(w, sel) ?? '', onChanged: _setColor),
                  if (remoteKeyColor(w, sel) != null) TextButton(onPressed: () => _setColor(null), child: const Text('Usual color')),
                ],
                if (hasIcon) ...[
                  const SizedBox(height: 10),
                  title('Icon or picture'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _iconOf(w, sel) != null ? iconWidget(_iconOf(w, sel), 24, c.ink) : remoteDefaultIconWidget(w, sel, 24, c.ink),
                      ),
                      const SizedBox(width: 8),
                      EvoButton(
                        label: 'Change',
                        small: true,
                        onPressed: () async {
                          final k = await pickIcon(context, d: d, current: _iconOf(w, sel), scope: IconScope.widget);
                          if (k != null && k.isNotEmpty) _setIcon(k);
                        },
                      ),
                      const SizedBox(width: 6),
                      EvoButton(label: 'Default', small: true, onPressed: () => _setIcon(null)),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );

        Widget check(String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          title: Text(label),
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        );
        final knx = remoteIsKnx(w);
        final side = SizedBox(
          width: sideW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title('Keys'), for (final e in kRemoteElements) check(e.$2, !remoteHidden(w, e.$1), (v) => _setHide(e.$1, !v))],
          ),
        );
        final size = SizedBox(
          width: gridW,
          child: Row(
            children: [
              title('Columns'),
              const SizedBox(width: 8),
              _Step(value: cols, min: 3, max: 6, onChanged: (v) => _setSize('cols', v)),
              const SizedBox(width: 24),
              title('Rows'),
              const SizedBox(width: 8),
              _Step(value: rows, min: remoteRows(items), max: 24, onChanged: (v) => _setSize('rows', v)),
            ],
          ),
        );
        Widget column(Widget child) => SingleChildScrollView(child: child);
        final custom = SizedBox(
          width: customW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title('Custom buttons'),
              const SizedBox(height: 6),
              for (final cb in remoteCustom(w)) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (cb['label'] ?? '').toString().isEmpty ? 'Custom button' : cb['label'].toString(),
                        style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete the button',
                      icon: Icon(Icons.delete_outline, color: c.danger),
                      onPressed: () => _delCustom([cb['id'].toString()]),
                    ),
                  ],
                ),
                FieldLabel('Name', SyncedField(value: (cb['label'] ?? '').toString(), onChanged: (v) => _setCustom(cb['id'].toString(), 'label', v))),
                FieldLabel(
                  'Icon',
                  IconField(d: d, value: (cb['icon'] ?? '').toString(), scope: IconScope.widget, onChanged: (v) => _setCustom(cb['id'].toString(), 'icon', v)),
                ),
                if (!knx)
                  FieldLabel(
                    'Key name',
                    SyncedField(
                      value: (cb['cmd'] ?? '').toString(),
                      hint: 'as the remote names it',
                      onChanged: (v) => _setCustom(cb['id'].toString(), 'cmd', v),
                    ),
                  ),
                Divider(color: c.line),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: EvoButton(label: 'Add a button', icon: Icons.add, onPressed: _addCustom),
              ),
            ],
          ),
        );

        return Focus(
          autofocus: true,
          onKeyEvent: (node, e) {
            if (e is KeyDownEvent &&
                e.logicalKey == LogicalKeyboardKey.delete &&
                customSel.isNotEmpty &&
                FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() == null) {
              _delCustom(customSel);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Dialog(
            backgroundColor: c.panel,
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dialogW, maxHeight: screen.height - 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arrange the keys',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        height: bodyH,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            column(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [size, const SizedBox(height: 10), grid])),
                            const SizedBox(width: 10),
                            VerticalDivider(color: c.line, width: 1),
                            const SizedBox(width: 10),
                            column(keyPanel),
                            const SizedBox(width: 10),
                            VerticalDivider(color: c.line, width: 1),
                            const SizedBox(width: 10),
                            column(side),
                            const SizedBox(width: 10),
                            VerticalDivider(color: c.line, width: 1),
                            const SizedBox(width: 10),
                            column(custom),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _edit((x) {
                            final o = _remote(x);
                            o.addAll(remoteDefaultSettings());
                            x['remote'] = o;
                          }),
                          child: const Text('Reset the layout'),
                        ),
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _face(EvoColors c, Json w, AppPalette pal, RemoteItem it, {double opacity = 1, bool selected = false}) {
    return Opacity(
      opacity: opacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The key as it is on the card.
          IgnorePointer(
            child: RemoteKeyFace(w: w, pal: pal, id: it.id),
          ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: c.accent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "− 3 +": a small whole-number stepper.
class _Step extends StatelessWidget {
  const _Step({required this.value, required this.min, required this.max, required this.onChanged});
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    Widget b(IconData i, bool on, VoidCallback f) => InkWell(
      onTap: on ? f : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(i, size: 18, color: on ? c.ink : c.line),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.lineStrong),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(Icons.remove, value > min, () => onChanged(value - 1)),
          SizedBox(
            width: 26,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: kUiText, color: c.ink),
            ),
          ),
          b(Icons.add, value < max, () => onChanged(value + 1)),
        ],
      ),
    );
  }
}
