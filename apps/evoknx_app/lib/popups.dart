import 'dart:ui' show ImageFilter;

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

/// Scene confirmation: blurs the screen behind, shows the picture or icon and
/// the message, then closes by itself (up to 5 seconds, as set in the Editor).
Future<void> showScenePopup(BuildContext context, Json w, AppPalette pal) {
  final pp = jsonMap(w['popup']);
  if (pp['enabled'] == false) return Future<void>.value();
  final blur = ((pp['blur'] as num?) ?? 8).toDouble().clamp(0, 30).toDouble();
  final size = ((pp['size'] as num?) ?? 20).toDouble().clamp(12, 40).toDouble();
  final secs = ((pp['seconds'] as num?) ?? 2).toDouble().clamp(0.5, 5.0);
  final label = (w['label'] ?? '').toString();
  final text = ((pp['text'] ?? 'Scene {name} activated').toString()).replaceAll('{name}', label).replaceAll('{tên}', label).replaceAll('{ten}', label);
  final image = w['btnStyle'] == 'image' && w['imgSource'] != 'icon' ? imageFromData((w['image'] ?? '').toString()) : null;
  final iconKey = w['btnStyle'] == 'image' && w['imgSource'] == 'icon' ? (w['imgIcon'] ?? 'mdi:gesture-tap-button').toString() : (w['icon'] as String?);
  var open = true;
  final shown = showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (c, a, b) => GestureDetector(
      onTap: () => Navigator.of(c).maybePop(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.12),
          child: Center(
            child: Material(
              color: pal.tile.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(22),
              elevation: 8,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 72, height: 72, child: image ?? Center(child: iconWidget(iconKey, 50, pal.accent))),
                    const SizedBox(height: 14),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: pal.ink, height: 1.25),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (c, a, b, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
      child: child,
    ),
  ).whenComplete(() => open = false);
  Future<void>.delayed(Duration(milliseconds: (secs * 1000).round()), () {
    if (open && context.mounted) Navigator.of(context, rootNavigator: true).maybePop();
  });
  return shown;
}

/// Brightness slider (and color temperature / RGB when the card has them).
void showDimmerSheet(BuildContext context, CardEngine engine, Json w, AppPalette pal) {
  if (pal.ios) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: false,
      builder: (c) => _IosDimmerSheet(engine: engine, w: w, pal: pal),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => _DimmerSheet(engine: engine, w: w, pal: pal),
  );
}

/// The blind popup of an iOS theme: like the dimmer one, with a tall bar for how far the blind is open.
class _IosShutterSheet extends StatelessWidget {
  const _IosShutterSheet({required this.engine, required this.w, required this.pal});
  final CardEngine engine;
  final Json w;
  final AppPalette pal;

  @override
  Widget build(BuildContext context) {
    final light = pal.iosLight;
    final bg = light ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E);
    final card = light ? Colors.white : const Color(0xFF3A3A3C);
    final maxH = MediaQuery.of(context).size.height * 0.88;
    // Like the dimmer popup: a bar three times as tall as wide, smaller on a short screen.
    final barH = (maxH - 150).clamp(180.0, 330.0);
    final barW = barH / 3;
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final p = ((engine.st(w['id'] as String)['pos'] as num?) ?? 0).toInt().clamp(0, 100);
        // The number is how far the blind is open (like the card); the bar fills from the bottom: drag up to open.
        final v = 100 - p;
        void at(double dy) => engine.act(w, 'preview', (100 - (1 - dy / barH) * 100).clamp(0, 100).round());
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (w['label'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: pal.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(p >= 100 ? 'Closed' : (p <= 0 ? 'Open' : 'Open · $v%'), style: TextStyle(fontSize: 15, color: pal.muted)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: card, shape: BoxShape.circle),
                          child: Icon(Icons.close, size: 18, color: pal.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => at(d.localPosition.dy),
                      onTapUp: (_) => engine.act(w, 'commit'),
                      onVerticalDragStart: (d) => at(d.localPosition.dy),
                      onVerticalDragUpdate: (d) => at(d.localPosition.dy),
                      onVerticalDragEnd: (_) => engine.act(w, 'commit'),
                      onVerticalDragCancel: () => engine.act(w, 'commit'),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: SizedBox(
                          width: barW,
                          height: barH,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Positioned.fill(child: ColoredBox(color: card)),
                              AnimatedContainer(duration: const Duration(milliseconds: 80), height: barH * v / 100, color: pal.accent),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  '$v%',
                                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: v > 14 ? Colors.white : pal.ink),
                                ),
                              ),
                            ],
                          ),
                        ),
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
}

/// The dimmer popup of an iOS theme, like the Home app: a tall brightness bar and the colors; a second page picks any color.
class _IosDimmerSheet extends StatefulWidget {
  const _IosDimmerSheet({required this.engine, required this.w, required this.pal});
  final CardEngine engine;
  final Json w;
  final AppPalette pal;
  @override
  State<_IosDimmerSheet> createState() => _IosDimmerSheetState();
}

class _IosDimmerSheetState extends State<_IosDimmerSheet> {
  static const _swatches = ['#FFFFFF', '#FF3B30', '#FF9500', '#AF52DE', '#34C759', '#007AFF'];
  bool _picker = false;
  bool _temp = false;
  double _h = 0, _sat = 1;
  double? _ct;

  AppPalette get pal => widget.pal;
  Json get w => widget.w;
  CardEngine get engine => widget.engine;
  bool get _light => pal.iosLight;
  Color get _bg => _light ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E);
  Color get _card => _light ? Colors.white : const Color(0xFF3A3A3C);
  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Widget _close() => GestureDetector(
    onTap: () => Navigator.of(context).maybePop(),
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: _card, shape: BoxShape.circle),
      child: Icon(Icons.close, size: 18, color: pal.ink),
    ),
  );

  /// "Edit color…" and "Done": the same compact pill, centred.
  Widget _wideButton(String text, VoidCallback onTap) => Center(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24)),
        child: Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF007AFF)),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = jsonMap(w['features']);
    final hasRgb = f['rgb'] == true, hasTw = f['tw'] == true;
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final s = engine.st(w['id'] as String);
        final val = ((s['val'] as num?) ?? 0).toInt().clamp(0, 100);
        final lit = hexColor(s['rgb']) ?? pal.led;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              child: _picker ? _pickerPage(s, hasRgb, hasTw, lit) : _mainPage(s, val, lit, hasRgb, hasTw),
            ),
          ),
        );
      },
    );
  }

  Widget _mainPage(Json s, int val, Color lit, bool hasRgb, bool hasTw) {
    final title = (w['label'] ?? '').toString();
    // The bar is three times as tall as wide: 110 x 330 at most, smaller on a short screen so the popup still fits.
    final room = MediaQuery.of(context).size.height * 0.88 - 150 - (hasRgb ? 58 : 0) - (hasRgb || hasTw ? 66 : 0);
    final barH = room.clamp(180.0, 330.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: pal.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(val > 0 ? 'On · $val%' : 'Off', style: TextStyle(fontSize: 15, color: pal.muted)),
                ],
              ),
            ),
            _close(),
          ],
        ),
        const SizedBox(height: 18),
        Center(child: _bar(val, lit, barH / 3, barH)),
        if (hasRgb) ...[
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 12,
            children: [
              for (final hx in _swatches)
                GestureDetector(
                  onTap: () => engine.act(w, 'rgb', hx),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: hexColor(hx),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s['rgb'] == hx ? const Color(0xFF007AFF) : (hx == '#FFFFFF' ? pal.line : Colors.transparent),
                        width: s['rgb'] == hx ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (hasRgb || hasTw) ...[
          const SizedBox(height: 18),
          _wideButton('Edit color…', () {
            final c = hexColor(s['rgb']) ?? Colors.white;
            final hsv = HSVColor.fromColor(c);
            setState(() {
              _h = hsv.hue;
              _sat = hsv.saturation;
              _temp = !hasRgb && hasTw;
              _picker = true;
            });
          }),
        ],
      ],
    );
  }

  /// The tall brightness bar: drag up or down, the percentage shows in it.
  Widget _bar(int val, Color lit, double w0, double h0) {
    void at(double dy) => engine.act(w, 'preview', ((1 - dy / h0) * 100).clamp(0, 100).round());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => at(d.localPosition.dy),
      onTapUp: (_) => engine.act(w, 'commit'),
      onVerticalDragStart: (d) => at(d.localPosition.dy),
      onVerticalDragUpdate: (d) => at(d.localPosition.dy),
      onVerticalDragEnd: (_) => engine.act(w, 'commit'),
      onVerticalDragCancel: () => engine.act(w, 'commit'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: w0,
          height: h0,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned.fill(child: ColoredBox(color: _card)),
              AnimatedContainer(duration: const Duration(milliseconds: 80), height: h0 * val / 100, color: lit),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  '$val%',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: val > 14 ? Colors.white : pal.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerPage(Json s, bool hasRgb, bool hasTw, Color lit) {
    final tw = jsonMap(w['tw']);
    final ctMin = ((tw['min'] as num?) ?? 2700).toDouble(), ctMax = ((tw['max'] as num?) ?? 6500).toDouble();
    final ct = (_ct ?? ((s['ct'] as num?) ?? ctMin).toDouble()).clamp(ctMin, ctMax);
    Widget tab(String text, bool on, VoidCallback tap) => Expanded(
      child: GestureDetector(
        onTap: tap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? _card : Colors.transparent, borderRadius: BorderRadius.circular(18)),
          child: Text(
            text,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.ink),
          ),
        ),
      ),
    );
    const bw = 300.0, bh = 300.0;
    final cur = HSVColor.fromAHSV(1, _h, _sat, 1).toColor();
    void pick(Offset o) => setState(() {
      _h = (o.dx / bw * 360).clamp(0.0, 359.9);
      _sat = (1 - o.dy / bh).clamp(0.0, 1.0);
    });
    void setCt(double dy) => setState(() => _ct = ((((1 - dy / bh).clamp(0.0, 1.0)) * (ctMax - ctMin) + ctMin) / 50).round() * 50.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose color',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: pal.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(_temp ? 'Drag to pick a color temperature' : 'Drag on the board to pick a hue', style: TextStyle(fontSize: 15, color: pal.muted)),
                ],
              ),
            ),
            _close(),
          ],
        ),
        const SizedBox(height: 16),
        if (hasRgb && hasTw)
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: _light ? const Color(0xFFE3E3E8) : const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [tab('Color', !_temp, () => setState(() => _temp = false)), tab('Temperature', _temp, () => setState(() => _temp = true))]),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: bh,
          child: Center(
            child: _temp
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => setCt(d.localPosition.dy),
                    onVerticalDragStart: (d) => setCt(d.localPosition.dy),
                    onVerticalDragUpdate: (d) => setCt(d.localPosition.dy),
                    onVerticalDragEnd: (_) => engine.act(w, 'ct', (_ct ?? ct).round()),
                    onTapUp: (_) => engine.act(w, 'ct', (_ct ?? ct).round()),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: SizedBox(
                        width: 110,
                        height: bh,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFFB9D6FF), Color(0xFFFFFFFF), Color(0xFFFFE9C7), Color(0xFFFFA64D)],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (1 - (ct - ctMin) / (ctMax - ctMin)) * (bh - 8),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.symmetric(horizontal: BorderSide(color: const Color(0x33000000), width: 0.5)),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 12,
                              child: Text(
                                '${ct.round()} K',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => pick(d.localPosition),
                    onPanStart: (d) => pick(d.localPosition),
                    onPanUpdate: (d) => pick(d.localPosition),
                    onPanEnd: (_) => engine.act(w, 'rgb', _hex(cur)),
                    onTapUp: (_) => engine.act(w, 'rgb', _hex(cur)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: SizedBox(
                        width: bw,
                        height: bh,
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFFF0000),
                                      Color(0xFFFFFF00),
                                      Color(0xFF00FF00),
                                      Color(0xFF00FFFF),
                                      Color(0xFF0000FF),
                                      Color(0xFFFF00FF),
                                      Color(0xFFFF0000),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: _h / 360 * bw - 17,
                              top: (1 - _sat) * bh - 17,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: cur,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        _wideButton('Done', () => setState(() => _picker = false)),
      ],
    );
  }
}

class _DimmerSheet extends StatelessWidget {
  const _DimmerSheet({required this.engine, required this.w, required this.pal});
  final CardEngine engine;
  final Json w;
  final AppPalette pal;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final s = engine.st(w['id'] as String);
        final f = jsonMap(w['features']);
        final tw = jsonMap(w['tw']);
        final ctMin = ((tw['min'] as num?) ?? 2700).toDouble(), ctMax = ((tw['max'] as num?) ?? 6500).toDouble();
        final val = ((s['val'] as num?) ?? 0).toDouble().clamp(0.0, 100.0);
        const swatches = ['#FFFFFF', '#FFB347', '#FF5E5E', '#FF4FA3', '#9B6BFF', '#4D8DFF', '#36C5D6', '#3DCB7A', '#F5E663'];
        TextStyle label() => TextStyle(fontSize: 15, color: pal.muted);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (w['label'] ?? '').toString(),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.ink),
                      ),
                    ),
                    Text(
                      '${val.round()}%',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Brightness', style: label()),
                Slider(
                  value: val,
                  max: 100,
                  divisions: 100,
                  activeColor: pal.accent,
                  onChanged: (v) => engine.act(w, 'preview', v.round()),
                  onChangeEnd: (v) => engine.act(w, 'set', v.round()),
                ),
                if (f['tw'] == true) ...[
                  const SizedBox(height: 8),
                  Text('Color temperature: ${((s['ct'] as num?) ?? ctMin).round()} K', style: label()),
                  Slider(
                    value: (((s['ct'] as num?) ?? ctMin).toDouble()).clamp(ctMin, ctMax),
                    min: ctMin,
                    max: ctMax,
                    activeColor: pal.accent,
                    onChanged: (v) => s['ct'] = (v / 50).round() * 50,
                    onChangeEnd: (v) => engine.act(w, 'ct', (v / 50).round() * 50),
                  ),
                ],
                if (f['rgb'] == true) ...[
                  const SizedBox(height: 8),
                  Text('Color', style: label()),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final hx in swatches)
                        GestureDetector(
                          onTap: () => engine.act(w, 'rgb', hx),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: hexColor(hx),
                              shape: BoxShape.circle,
                              border: Border.all(color: s['rgb'] == hx ? pal.ink : pal.tileEdge, width: s['rgb'] == hx ? 2.5 : 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Position slider of a blind that has one next to its buttons.
void showShutterSheet(BuildContext context, CardEngine engine, Json w, AppPalette pal) {
  if (pal.ios) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: false,
      builder: (c) => _IosShutterSheet(engine: engine, w: w, pal: pal),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: ListenableBuilder(
          listenable: engine,
          builder: (context, _) {
            final p = ((engine.st(w['id'] as String)['pos'] as num?) ?? 0).toDouble().clamp(0.0, 100.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (w['label'] ?? '').toString(),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.ink),
                      ),
                    ),
                    Text(
                      'Open ${100 - p.round()}%',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Slider(
                  value: 100 - p,
                  max: 100,
                  divisions: 100,
                  activeColor: pal.accent,
                  onChanged: (v) => engine.act(w, 'preview', (100 - v).round()),
                  onChangeEnd: (v) => engine.act(w, 'set', (100 - v).round()),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// The air conditioner's modes and fan speeds (simple card).
void showAcControls(BuildContext context, CardEngine engine, Json w, AppPalette pal, List<Json> gas) {
  // Simple card: the popup also holds the temperature slider.
  final simple = w['look'] == 'simple';
  final full = {...w, 'look': simple ? 'controlsSp' : 'controls'};
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: ListenableBuilder(
          listenable: engine,
          builder: (context, _) {
            final fan = jsonMap(jsonMap(w['ac'])['fan'])['enabled'] == true;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (w['label'] ?? '').toString(),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.ink),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: (fan ? 190 : 110) + (simple ? 96 : 0),
                  child: TileView(
                    w: full,
                    pal: pal.copyWith(tile: Colors.transparent),
                    gas: gas,
                    sim: engine.st(w['id'] as String),
                    act: (a, [x]) => engine.act(w, a, x),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Camera popup: the live picture of the camera (RTSP or HTTP).
void showCamera(BuildContext context, Json w) {
  final cam = jsonMap(w['cam']);
  showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          children: [
            Positioned.fill(child: CameraView(cam: cam, live: true)),
            Positioned(
              left: 14,
              top: 12,
              child: Text(
                (w['label'] ?? '').toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
