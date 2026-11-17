import 'package:flutter/material.dart';

/// The press feedback of iOS: while a finger is down the child fades to [pressedOpacity];
/// no ripple and no light patch.
class PressFade extends StatefulWidget {
  const PressFade({super.key, required this.child, this.onTap, this.pressedOpacity = 0.4});
  final Widget child;
  final VoidCallback? onTap;
  final double pressedOpacity;

  @override
  State<PressFade> createState() => _PressFadeState();
}

class _PressFadeState extends State<PressFade> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedOpacity(
        opacity: _down ? widget.pressedOpacity : 1,
        duration: Duration(milliseconds: _down ? 60 : 180),
        child: widget.child,
      ),
    );
  }
}

/// Tells its child whether a finger is down on it (a Listener, so it never steals taps or drags). Used to light a button with
/// the accent color while it is pressed.
class PressTint extends StatefulWidget {
  const PressTint({super.key, required this.builder});
  final Widget Function(bool down) builder;

  @override
  State<PressTint> createState() => _PressTintState();
}

class _PressTintState extends State<PressTint> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(onPointerDown: (_) => _set(true), onPointerUp: (_) => _set(false), onPointerCancel: (_) => _set(false), child: widget.builder(_down));
  }
}
