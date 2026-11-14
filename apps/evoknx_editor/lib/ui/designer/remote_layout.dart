import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, iconWidget;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icon_picker.dart';

/// Opens the window where the keys of a remote control card are dragged to the cell they should take, and where the size
/// of the icon of each key is set.
Future<void> showRemoteLayout(BuildContext context, Designer d, String widgetId) => showDialog<void>(
  context: context,
  builder: (_) => _RemoteLayoutDialog(d: d, id: widgetId),
);

const Map<String, IconData> _icons = {
  'dpad': Icons.control_camera,
  'touchpad': Icons.touch_app_outlined,
  'back': Icons.arrow_back,
  'home': Icons.home_outlined,
  'menu': Icons.menu,
  'voldown': Icons.volume_down,
  'mute': Icons.volume_off_outlined,
  'volup': Icons.volume_up,
  'prev': Icons.skip_previous,
  'playpause': Icons.play_arrow,
  'next': Icons.skip_next,
};

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

  void _apply(Map<String, (int, int)> pos) => d.editWidget(widget.id, (x) {
    final o = jsonMap(x['remote']);
    o['layout'] = {
      for (final e in pos.entries) e.key: {'c': e.value.$1, 'r': e.value.$2},
    };
    x['remote'] = o;
  });

  void _show(String part) => d.editWidget(widget.id, (x) {
    final o = jsonMap(x['remote']);
    final h = jsonMap(o['hide']);
    h[part] = false;
    o['hide'] = h;
    x['remote'] = o;
  });

  void _setScale(String part, int pct) => d.editWidget(widget.id, (x) {
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

  void _setBg(String part, String mode) => d.editWidget(widget.id, (x) {
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
  void _setIcon(String part, String? key) => d.editWidget(widget.id, (x) {
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
        final rows = remoteRows(items) + 2;
        final dialogW = (screen.width - 80).clamp(520.0, 860.0).toDouble();
        const sideW = 250.0;
        final cell = ((dialogW - 48 - sideW - 20) / cols).clamp(56.0, 112.0).toDouble();
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
          return part;
        }

        if (_sel != null && items.every((x) => x.id != _sel)) _sel = null;
        final dragging = _drag == null ? null : items.where((x) => x.id == _drag).firstOrNull;
        // Where the dragged key would land, and whether it can.
        int? tc, tr;
        Map<String, (int, int)>? plan;
        if (dragging != null && _moved) {
          tc = ((_pos.dx - _grab.dx) / cell).round().clamp(0, cols - dragging.cw);
          tr = ((_pos.dy - _grab.dy) / cell).round().clamp(0, rows - dragging.rh);
          plan = _plan(w, dragging, tc, tr);
        }

        final grid = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            final p = e.localPosition;
            final hit = items.where((x) => p.dx >= x.c * cell && p.dx < (x.c + x.cw) * cell && p.dy >= x.r * cell && p.dy < (x.r + x.rh) * cell).firstOrNull;
            setState(() {
              _sel = hit?.id;
              _drag = hit?.id;
              _moved = false;
              _start = p;
              _pos = p;
              _grab = hit == null ? Offset.zero : p - Offset(hit.c * cell, hit.r * cell);
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
              width: cols * cell,
              height: rows * cell,
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
                        left: gx * cell,
                        top: gy * cell,
                        width: cell,
                        height: cell,
                        child: DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: c.line.withAlpha(120), width: 0.5)),
                        ),
                      ),
                  // The place the dragged key would take.
                  if (dragging != null && tc != null && tr != null)
                    Positioned(
                      left: tc * cell,
                      top: tr * cell,
                      width: dragging.cw * cell,
                      height: dragging.rh * cell,
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
                      left: it.c * cell,
                      top: it.r * cell,
                      width: it.cw * cell,
                      height: it.rh * cell,
                      child: _face(c, w, it, cell, nameOf(it.id), opacity: it.id == _drag && _moved ? 0.3 : 1, selected: it.id == _sel),
                    ),
                  if (dragging != null && _moved)
                    Positioned(
                      left: _pos.dx - _grab.dx,
                      top: _pos.dy - _grab.dy,
                      width: dragging.cw * cell,
                      height: dragging.rh * cell,
                      child: IgnorePointer(child: _face(c, w, dragging, cell, nameOf(dragging.id), opacity: 0.85, selected: true)),
                    ),
                ],
              ),
            ),
          ),
        );

        final sel = _sel;
        final pct = sel == null ? 100 : remoteScale(w, sel);
        final side = SizedBox(
          width: sideW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Icon size',
                style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600, color: c.ink),
              ),
              const SizedBox(height: 6),
              if (sel == null)
                Text('Click a key to change the size of its icon.', style: TextStyle(fontSize: 12.5, color: c.muted))
              else ...[
                Text(
                  nameOf(sel),
                  style: TextStyle(fontSize: kUiText, color: c.ink),
                ),
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
                const SizedBox(height: 14),
                Text(
                  'Background',
                  style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: 6),
                Seg<String>(
                  items: const [('default', 'Default'), ('outline', 'Border only'), ('transparent', 'Transparent')],
                  value: remoteKeyBg(w, sel),
                  onChanged: (v) => _setBg(sel, v),
                ),
                if (sel != 'dpad') ...[
                  const SizedBox(height: 14),
                  Text(
                    'Icon or picture',
                    style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600, color: c.ink),
                  ),
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
                        child: _iconOf(w, sel) != null
                            ? iconWidget(_iconOf(w, sel), 24, c.ink)
                            : Icon(_icons[sel] ?? Icons.crop_square, size: 22, color: c.muted),
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
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [grid, const SizedBox(width: 20), side]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => d.editWidget(widget.id, (x) {
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

  Widget _face(EvoColors c, Json w, RemoteItem it, double cell, String name, {double opacity = 1, bool selected = false}) {
    final z = remoteScale(w, it.id) / 100;
    final base = it.cw > 1 ? cell * 0.5 : cell * 0.36;
    final custom = remoteCustom(w).where((x) => x['id'] == it.id).firstOrNull;
    final mode = remoteKeyBg(w, it.id);
    final over = _iconOf(w, it.id);
    return Opacity(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: mode == 'default' ? c.accentSoft : null,
          borderRadius: BorderRadius.circular(8),
          border: mode == 'transparent' && !selected ? Border.all(color: c.line) : Border.all(color: selected ? c.ink : c.accent, width: selected ? 2 : 1),
        ),
        child: ClipRect(
          child: Center(
            child: over != null
                ? iconWidget(over, base * z, c.ink)
                : _icons[it.id] != null
                ? Icon(_icons[it.id], size: base * z, color: c.ink)
                : (custom != null && (custom['icon'] ?? '').toString().isNotEmpty
                      ? Icon(Icons.radio_button_unchecked, size: base * z, color: c.ink)
                      : Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12 * z, color: c.ink),
                        )),
          ),
        ),
      ),
    );
  }
}
