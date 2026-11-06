import 'package:flutter/material.dart';

import 'tiles.dart';

/// A raised ("nổi") look for buttons: a soft shadow underneath, a light edge
/// and a gentle top-to-bottom shade, so a button seems to float above the card.
/// [glow] adds a coloured halo (used by selected buttons).
BoxDecoration raisedDecoration(AppPalette pal, Color fill, {BorderRadius? radius, bool circle = false, Color? glow, Color? edge}) {
  final dark = pal.ink.computeLuminance() > 0.5;
  final top = Color.lerp(fill, Colors.white, dark ? 0.10 : 0.45)!;
  final bottom = Color.lerp(fill, Colors.black, dark ? 0.16 : 0.07)!;
  return BoxDecoration(
    shape: circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circle ? null : radius,
    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
    border: Border.all(color: edge ?? (dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.85))),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.40 : 0.16),
        blurRadius: 6,
        offset: const Offset(0, 2.5),
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
