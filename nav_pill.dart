import 'package:flutter/material.dart';

/// A row of [count] equal items with one pill behind them that slides to the [selected] one (as the bar of YouTube).
/// A [selected] below 0 hides the pill.
class SlidingPillRow extends StatelessWidget {
  const SlidingPillRow({super.key, required this.count, required this.selected, required this.color, required this.children});
  final int count, selected;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final has = selected >= 0 && selected < count;
    final x = count <= 1 ? 0.0 : -1.0 + 2.0 * (has ? selected : 0) / (count - 1);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment(x, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: has ? 1 : 0,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ),
        ),
        Row(children: children),
      ],
    );
  }
}
