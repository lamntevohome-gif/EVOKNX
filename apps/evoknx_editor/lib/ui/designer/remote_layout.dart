import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show AppPalette, RemoteKeyFace, Text, iconWidget, liftOf;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icon_picker.dart';
import 'props.dart' show ColorPicker;

/// Opens the window where the keys of a remote control card are dragged to the cell they should take, and where the size
/// of the icon of each key is set.
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
  /// The key that is selected (its icon size is shown on the right).
  String? _sel;

  /// The key that is being dragged, where the pointer is (in the grid) and where on the key it took hold.
  String? _drag;
  Offset _pos = Offset.zero, _grab = Offset.zero, _start = Offset.zero;
  bool _moved = false;

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

  void _apply(Map<String, (int, int)> pos) => _edit((x) {
    final o = jsonMap(x['remote']);
    o['layout'] = {
      for (final e in pos.entries) e.key: {'c': e.value.$1, 'r': e.value.$2},
    };
    x['remote'] = o;
  });

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

  void _setSize(String key, int v) => _edit((x) {
    final o = jsonMap(x['remote']);
    o[key] = v;
    x['remote'] = o;
  });

  void _show(String part) => _edit((x) {
    final o = jsonMap(x['remote']);
    final h = jsonMap(o['hide']);
    h[part] = false;
    o['hide'] = h;
    x['remote'] = o;
  });

  void _setScale(String part, int pct) => _edit((x) {
    final o = jsonMap(x['remote']);
    final s = jsonMap(o['scale']);
    if (pct == 100) {
      s.remove(part);
    } else {
      s[part] = pct;
    }
    o['scale'] = s;
    x['remote'] = o;
  }, coalesce: 'rscale-${widget.id}-$part');

  void _setColor(String part, String? hex) => _edit((x) {
    final o = jsonMap(x['remote']);
    final m = jsonMap(o['kcolor']);
    if (hex == null) {
      m.remove(part);
    } else {
      m[part] = hex;
    }
    o['kcolor'] = m;
    x['remote'] = o;
  });

  void _setBg(String part, String mode) => _edit((x) {
    final o = jsonMap(x['remote']);
    final m = jsonMap(o['kbg']);
    if (mode == 'default') {
      m.remove(part);
    } else {
      m[part] = mode;
    }
    o['kbg'] = m;
    x['remote'] = o;
  });

  /// The icon of a key: a custom button keeps it in its own entry, the others in remote.icons.
  void _setIcon(String part, String? key) => _edit((x) {
    final o = jsonMap(x['remote']);
    final cu = remoteCustom(x);
    final i = cu.indexWhere((e) => e['id'] == part);
    if (i >= 0) {
      final e = Map<String, dynamic>.from(cu[i]);
      if (key == null) {
        e.remove('icon');
      } else {
        e['icon'] = key;
      }
      cu[i] = e;
      o['custom'] = cu;
    } else {
      final m = jsonMap(o['icons']);
      if (key == null) {
        m.remove(part);
      } else {
        m[part] = key;
      }
      o['icons'] = m;
    }
    x['remote'] = o;
  });

  String? _iconOf(Json w, String part) {
    final e = remoteCustom(w).where((x) => x['id'] == part).firstOrNull;
    if (e != null) {
      final k = (e['icon'] ?? '').toString();
      return k.isEmpty ? null : k;
    }
    return remoteKeyIcon(w, part);
  }

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
        final dialogW = (screen.width - 80).clamp(560.0, 820.0).toDouble();
        const sideW = 330.0;
        final cellW = ((dialogW - 48 - sideW - 20) / cols).clamp(56.0, 92.0).toDouble();
        final cellH = (cellW * 0.8).clamp(44.0, 74.0).toDouble();
        final th = jsonMap(d.doc['theme']);
        final pal = AppPalette.of(d.previewTheme ?? (th['mode'] ?? 'light').toString()).copyWith(
          tileOpacity: ((th['cardOpacity'] as num?) ?? 100).toDouble().clamp(0, 100) / 100,
          edgeOpacity: ((th['cardEdge'] as num?) ?? 100).toDouble().clamp(0, 100) / 100,
          radius: ((th['cardRadius'] as num?) ?? 12).toDouble().clamp(0, 32).toDouble(),
          border: ((th['cardBorder'] as num?) ?? 1).toDouble().clamp(0, 4).toDouble(),
          lift: liftOf(((th['btnRaise'] as num?) ?? 60).toDouble().clamp(0, 100)),
        );
        final hidden = <(String, String)>[
          for (final e in kRemoteElements)
            if (remoteHidden(w, e.$1)) (e.$1, e.$2),
          for (final x in remoteCustom(w))
            if (remoteHidden(w, (x['id'] ?? '').toString())) ((x['id'] ?? '').toString(), (x['label'] ?? 'Custom button').toString()),
        ];
        String nameOf(String part) {
          for (final e in kRemoteElements) {
            if (e.$1 == part) return e.$2;
          }
          for (final x in remoteCustom(w)) {
            if (x['id'] == part) return (x['label'] ?? '').toString().isEmpty ? 'Custom button' : (x['label'] ?? '').toString();
          }
          if (part == 'poweron') return 'Power on';
          if (part == 'poweroff') return 'Power off';
          return part;
        }

        if (_sel != null && _sel != 'poweron' && _sel != 'poweroff' && items.every((x) => x.id != _sel)) _sel = null;
        final dragging = _drag == null ? null : items.where((x) => x.id == _drag).firstOrNull;
        // Where the dragged key would land, and whether it can.
        int? tc, tr;
        Map<String, (int, int)>? plan;
        if (dragging != null && _moved) {
          tc = ((_pos.dx - _grab.dx) / cellW).round().clamp(0, cols - dragging.cw);
          tr = ((_pos.dy - _grab.dy) / cellH).round().clamp(0, rows - dragging.rh);
          plan = _plan(w, dragging, tc, tr);
        }

        final grid = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            final p = e.localPosition;
            final hit = items
                .where((x) => p.dx >= x.c * cellW && p.dx < (x.c + x.cw) * cellW && p.dy >= x.r * cellH && p.dy < (x.r + x.rh) * cellH)
                .firstOrNull;
            setState(() {
              _sel = hit?.id;
              _drag = hit?.id;
              _moved = false;
              _start = p;
              _pos = p;
              _grab = hit == null ? Offset.zero : p - Offset(hit.c * cellW, hit.r * cellH);
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
            final it = dragging;
            final p = plan;
            if (it != null && _moved) {
              if (p != null) {
                _apply(p);
              } else {
                toast(context, 'Not enough room there.');
              }
            }
            setState(() {
              _drag = null;
              _moved = false;
            });
          },
          onPointerCancel: (_) => setState(() {
            _drag = null;
            _moved = false;
          }),
          child: MouseRegion(
            cursor: _drag != null ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
            child: Container(
              width: cols * cellW,
              height: rows * cellH,
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
                  // The place the dragged key would take.
                  if (dragging != null && tc != null && tr != null)
                    Positioned(
                      left: tc * cellW,
                      top: tr * cellH,
                      width: dragging.cw * cellW,
                      height: dragging.rh * cellH,
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
                      child: _face(c, w, pal, it, opacity: it.id == _drag && _moved ? 0.3 : 1, selected: it.id == _sel),
                    ),
                  if (dragging != null && _moved)
                    Positioned(
                      left: _pos.dx - _grab.dx,
                      top: _pos.dy - _grab.dy,
                      width: dragging.cw * cellW,
                      height: dragging.rh * cellH,
                      child: IgnorePointer(child: _face(c, w, pal, dragging, opacity: 0.85, selected: true)),
                    ),
                ],
              ),
            ),
          ),
        );

        final sel = _sel;
        final pct = sel == null ? 100 : remoteScale(w, sel);
        final isPad = sel == 'touchpad';
        final hasIcon = sel != null && sel != 'dpad' && !isPad;
        final own = sel == null ? null : remoteKeyColor(w, sel);
        Widget title(String t) => Text(
          t,
          style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600, color: c.ink),
        );
        final side = SizedBox(
          width: sideW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  title('Columns'),
                  const SizedBox(width: 8),
                  _Step(value: cols, min: 3, max: 6, onChanged: (v) => _setSize('cols', v)),
                  const SizedBox(width: 22),
                  title('Rows'),
                  const SizedBox(width: 8),
                  _Step(value: rows, min: remoteRows(items), max: 24, onChanged: (v) => _setSize('rows', v)),
                ],
              ),
              const SizedBox(height: 14),
              if (sel == null)
                Text('Click a key to change its size, its background and its icon.', style: TextStyle(fontSize: 12.5, color: c.muted))
              else ...[
                Text(
                  nameOf(sel),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                ),
                if (!isPad) ...[
                  const SizedBox(height: 10),
                  title('Icon size'),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: pct.toDouble().clamp(40, 300).toDouble(),
                          min: 40,
                          max: 300,
                          divisions: 52,
                          onChanged: (v) => _setScale(sel, v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '$pct %',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: kUiText, color: c.muted),
                        ),
                      ),
                    ],
                  ),
                  if (pct != 100) TextButton(onPressed: () => _setScale(sel, 100), child: const Text('Usual size')),
                ],
                const SizedBox(height: 12),
                title('Background'),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Seg<String>(
                    items: const [('default', 'Default'), ('outline', 'Border only'), ('transparent', 'Transparent')],
                    value: remoteKeyBg(w, sel),
                    onChanged: (v) => _setBg(sel, v),
                  ),
                ),
                if (remoteKeyBg(w, sel) != 'transparent') ...[
                  const SizedBox(height: 10),
                  title(remoteKeyBg(w, sel) == 'outline' ? 'Border color' : 'Color'),
                  const SizedBox(height: 6),
                  ColorPicker(value: own ?? '', onChanged: (v) => _setColor(sel, v)),
                  if (own != null) TextButton(onPressed: () => _setColor(sel, null), child: const Text('Usual color')),
                ],
                if (hasIcon) ...[
                  const SizedBox(height: 14),
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
                        child: _iconOf(w, sel) != null ? iconWidget(_iconOf(w, sel), 24, c.ink) : Icon(Icons.crop_square, size: 22, color: c.muted),
                      ),
                      const SizedBox(width: 8),
                      EvoButton(
                        label: 'Change',
                        small: true,
                        onPressed: () async {
                          final k = await pickIcon(context, d: d, current: _iconOf(w, sel), scope: IconScope.widget);
                          if (k != null && k.isNotEmpty) _setIcon(sel, k);
                        },
                      ),
                      const SizedBox(width: 6),
                      EvoButton(label: 'Default', small: true, onPressed: _iconOf(w, sel) == null ? null : () => _setIcon(sel, null)),
                    ],
                  ),
                ],
              ],
              if (hidden.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Hidden keys (click to show):', style: TextStyle(fontSize: 12.5, color: c.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final h in hidden) ActionChip(label: Text(h.$2), onPressed: () => _show(h.$1))],
                ),
              ],
            ],
          ),
        );

        return Dialog(
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
                  const SizedBox(height: 6),
                  Text('Drag a key to another cell. Dropping it on a key of the same size swaps them.', style: TextStyle(fontSize: 12.5, color: c.muted)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // The On and Off keys of the top bar: they are not dragged, but they can be changed here.
                              if (remoteShowTop(w, 'PowerOn') || remoteShowTop(w, 'PowerOff'))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      for (final k in ['poweron', 'poweroff'])
                                        if (remoteShowTop(w, k == 'poweron' ? 'PowerOn' : 'PowerOff'))
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => setState(() => _sel = k),
                                            child: SizedBox(
                                              width: cellW,
                                              height: 40,
                                              child: _face(c, w, pal, RemoteItem(k, 0, 0, 1, 1), selected: _sel == k),
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              grid,
                            ],
                          ),
                          const SizedBox(width: 20),
                          side,
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
                          final o = jsonMap(x['remote']);
                          o.remove('layout');
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
