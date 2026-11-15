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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(kh / 2),
            boxShadow: const [
              BoxShadow(color: Color(0x2E000000), blurRadius: 6, offset: Offset(0, 2)),
              BoxShadow(color: Color(0x1F000000), blurRadius: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// The slider of the iOS themes: a thick rounded track with a fill and a white capsule knob. [f] is 0…1.
class IosSliderBar extends StatelessWidget {
  const IosSliderBar({super.key, required this.f, required this.fill, required this.track});

  final double f;
  final Color fill, track;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bc) {
        final width = bc.maxWidth.isFinite ? bc.maxWidth : 200.0;
        const kw = 36.0, kh = 24.0, th = 8.0, h = 28.0;
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(kh / 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
                      BoxShadow(color: Color(0x1F000000), blurRadius: 1),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
