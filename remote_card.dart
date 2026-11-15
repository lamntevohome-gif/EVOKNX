import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:knx_config/knx_config.dart';

import 'icons.dart';
import 'look.dart';
import 'media_card.dart' show MediaHost;
import 'model.dart';
import 'tiles.dart';

/// The remote control card: a top bar with the title and the power on and off keys, and under it the parts the card shows
/// (a ring with the four directions and OK, single keys, a touchpad, custom buttons), each in its cell of a grid that
/// the Editor lays out. The source is Home Assistant (a key sends the `remote.send_command` with the name that the
/// platform of the card gives it) or KNX (a key sends a value on its address, or on the one address of all the keys).
/// The directions and the volume go on while the finger stays down. With no [host] and no [act] (the design view of
/// the Editor) the card is only shown.
/// The look of the button of a key: filled (with its own color if it has one), only a border, or nothing.
BoxDecoration remoteKeyDeco(Json w, AppPalette pal, String id, {bool pressed = false, Color? pressedColor, required double radius}) {
  final mode = remoteKeyBg(w, id);
  final own = hexColor(remoteKeyColor(w, id));
  return BoxDecoration(
    color: pressed ? (pressedColor ?? pal.accent).withValues(alpha: 0.35) : (mode == 'default' ? (own ?? pal.panel) : Colors.transparent),
    borderRadius: BorderRadius.circular(remoteKeyRadius(w, id) ?? radius),
    border: mode == 'outline' ? Border.all(color: own ?? (pal.edge == Colors.transparent ? pal.line : pal.edge), width: math.max(1.0, pal.border)) : null,
  );
}

/// An icon or a label inside a key: it shrinks when it is bigger than the key, so it never leaves its cell.
Widget _fitIn(Widget c) => Padding(
  padding: const EdgeInsets.all(3),
  child: FittedBox(fit: BoxFit.scaleDown, child: c),
);

const kRemoteKeyIcons = <String, IconData>{
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

/// One key drawn as on the card (the ring, the touchpad, a key or a custom button), without any action: the window that
/// arranges the keys shows the keys with it.
class RemoteKeyFace extends StatelessWidget {
  const RemoteKeyFace({super.key, required this.w, required this.pal, required this.id});
  final Json w;
  final AppPalette pal;
  final String id;

  @override
  Widget build(BuildContext context) {
    final f = remoteBgSize(w, id) / 100;
    final child = _inner(context);
    return f >= 1 || id == 'dpad'
        ? child
        : Center(
            child: FractionallySizedBox(widthFactor: f, heightFactor: f, child: child),
          );
  }

  Widget _inner(BuildContext context) {
    final p = cardPalette(w, pal).$1;
    final z = remoteScale(w, id) / 100;
    if (id == 'dpad') {
      return LayoutBuilder(
        builder: (context, bc) {
          final s = math.max(20.0, (math.min(bc.maxWidth, bc.maxHeight) - 6) * remoteBgSize(w, 'dpad') / 100);
          return Center(
            child: SizedBox(
              width: s,
              height: s,
              child: CustomPaint(
                painter: _DpadPainter(p, null, z, remoteKeyBg(w, 'dpad'), hexColor(remoteKeyColor(w, 'dpad')), const {
                  'up': true,
                  'down': true,
                  'left': true,
                  'right': true,
                  'ok': true,
                }),
              ),
            ),
          );
        },
      );
    }
    if (id == 'poweron' || id == 'poweroff') {
      return Container(
        margin: const EdgeInsets.all(3),
        decoration: remoteKeyDeco(w, p, id, radius: p.radius * 0.5),
        child: Center(child: _fitIn(_powerFace(w, p, id, z, true, id == 'poweron' ? p.accent : p.muted))),
      );
    }
    if (id == 'touchpad') {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: remoteKeyDeco(w, p, id, radius: p.radius * 0.6),
        child: Center(
          child: _fitIn(
            remoteKeyIcon(w, id) != null ? iconWidget(remoteKeyIcon(w, id), 28 * z, p.muted) : Icon(Icons.touch_app_outlined, size: 28 * z, color: p.muted),
          ),
        ),
      );
    }
    final custom = remoteCustom(w).where((c) => c['id'] == id).firstOrNull;
    final Widget child;
    if (custom != null) {
      final icon = (custom['icon'] ?? '').toString();
      final label = (custom['label'] ?? '').toString().trim();
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon.isNotEmpty) iconWidget(icon, 22 * z, p.ink),
          if (label.isNotEmpty)
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fs(w, 'labelSize') - 3, color: p.ink),
            ),
          if (icon.isEmpty && label.isEmpty) Icon(Icons.touch_app_outlined, size: 22 * z, color: p.ink),
        ],
      );
    } else {
      child = remoteKeyIcon(w, id) != null
          ? iconWidget(remoteKeyIcon(w, id), 22 * z, p.ink)
          : Icon(kRemoteKeyIcons[id] ?? Icons.circle_outlined, size: 22 * z, color: p.ink);
    }
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: remoteKeyDeco(w, p, id, radius: p.radius * 0.5),
      child: Center(child: _fitIn(child)),
    );
  }
}

/// The default icon of a key as the card draws it (for the window that arranges the keys).
Widget remoteDefaultIconWidget(Json w, String id, double size, Color color) {
  if (id == 'poweron' || id == 'poweroff') return iconWidget(id == 'poweron' ? 'mdi:power' : 'mdi:power-off', size, color);
  if (id == 'dpad') return Icon(Icons.open_with, size: size, color: color);
  if (id == 'touchpad') return Icon(Icons.touch_app_outlined, size: size, color: color);
  final custom = remoteCustom(w).where((c) => c['id'] == id).firstOrNull;
  if (custom != null) return iconWidget((custom['icon'] ?? '').toString().isEmpty ? 'mdi:gesture-tap-button' : custom['icon'].toString(), size, color);
  return Icon(kRemoteKeyIcons[id] ?? Icons.circle_outlined, size: size, color: color);
}

/// The inside of an On or Off key: only the sign (power-on / power-off), or the icon chosen for it.
Widget _powerFace(Json w, AppPalette pal, String key, double z, bool on, Color color) =>
    iconWidget(remoteKeyIcon(w, key) ?? (key == 'poweron' ? 'mdi:power' : 'mdi:power-off'), 24 * z, on ? color : pal.line);

class RemoteCard extends StatefulWidget {
  const RemoteCard({super.key, required this.w, required this.pal, this.host, this.act, this.simulate = false});
  final Json w;
  final AppPalette pal;
  final MediaHost? host;

  /// The Editor's test mode without Home Assistant: a key only reports (`act('key', keyId)`) what it would send.
  final bool simulate;

  /// With the source KNX: what a key does (`act('key', keyId)`). Null = the card only shows.
  final void Function(String action, [Object? arg])? act;

  @override
  State<RemoteCard> createState() => _RemoteCardState();
}

class _RemoteCardState extends State<RemoteCard> {
  Timer? _hold, _rep;
  String? _down;
  double _ax = 0, _ay = 0;

  /// The palette of the card: its own background (style) changes the colors.
  AppPalette get _pal => cardPalette(widget.w, widget.pal).$1;
  bool get _noBorder => cardPalette(widget.w, widget.pal).$2;

  Json get _r => remoteSettings(widget.w);
  bool get _knx => remoteIsKnx(widget.w);

  @override
  void dispose() {
    _hold?.cancel();
    _rep?.cancel();
    super.dispose();
  }

  bool get _sim => widget.simulate && !_knx && widget.host == null;

  void _send(String key) {
    if (_sim) {
      widget.act?.call('key', key);
      return;
    }
    if (_knx) {
      if (widget.act == null) return;
      HapticFeedback.selectionClick();
      widget.act!('key', key);
      return;
    }
    final c = remoteCall(widget.w, key);
    final host = widget.host;
    if (host == null || c == null) return;
    HapticFeedback.selectionClick();
    host.call(c.service, c.entity, c.data).then((err) {
      if (err != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(err)));
    });
  }

  void _press(String key, {bool repeat = false}) {
    _release();
    setState(() => _down = key);
    _send(key);
    if (repeat && !_sim) {
      final ms = ((_r['repeatMs'] as int).clamp(60, 1000)).toInt();
      _hold = Timer(const Duration(milliseconds: 420), () {
        _rep = Timer.periodic(Duration(milliseconds: ms), (_) => _send(key));
      });
    }
  }

  void _release() {
    _hold?.cancel();
    _rep?.cancel();
    _hold = null;
    _rep = null;
    if (_down != null && mounted) setState(() => _down = null);
  }

  BoxDecoration _deco(String id, bool pressed, Color pressedColor, double radius) =>
      remoteKeyDeco(widget.w, _pal, id, pressed: pressed, pressedColor: pressedColor, radius: radius);

  /// Whether the key can send something: it has a name for the remote (Home Assistant) or an address and a value (KNX).
  bool _has(String key) {
    final w = widget.w;
    if (_sim) return true;
    if (_knx) {
      final sd = remoteKnxSend(w, key);
      return sd != null && jsonMap(w['bind'])[sd.slot] != null;
    }
    if (key == 'poweron' || key == 'poweroff') return (_r['entity'] as String).isNotEmpty;
    return remoteCommand(w, key).isNotEmpty;
  }

  /// Whether a key of the card works now: not in the design view.
  bool get _live => _sim || (_knx ? widget.act != null : widget.host != null);

  static const _icons = kRemoteKeyIcons;

  @override
  Widget build(BuildContext context) {
    final pal = _pal, host = widget.host, w = widget.w;
    final r = _r;
    String? note;
    if (!_knx && host != null) {
      if ((r['entity'] as String).isEmpty) {
        note = 'Choose the remote in the settings of the card.';
      } else if (!host.connected) {
        note = 'Waiting for Home Assistant…';
      }
    }
    final title = (w['label'] ?? '').toString().trim();
    final showTitle = remoteShowTop(w, 'Title') && title.isNotEmpty && w['showLabel'] != false;
    final top = showTitle;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: raisedDecoration(
        pal,
        pal.fill(pal.tile),
        radius: BorderRadius.circular(pal.radius),
        lift: pal.cardLift,
        border: pal.border <= 0 || _noBorder ? Border.fromBorderSide(BorderSide.none) : Border.all(color: pal.edge, width: pal.border),
        shadow: false,
      ),
      child: note != null
          ? Center(
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fs(w, 'labelSize') - 1, color: pal.muted),
              ),
            )
          : Column(
              children: [
                if (top)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: switch (remoteTitleAlign(w)) {
                              'center' => TextAlign.center,
                              'right' => TextAlign.right,
                              _ => TextAlign.left,
                            },
                            style: TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w600, color: pal.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: LayoutBuilder(builder: (context, bc) => _grid(bc))),
              ],
            ),
    );
  }

  /// The On and Off keys: a key of the grid with the name of the key and the power sign.
  Widget _powerKey(String key, double z) {
    final pal = _pal;
    final isOn = key == 'poweron';
    final color = isOn ? pal.accent : pal.muted;
    final on = _has(key) || !_live;
    final pressed = _down == key;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _live && _has(key) ? (_) => _press(key) : null,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: PressEffect(
        enabled: _live && _has(key) || _sim,
        scale: 0.92,
        radius: _pal.radius * 0.5,
        dark: _pal.tile.computeLuminance() < 0.35,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: remoteKeyDeco(widget.w, pal, key, pressed: pressed, pressedColor: color, radius: pal.radius * 0.5),
          child: Center(child: _fitIn(_powerFace(widget.w, pal, key, z, on, color))),
        ),
      ),
    );
  }

  /// The parts, each in its cell.
  Widget _grid(BoxConstraints bc) {
    final w = widget.w;
    final items = remoteItems(w);
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Nothing to show: turn on some keys in the settings.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _pal.muted),
        ),
      );
    }
    final cols = remoteCols(w), rows = remoteRowCount(w, items);
    final cw = bc.maxWidth / cols;
    // A cell is not much higher than wide, so a tall card does not make huge keys.
    final ch = math.min(bc.maxHeight.isFinite ? bc.maxHeight / rows : cw, cw * 1.1);
    return Center(
      child: SizedBox(
        width: bc.maxWidth,
        height: ch * rows,
        child: Stack(
          children: [for (final i in items) Positioned(left: i.c * cw, top: i.r * ch, width: i.cw * cw, height: i.rh * ch, child: _part(i))],
        ),
      ),
    );
  }

  Widget _part(RemoteItem i) {
    final f = remoteBgSize(widget.w, i.id) / 100;
    final child = _partInner(i);
    return f >= 1 || i.id == 'dpad'
        ? child
        : Center(
            child: FractionallySizedBox(widthFactor: f, heightFactor: f, child: child),
          );
  }

  Widget _partInner(RemoteItem i) {
    final z = remoteScale(widget.w, i.id) / 100;
    if (i.id == 'dpad') {
      final f = remoteBgSize(widget.w, 'dpad') / 100;
      return LayoutBuilder(builder: (context, bc) => Center(child: _dpad(math.max(20.0, (math.min(bc.maxWidth, bc.maxHeight) - 6) * f), z)));
    }
    if (i.id == 'poweron' || i.id == 'poweroff') return _powerKey(i.id, z);
    if (i.id == 'touchpad') return _touchpad(z);
    final custom = remoteCustom(widget.w).where((c) => c['id'] == i.id).firstOrNull;
    if (custom != null) return _customButton(custom, z);
    return _keyButton(i.id, _icons[i.id] ?? Icons.circle_outlined, z, repeat: i.id == 'voldown' || i.id == 'volup');
  }

  Widget _customButton(Json c, double z) {
    final pal = _pal;
    final key = (c['id'] ?? '').toString();
    final on = _has(key);
    final pressed = _down == key;
    final icon = (c['icon'] ?? '').toString();
    final label = (c['label'] ?? '').toString().trim();
    final color = on || !_live ? pal.ink : pal.line;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _live && on ? (_) => _press(key) : null,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: PressEffect(
        enabled: _live && _has(key) || _sim,
        scale: 0.92,
        radius: _pal.radius * 0.5,
        dark: _pal.tile.computeLuminance() < 0.35,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: _deco(key, pressed, pal.accent, pal.radius * 0.5),
          child: Center(
            child: _fitIn(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon.isNotEmpty) iconWidget(icon, 22 * z, color),
                  if (label.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: icon.isNotEmpty ? 1 : 0),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: fs(widget.w, 'labelSize') - 3, color: color),
                      ),
                    ),
                  if (icon.isEmpty && label.isEmpty) Icon(Icons.touch_app_outlined, size: 22 * z, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyButton(String key, IconData icon, double z, {bool repeat = false}) {
    final pal = _pal;
    final on = _has(key);
    final pressed = _down == key;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _live && on ? (_) => _press(key, repeat: repeat) : null,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: PressEffect(
        enabled: _live && _has(key) || _sim,
        scale: 0.92,
        radius: _pal.radius * 0.5,
        dark: _pal.tile.computeLuminance() < 0.35,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: _deco(key, pressed, pal.accent, pal.radius * 0.5),
          child: Center(
            child: _fitIn(
              remoteKeyIcon(widget.w, key) != null
                  ? iconWidget(remoteKeyIcon(widget.w, key), 22 * z, on || !_live ? pal.ink : pal.line)
                  : Icon(icon, size: 22 * z, color: on || !_live ? pal.ink : pal.line),
            ),
          ),
        ),
      ),
    );
  }

  String? _dpadKey(Offset p, double s) {
    final c = Offset(s / 2, s / 2), d = p - c;
    final dist = d.distance;
    if (dist > s / 2) return null;
    if (dist < s / 2 * 0.34) return 'ok';
    final a = math.atan2(d.dy, d.dx);
    if (a.abs() <= math.pi / 4) return 'right';
    if (a >= math.pi / 4 && a < 3 * math.pi / 4) return 'down';
    if (a.abs() >= 3 * math.pi / 4) return 'left';
    return 'up';
  }

  Widget _dpad(double s, double z) {
    final pal = _pal;
    return SizedBox(
      width: s,
      height: s,
      child: Listener(
        onPointerDown: (e) {
          final k = _dpadKey(e.localPosition, s);
          if (k != null && _live && _has(k)) _press(k, repeat: k != 'ok');
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: CustomPaint(
          painter: _DpadPainter(pal, _down, z, remoteKeyBg(widget.w, 'dpad'), hexColor(remoteKeyColor(widget.w, 'dpad')), {
            for (final k in const ['up', 'down', 'left', 'right', 'ok']) k: _has(k),
          }),
        ),
      ),
    );
  }

  Widget _touchpad(double z) {
    final pal = _pal;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _live && _has('ok') ? () => _send('ok') : null,
      onPanStart: (_) {
        _ax = 0;
        _ay = 0;
      },
      onPanUpdate: (d) {
        _ax += d.delta.dx;
        _ay += d.delta.dy;
        if (_ax.abs() > 24 || _ay.abs() > 24) {
          final k = _ax.abs() > _ay.abs() ? (_ax > 0 ? 'right' : 'left') : (_ay > 0 ? 'down' : 'up');
          if (_live && _has(k)) _send(k);
          _ax = 0;
          _ay = 0;
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: _deco('touchpad', false, pal.accent, pal.radius * 0.6),
        child: Center(
          child: _fitIn(
            remoteKeyIcon(widget.w, 'touchpad') != null
                ? iconWidget(remoteKeyIcon(widget.w, 'touchpad'), 28 * z, pal.muted)
                : Icon(Icons.touch_app_outlined, size: 28 * z, color: pal.muted),
          ),
        ),
      ),
    );
  }
}

class _DpadPainter extends CustomPainter {
  _DpadPainter(this.pal, this.down, this.scale, this.mode, this.fill, this.on);
  final AppPalette pal;
  final String? down;
  final double scale;

  /// 'default' (filled), 'outline' (only the lines) or 'transparent' (no ring, only the signs).
  final String mode;
  final Color? fill;
  final Map<String, bool> on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    if (mode == 'default') canvas.drawCircle(c, r, Paint()..color = fill ?? pal.panel);
    // The pressed direction is a quarter of the ring.
    const starts = {'right': -math.pi / 4, 'down': math.pi / 4, 'left': 3 * math.pi / 4, 'up': -3 * math.pi / 4};
    final s = starts[down];
    if (s != null) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), s, math.pi / 2, true, Paint()..color = pal.accent.withValues(alpha: 0.35));
    }
    final inner = r * 0.34;
    if (mode == 'default' || down == 'ok') canvas.drawCircle(c, inner, Paint()..color = down == 'ok' ? pal.accent.withValues(alpha: 0.5) : pal.fill(pal.tile));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = pal.line;
    if (mode != 'transparent') {
      canvas.drawCircle(c, r - 0.5, edge);
      canvas.drawCircle(c, inner, edge);
    }
    void glyph(IconData icon, Offset at, bool enabled) {
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, fontSize: r * 0.3 * math.min(scale, 1.6), color: enabled ? pal.ink : pal.line),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    final d = r * 0.67;
    glyph(Icons.keyboard_arrow_up, c + Offset(0, -d), on['up'] ?? false);
    glyph(Icons.keyboard_arrow_down, c + Offset(0, d), on['down'] ?? false);
    glyph(Icons.keyboard_arrow_left, c + Offset(-d, 0), on['left'] ?? false);
    glyph(Icons.keyboard_arrow_right, c + Offset(d, 0), on['right'] ?? false);
    final ok = TextPainter(
      text: TextSpan(
        text: 'OK',
        style: TextStyle(fontSize: r * 0.2 * math.min(scale, 2.0), fontWeight: FontWeight.w600, color: (on['ok'] ?? false) ? pal.ink : pal.line),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ok.paint(canvas, c - Offset(ok.width / 2, ok.height / 2));
  }

  @override
  bool shouldRepaint(_DpadPainter old) => old.down != down || old.pal != pal || old.scale != scale || old.mode != mode || old.fill != fill;
}
