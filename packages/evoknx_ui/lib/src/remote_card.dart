import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:knx_config/knx_config.dart';

import 'look.dart';
import 'media_card.dart' show MediaHost;
import 'model.dart';
import 'tiles.dart';

/// The remote control card: a ring with the four directions and OK, a row of Back, Home and Menu, the volume, the
/// transport buttons and (when it is turned on) a touchpad. A key sends the `remote.send_command` of Home Assistant
/// with the name that the platform of the card gives it; the directions and the volume go on while the finger stays
/// down. With no [host] (the design view of the Editor) the card is only shown.
class RemoteCard extends StatefulWidget {
  const RemoteCard({super.key, required this.w, required this.pal, this.host});
  final Json w;
  final AppPalette pal;
  final MediaHost? host;

  @override
  State<RemoteCard> createState() => _RemoteCardState();
}

class _RemoteCardState extends State<RemoteCard> {
  Timer? _hold, _rep;
  String? _down;
  double _ax = 0, _ay = 0;

  Json get _r => remoteSettings(widget.w);

  @override
  void dispose() {
    _hold?.cancel();
    _rep?.cancel();
    super.dispose();
  }

  void _send(String key) {
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
    if (repeat) {
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

  bool _has(String key) => remoteCommand(widget.w, key).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal, host = widget.host;
    final r = _r;
    String? note;
    if (host != null) {
      if ((r['entity'] as String).isEmpty) {
        note = 'Choose the remote in the settings of the card.';
      } else if (!host.connected) {
        note = 'Waiting for Home Assistant…';
      }
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: raisedDecoration(
        pal,
        pal.fill(pal.tile),
        radius: BorderRadius.circular(pal.radius),
        lift: pal.cardLift,
        border: pal.border <= 0 ? Border.fromBorderSide(BorderSide.none) : Border.all(color: pal.edge, width: pal.border),
        shadow: false,
      ),
      child: note != null
          ? Center(
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fs(widget.w, 'labelSize') - 1, color: pal.muted),
              ),
            )
          : Column(
              children: [
                if (r['touchpad'] == true) Expanded(flex: 4, child: _touchpad()),
                if (r['dpad'] == true)
                  Expanded(
                    flex: 8,
                    child: LayoutBuilder(builder: (context, bc) => Center(child: _dpad(math.min(bc.maxWidth, bc.maxHeight)))),
                  ),
                if (r['nav'] == true)
                  Expanded(flex: 2, child: _row([('back', Icons.arrow_back, false), ('home', Icons.home_outlined, false), ('menu', Icons.menu, false)])),
                if (r['volume'] == true)
                  Expanded(
                    flex: 2,
                    child: _row([('voldown', Icons.volume_down, true), ('mute', Icons.volume_off_outlined, false), ('volup', Icons.volume_up, true)]),
                  ),
                if (r['transport'] == true)
                  Expanded(
                    flex: 2,
                    child: _row([('prev', Icons.skip_previous, false), ('playpause', Icons.play_arrow, false), ('next', Icons.skip_next, false)]),
                  ),
              ],
            ),
    );
  }

  Widget _row(List<(String, IconData, bool)> keys) => Row(
    children: [for (final k in keys) Expanded(child: _keyButton(k.$1, k.$2, repeat: k.$3))],
  );

  Widget _keyButton(String key, IconData icon, {bool repeat = false}) {
    final pal = widget.pal;
    final on = _has(key);
    final pressed = _down == key;
    return Listener(
      onPointerDown: on ? (_) => _press(key, repeat: repeat) : null,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: pressed ? pal.accent.withValues(alpha: 0.35) : pal.panel, borderRadius: BorderRadius.circular(pal.radius * 0.5)),
        child: Center(child: Icon(icon, size: 22, color: on ? pal.ink : pal.line)),
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

  Widget _dpad(double s) {
    final pal = widget.pal;
    return SizedBox(
      width: s,
      height: s,
      child: Listener(
        onPointerDown: (e) {
          final k = _dpadKey(e.localPosition, s);
          if (k != null && _has(k)) _press(k, repeat: k != 'ok');
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: CustomPaint(
          painter: _DpadPainter(pal, _down, {
            for (final k in const ['up', 'down', 'left', 'right', 'ok']) k: _has(k),
          }),
        ),
      ),
    );
  }

  Widget _touchpad() {
    final pal = widget.pal;
    return GestureDetector(
      onTap: _has('ok') ? () => _send('ok') : null,
      onPanStart: (_) {
        _ax = 0;
        _ay = 0;
      },
      onPanUpdate: (d) {
        _ax += d.delta.dx;
        _ay += d.delta.dy;
        if (_ax.abs() > 30 || _ay.abs() > 30) {
          final k = _ax.abs() > _ay.abs() ? (_ax > 0 ? 'right' : 'left') : (_ay > 0 ? 'down' : 'up');
          if (_has(k)) _send(k);
          _ax = 0;
          _ay = 0;
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(pal.radius * 0.6)),
        child: Center(child: Icon(Icons.touch_app_outlined, size: 28, color: pal.muted)),
      ),
    );
  }
}

class _DpadPainter extends CustomPainter {
  _DpadPainter(this.pal, this.down, this.on);
  final AppPalette pal;
  final String? down;
  final Map<String, bool> on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = pal.panel);
    // The pressed direction is a quarter of the ring.
    const starts = {'right': -math.pi / 4, 'down': math.pi / 4, 'left': 3 * math.pi / 4, 'up': -3 * math.pi / 4};
    final s = starts[down];
    if (s != null) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), s, math.pi / 2, true, Paint()..color = pal.accent.withValues(alpha: 0.35));
    }
    final inner = r * 0.34;
    canvas.drawCircle(c, inner, Paint()..color = down == 'ok' ? pal.accent.withValues(alpha: 0.5) : pal.fill(pal.tile));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = pal.line;
    canvas.drawCircle(c, r - 0.5, edge);
    canvas.drawCircle(c, inner, edge);
    void glyph(IconData icon, Offset at, bool enabled) {
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, fontSize: r * 0.3, color: enabled ? pal.ink : pal.line),
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
        style: TextStyle(fontSize: r * 0.2, fontWeight: FontWeight.w600, color: (on['ok'] ?? false) ? pal.ink : pal.line),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ok.paint(canvas, c - Offset(ok.width / 2, ok.height / 2));
  }

  @override
  bool shouldRepaint(_DpadPainter old) => old.down != down || old.pal != pal;
}
