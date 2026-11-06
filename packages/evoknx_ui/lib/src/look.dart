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
  final top = Color.lerp(fill, Colors.white, ((dark ? 0.10 : 0.45) * lift).clamp(0.0, 0.85))!;
  final bottom = Color.lerp(fill, Colors.black, ((dark ? 0.16 : 0.07) * lift).clamp(0.0, 0.5))!;
  return BoxDecoration(
    shape: circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circle ? null : radius,
    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
    border: Border.all(color: edge ?? (dark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.9))),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: ((dark ? 0.40 : 0.16) * lift).clamp(0.0, 0.6)),
        blurRadius: 6 * lift,
        offset: Offset(0, 2.5 * lift),
      ),
      // A solid lip under the button, like its thickness.
      if (lift > 1)
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.35 : 0.13),
          offset: const Offset(0, 1.5),
        ),
      if (glow != null)
        BoxShadow(
          color: glow.withValues(alpha: dark ? 0.35 : 0.40),
          blurRadius: 12,
          offset: const Offset(0, 3),
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
