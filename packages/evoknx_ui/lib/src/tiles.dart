import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:knx_config/knx_config.dart';

import 'icons.dart';
import 'model.dart';

/// Colours of the simulated app screen (light/dark like the real app).
/// The App themes shown in the pickers: (key, Vietnamese name).
const List<(String, String)> kAppThemes = [('light', 'Sáng'), ('dark', 'Tối'), ('graphite', 'Xám than'), ('gray', 'Xám'), ('ocean', 'Xanh biển')];

/// A valid theme key ('sand', the old cream theme, becomes 'gray').
String themeKey(Object? mode) {
  final m = mode == 'sand' ? 'gray' : mode;
  return kAppThemes.any((t) => t.$1 == m) ? m as String : 'light';
}

/// The text style of a card's name. Frame titles use it too, so every name in
/// the Editor preview and the App looks the same.
TextStyle evoLabelStyle(Json w, Color color) => TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w400, color: color, height: 1.2);

/// Selection colour of the Editor (not part of the App's palette).
const Color kEditorSelection = Color(0xFF0D99FF);

class AppPalette {
  final Color screen, tile, tileEdge, panel, ink, muted, line, lineStrong, accent, accentSoft, led, ledSoft, danger;

  /// Text colours used directly on the screen background (title, page name…),
  /// which may differ when a custom background colour or image is used.
  final Color? onScreenInk, onScreenMuted;

  /// Card shape (Tổng quan → Kiểu thẻ): corner radius, border width, shadow.
  final double radius, border, shadow;

  /// Card background and border strength (Tổng quan → Kiểu thẻ), 0…1.
  final double tileOpacity, edgeOpacity;

  /// Border colour after the border-strength setting.
  Color get edge => tileEdge.withValues(alpha: tileEdge.a * edgeOpacity);

  /// A card background after the background-opacity setting.
  Color fill(Color c) => c.withValues(alpha: c.a * tileOpacity);

  List<BoxShadow> get shadows => shadow <= 0
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10 + shadow * 0.006),
            blurRadius: shadow * 1.6,
            offset: Offset(0, shadow * 0.45),
          ),
        ];
  Color get sInk => onScreenInk ?? ink;
  Color get sMuted => onScreenMuted ?? muted;

  const AppPalette({
    this.onScreenInk,
    this.onScreenMuted,
    this.radius = 12,
    this.border = 1,
    this.shadow = 0,
    this.tileOpacity = 1,
    this.edgeOpacity = 1,
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
    double? radius,
    double? border,
    double? shadow,
    double? tileOpacity,
    double? edgeOpacity,
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
    radius: radius ?? this.radius,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
    tileOpacity: tileOpacity ?? this.tileOpacity,
    edgeOpacity: edgeOpacity ?? this.edgeOpacity,
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

  /// App themes: Sáng, Tối, Xám than, Xám and Xanh biển.
  /// Older projects using "system" fall back to Sáng.
  static AppPalette of(String? mode) => switch (mode) {
    'dark' => dark,
    'graphite' => graphite,
    'gray' || 'sand' => gray,
    'ocean' => ocean,
    _ => light,
  };

  /// Neutral dark grey (graphite), softer than full dark.
  static const graphite = AppPalette(
    screen: Color(0xFF23272B),
    tile: Color(0xFF3F454B),
    tileEdge: Color(0xFF50575E),
    panel: Color(0xFF2E3338),
    ink: Color(0xFFF1F3F4),
    muted: Color(0xFFA9B0B6),
    line: Color(0xFF454C52),
    lineStrong: Color(0xFF5A6168),
    accent: Color(0xFF4DB38A),
    accentSoft: Color(0xFF23392F),
    led: Color(0xFFF2AA45),
    ledSoft: Color(0xFF3E3220),
    danger: Color(0xFFEE7B66),
  );

  /// Neutral mid grey ("Xám"): grey screen, lighter grey cards. Older
  /// projects that used the cream theme ('sand') show this one.
  static const gray = AppPalette(
    screen: Color(0xFF8D9298),
    tile: Color(0xFFB8BCC1),
    tileEdge: Color(0xFF7C8289),
    panel: Color(0xFFC9CCD0),
    ink: Color(0xFF14171A),
    muted: Color(0xFF3E444A),
    line: Color(0xFFA1A6AC),
    lineStrong: Color(0xFF787E85),
    accent: Color(0xFF176B49),
    accentSoft: Color(0xFFB3CBBF),
    led: Color(0xFFD97A0F),
    ledSoft: Color(0xFFD4C4A4),
    danger: Color(0xFFA6301F),
  );

  /// Sea blue ("Xanh biển"): a deep blue-green screen with cards of nearly
  /// the same tone, a little lighter.
  static const ocean = AppPalette(
    screen: Color(0xFF054F66),
    tile: Color(0xFF1B6E84),
    tileEdge: Color(0xFF3A8397),
    panel: Color(0xFF2C7E93),
    ink: Color(0xFFF2FAFC),
    muted: Color(0xFFAFD3DD),
    line: Color(0xFF3B8497),
    lineStrong: Color(0xFF5C9DAE),
    accent: Color(0xFF1FB58F),
    accentSoft: Color(0xFF1F6B7D),
    led: Color(0xFFF5B54A),
    ledSoft: Color(0xFF455C4A),
    danger: Color(0xFFFF8F7A),
    // Text written straight on the screen.
    onScreenInk: Color(0xFFFFFFFF),
    onScreenMuted: Color(0xC0FFFFFF),
  );

  static const light = AppPalette(
    screen: Color(0xFFD0D4D9),
    tile: Color(0xFFFFFFFF),
    tileEdge: Color(0xFFC2C8CE),
    panel: Color(0xFFFFFFFF),
    ink: Color(0xFF1B2320),
    muted: Color(0xFF66716C),
    line: Color(0xFFDEE3E0),
    lineStrong: Color(0xFFBAC2BE),
    accent: Color(0xFF1E7F57),
    accentSoft: Color(0xFFE2F1E9),
    led: Color(0xFFEE9B2A),
    ledSoft: Color(0xFFFDF1DC),
    danger: Color(0xFFC2412D),
  );

  static const dark = AppPalette(
    screen: Color(0xFF121618),
    tile: Color(0xFF2B3235),
    tileEdge: Color(0xFF3B4447),
    panel: Color(0xFF1D2326),
    ink: Color(0xFFE7ECE9),
    muted: Color(0xFF9AA59F),
    line: Color(0xFF2F3739),
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

  /// Icon button used by every card (the curtain card's look): the button is
  /// the icon size plus 12, so the icon fills about two thirds of it. The
  /// same proportions everywhere keep buttons and icons in step.
  Widget _ibtn(String action, Object icon, double s, {Object? arg, bool expand = true, bool circle = false, Color? fill, Color? edge, Color? fg}) {
    final h = s + 12;
    final color = fg ?? pal.muted;
    final inner = Container(
      width: circle ? h : null,
      height: h,
      margin: expand ? const EdgeInsets.symmetric(horizontal: 1.5) : null,
      decoration: BoxDecoration(
        color: fill ?? pal.panel,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(s * 0.4 + 2),
        border: Border.all(color: edge ?? pal.tileEdge),
      ),
      child: Center(
        child: icon is IconData ? Icon(icon, size: s, color: color) : iconWidget(icon as String, s, color),
      ),
    );
    final t = _tap(action, inner, arg);
    return expand ? Expanded(child: t) : t;
  }

  Widget _tap(String action, Widget child, [Object? arg]) => act == null
      ? child
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => act!(action, arg),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: PressEffect(scale: 0.92, radius: 10, dark: pal.tile.computeLuminance() < 0.35, child: child),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final type = w['type'] as String? ?? '';
    final style = jsonMap(w['style']);
    final cardBg = hexColor(style['bg']);
    if (cardBg != null && pal.tile != cardBg) {
      return TileView(w: w, pal: pal.forCard(cardBg), gas: gas, sim: sim, selected: selected, flagged: flagged, act: act);
    }
    // "Chỉ có viền" / "Trong suốt": no background (and no border for the
    // latter); text follows the screen background.
    final noBg = style['bg'] == 'outline' || style['bg'] == 'transparent';
    final noBorder = style['bg'] == 'transparent';
    if (noBg && pal.tile != Colors.transparent) {
      final tp = pal.copyWith(tile: Colors.transparent, ink: pal.sInk, muted: pal.sMuted, panel: pal.panel.withValues(alpha: 0.85));
      return TileView(w: w, pal: tp, gas: gas, sim: sim, selected: selected, flagged: flagged, act: act);
    }
    final on = type == 'switch' ? sim['on'] == true : (type == 'dimmer' ? ((sim['val'] as num?) ?? 0) > 0 : false);
    final rgb = type == 'dimmer' ? hexColor(sim['rgb']) : null;
    final colorOn = rgb ?? hexColor(style['colorOn']) ?? pal.led;
    final colorOff = hexColor(style['colorOff']) ?? pal.muted;
    // On: the card is tinted with the "on" colour (full and simple looks).
    // Value card, state style: a state marked as alarm tints the card red.
    final alarm = _stateRow()?['alarm'] == true;
    final bg = alarm
        ? Color.alphaBlend(pal.danger.withValues(alpha: 0.18), pal.tile)
        : (on ? Color.alphaBlend(colorOn.withValues(alpha: 0.30), pal.tile) : pal.tile);
    final imageBtn = (type == 'button' || type == 'scene') && w['btnStyle'] == 'image';
    final self = this;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: pal.fill(type == 'webview' ? pal.tile : bg),
        borderRadius: BorderRadius.circular(pal.radius),
        border: alarm
            ? Border.all(color: pal.danger, width: max(1.5, pal.border))
            : pal.border <= 0 || (noBorder && !on)
            ? null
            : Border.all(
                color: on ? colorOn.withValues(alpha: 0.6 * pal.edgeOpacity) : pal.edge,
                width: pal.border,
              ),
        boxShadow: pal.tile == Colors.transparent ? const [] : pal.shadows,
      ),
      foregroundDecoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(pal.radius),
              border: Border.all(color: kEditorSelection, width: 1.5),
            )
          : null,
      padding: imageBtn ? const EdgeInsets.all(8) : const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: self._content(type, on, colorOn, colorOff)),
            if (flagged) Positioned(right: -2, bottom: -2, child: Icon(Icons.warning_amber_rounded, size: 15, color: pal.danger)),
          ],
        ),
      ),
    );
  }

  /// The state row shown by a state-style value card (the first row as a
  /// sample while designing, when no value is known yet).
  Json? _stateRow() {
    if (!isStateValue(w)) return null;
    final r = valueState(w, sim['val']);
    if (r != null || sim['val'] != null || act != null) return r;
    final rows = jsonList(w['states']);
    return rows.isEmpty ? null : rows.first;
  }

  Widget _label() => Text(
    (w['label'] ?? '').toString(),
    maxLines: w['type'] == 'shutter' || w['type'] == 'value' || w['type'] == 'ac' ? 1 : 2,
    overflow: TextOverflow.ellipsis,
    style: evoLabelStyle(w, pal.ink),
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
      if (!isNoIcon(w['icon'] as String?)) ...[_icon(iconColor), const SizedBox(width: 8)],
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

  Widget _liveDot() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(6)),
    child: Text(
      'LIVE',
      style: TextStyle(fontSize: 9.5 * EvoScale.k, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5),
    ),
  );

  /// Simple look: icon (and optional control) on top, name below, no state
  /// text; on/off is shown by the card colour.
  Widget _simple(Color iconColor, {Widget? trailing}) => Row(
    children: [
      if (!isNoIcon(w['icon'] as String?)) ...[_icon(iconColor), const SizedBox(width: 10)],
      Expanded(
        child: Text(
          (w['label'] ?? '').toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w500, color: pal.ink, height: 1.2),
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 6), trailing],
    ],
  );

  /// Button style "Hình ảnh": the picture centred, optional label below.
  Widget _imageButton() {
    final size = (((w['imageSize'] as num?) ?? 70).toDouble().clamp(20, 100)) / 100;
    final showLabel = w['showLabel'] != false && (w['label'] ?? '').toString().isNotEmpty;
    final useIcon = w['imgSource'] == 'icon';
    final img = useIcon ? null : imageFromData((w['image'] ?? '').toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (useIcon)
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Center(
                child: iconWidget(
                  (w['imgIcon'] ?? 'mdi:gesture-tap-button').toString(),
                  max(8.0, min(c.maxWidth, c.maxHeight) * size),
                  hexColor(w['imgColor']) ?? pal.ink,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: size,
                heightFactor: size,
                child:
                    img ??
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 26, color: pal.muted),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            'Chưa có ảnh',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11 * EvoScale.k, color: pal.muted),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            (w['label'] ?? '').toString(),
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fs(w, 'labelSize'), color: pal.ink, height: 1.2),
          ),
        ],
      ],
    );
  }

  Widget _col(List<Widget> children) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: children);

  Widget _content(String type, bool on, Color colorOn, Color colorOff) {
    final style = jsonMap(w['style']);
    final textOn = (style['textOn'] ?? 'Đang bật').toString(), textOff = (style['textOff'] ?? 'Đang tắt').toString();
    switch (type) {
      case 'switch':
        if (w['look'] == 'simple') return _simple(pal.muted);
        return _col([_head(pal.muted, trailing: _led(on, colorOn)), _state(on ? textOn : textOff)]);
      case 'dimmer':
        if (w['look'] == 'simple') {
          return _simple(
            pal.muted,
            trailing: act == null && w['showTune'] == false
                ? null
                : _tap(
                    'tune',
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: iconWidget((w['tuneIcon'] ?? 'mdi:tune-vertical').toString(), fs(w, 'iconSize') * 0.85, pal.muted),
                    ),
                  ),
          );
        }
        final v = ((sim['val'] as num?) ?? 0).toInt();
        return _col([
          _head(
            pal.muted,
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
        if (isStateValue(w)) {
          final row = _stateRow();
          final raw = sim['val'];
          final text = row != null
              ? (row['text'] ?? '').toString()
              : (raw is num ? fmtNum(raw, 0) : (jsonList(w['states']).isEmpty ? 'Chưa đặt trạng thái' : '–'));
          return _col([
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconWidget((row?['icon'] ?? w['icon'])?.toString(), fs(w, 'iconSize'), hexColor(row?['color']) ?? pal.muted),
                const Spacer(),
                if (row?['alarm'] == true) Icon(Icons.warning_amber_rounded, size: fs(w, 'iconSize') * 0.8, color: pal.danger),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _label(),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fs(w, 'stateSize') * 1.15,
                    fontWeight: FontWeight.w600,
                    color: row == null ? pal.muted : (hexColor(row['color']) ?? pal.ink),
                  ),
                ),
              ],
            ),
          ]);
        }
        if (w['look'] == 'simple') {
          const samples0 = {'9.001': 24.5, '9.004': 320, '9.007': 62, '14.056': 1250, '13.010': 8420, '5.001': 45};
          final raw0 = sim['val'] ?? samples0[(g?['dpt'] ?? '').toString()];
          final f0 = jsonMap(w['format']);
          final dec0 = (f0['decimals'] as num?)?.toInt() ?? 0;
          return Row(
            children: [
              _icon(pal.muted),
              const SizedBox(width: 8),
              Expanded(child: _label()),
              const SizedBox(width: 8),
              Text(
                raw0 is num ? fmtNum(raw0, dec0) : '–',
                style: TextStyle(fontSize: fs(w, 'valueSize') * 0.75, color: pal.ink, fontWeight: FontWeight.w500),
              ),
              if ((f0['unit'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  (f0['unit'] ?? '').toString(),
                  style: TextStyle(fontSize: fs(w, 'valueSize') * 0.42, color: pal.muted),
                ),
              ],
            ],
          );
        }
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
        if (w['btnStyle'] == 'image') return _imageButton();
        return _col([_head(pal.muted), _state('Nhấn để gửi')]);
      case 'scene':
        if (w['btnStyle'] == 'image') return _imageButton();
        return _col([_head(pal.muted), _state('Nhấn để bật cảnh')]);
      case 'camera':
        final cam = jsonMap(w['cam']);
        if (cam['view'] == 'button') return _simple(pal.muted, trailing: _liveDot());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w['showHeader'] != false) ...[_head(pal.muted, trailing: _liveDot()), const SizedBox(height: 8)],
            Expanded(
              child: CameraView(cam: cam, live: act != null),
            ),
          ],
        );
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
                              style: TextStyle(fontSize: 11 * EvoScale.k, color: pal.muted),
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
                              style: TextStyle(fontSize: 12 * EvoScale.k, color: pal.muted),
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
        final bi = fs(w, 'btnIcon') * 1.55;
        Widget btn(Object i, String a) => _ibtn(a, i, bi);
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
                btn(curtain ? 'mdi:arrow-expand-horizontal' : Icons.keyboard_arrow_up, 'up'),
                if (w['showStop'] != false) btn(Icons.stop_outlined, 'stop'),
                btn(curtain ? 'mdi:arrow-collapse-horizontal' : Icons.keyboard_arrow_down, 'down'),
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
        final modeLabel = (ac['modeLabel'] ?? 'icon').toString();
        final showCur = ac['showCur'] != false && jsonMap(w['bind'])['current'] != null;
        Widget round(IconData i, String a) => _ibtn(a, i, ab * 1.2, expand: false, circle: true);
        Widget modeBtn(String key, String name, String icon, bool active) => modeLabel == 'icon'
            ? _ibtn(
                key == 'off' ? 'off' : 'mode',
                icon,
                am * 1.5,
                arg: key,
                fill: active ? pal.ink : pal.panel,
                edge: active ? pal.ink : pal.tileEdge,
                fg: active ? pal.screen : pal.muted,
              )
            : Expanded(
                child: _tap(
                  key == 'off' ? 'off' : 'mode',
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: EdgeInsets.symmetric(vertical: modeLabel == 'icon' ? am * 0.55 : am * 0.35),
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
        final fanOn = jsonMap(ac['fan'])['enabled'] == true;
        final fan = (sim['fan'] ?? 'auto').toString();
        final levels = acFanLevels(ac);
        // Fan speed icons (MDI): auto, low, medium, high (+ extra levels).
        String fanIcon(String k) {
          if (k == 'auto') return 'mdi:fan-auto';
          final n = levels.where((x) => x != 'auto').length;
          final i = int.tryParse(k) ?? 1;
          if (n == 2) return i == 1 ? 'mdi:fan-speed-1' : 'mdi:fan-speed-3';
          if (i <= 3) return 'mdi:fan-speed-$i';
          return i == 4 && n == 5 ? 'mdi:fan-chevron-up' : 'mdi:fan-plus';
        }
        Widget spText() => Row(
          mainAxisSize: MainAxisSize.min,
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
        );
        // The number sits in a box of fixed width, so the − / + buttons keep
        // their place when the setpoint changes (24,0 → 9,5, 16 → 100…).
        Widget spBox() => SizedBox(
          width: fs(w, 'valueSize') * 4.2,
          child: Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: spText()),
          ),
        );
        Widget spRow() => Center(
          // Scales down instead of overflowing on a small card.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                round(Icons.remove, 'minus'),
                SizedBox(width: ab * 1.8),
                spBox(),
                SizedBox(width: ab * 1.8),
                round(Icons.add, 'plus'),
              ],
            ),
          ),
        );
        if (w['look'] == 'simple') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(
                pal.muted,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ibtn(
                      'power',
                      'mdi:power',
                      ab * 1.2,
                      expand: false,
                      circle: true,
                      fill: acOn ? pal.accent : pal.panel,
                      edge: acOn ? pal.accent : pal.tileEdge,
                      fg: acOn ? Colors.white : pal.muted,
                    ),
                    const SizedBox(width: 6),
                    _tap(
                      'popup',
                      Padding(
                        padding: const EdgeInsets.all(2),
                        child: iconWidget((ac['moreIcon'] ?? 'mdi:tune-variant').toString(), fs(w, 'iconSize') * 0.85, pal.muted),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: spRow()),
            ],
          );
        }
        // Popup of the simple card: modes and fan only (setpoint is on the card).
        if (w['look'] == 'controls') {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  modeBtn('off', nm('off', 'Tắt'), 'power', !acOn),
                  for (final m in kAcModes)
                    if (modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat') modeBtn(m.key, nm(m.key, m.name), m.icon, acOn && mode == m.key),
                ],
              ),
              if (fanOn) ...[
                SizedBox(height: am * 0.8),
                Row(
                  children: [
                    for (final k in levels)
                      _ibtn(
                        'fan',
                        fanIcon(k),
                        am * 1.5,
                        arg: k,
                        fill: acOn && fan == k ? pal.ink : pal.panel,
                        edge: acOn && fan == k ? pal.ink : pal.tileEdge,
                        fg: acOn && fan == k ? pal.screen : pal.muted,
                      ),
                  ],
                ),
              ],
            ],
          );
        }
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
            Expanded(child: spRow()),
            Row(
              children: [
                modeBtn('off', nm('off', 'Tắt'), 'power', !acOn),
                for (final m in kAcModes)
                  if (modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat') modeBtn(m.key, nm(m.key, m.name), m.icon, acOn && mode == m.key),
              ],
            ),
            if (fanOn) ...[
              SizedBox(height: am * 0.4),
              Row(
                children: [
                  for (final k in levels)
                    _ibtn(
                      'fan',
                      fanIcon(k),
                      am * 1.5,
                      arg: k,
                      fill: acOn && fan == k ? pal.ink : pal.panel,
                      edge: acOn && fan == k ? pal.ink : pal.tileEdge,
                      fg: acOn && fan == k ? pal.screen : pal.muted,
                    ),
                ],
              ),
            ],
          ],
        );
    }
    return _head(pal.muted);
  }
}

// ------------------------------------------------------------------ images

final Map<String, ({Uint8List bytes, bool svg})> _imgCache = {};

/// Draws an image stored as a data URL (PNG, JPEG or SVG), untinted.
Widget? imageFromData(String data, {BoxFit fit = BoxFit.contain}) {
  if (data.isEmpty) return null;
  var e = _imgCache[data];
  if (e == null) {
    final m = RegExp(r'^data:image/(png|jpeg|jpg|svg\+xml|webp)(;[^,]*)?,(.*)$', dotAll: true).firstMatch(data);
    if (m == null) return null;
    try {
      final payload = m[3]!;
      final bytes = (m[2] ?? '').contains('base64') ? base64Decode(payload) : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
      e = (bytes: bytes, svg: m[1] == 'svg+xml');
      if (_imgCache.length > 40) _imgCache.clear();
      _imgCache[data] = e;
    } catch (_) {
      return null;
    }
  }
  return e.svg ? SvgPicture.memory(e.bytes, fit: fit) : Image.memory(e.bytes, fit: fit, gaplessPlayback: true, filterQuality: FilterQuality.medium);
}

// ------------------------------------------------------------------ press effect

/// Visual feedback while a card or button is held down: it shrinks slightly
/// and darkens. Uses a Listener so it never steals taps or drags; moving the
/// finger (e.g. dragging a dimmer) releases the effect.
class PressEffect extends StatefulWidget {
  const PressEffect({super.key, required this.child, this.scale = 0.97, this.radius = 16, this.dark = false, this.enabled = true});
  final Widget child;
  final double scale, radius;
  final bool dark, enabled;

  @override
  State<PressEffect> createState() => _PressEffectState();
}

class _PressEffectState extends State<PressEffect> {
  bool _down = false;
  Offset? _start;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _start = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        if (_down && _start != null && (e.position - _start!).distance > 10) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 240),
        curve: Curves.easeOutCubic,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _down ? 1 : 0,
                  duration: Duration(milliseconds: _down ? 90 : 240),
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.dark ? const Color(0x14FFFFFF) : const Color(0x0D000000),
                      borderRadius: BorderRadius.circular(widget.radius),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ camera

/// Camera picture area. The Editor cannot play RTSP; with HTTP and [live]
/// (test mode) it shows a snapshot from the address so the settings can be
/// checked. The App plays the real stream.
class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.cam, this.live = false});
  final Json cam;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final url = cameraUrl(cam, hidePass: true);
    final http = cam['protocol'] == 'http' && url.isNotEmpty;
    Widget placeholder(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_outlined, size: 28, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5 * EvoScale.k, color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
    Widget body;
    if (url.isEmpty) {
      body = placeholder('Nhập địa chỉ IP camera trong thuộc tính');
    } else if (http && live) {
      final user = (cam['user'] ?? '').toString(), pass = (cam['pass'] ?? '').toString();
      body = Image.network(
        cameraUrl({...cam, 'user': '', 'pass': ''}),
        headers: user.isEmpty ? null : {'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}'},
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder('Không lấy được ảnh từ camera.\n$url\nVideo trực tiếp sẽ phát trong App.'),
      );
    } else {
      body = placeholder('$url\nVideo trực tiếp phát trong App');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFF15191B),
        child: SizedBox.expand(child: body),
      ),
    );
  }
}
