import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show EagerGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:knx_config/knx_config.dart';

import 'icons.dart';
import 'ios_controls.dart';
import 'look.dart';
import 'model.dart';
import 'press.dart';

/// The App themes: iOS style, Light and Dark.
const List<(String, List<(String, String)>)> kAppThemeGroups = [
  ('Theme', [('i1', 'Light'), ('i2', 'Dark')]),
];

/// Flat list for drop-downs: (key, name).
const List<(String, String)> kAppThemes = [('i1', 'Light'), ('i2', 'Dark')];

/// A valid theme key. Any older theme key becomes the nearest of the two: the dark ones Dark, every other one Light.
String themeKey(Object? mode) {
  const dark = {'dark', 'ocean', 'graphite', 'gray', 'd1', 'd2', 'd3', 'g1', 'g2', 'g3'};
  if (dark.contains(mode)) return 'i2';
  return kAppThemes.any((t) => t.$1 == mode) ? mode as String : 'i1';
}

/// The color a lit card (switch, dimmer, AC that is on) glows in, or null.
/// The grid draws it in the shadow layer under the cards.
Color? tileGlowColor(Json w, AppPalette pal, Map<String, dynamic> sim) {
  if (pal.ios) return null;
  final type = w['type'];
  final on = type == 'switch' || type == 'ac' ? sim['on'] == true : (type == 'dimmer' ? ((sim['val'] as num?) ?? 0) > 0 : false);
  if (!on) return null;
  final style = jsonMap(w['style']);
  final rgb = type == 'dimmer' ? hexColor(sim['rgb']) : null;
  final styleOn = hexColor(style['colorOn']);
  final customOn = styleOn != null && styleOn != const Color(0xFFEE9B2A);
  return rgb ?? (customOn ? styleOn : pal.led);
}

/// The text style of a card's name. Frame titles use it too, so every name in
/// the Editor preview and the App looks the same.
TextStyle evoLabelStyle(Json w, Color color) => TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w400, color: color, height: 1.2);

/// Selection color of the Editor (not part of the App's palette).
const Color kEditorSelection = Color(0xFF0D99FF);

class AppPalette {
  final Color screen, tile, tileEdge, panel, ink, muted, line, lineStrong, accent, accentSoft, led, ledSoft, danger;

  /// Card background while on, and the floor / room buttons (idle, selected,
  /// text on the selected one). Null = derived from the other colors.
  final Color? tileOn, chip, chipOn, chipOnText;

  /// The iOS themes: wide switch and slider, no borders, round cards. [iosOn] is the palette of a lit card (white).
  final bool ios, iosOn;
  Color get chipFill => chip ?? panel;
  Color get chipSel => chipOn ?? ink;
  Color get onChipSel => chipOnText ?? screen;

  /// Text colors used directly on the screen background (title, page name…),
  /// which may differ when a custom background color or image is used.
  final Color? onScreenInk, onScreenMuted;

  /// Card shape (Tổng quan → Kiểu thẻ): corner radius, border width, shadow.
  final double radius, border, shadow;

  /// Largest blur of a card shadow (set by the grid from the gap between
  /// cards, so a shadow never falls on the next card).
  final double shadowCap;

  /// How much the control buttons and the Nút nhấn / Cảnh cards stand out
  /// (Tổng quan → Độ nổi nút): 0 = flat, 1.6 = default, up to about 2.7.
  final double lift;

  /// Card background and border strength (Tổng quan → Kiểu thẻ), 0…1.
  final double tileOpacity, edgeOpacity;

  /// Border color after the border-strength setting.
  Color get edge => tileEdge.withValues(alpha: tileEdge.a * edgeOpacity);

  /// A card background after the background-opacity setting.
  Color fill(Color c) => c.withValues(alpha: c.a * tileOpacity);

  double get _shadowBlur => min(shadow * 1.6, shadowCap);
  double get _shadowDrop => min(shadow * 0.45, _shadowBlur * 0.4);

  List<BoxShadow> get shadows => shadow <= 0
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10 + shadow * 0.006),
            blurRadius: _shadowBlur,
            offset: Offset(0, _shadowDrop),
          ),
        ];

  /// Margin kept free around the cards of a page so the shadow and the glow of
  /// the outer cards are not cut off (at least 14 px).
  /// Strength of the bevel of a card (from the "Độ nổi" setting) and of the
  /// soft shadow under it.
  double get cardLift => lift * 1.05;
  double get cardShadowLift => (lift * 1.5).clamp(0.0, 2.8).toDouble();

  double get safeMargin => max(14.0, min(shadow * 1.6, 15.0) + min(shadow * 0.45, min(shadow * 1.6, 15.0) * 0.4));
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
    this.shadowCap = 15,
    this.lift = 1.6,
    this.ios = false,
    this.iosOn = false,
    this.tileOn,
    this.chip,
    this.chipOn,
    this.chipOnText,
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
    double? shadowCap,
    double? lift,
    Color? tileOn,
    bool? iosOn,
  }) => AppPalette(
    ios: ios,
    iosOn: iosOn ?? this.iosOn,
    tileOn: tileOn ?? this.tileOn,
    chip: chip,
    chipOn: chipOn,
    chipOnText: chipOnText,
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
    radius: ios ? max(radius ?? this.radius, 22.0) : (radius ?? this.radius),
    border: ios ? 0.0 : (border ?? this.border),
    shadow: ios ? max(shadow ?? this.shadow, 3.0) : (shadow ?? this.shadow),
    tileOpacity: tileOpacity ?? this.tileOpacity,
    edgeOpacity: edgeOpacity ?? this.edgeOpacity,
    shadowCap: shadowCap ?? this.shadowCap,
    lift: ios ? 0.0 : (lift ?? this.lift),
  );

  /// Palette for a card with a custom background: readable text on dark colors.
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

  static AppPalette of(String? mode) => themeKey(mode) == 'i2' ? i2 : i1;

  /// The default light theme (also used by the welcome screen).
  static AppPalette get light => i1;

  // ---- iOS (Apple system colors, iOS 26)
  static const AppPalette i1 = AppPalette(
    ios: true,
    radius: 22,
    border: 0,
    shadow: 3,
    lift: 0,
    screen: Color(0xFFF2F2F7),
    tile: Color(0xFFDCDCE1),
    tileEdge: Color(0x00000000),
    tileOn: Color(0xFFFFFFFF),
    panel: Color(0xFFF2F2F7),
    ink: Color(0xFF1C1C1E),
    muted: Color(0xFF5A5A5E),
    line: Color(0xFFD1D1D6),
    lineStrong: Color(0xFFAEAEB2),
    accent: Color(0xFF0088FF),
    accentSoft: Color(0xFFFFFFFF),
    led: Color(0xFFFF8D28),
    ledSoft: Color(0xFFFFF1E0),
    danger: Color(0xFFFF383C),
    chip: Color(0xFFE3E3E8),
    chipOn: Color(0xFF0088FF),
    chipOnText: Color(0xFFFFFFFF),
  );
  static const AppPalette i2 = AppPalette(
    ios: true,
    radius: 22,
    border: 0,
    shadow: 3,
    lift: 0,
    screen: Color(0xFF000000),
    tile: Color(0xFF3A3A3C),
    tileEdge: Color(0x00000000),
    tileOn: Color(0xFFFFFFFF),
    panel: Color(0xFF48484A),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFFA1A1A6),
    line: Color(0xFF545456),
    lineStrong: Color(0xFF48484A),
    accent: Color(0xFF0091FF),
    accentSoft: Color(0xFF1B2A40),
    led: Color(0xFFFF9230),
    ledSoft: Color(0xFF3A2A18),
    danger: Color(0xFFFF4245),
    chip: Color(0xFF48484A),
    chipOn: Color(0xFF0091FF),
    chipOnText: Color(0xFFFFFFFF),
  );

  /// A lit card of an iOS theme is white with black text (like the Home app), also in the dark theme.
  /// An iOS light theme: white cards with a hairline on the grey screen, plain (not glass) buttons.
  bool get iosLight => ios && screen.computeLuminance() > 0.5;

  AppPalette get asIosOn => iosLight
      ? copyWith(tile: Colors.white, iosOn: true)
      : copyWith(
          tile: Colors.white,
          tileOn: Colors.white,
          ink: const Color(0xFF1C1C1E),
          muted: const Color(0xFF6C6C70),
          panel: const Color(0xFFF2F2F7),
          line: const Color(0xFFE5E5EA),
          iosOn: true,
        );
}

/// The palette of a card with its own background (the "Background" of its style): a color, "outline" (only a border) or
/// "transparent". [noBorder] is true for "transparent". Used by the cards that are not drawn by [TileView].
(AppPalette, bool) cardPalette(Json w, AppPalette pal) {
  final style = jsonMap(w['style']);
  final bg = style['bg'];
  final cardBg = hexColor(bg);
  if (cardBg != null && pal.tile != cardBg) return (pal.forCard(cardBg), false);
  if (bg == 'outline' || bg == 'transparent') {
    return (pal.copyWith(tile: Colors.transparent, ink: pal.sInk, muted: pal.sMuted, panel: pal.panel.withValues(alpha: 0.85)), bg == 'transparent');
  }
  return (pal, false);
}

/// The edge of a "Border only" card in the iOS themes (they have no border of their own, so the card would be invisible): a clear
/// line, or null for any other card.
Border? iosOutlineBorder(Json w, AppPalette pal) =>
    pal.ios && jsonMap(w['style'])['bg'] == 'outline' ? Border.all(color: pal.iosLight ? pal.lineStrong : pal.line, width: 1.0) : null;

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
  Widget _ibtn(
    String action,
    Object icon,
    double s, {
    Object? arg,
    bool expand = true,
    bool circle = false,
    Color? fill,
    Color? edge,
    Color? fg,
    double pad = 12,
    bool tint = false,
  }) {
    final h = s + pad;
    // [tint]: a clearer button (the blind card's): see-through fill, the icon in the text color, and the accent color while pressed.
    final color = fg ?? (tint ? pal.ink : pal.muted);
    // A selected button (filled with a strong color) also glows a little.
    final selected = fill != null && fill != pal.panel;
    final radius = BorderRadius.circular(s * 0.4 + 2);
    Widget face(bool down) => Container(
      width: circle ? h : null,
      height: h,
      margin: expand ? const EdgeInsets.symmetric(horizontal: 2.5) : null,
      decoration: down
          ? BoxDecoration(color: pal.accent, shape: circle ? BoxShape.circle : BoxShape.rectangle, borderRadius: circle ? null : radius)
          : pal.iosLight && fill == null
          ? BoxDecoration(
              color: tint ? pal.panel.withValues(alpha: 0.6) : pal.panel,
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle ? null : BorderRadius.circular(s * 0.4 + 2),
              border: Border.all(color: pal.line, width: 0.5),
            )
          : pal.ios && fill == null && tint
          // The blind card's buttons in Dark: a light, flat see-through fill and a thin rim, no shadow (the glass look is too heavy there).
          ? BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle ? null : BorderRadius.circular(s * 0.4 + 2),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.5),
            )
          : pal.ios && fill == null
          ? glassDeco(dark: pal.ink.computeLuminance() > 0.5, radius: BorderRadius.circular(s * 0.4 + 2), circle: circle, alpha: 0.9)
          : raisedDecoration(
              pal,
              fill ?? pal.panel,
              radius: BorderRadius.circular(s * 0.4 + 2),
              circle: circle,
              edge: edge,
              glow: selected ? fill : null,
              lift: pal.lift,
            ),
      child: Center(
        child: icon is IconData ? Icon(icon, size: s, color: down ? Colors.white : color) : iconWidget(icon as String, s, down ? Colors.white : color),
      ),
    );
    final inner = tint ? PressTint(builder: face) : face(false);
    final t = _tap(action, inner, arg);
    return expand ? Expanded(child: t) : t;
  }

  /// A dimmer with RGB or color temperature has more to set than the brightness.
  bool get _hasColorTune {
    final f = jsonMap(w['features']);
    return f['rgb'] == true || f['tw'] == true;
  }

  /// The button of the dimmer's controls: three dots, no background, no border (the touch area stays 32 px).
  Widget _tuneBtn() {
    var icon = (w['tuneIcon'] ?? '').toString();
    if (icon.isEmpty || icon == 'mdi:tune-vertical') icon = 'mdi:dots-horizontal';
    return _tap('tune', SizedBox(width: 32, height: 32, child: Center(child: iconWidget(icon, fs(w, 'iconSize') * 0.85, pal.muted))));
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
    // An AC card lights up like a dimmer while it runs (any mode but off).
    final on = type == 'switch' || type == 'ac' ? sim['on'] == true : (type == 'dimmer' ? ((sim['val'] as num?) ?? 0) > 0 : false);
    if (pal.ios && !pal.iosOn && on && (type == 'switch' || type == 'dimmer' || type == 'ac')) {
      return TileView(w: w, pal: pal.asIosOn, gas: gas, sim: sim, selected: selected, flagged: flagged, act: act);
    }
    final rgb = type == 'dimmer' ? hexColor(sim['rgb']) : null;
    // The orange stored in older cards as the default means "follow the theme".
    final styleOn = hexColor(style['colorOn']);
    final customOn = styleOn != null && styleOn != const Color(0xFFEE9B2A);
    final colorOn = rgb ?? (customOn ? styleOn : pal.led);
    final colorOff = hexColor(style['colorOff']) ?? pal.muted;
    // The popups of an AC card (modes, fan) are not tinted.
    final lit = on && w['look'] != 'controls' && w['look'] != 'controlsSp';
    // On: the card is tinted with the "on" color (full and simple looks).
    // Value card, state style: a state marked as alarm tints the card red.
    final alarm = _stateRow()?['alarm'] == true;
    final bg = alarm
        ? Color.alphaBlend(pal.danger.withValues(alpha: 0.18), pal.tile)
        : (lit ? (pal.tileOn != null && rgb == null && !customOn ? pal.tileOn! : Color.alphaBlend(colorOn.withValues(alpha: 0.30), pal.tile)) : pal.tile);
    final imageBtn = (type == 'button' || type == 'scene') && w['btnStyle'] == 'image';
    final self = this;
    // A Nút nhấn / Cảnh card is a button as a whole: it stands out like one.
    // Every card with a body is lifted (bevel + the shadow layer of the grid).
    final raisedCard = pal.tile != Colors.transparent && pal.lift > 0.01;
    final cardBorder = alarm
        ? null // the alarm edge is drawn over the card (below), so it takes no room: the content does not move
        : pal.iosLight && !noBorder
        ? null // the hairline of iOS Light is drawn over the card (below), so it takes no room: same inner size as Dark
        : pal.border <= 0 || pal.ios || (noBorder && !lit)
        ? null
        : Border.all(
            color: lit ? colorOn.withValues(alpha: 0.85 * pal.edgeOpacity) : pal.edge,
            width: lit ? max(1.5, pal.border) : pal.border,
          );
    final fullCamera = type == 'camera' && noBorder && jsonMap(w['cam'])['view'] != 'button';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: raisedCard
          ? raisedDecoration(
              pal,
              pal.fill(type == 'webview' ? pal.tile : bg),
              radius: BorderRadius.circular(pal.radius),
              lift: pal.cardLift,
              border: cardBorder ?? Border.fromBorderSide(BorderSide.none),
              shadow: false,
            )
          : BoxDecoration(color: pal.fill(type == 'webview' ? pal.tile : bg), borderRadius: BorderRadius.circular(pal.radius), border: cardBorder),
      foregroundDecoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(pal.radius),
              border: Border.all(color: kEditorSelection, width: 1.5),
            )
          : (pal.ios && style['bg'] == 'outline' && !alarm
                ? BoxDecoration(
                    // "Border only": the card has no fill, so its edge is drawn in a clear line (drawn over the card, it takes no room).
                    borderRadius: BorderRadius.circular(pal.radius),
                    border: Border.all(color: pal.iosLight ? pal.lineStrong : pal.line, width: 1.0),
                  )
                : pal.iosLight && !noBorder && !alarm
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(pal.radius),
                    border: Border.all(color: pal.line, width: 0.5),
                  )
                : alarm
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(pal.radius),
                    border: Border.all(color: pal.danger, width: max(1.5, pal.border)),
                  )
                : null),
      // A camera on a transparent card: the picture fills the whole card, edge to edge.
      padding: fullCamera ? EdgeInsets.zero : (imageBtn ? const EdgeInsets.all(8) : const EdgeInsets.fromLTRB(12, 10, 12, 10)),
      // Clipped to the card's rounded shape (not to the padded content), so a
      // button's shadow may use the card's padding.
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: self._content(type, on, colorOn, colorOff)),
          if (flagged) Positioned(right: -2, bottom: -2, child: Icon(Icons.warning_amber, size: 15, color: pal.danger)),
        ],
      ),
    );
  }

  /// The status row shown by a value card (in the Full look the first row as a
  /// sample while designing, when no value is known yet).
  Json? _stateRow() {
    if (w['type'] != 'value') return null;
    // The Simple look has its own status table too: only the row that matches the value counts (no sample row).
    if (!isStateValue(w)) return valueState(w, sim['val'] ?? sim['raw']);
    final r = valueState(w, sim['val'] ?? sim['raw']);
    if (r != null || sim['val'] != null || sim['raw'] != null || act != null) return r;
    final rows = jsonList(w['states']);
    return rows.isEmpty ? null : rows.first;
  }

  Widget _label({int? maxLines}) => Text(
    (w['label'] ?? '').toString(),
    maxLines: maxLines ?? (w['type'] == 'shutter' || w['type'] == 'value' || w['type'] == 'ac' ? 1 : 2),
    overflow: TextOverflow.ellipsis,
    style: pal.ios ? evoLabelStyle(w, pal.ink).copyWith(fontWeight: FontWeight.w600) : evoLabelStyle(w, pal.ink),
  );

  /// The small state line; [color] lights it up while the card is on.
  Widget _state(String s, {Color? color}) => Text(
    s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: fs(w, 'stateSize'), color: color ?? pal.muted, fontFeatures: const [FontFeature.tabularFigures()]),
  );

  Widget _icon(Color color) => iconWidget(w['icon'] as String?, fs(w, 'iconSize'), color);

  Widget _head(Color iconColor, {Widget? trailing}) => Row(
    children: [
      if (!isNoIcon(w['icon'] as String?)) ...[_icon(iconColor), const SizedBox(width: 8)],
      Expanded(child: _label()),
      if (trailing != null) ...[const SizedBox(width: 6), trailing],
    ],
  );

  Widget _led(bool on, Color c, {double scale = 1}) {
    if (pal.ios) {
      // iOS themes: the switch card shows an iOS switch, other cards show nothing here.
      if (w['type'] != 'switch') return const SizedBox.shrink();
      return IosSwitch(
        on: on,
        offTrack: pal.iosLight ? const Color(0xFFBDBDC2) : pal.ink.withValues(alpha: 0.16),
        onTrack: const Color(0xFF34C759),
        scale: scale,
      );
    }
    return _ledDot(on, c);
  }

  Widget _ledDot(bool on, Color c) => Container(
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
  Widget _slider(double v, Color c, {bool invert = false, String? bubble, bool showBubble = false}) {
    if (act == null) return _bar(v, c);
    if (pal.ios) return _iosSlider(v, c, invert: invert);
    final f = v.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, bc) {
        final width = bc.maxWidth;
        void at(double dx) {
          var n = ((dx - 8) / (width - 16) * 100).clamp(0.0, 100.0).round();
          if (invert) n = 100 - n;
          act!('preview', n);
        }

        return _sliderGrip(
          at: at,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              height: 22,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(color: _track, borderRadius: BorderRadius.circular(3)),
                  ),
                  FractionallySizedBox(
                    widthFactor: f,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  // Value bubble above the thumb while dragging (or always).
                  if (bubble != null && showBubble)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: -32,
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment(f * 2 - 1, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              bubble,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white, decoration: TextDecoration.none),
                            ),
                          ),
                        ),
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

  /// Track of a slider (the part not reached yet): a visible tint of the text
  /// color over the card, on every theme.
  Color get _track => Color.alphaBlend(pal.ink.withValues(alpha: 0.24), pal.tile == Colors.transparent ? pal.screen : pal.tile);

  Color get _iosTrack => pal.iosLight ? const Color(0xFFBDBDC2) : pal.ink.withValues(alpha: 0.14);

  /// The iOS slider; dragging it works like the normal one.
  /// The grip of a slider: it wins the gesture at the first touch (so a swipe between pages or a scroll cannot take it over),
  /// and follows the pointer with raw events: the value is set on touch and on every move, and sent when the finger lifts.
  Widget _sliderGrip({required void Function(double dx) at, required Widget child}) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: <Type, GestureRecognizerFactory>{
      EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(() => EagerGestureRecognizer(), (_) {}),
    },
    child: Listener(
      onPointerDown: (e) => at(e.localPosition.dx),
      onPointerMove: (e) => at(e.localPosition.dx),
      onPointerUp: (_) => act!('commit'),
      onPointerCancel: (_) => act!('commit'),
      child: child,
    ),
  );

  Widget _iosSlider(double v, Color c, {bool invert = false}) {
    final f = v.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, bc) {
        final width = bc.maxWidth;
        void at(double dx) {
          var n = ((dx - kIosKnobW / 2) / (width - kIosKnobW) * 100).clamp(0.0, 100.0).round();
          if (invert) n = 100 - n;
          act!('preview', n);
        }

        return _sliderGrip(
          at: at,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: IosSliderBar(f: f, fill: c, track: _iosTrack),
          ),
        );
      },
    );
  }

  Widget _bar(double v, Color c) => pal.ios
      ? IosSliderBar(f: v.clamp(0, 1).toDouble(), fill: c, track: _iosTrack)
      : ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: v.clamp(0, 1).toDouble(), minHeight: 4, backgroundColor: _track, color: c),
        );

  /// Simple look: icon (and optional control) on top, name below, no state
  /// text; on/off is shown by the card color.
  Widget _simple(Color iconColor, {Widget? trailing}) => Row(
    children: [
      if (!isNoIcon(w['icon'] as String?)) ...[_icon(iconColor), const SizedBox(width: 10)],
      Expanded(
        child: Text((w['label'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: evoLabelStyle(w, pal.ink)),
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
                            'No image',
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
          Text((w['label'] ?? '').toString(), maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: evoLabelStyle(w, pal.ink)),
        ],
      ],
    );
  }

  Widget _col(List<Widget> children) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: children);

  Widget _content(String type, bool on, Color colorOn, Color colorOff) {
    final style = jsonMap(w['style']);
    final textOn = (style['textOn'] ?? 'On').toString(), textOff = (style['textOff'] ?? 'Off').toString();
    // The state line of a switch or dimmer card can be hidden ("Show status" off).
    final showSt = w['showState'] != false;
    switch (type) {
      case 'switch':
        if (w['look'] == 'simple') return _simple(on ? colorOn : pal.muted);
        if (pal.ios) {
          // Like the Home app: icon and switch on top, the name (2 lines) and the state below. A low card keeps one row.
          return LayoutBuilder(
            builder: (context, bc) {
              final stateLine = _state(on ? textOn : textOff, color: on ? colorOn : null);
              final hasIcon = !isNoIcon(w['icon'] as String?);
              // Without a state line the stacked layout needs less height.
              if (bc.maxHeight < (showSt ? 68 : 56)) {
                // Low card: icon, name with the state under it, and the switch, all centred on one row.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (hasIcon) ...[_icon(on ? colorOn : pal.muted), const SizedBox(width: 8)],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(),
                          if (showSt && bc.maxHeight >= 44) ...[const SizedBox(height: 1), stateLine],
                        ],
                      ),
                    ),
                    _led(on, colorOn, scale: 0.7),
                  ],
                );
              }
              return _col([
                Row(children: [if (hasIcon) _icon(on ? colorOn : pal.muted), const Spacer(), _led(on, colorOn)]),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bc.maxHeight < 84 ? _label(maxLines: 1) : _label(),
                    if (showSt) ...[const SizedBox(height: 2), stateLine],
                  ],
                ),
              ]);
            },
          );
        }
        if (!showSt) return Center(child: _head(on ? colorOn : pal.muted, trailing: _led(on, colorOn)));
        return _col([_head(on ? colorOn : pal.muted, trailing: _led(on, colorOn)), _state(on ? textOn : textOff, color: on ? colorOn : null)]);
      case 'dimmer':
        if (w['look'] == 'simple') {
          return _simple(on ? colorOn : pal.muted, trailing: act == null && w['showTune'] == false ? null : _tuneBtn());
        }
        final v = ((sim['val'] as num?) ?? 0).toInt();
        return _col([
          _head(
            on ? colorOn : pal.muted,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // With a brightness slider only, the card already does it all: the button comes with RGB or color temperature.
                if (act != null && _hasColorTune) _tuneBtn(),
                const SizedBox(width: 4),
                _led(on, colorOn),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _slider(v / 100, colorOn),
              if (showSt) ...[const SizedBox(height: 6), _state(on ? '$textOn $v%' : textOff, color: on ? colorOn : null)],
            ],
          ),
        ]);
      case 'value':
        final g = _ga('status');
        final dpt = (g?['dpt'] ?? '').toString();
        // The value as received: a number, true/false or text (a date, a word…). While designing, a card in the Simple look shows a
        // sample of its type until it has a value.
        final raw = sim['val'] ?? sim['raw'] ?? (isStateValue(w) || !EvoHooks.samples ? null : dptSample(dpt));
        final vv = valueView(w, raw, dpt: dpt);
        final row = _stateRow();
        // The value with its unit, for a value that has no text of its own.
        final shown = vv.unit.isEmpty ? vv.text : '${vv.text} ${vv.unit}';
        if (isStateValue(w)) {
          final rowText = (row?['text'] ?? '').toString();
          final text = rowText.isNotEmpty ? rowText : (raw != null ? shown : (jsonList(w['states']).isEmpty ? 'No state set' : '–'));
          return _col([
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconWidget((row?['icon'] ?? w['icon'])?.toString(), fs(w, 'iconSize'), hexColor(row?['color']) ?? pal.muted),
                const Spacer(),
                if (row?['alarm'] == true) Icon(Icons.warning_amber, size: fs(w, 'iconSize') * 0.8, color: pal.danger),
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
                    fontSize: fs(w, 'valueSize'),
                    fontWeight: FontWeight.w600,
                    color: row == null ? pal.muted : (hexColor(row['color']) ?? pal.ink),
                  ),
                ),
              ],
            ),
          ]);
        }
        // Simple look: the value with its unit. A status that matches the value gives its own text, icon and color.
        final iconKey = (vv.row?['icon'] ?? w['icon'])?.toString();
        final rowColor = hexColor(vv.row?['color']);
        final iconColor = rowColor ?? pal.muted;
        final valueColor = rowColor ?? pal.ink;
        if (w['look'] == 'simple') {
          return LayoutBuilder(
            builder: (context, bc) => Row(
              children: [
                iconWidget(iconKey, fs(w, 'iconSize'), iconColor),
                const SizedBox(width: 8),
                // The name and the value share one text baseline (the icon stays centred), so the two texts line up.
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: _label()),
                      const SizedBox(width: 8),
                      // A long text never pushes the name out: the value takes at most a little over half of the row.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: bc.maxWidth * 0.55),
                        child: Text.rich(
                          // The line is as high as the name's: a bigger value grows over it and the name stays where it is.
                          strutStyle: StrutStyle(fontFamily: 'packages/evoknx_ui/Inter', fontSize: fs(w, 'labelSize'), height: 1.2, forceStrutHeight: true),
                          TextSpan(
                            text: vv.text,
                            style: TextStyle(fontSize: fs(w, 'valueSize'), color: valueColor, fontWeight: FontWeight.w500),
                            children: [
                              if (vv.unit.isNotEmpty)
                                TextSpan(
                                  text: ' ${vv.unit}',
                                  // Same size, color and weight as the value.
                                  style: TextStyle(fontSize: fs(w, 'valueSize'), color: valueColor, fontWeight: FontWeight.w500),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return _col([
          Row(
            children: [
              if (!isNoIcon(iconKey)) ...[iconWidget(iconKey, fs(w, 'iconSize'), iconColor), const SizedBox(width: 8)],
              Expanded(child: _label()),
              if (vv.row?['alarm'] == true) ...[const SizedBox(width: 6), Icon(Icons.warning_amber, size: fs(w, 'iconSize') * 0.8, color: pal.danger)],
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  vv.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: fs(w, 'valueSize'), color: valueColor, height: 1),
                ),
              ),
              if (vv.unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  vv.unit,
                  style: TextStyle(fontSize: fs(w, 'valueSize'), color: valueColor, height: 1),
                ),
              ],
            ],
          ),
        ]);
      case 'button':
        if (w['btnStyle'] == 'image') return _imageButton();
        return _col([_head(pal.muted), _state('Tap to send')]);
      case 'scene':
        if (w['btnStyle'] == 'image') return _imageButton();
        return _col([_head(pal.muted), _state('Tap to activate scene')]);
      case 'camera':
        final cam = jsonMap(w['cam']);
        if (cam['view'] == 'button') return _simple(pal.muted);
        if (w['style'] is Map && jsonMap(w['style'])['bg'] == 'transparent') {
          // Transparent card: the picture fills the card; the name sits on it, at the top, over a soft shade.
          final white = Colors.white;
          return Stack(
            fit: StackFit.expand,
            children: [
              CameraView(cam: cam, live: act != null, radius: 0),
              if (w['showHeader'] != false)
                // The shade and the name must not catch touches: the full screen button of the picture sits at the top right.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 40, 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: 0.5), Colors.black.withValues(alpha: 0)],
                        ),
                      ),
                      // The right side stays free for the full screen button of the picture.
                      child: Row(
                        children: [
                          if (!isNoIcon(w['icon'] as String?)) ...[iconWidget(w['icon'] as String?, fs(w, 'iconSize'), white), const SizedBox(width: 8)],
                          Flexible(
                            child: Text(
                              (w['label'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: evoLabelStyle(w, white).copyWith(fontWeight: pal.ios ? FontWeight.w600 : FontWeight.w400),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w['showHeader'] != false) ...[_head(pal.muted), const SizedBox(height: 8)],
            Expanded(
              child: CameraView(cam: cam, live: act != null),
            ),
          ],
        );
      case 'text':
        final t = jsonMap(w['txt']);
        final ha = (t['align'] ?? 'center').toString(), va = (t['valign'] ?? 'center').toString();
        return Align(
          alignment: Alignment(ha == 'left' ? -1 : (ha == 'right' ? 1 : 0), va == 'top' ? -1 : (va == 'bottom' ? 1 : 0)),
          child: Text(
            (t['content'] ?? '').toString(),
            textAlign: ha == 'left' ? TextAlign.left : (ha == 'right' ? TextAlign.right : TextAlign.center),
            style: TextStyle(
              fontSize: ((t['size'] as num?) ?? 20).toDouble().clamp(8, 200) * EvoScale.k,
              color: hexColor(t['color']) ?? pal.ink,
              fontWeight: t['bold'] == true ? FontWeight.w700 : FontWeight.w400,
              fontStyle: t['italic'] == true ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        );
      case 'link':
        final host = Uri.tryParse((w['url'] ?? '').toString())?.host ?? '';
        return _col([_head(pal.muted), _state(host.isEmpty ? 'No web address' : host)]);
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
                              host.isEmpty ? 'No web address' : host,
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
                              host.isEmpty ? 'Enter the web address in the properties' : 'The web page is shown here in the App',
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
        if (pal.ios) {
          // iOS: the name on top (the three dots at its right when the blind has a slider), the controls in the middle
          // and the state below; the slider-only blind shows its slider in the middle, like the dimmer.
          final stateText = showPct && showSt ? 'Open ${100 - p}%' : null;
          final hasIcon = !isNoIcon(w['icon'] as String?);
          final dots = ctrl == 'both' ? _tuneBtn() : null;
          final ib = fs(w, 'btnIcon') * 1.15;
          Widget ibtn(Object i, String a) => _ibtn(a, i, ib, pad: 6, tint: true);
          final controls = ctrl == 'slider'
              ? _slider((100 - p) / 100, pal.accent, invert: true)
              : Row(
                  children: [
                    ibtn(curtain ? 'mdi:arrow-expand-horizontal' : Icons.keyboard_arrow_up, 'up'),
                    if (w['showStop'] != false) ibtn(Icons.stop_outlined, 'stop'),
                    ibtn(curtain ? 'mdi:arrow-collapse-horizontal' : Icons.keyboard_arrow_down, 'down'),
                  ],
                );
          return LayoutBuilder(
            builder: (context, bc) {
              if (bc.maxHeight < 64) {
                // Low card: the name and the controls on one row.
                return Row(
                  children: [
                    if (hasIcon) ...[_icon(pal.muted), const SizedBox(width: 8)],
                    Expanded(flex: 2, child: _label(maxLines: 1)),
                    const SizedBox(width: 6),
                    Expanded(flex: 3, child: controls),
                    if (dots != null) dots,
                  ],
                );
              }
              // The rows follow each other (the controls right under the name) and the state sits at the bottom; it is shown
              // only when the card is tall enough, so nothing is ever cut.
              final need = 22 + 6 + (ib + 6) + fs(w, 'stateSize') * 1.4 + 3;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 22, child: _head(pal.muted, trailing: dots)),
                  if (stateText != null && bc.maxHeight >= need) ...[
                    // Enough room: the controls sit in the middle, the same gap above and below them.
                    const SizedBox(height: 6),
                    const Spacer(),
                    controls,
                    const Spacer(),
                    _state(stateText),
                  ] else ...[
                    // No state line: the controls sit in the middle of what is left below the name.
                    const SizedBox(height: 6),
                    const Spacer(),
                    Transform.translate(offset: const Offset(0, 4), child: controls),
                    const Spacer(),
                  ],
                ],
              );
            },
          );
        }
        return _col([
          _head(
            pal.muted,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPct && showSt) _state('Open ${100 - p}%'),
                if (ctrl != 'buttons') ...[const SizedBox(width: 6), _ibtn('tune', 'mdi:tune-vertical', fs(w, 'iconSize') * 0.7, expand: false, circle: true)],
              ],
            ),
          ),
          if (ctrl == 'slider')
            _slider((100 - p) / 100, pal.accent, invert: true)
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
        final step = acStep(ac);
        final mode = (sim['mode'] ?? 'cool').toString();
        final modes = jsonMap(ac['modes']);
        final names = jsonMap(ac['names']);
        final ab = fs(w, 'acBtn'), am = fs(w, 'acMode');
        final modeLabel = (ac['modeLabel'] ?? 'icon').toString();
        final showCur = ac['showCur'] != false && jsonMap(w['bind'])['current'] != null;
        Widget modeBtn(String key, String name, String icon, bool active) => modeLabel == 'icon'
            ? _ibtn(key == 'off' ? 'off' : 'mode', icon, am * 1.5, arg: key, fill: active ? pal.chipSel : pal.panel, fg: active ? pal.onChipSel : pal.muted)
            : Expanded(
                child: _tap(
                  key == 'off' ? 'off' : 'mode',
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: EdgeInsets.symmetric(vertical: modeLabel == 'icon' ? am * 0.55 : am * 0.35),
                    decoration: raisedDecoration(
                      pal,
                      active ? pal.chipSel : pal.panel,
                      radius: BorderRadius.circular(am * 0.62),
                      glow: active ? pal.chipSel : null,
                      lift: pal.lift,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (modeLabel != 'text') iconWidget(icon, am, active ? pal.onChipSel : pal.muted),
                        if (modeLabel == 'both') const SizedBox(height: 2),
                        if (modeLabel != 'icon')
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: modeLabel == 'text' ? am * 0.85 : am * 0.7, color: active ? pal.onChipSel : pal.muted),
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
        // ---- setpoint text, status line and slider (as on the dimmer)
        final dec = (step * 10 - (step * 10).roundToDouble()).abs() < 1e-9 ? 1 : 2;
        String tempText(num v) => v % 1 == 0 ? fmtNum(v, 0) : fmtNum(v, dec);
        final curMode = kAcModes.where((m) => m.key == mode).firstOrNull;
        // "Đang tắt", or the mode and the setpoint ("Cool - 25°C"); the fan-only mode has no setpoint.
        final status = !acOn ? 'Off' : [if (curMode != null) nm(curMode.key, curMode.name), if (curMode?.key != 'fan') '${tempText(sp)}°C'].join(' - ');
        final stepButtons = ac['stepButtons'] != false;
        Widget spSlider({bool always = false}) => Row(
          children: [
            if (stepButtons) _ibtn('minus', Icons.remove, ab * 1.2, expand: false, circle: true),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: stepButtons ? 10 : 0),
                child: _slider(
                  acFraction(ac, sp),
                  acOn ? colorOn : pal.muted.withValues(alpha: 0.7),
                  bubble: '${tempText(sp)}°',
                  showBubble: always || sim['drag'] == true,
                ),
              ),
            ),
            if (stepButtons) _ibtn('plus', Icons.add, ab * 1.2, expand: false, circle: true),
          ],
        );
        Widget modeRow() => Row(
          children: [
            modeBtn('off', nm('off', 'Off'), 'power', !acOn),
            for (final m in kAcModes)
              if (modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat') modeBtn(m.key, nm(m.key, m.name), m.icon, acOn && mode == m.key),
          ],
        );
        Widget fanRow() => Row(
          children: [
            for (final k in levels)
              _ibtn('fan', fanIcon(k), am * 1.5, arg: k, fill: acOn && fan == k ? pal.chipSel : pal.panel, fg: acOn && fan == k ? pal.onChipSel : pal.muted),
          ],
        );
        // Button of the card that opens the modes / fan popup.
        Widget tuneBtn() => _ibtn('popup', (ac['moreIcon'] ?? 'mdi:tune-variant').toString(), fs(w, 'iconSize') * 0.7, expand: false, circle: true);
        // Popup of a full card: modes and fan speed (the slider is on the card).
        if (w['look'] == 'controls') {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              modeRow(),
              if (fanOn) ...[SizedBox(height: am * 0.8), fanRow()],
            ],
          );
        }
        // Popup of a simple card: the slider too.
        if (w['look'] == 'controlsSp') {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              spSlider(always: true),
              SizedBox(height: am * 1.2),
              modeRow(),
              if (fanOn) ...[SizedBox(height: am * 0.8), fanRow()],
            ],
          );
        }
        if (w['look'] == 'simple') {
          return Row(
            children: [
              if (!isNoIcon(w['icon'] as String?)) ...[_icon(acOn ? colorOn : pal.muted), const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(),
                    const SizedBox(height: 2),
                    _state(status, color: acOn ? colorOn : null),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              tuneBtn(),
            ],
          );
        }
        return _col([
          _head(
            acOn ? colorOn : pal.muted,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showCur) ...[
                  Icon(Icons.thermostat, size: fs(w, 'stateSize') * 1.25, color: pal.muted),
                  _state('${fmtNum((sim['cur'] as num?) ?? 26.5, 1)}°C'),
                  const SizedBox(width: 8),
                ],
                tuneBtn(),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              spSlider(),
              const SizedBox(height: 6),
              _state(status, color: acOn ? colorOn : null),
            ],
          ),
        ]);
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
/// Lets the App play real video in camera cards (RTSP and HTTP): the Editor
/// cannot, so there it stays null and the card shows the address instead.
class EvoHooks {
  static Widget Function(BuildContext context, Json cam)? camera;

  /// A Value card with no value yet shows a sample of its type (design only). The App never does, and the Editor stops while it is
  /// connected to KNX: a card then shows only what the address returned ("–" until it has answered).
  static bool samples = true;
}

class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.cam, this.live = false, this.radius = 10});
  final Json cam;
  final bool live;
  final double radius;

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
    final hook = EvoHooks.camera;
    if (url.isEmpty) {
      body = placeholder('Enter the camera IP address in the properties');
    } else if (hook != null && live) {
      body = hook(context, cam);
    } else if (http && live) {
      final user = (cam['user'] ?? '').toString(), pass = (cam['pass'] ?? '').toString();
      body = Image.network(
        cameraUrl({...cam, 'user': '', 'pass': ''}),
        headers: user.isEmpty ? null : {'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}'},
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder('Could not get a picture from the camera.\n$url\nLive video plays in the App.'),
      );
    } else {
      body = placeholder('$url\nLive video plays in the App');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: const Color(0xFF15191B),
        child: SizedBox.expand(child: body),
      ),
    );
  }
}
