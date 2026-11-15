import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The switch of the iOS themes (iOS 26 look): a capsule track and a wide white capsule knob that slides.
class IosSwitch extends StatelessWidget {
  const IosSwitch({super.key, required this.on, required this.offTrack, this.onTrack = const Color(0xFF34C759), this.scale = 1});

  final bool on;

  /// Track color while off.
  final Color offTrack;

  /// Track color while on (iOS green).
  final Color onTrack;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final w = 60.0 * scale, h = 28.0 * scale, kw = 38.0 * scale, kh = 24.0 * scale;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: w,
      height: h,
      decoration: BoxDecoration(color: on ? onTrack : offTrack, borderRadius: BorderRadius.circular(h / 2)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 2 * scale),
          width: kw,
          height: kh,
          decoration: glassDeco(radius: BorderRadius.circular(kh / 2)),
        ),
      ),
    );
  }
}

/// The slider of the iOS themes: a thick rounded track with a fill and a white capsule knob. [f] is 0…1.
/// Width of the knob of the iOS slider (the value is measured from the centre of the knob).
const double kIosKnobW = 36;

class IosSliderBar extends StatelessWidget {
  const IosSliderBar({super.key, required this.f, required this.fill, required this.track});

  final double f;
  final Color fill, track;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bc) {
        final width = bc.maxWidth.isFinite ? bc.maxWidth : 200.0;
        const kw = kIosKnobW, kh = 24.0, th = 8.0, h = 28.0;
        final x = (width - kw) * f.clamp(0.0, 1.0);
        return SizedBox(
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: (h - th) / 2,
                child: Container(
                  height: th,
                  decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(th / 2)),
                ),
              ),
              Positioned(
                left: 0,
                top: (h - th) / 2,
                child: Container(
                  width: x + kw / 2,
                  height: th,
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(th / 2)),
                ),
              ),
              Positioned(
                left: x,
                top: (h - kh) / 2,
                child: Container(
                  width: kw,
                  height: kh,
                  decoration: glassDeco(radius: BorderRadius.circular(kh / 2)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The look of a small piece of glass (a knob, a round button): a soft light gradient and a bright rim.
BoxDecoration glassDeco({bool dark = false, BorderRadius? radius, bool circle = false, double alpha = 1}) => BoxDecoration(
  shape: circle ? BoxShape.circle : BoxShape.rectangle,
  borderRadius: circle ? null : radius,
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: dark
        ? [Colors.white.withValues(alpha: 0.30 * alpha), Colors.white.withValues(alpha: 0.12 * alpha)]
        : [Colors.white.withValues(alpha: 0.98 * alpha), const Color(0xFFEFF1F6).withValues(alpha: 0.92 * alpha)],
  ),
  border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.35 : 0.9), width: 0.8),
  boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 6, offset: Offset(0, 2))],
);

/// A bar or panel of glass: it blurs what is behind it (a page background image shows through), with a light tint and a bright rim.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, required this.radius, this.dark = false, this.blur = 22});

  final Widget child;
  final double radius;
  final bool dark;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: _RimPainter(radius, dark),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.06)]
                      : [Colors.white.withValues(alpha: 0.62), Colors.white.withValues(alpha: 0.32)],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.radius, this.dark);
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.55 : 0.95),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: dark ? 0.25 : 0.6),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(_RimPainter o) => o.radius != radius || o.dark != dark;
}
