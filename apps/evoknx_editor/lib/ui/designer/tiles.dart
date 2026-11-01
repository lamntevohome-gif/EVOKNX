import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import 'icons.dart';
import 'model.dart';

/// Colours of the simulated app screen (light/dark like the real app).
class AppPalette {
  final Color screen, tile, tileEdge, panel, ink, muted, line, lineStrong, accent, accentSoft, led, ledSoft, danger;

  /// Text colours used directly on the screen background (title, page name…),
  /// which may differ when a custom background colour or image is used.
  final Color? onScreenInk, onScreenMuted;
  Color get sInk => onScreenInk ?? ink;
  Color get sMuted => onScreenMuted ?? muted;

  const AppPalette({
    this.onScreenInk,
    this.onScreenMuted,
    required this.screen,
    required this.tile,
    required this.tileEdge,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentSoft,
    required this.led,
    required this.ledSoft,
    required this.danger,
  });

  AppPalette copyWith({
    Color? tile,
    Color? tileEdge,
    Color? panel,
    Color? ink,
    Color? muted,
    Color? line,
    Color? lineStrong,
    Color? onScreenInk,
    Color? onScreenMuted,
  }) => AppPalette(
    screen: screen,
    tile: tile ?? this.tile,
    tileEdge: tileEdge ?? this.tileEdge,
    panel: panel ?? this.panel,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    lineStrong: lineStrong ?? this.lineStrong,
    accent: accent,
    accentSoft: accentSoft,
    led: led,
    ledSoft: ledSoft,
    danger: danger,
    onScreenInk: onScreenInk ?? this.onScreenInk,
    onScreenMuted: onScreenMuted ?? this.onScreenMuted,
  );

  /// Palette for a card with a custom background: readable text on dark colours.
  AppPalette forCard(Color bg) {
    if (bg.computeLuminance() < 0.35) {
      return copyWith(
        tile: bg,
        ink: Colors.white,
        muted: Colors.white.withValues(alpha: 0.72),
        line: Colors.white.withValues(alpha: 0.22),
        lineStrong: Colors.white.withValues(alpha: 0.38),
        tileEdge: Colors.white.withValues(alpha: 0.18),
        panel: Color.alphaBlend(Colors.white.withValues(alpha: 0.12), bg),
      );
    }
    return copyWith(
      tile: bg,
      ink: const Color(0xFF1B2320),
      muted: const Color(0xFF5B6662),
      tileEdge: Color.alphaBlend(Colors.black.withValues(alpha: 0.10), bg),
      panel: Color.alphaBlend(Colors.white.withValues(alpha: 0.55), bg),
    );
  }

  /// App themes: Sáng, Tối, and two neutral themes (Xám than, Kem).
  /// Older projects using "system" fall back to Sáng.
  static AppPalette of(String? mode) => switch (mode) {
    'dark' => dark,
    'graphite' => graphite,
    'sand' => sand,
    _ => light,
  };

  /// Neutral dark grey (graphite), softer than full dark.
  static const graphite = AppPalette(
    screen: Color(0xFF2B2F33),
    tile: Color(0xFF383D42),
    tileEdge: Color(0xFF464C52),
    panel: Color(0xFF32373C),
    ink: Color(0xFFF1F3F4),
    muted: Color(0xFFA9B0B6),
    line: Color(0xFF444A50),
    lineStrong: Color(0xFF5A6168),
    accent: Color(0xFF4DB38A),
    accentSoft: Color(0xFF23392F),
    led: Color(0xFFF2AA45),
    ledSoft: Color(0xFF3E3220),
    danger: Color(0xFFEE7B66),
  );

  /// Neutral warm light (sand / ivory).
  static const sand = AppPalette(
    screen: Color(0xFFE9E4DC),
    tile: Color(0xFFFBF9F6),
    tileEdge: Color(0xFFDDD6CB),
    panel: Color(0xFFFFFDFA),
    ink: Color(0xFF2A2622),
    muted: Color(0xFF7A7067),
    line: Color(0xFFE4DDD2),
    lineStrong: Color(0xFFCFC6B8),
    accent: Color(0xFF2F7D5B),
    accentSoft: Color(0xFFE3EFE6),
    led: Color(0xFFE08E2B),
    ledSoft: Color(0xFFF8EBD7),
    danger: Color(0xFFC2412D),
  );

  static const light = AppPalette(
    screen: Color(0xFFD8DBDF),
    tile: Color(0xFFFFFFFF),
    tileEdge: Color(0xFFCDD1D6),
    panel: Color(0xFFFFFFFF),
    ink: Color(0xFF1B2320),
    muted: Color(0xFF66716C),
    line: Color(0xFFDEE3E0),
    lineStrong: Color(0xFFC3CBC7),
    accent: Color(0xFF1E7F57),
    accentSoft: Color(0xFFE2F1E9),
    led: Color(0xFFEE9B2A),
    ledSoft: Color(0xFFFDF1DC),
    danger: Color(0xFFC2412D),
  );

  static const dark = AppPalette(
    screen: Color(0xFF191E20),
    tile: Color(0xFF242A2C),
    tileEdge: Color(0xFF323A3C),
    panel: Color(0xFF1C2123),
    ink: Color(0xFFE7ECE9),
    muted: Color(0xFF9AA59F),
    line: Color(0xFF2E3537),
    lineStrong: Color(0xFF434C4F),
    accent: Color(0xFF3DAA7A),
    accentSoft: Color(0xFF1D3328),
    led: Color(0xFFF2AA45),
    ledSoft: Color(0xFF3A2D17),
    danger: Color(0xFFE7735E),
  );
}

Color? hexColor(Object? s) {
  final t = (s ?? '').toString().replaceAll('#', '');
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String fmtNum(num v, int d) => v.toStringAsFixed(d).replaceAll('.', ',');

/// Renders one component tile (except grid frames, drawn by the canvas).
class TileView extends StatelessWidget {
  const TileView({
    super.key,
    required this.w,
    required this.pal,
    required this.gas,
    this.sim = const {},
    this.selected = false,
    this.flagged = false,
    this.act,
  });
  final Json w;
  final AppPalette pal;
  final List<Json> gas;
  final Map<String, dynamic> sim;
  final bool selected, flagged;

  /// Test mode: called for control actions (up, down, stop, tune, plus, minus, off, mode).
  final void Function(String action, [Object? arg])? act;

  Widget _tap(String action, Widget child, [Object? arg]) => act == null
      ? child
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => act!(action, arg),
          child: MouseRegion(cursor: SystemMouseCursors.click, child: child),
        );

  @override
  Widget build(BuildContext context) {
    final type = w['type'] as String? ?? '';
    final style = jsonMap(w['style']);
    final cardBg = hexColor(style['bg']);
    if (cardBg != null && pal.tile != cardBg) {
      return TileView(w: w, pal: pal.forCard(cardBg), gas: gas, sim: sim, selected: selected, flagged: flagged, act: act);
    }
    final on = type == 'switch' ? sim['on'] == true : (type == 'dimmer' ? ((sim['val'] as num?) ?? 0) > 0 : false);
    final rgb = type == 'dimmer' ? hexColor(sim['rgb']) : null;
    final colorOn = rgb ?? hexColor(style['colorOn']) ?? pal.led;
    final colorOff = hexColor(style['colorOff']) ?? pal.muted;
    final bg = on ? Color.alphaBlend(colorOn.withValues(alpha: 0.16), pal.tile) : pal.tile;
    return Container(
      decoration: BoxDecoration(
        color: type == 'webview' ? pal.tile : bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? colorOn.withValues(alpha: 0.45) : pal.tileEdge),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      foregroundDecoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: pal.accent, width: 2),
            )
          : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: _content(type, on, colorOn, colorOff)),
            if (flagged) Positioned(right: -2, bottom: -2, child: Icon(Icons.warning_amber_rounded, size: 15, color: pal.danger)),
          ],
        ),
      ),
    );
  }

  Widget _label() => Text(
    (w['label'] ?? '').toString(),
    maxLines: w['type'] == 'shutter' || w['type'] == 'value' || w['type'] == 'ac' ? 1 : 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w400, color: pal.ink, height: 1.2),
  );

  Widget _state(String s) => Text(
    s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: fs(w, 'stateSize'), color: pal.muted, fontFeatures: const [FontFeature.tabularFigures()]),
  );

  Widget _icon(Color color) => iconWidget(w['icon'] as String?, fs(w, 'iconSize'), color);

  Widget _head(Color iconColor, {Widget? trailing}) => Row(
    children: [
      _icon(iconColor),
      const SizedBox(width: 8),
      Expanded(child: _label()),
      if (trailing != null) ...[const SizedBox(width: 6), trailing],
    ],
  );

  Widget _led(bool on, Color c) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: on ? c : pal.lineStrong,
      shape: BoxShape.circle,
      boxShadow: on ? [BoxShadow(color: c, blurRadius: 6)] : null,
    ),
  );

  Json? _ga(String key) => byId(gas, jsonMap(w['bind'])[key] as String?);

  /// Progress bar; in test mode a draggable slider (preview while dragging,
  /// command sent on release).
  Widget _slider(double v, Color c, {bool invert = false}) {
    if (act == null) return _bar(v, c);
    final f = v.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, bc) {
        final width = bc.maxWidth;
        void at(double dx) {
          var n = (dx / width * 100).clamp(0.0, 100.0).round();
          if (invert) n = 100 - n;
          act!('preview', n);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (e) => at(e.localPosition.dx),
          onHorizontalDragUpdate: (e) => at(e.localPosition.dx),
          onHorizontalDragEnd: (_) => act!('commit'),
          onTapUp: (e) {
            at(e.localPosition.dx);
            act!('commit');
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              height: 22,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(color: pal.line, borderRadius: BorderRadius.circular(3)),
                  ),
                  FractionallySizedBox(
                    widthFactor: f,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  Positioned(
                    left: (width - 16) * f,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: c, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(double v, Color c) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: LinearProgressIndicator(value: v.clamp(0, 1).toDouble(), minHeight: 4, backgroundColor: pal.line, color: c),
  );

  Widget _col(List<Widget> children) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: children);

  Widget _content(String type, bool on, Color colorOn, Color colorOff) {
    final style = jsonMap(w['style']);
    final textOn = (style['textOn'] ?? 'Đang bật').toString(), textOff = (style['textOff'] ?? 'Đang tắt').toString();
    switch (type) {
      case 'switch':
        return _col([_head(on ? colorOn : colorOff, trailing: _led(on, colorOn)), _state(on ? textOn : textOff)]);
      case 'dimmer':
        final v = ((sim['val'] as num?) ?? 0).toInt();
        return _col([
          _head(
            on ? colorOn : colorOff,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (act != null)
                  _tap(
                    'tune',
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.tune, size: 18, color: pal.muted),
                    ),
                  ),
                const SizedBox(width: 4),
                _led(on, colorOn),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [_state(on ? '$textOn $v%' : textOff), const SizedBox(height: 6), _slider(v / 100, colorOn)],
          ),
        ]);
      case 'value':
        final g = _ga('status');
        final dpt = (g?['dpt'] ?? '').toString();
        const samples = {'9.001': 24.5, '9.004': 320, '9.007': 62, '14.056': 1250, '13.010': 8420, '5.001': 45};
        final raw = sim['val'] ?? samples[dpt];
        final f = jsonMap(w['format']);
        final dec = (f['decimals'] as num?)?.toInt() ?? 0;
        return _col([
          _head(pal.muted),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                raw is num ? fmtNum(raw, dec) : '–',
                style: TextStyle(fontSize: fs(w, 'valueSize'), color: pal.ink, height: 1),
              ),
              const SizedBox(width: 3),
              Text(
                (f['unit'] ?? '').toString(),
                style: TextStyle(fontSize: fs(w, 'valueSize') * 0.5, color: pal.muted),
              ),
            ],
          ),
        ]);
      case 'button':
        return _col([_head(pal.muted), _state('Nhấn để gửi')]);
      case 'scene':
        return _col([_head(pal.muted), _state('Cảnh ${w['sceneNumber'] ?? 1}')]);
      case 'link':
        final host = Uri.tryParse((w['url'] ?? '').toString())?.host ?? '';
        return _col([_head(pal.muted), _state(host.isEmpty ? 'Chưa có địa chỉ web' : host)]);
      case 'webview':
        final host = Uri.tryParse((w['url'] ?? '').toString())?.host ?? '';
        final showHead = jsonMap(w['web'])['showHeader'] != false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHead) ...[_head(pal.muted), const SizedBox(height: 8)],
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: pal.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: pal.tileEdge),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: pal.tileEdge)),
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < 3; i++)
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(color: pal.lineStrong, shape: BoxShape.circle),
                            ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              host.isEmpty ? 'Chưa có địa chỉ web' : host,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: pal.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.language, size: 26, color: pal.muted),
                            const SizedBox(height: 6),
                            Text(
                              host.isEmpty ? 'Nhập địa chỉ web trong thuộc tính' : 'Trang web hiển thị tại đây trong App',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: pal.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case 'shutter':
        final curtain = w['shStyle'] == 'curtain';
        final ctrl = (w['shCtrl'] ?? 'buttons').toString();
        final p = ((sim['pos'] as num?) ?? 0).toInt();
        final b = jsonMap(w['bind']);
        final showPct = b['status'] != null || b['position'] != null;
        final bi = fs(w, 'btnIcon');
        Widget btn(IconData i, String a) => Expanded(
          child: _tap(
            a,
            Container(
              height: bi + 12,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: pal.panel,
                border: Border.all(color: pal.tileEdge),
                borderRadius: BorderRadius.circular(bi * 0.5 + 2),
              ),
              child: Icon(i, size: bi, color: pal.ink),
            ),
          ),
        );
        return _col([
          _head(
            pal.muted,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPct) _state(curtain ? 'Mở ${100 - p}%' : 'Đóng $p%'),
                if (ctrl != 'buttons') ...[const SizedBox(width: 6), _tap('tune', Icon(Icons.tune, size: 18, color: pal.muted))],
              ],
            ),
          ),
          if (ctrl == 'slider')
            _slider((curtain ? 100 - p : p) / 100, pal.accent, invert: curtain)
          else
            Row(
              children: [
                btn(curtain ? Icons.open_in_full : Icons.keyboard_arrow_up, 'up'),
                if (w['showStop'] != false) btn(Icons.stop_outlined, 'stop'),
                btn(curtain ? Icons.close_fullscreen : Icons.keyboard_arrow_down, 'down'),
              ],
            ),
        ]);
      case 'ac':
        final ac = jsonMap(w['ac']);
        final acOn = sim['on'] == true;
        final sp = (sim['sp'] as num?) ?? 24;
        final step = (ac['step'] as num?) == 1 ? 1 : 0.5;
        final mode = (sim['mode'] ?? 'cool').toString();
        final modes = jsonMap(ac['modes']);
        final names = jsonMap(ac['names']);
        final ab = fs(w, 'acBtn'), am = fs(w, 'acMode');
        final modeLabel = (ac['modeLabel'] ?? 'both').toString();
        final showCur = ac['showCur'] != false && jsonMap(w['bind'])['current'] != null;
        Widget round(IconData i, String a) => _tap(
          a,
          Container(
            width: ab * 2.2,
            height: ab * 2.2,
            decoration: BoxDecoration(
              color: pal.panel,
              shape: BoxShape.circle,
              border: Border.all(color: pal.tileEdge),
            ),
            child: Icon(i, size: ab, color: pal.ink),
          ),
        );
        Widget modeBtn(String key, String name, String icon, bool active) => Expanded(
          child: _tap(
            key == 'off' ? 'off' : 'mode',
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: EdgeInsets.symmetric(vertical: am * 0.35),
              decoration: BoxDecoration(
                color: active ? pal.ink : pal.panel,
                border: Border.all(color: active ? pal.ink : pal.tileEdge),
                borderRadius: BorderRadius.circular(am * 0.62),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (modeLabel != 'text') iconWidget(icon, am, active ? pal.screen : pal.muted),
                  if (modeLabel == 'both') const SizedBox(height: 2),
                  if (modeLabel != 'icon')
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: modeLabel == 'text' ? am * 0.85 : am * 0.7, color: active ? pal.screen : pal.muted),
                    ),
                ],
              ),
            ),
            key,
          ),
        );
        String nm(String k, String d) => ((names[k] ?? '').toString().trim().isEmpty) ? d : names[k].toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(
              pal.muted,
              trailing: showCur
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.thermostat, size: fs(w, 'stateSize') * 1.25, color: pal.muted),
                        _state('${fmtNum((sim['cur'] as num?) ?? 26.5, 1)}°C'),
                      ],
                    )
                  : null,
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  round(Icons.remove, 'minus'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        fmtNum(sp, step == 1 ? 0 : 1),
                        style: TextStyle(fontSize: fs(w, 'valueSize') * 1.3, color: acOn ? pal.ink : pal.muted, height: 1),
                      ),
                      Text(
                        '°C',
                        style: TextStyle(fontSize: fs(w, 'valueSize') * 0.55, color: pal.muted),
                      ),
                    ],
                  ),
                  round(Icons.add, 'plus'),
                ],
              ),
            ),
            Row(
              children: [
                modeBtn('off', nm('off', 'Tắt'), 'power', !acOn),
                for (final m in kAcModes)
                  if (modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat') modeBtn(m.key, nm(m.key, m.name), m.icon, acOn && mode == m.key),
              ],
            ),
          ],
        );
    }
    return _head(pal.muted);
  }
}
