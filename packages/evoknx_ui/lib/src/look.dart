import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'tiles.dart';

/// A raised ("nổi") look for the control buttons of a card: a soft shadow
/// underneath, a solid lip below, a light edge and a gentle top-to-bottom
/// shade, so the button seems to stand above the card. [lift] makes the effect
/// stronger or weaker; [glow] adds a coloured halo (selected buttons).
BoxDecoration raisedDecoration(AppPalette pal, Color fill, {BorderRadius? radius, bool circle = false, Color? glow, Color? edge, double lift = 1}) {
  // Lift 0 (Tổng quan → Độ nổi nút) = a flat button.
  if (lift <= 0.01) {
    return BoxDecoration(
      color: fill,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : radius,
      border: Border.all(color: edge ?? pal.tileEdge),
    );
  }
  final dark = pal.ink.computeLuminance() > 0.5;
  final top = Color.lerp(fill, Colors.white, ((dark ? 0.14 : 0.50) * lift).clamp(0.0, 0.9))!;
  final bottom = Color.lerp(fill, Colors.black, ((dark ? 0.20 : 0.11) * lift).clamp(0.0, 0.55))!;
  // The shadow grows slowly with the lift so that it always stays inside the
  // card's padding (about 9 px at most): it is never cut off.
  final blur = 3 + 1.2 * lift, drop = 0.8 + 0.7 * lift;
  return BoxDecoration(
    shape: circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circle ? null : radius,
    // A bevel made of the colour itself, inside the button: a light rim on top,
    // the body, a darker rim below. It needs no room outside the button.
    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, fill, fill, bottom], stops: const [0, 0.14, 0.76, 1]),
    border: Border.all(color: edge ?? (dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.85))),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: ((dark ? 0.28 : 0.13) * lift).clamp(0.0, 0.45)),
        blurRadius: blur,
        offset: Offset(0, drop),
      ),
      if (glow != null)
        BoxShadow(
          color: glow.withValues(alpha: dark ? 0.30 : 0.35),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
    ],
  );
}

/// "Độ nổi nút" (0–100 %, default 60) as the lift used by [raisedDecoration].
double liftOf(num percent) => percent.clamp(0, 100) * 0.0267;

/// Flat look of the navigation buttons (floors, rooms, pages, settings).
BoxDecoration flatDecoration(AppPalette pal, Color fill, {BorderRadius? radius, bool circle = false, Color? glow}) => BoxDecoration(
  color: fill,
  shape: circle ? BoxShape.circle : BoxShape.rectangle,
  borderRadius: circle ? null : radius,
  border: Border.all(color: glow != null ? fill : pal.tileEdge),
);

/// Small preview of a theme: its screen colour, a card and the accent dot.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch(this.pal, {super.key, this.size = 30});
  final AppPalette pal;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pal.screen,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: pal.lineStrong),
      ),
      child: Stack(
        children: [
          Positioned(
            left: size * 0.14,
            bottom: size * 0.14,
            child: Container(
              width: size * 0.44,
              height: size * 0.34,
              decoration: BoxDecoration(color: pal.tileOn ?? pal.tile, borderRadius: BorderRadius.circular(size * 0.1)),
            ),
          ),
          Positioned(
            right: size * 0.14,
            top: size * 0.14,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(color: pal.chipSel, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shadow (and the glow of a lit card) of one card, drawn only OUTSIDE the
/// card's shape. The grid puts all of them in one layer under every card, so a
/// shadow never falls on another card's body and never shows through a card
/// whose background is faded.
class CardShadow extends StatelessWidget {
  const CardShadow({super.key, required this.radius, required this.pal, this.glow});
  final double radius;
  final AppPalette pal;

  /// "On" colour of a lit card: adds a soft glow.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final list = <BoxShadow>[...pal.shadows, if (glow != null) BoxShadow(color: glow!.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))];
    if (list.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: _ShadowPainter(radius, list), size: Size.infinite),
    );
  }
}

class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.radius, this.shadows);
  final double radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(-120, -120, size.width + 240, size.height + 240)),
      Path()..addRRect(rrect),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      canvas.drawRRect(rrect.shift(s.offset).inflate(s.spreadRadius), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => old.radius != radius || !listEquals(old.shadows, shadows);
}
