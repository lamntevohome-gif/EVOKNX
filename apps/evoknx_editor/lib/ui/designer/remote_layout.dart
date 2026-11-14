import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';

/// Opens the window where the keys of a remote control card are dragged to the cell they should take.
Future<void> showRemoteLayout(BuildContext context, Designer d, String widgetId) => showDialog<void>(
  context: context,
  builder: (_) => _RemoteLayoutDialog(d: d, id: widgetId),
);

const double _cell = 64;

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

class _RemoteLayoutDialog extends StatelessWidget {
  _RemoteLayoutDialog({required this.d, required this.id});
  final Designer d;
  final String id;
  final GlobalKey _gridKey = GlobalKey();

  Json? _card() => allWidgets(d.doc).where((x) => x['id'] == id).firstOrNull;

  /// Puts [item] on the cell ([c], [r]): on a free place it moves there, on one other part of the same size it swaps with it.
  void _move(BuildContext context, Json w, RemoteItem item, int c, int r) {
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
      toast(context, 'Not enough room there.');
      return;
    }
    d.editWidget(id, (x) {
      final o = jsonMap(x['remote']);
      o['layout'] = {
        for (final e in pos.entries) e.key: {'c': e.value.$1, 'r': e.value.$2},
      };
      x['remote'] = o;
    });
  }

  void _show(String part) => d.editWidget(id, (x) {
    final o = jsonMap(x['remote']);
    final h = jsonMap(o['hide']);
    h[part] = false;
    o['hide'] = h;
    x['remote'] = o;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final w = _card();
        if (w == null) return const SizedBox.shrink();
        final items = remoteItems(w);
        final cols = remoteCols(w);
        final rows = remoteRows(items) + 2;
        final hidden = <(String, String)>[
          for (final e in kRemoteElements)
            if (remoteHidden(w, e.$1)) (e.$1, e.$2),
          for (final x in remoteCustom(w))
            if (remoteHidden(w, (x['id'] ?? '').toString())) ((x['id'] ?? '').toString(), (x['label'] ?? 'Custom button').toString()),
        ];
        String nameOf(String part) {
          for (final x in remoteCustom(w)) {
            if (x['id'] == part) return (x['label'] ?? '').toString();
          }
          return '';
        }

        return AlertDialog(
          title: const Text('Arrange the keys'),
          content: SizedBox(
            width: cols * _cell + 8,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Drag a key to another cell. Dropping it on a key of the same size swaps them.', style: TextStyle(fontSize: 12.5, color: c.muted)),
                  const SizedBox(height: 10),
                  DragTarget<String>(
                    onWillAcceptWithDetails: (_) => true,
                    onAcceptWithDetails: (details) {
                      final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
                      final item = items.where((x) => x.id == details.data).firstOrNull;
                      if (box == null || item == null) return;
                      final p = box.globalToLocal(details.offset);
                      _move(context, w, item, (p.dx / _cell).round(), (p.dy / _cell).round());
                    },
                    builder: (context, _, __) => Container(
                      key: _gridKey,
                      width: cols * _cell,
                      height: rows * _cell,
                      decoration: BoxDecoration(
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Stack(
                        children: [
                          for (var gx = 0; gx < cols; gx++)
                            for (var gy = 0; gy < rows; gy++)
                              Positioned(
                                left: gx * _cell,
                                top: gy * _cell,
                                width: _cell,
                                height: _cell,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(border: Border.all(color: c.line.withAlpha(120), width: 0.5)),
                                ),
                              ),
                          for (final it in items)
                            Positioned(
                              left: it.c * _cell,
                              top: it.r * _cell,
                              width: it.cw * _cell,
                              height: it.rh * _cell,
                              child: _tile(context, c, it, nameOf(it.id)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (hidden.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Hidden keys (click to show):', style: TextStyle(fontSize: 12.5, color: c.muted)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final h in hidden) ActionChip(label: Text(h.$2), onPressed: () => _show(h.$1))],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => d.editWidget(id, (x) {
                final o = jsonMap(x['remote']);
                o.remove('layout');
                x['remote'] = o;
              }),
              child: const Text('Reset the layout'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, EvoColors c, RemoteItem it, String custom) {
    Widget face({double opacity = 1}) => Opacity(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.accent),
        ),
        child: Center(
          child: _icons[it.id] != null
              ? Icon(_icons[it.id], size: it.cw > 1 ? 40 : 24, color: c.ink)
              : Text(
                  custom.isEmpty ? 'Custom' : custom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.ink),
                ),
        ),
      ),
    );
    return Draggable<String>(
      data: it.id,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: it.cw * _cell, height: it.rh * _cell, child: face(opacity: 0.85)),
      ),
      childWhenDragging: face(opacity: 0.25),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: face()),
    );
  }
}
