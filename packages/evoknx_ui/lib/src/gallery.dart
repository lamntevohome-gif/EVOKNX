import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import 'i18n.dart' show tr;
import 'icons.dart';
import 'model.dart';
import 'tiles.dart';

final Map<String, MemoryImage> _covers = {};

MemoryImage? _coverOf(String data) {
  final i = data.indexOf('base64,');
  if (i < 0) return null;
  return _covers['${data.length}:${data.hashCode}'] ??= MemoryImage(base64Decode(data.substring(i + 7)));
}

/// Fades the top and the bottom edge of a scrolling list, so the cards that slide under the title or the bar melt away instead of
/// being cut. Each fade grows with the distance scrolled (up to [fade]), so at rest, at the start or the end of the list, none is seen.
Widget edgeFade(Widget child, {double fade = 44}) => _EdgeFade(fade: fade, child: child);

class _EdgeFade extends StatefulWidget {
  const _EdgeFade({required this.child, required this.fade});
  final Widget child;
  final double fade;

  @override
  State<_EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<_EdgeFade> {
  double _top = 0, _bottom = 0;

  bool _onNote(Notification n) {
    ScrollMetrics? m;
    if (n is ScrollNotification) m = n.metrics;
    if (n is ScrollMetricsNotification) m = n.metrics;
    if (m == null || m.axis != Axis.vertical) return false;
    final top = m.pixels.clamp(0.0, widget.fade).toDouble();
    final bottom = (m.maxScrollExtent - m.pixels).clamp(0.0, widget.fade).toDouble();
    if ((top - _top).abs() > 0.5 || (bottom - _bottom).abs() > 0.5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          setState(() {
            _top = top;
            _bottom = bottom;
          });
      });
    }
    return false;
  }

  /// A strip at one edge that blurs what is under it more and more towards the edge (a few bands, each a little stronger than the
  /// one inside it), like the scroll edge of iOS. [k] (0..1) is how far the fade has grown, so the blur grows with it.
  Widget _blur({required bool top, required double height, required double k}) {
    const bands = 6;
    const maxSigma = 3.0;
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: Column(
          children: [
            for (var i = 0; i < bands; i++)
              Expanded(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: maxSigma * k * (top ? (bands - i) : (i + 1)) / bands,
                      sigmaY: maxSigma * k * (top ? (bands - i) : (i + 1)) / bands,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => NotificationListener<Notification>(
    onNotification: _onNote,
    child: Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final h = rect.height <= 0 ? 1.0 : rect.height;
              final top = (_top / h).clamp(0.0, 0.5), bottom = (_bottom / h).clamp(0.0, 0.5);
              // An eased ramp (smoothstep) instead of a straight one: the fade starts and ends softly, with no visible edge.
              const steps = 8;
              final colors = <Color>[], stops = <double>[];
              for (var i = 0; i <= steps; i++) {
                final t = i / steps, e = t * t * (3 - 2 * t);
                colors.add(Color.fromRGBO(0, 0, 0, e));
                stops.add(top * t);
              }
              for (var i = 0; i <= steps; i++) {
                final t = i / steps, e = t * t * (3 - 2 * t);
                colors.add(Color.fromRGBO(0, 0, 0, 1 - e));
                stops.add(1 - bottom + bottom * t);
              }
              return LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: stops).createShader(rect);
            },
            child: widget.child,
          ),
        ),
        if (_top > 1) _blur(top: true, height: _top, k: _top / widget.fade),
        if (_bottom > 1) _blur(top: false, height: _bottom, k: _bottom / widget.fade),
      ],
    ),
  );
}

/// The room gallery: a grid of room cards (cover image or color, icon, name).
/// Tapping a card opens the room. Used by the App and by the Editor preview.
class RoomGallery extends StatelessWidget {
  const RoomGallery({super.key, required this.doc, required this.rooms, required this.pal, required this.onOpen, this.unlocked, this.showIcons = true});

  final Json doc;
  final List<Json> rooms;
  final AppPalette pal;
  final void Function(String roomId) onOpen;

  /// The icon of each card (the cards of floors have none).
  final bool showIcons;

  /// Ids of the locks that are open (a card with a lock that is not in this set shows a padlock).
  final Set<String>? unlocked;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
            tr('This floor has no rooms yet.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: pal.sMuted),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        // The same cards as the Area screen: 4:3, two columns (more on a wide screen).
        final cols = w >= 1000 ? 4 : (w >= 760 ? 3 : 2);
        return edgeFade(
          GridView.builder(
            padding: EdgeInsets.all(pal.safeMargin),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 4 / 3),
            itemCount: rooms.length,
            itemBuilder: (context, i) => _RoomCard(
              doc: doc,
              room: rooms[i],
              pal: pal,
              showIcon: showIcons,
              locked: RegExp(r'^\d{4}$').hasMatch((rooms[i]['lock'] ?? '').toString()) && !(unlocked?.contains(rooms[i]['id']) ?? false),
              onTap: () => onOpen(rooms[i]['id'] as String),
            ),
          ),
        );
      },
    );
  }
}

/// The Area screen of the Modern layout: every floor with rooms is a heading (a padlock when it is locked)
/// with its rooms under it, in two columns of 4:3 cards (more on a wide screen). A floor without rooms is left out.
class AreaList extends StatefulWidget {
  const AreaList({
    super.key,
    required this.doc,
    required this.floors,
    required this.pal,
    required this.onOpenRoom,
    this.unlocked,
    this.scrollToFloor,
    this.scrollSeq = 0,
  });
  final Json doc;
  final List<Json> floors;
  final AppPalette pal;
  final void Function(String roomId) onOpenRoom;

  /// Ids of the locks that are open.
  final Set<String>? unlocked;

  /// The floor to scroll to when the screen is built, and again whenever [scrollSeq] changes.
  final String? scrollToFloor;
  final int scrollSeq;

  @override
  State<AreaList> createState() => _AreaListState();
}

class _AreaListState extends State<AreaList> {
  final Map<String, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _scroll();
  }

  @override
  void didUpdateWidget(AreaList old) {
    super.didUpdateWidget(old);
    if (old.scrollSeq != widget.scrollSeq) _scroll();
  }

  void _scroll() {
    final id = widget.scrollToFloor;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final doc = widget.doc;
    final groups = [
      for (final f in widget.floors)
        if (roomsOf(doc, f['id'] as String).isNotEmpty) (f, roomsOf(doc, f['id'] as String)),
    ];
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
            tr('There are no rooms yet.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: pal.sMuted),
          ),
        ),
      );
    }
    // The name of a floor has its own size; the text on the room cards follows the card size of the floor.
    final hs = tfs(doc, 'areaFloor');
    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        final cols = w >= 1000 ? 4 : (w >= 760 ? 3 : 2);
        return edgeFade(
          SingleChildScrollView(
            padding: EdgeInsets.all(pal.safeMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var g = 0; g < groups.length; g++) ...[
                  Padding(
                    key: _keys.putIfAbsent(groups[g].$1['id'] as String, () => GlobalKey()),
                    padding: EdgeInsets.only(top: 0, bottom: 10, left: 2),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            (groups[g].$1['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: hs, fontWeight: FontWeight.w700, color: pal.sInk),
                          ),
                        ),
                        if (RegExp(r'^\d{4}$').hasMatch((groups[g].$1['lock'] ?? '').toString()) &&
                            !(widget.unlocked?.contains(groups[g].$1['id']) ?? false)) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.lock_outline, size: hs * 0.95, color: pal.sMuted),
                        ],
                      ],
                    ),
                  ),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: cols,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 4 / 3,
                    children: [
                      for (final r in groups[g].$2)
                        _RoomCard(
                          doc: doc,
                          room: r,
                          pal: pal,
                          locked: RegExp(r'^\d{4}$').hasMatch((r['lock'] ?? '').toString()) && !(widget.unlocked?.contains(r['id']) ?? false),
                          onTap: () => widget.onOpenRoom(r['id'] as String),
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

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.doc, required this.room, required this.pal, required this.onTap, this.locked = false, this.showIcon = true});
  final bool locked, showIcon;
  final Json doc, room;
  final AppPalette pal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(pal.radius + 4);
    final cover = (room['cover'] ?? '').toString();
    final img = cover.isEmpty ? null : _coverOf(cover);
    final f = tfs(doc, 'galleryTitle');
    final fg = img != null ? Colors.white : pal.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: pal.edge),
      ),
      child: Material(
        color: img != null ? Colors.black : pal.tile,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (img != null)
                Image(image: img, fit: BoxFit.cover, gaplessPlayback: true)
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pal.tileOn ?? pal.accentSoft, pal.tile]),
                  ),
                ),
              if (img != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.62)],
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
              if (showIcon) Positioned(left: 12, top: 12, child: iconWidget(room['icon'] as String?, tfs(doc, 'galleryIcon'), fg)),
              if (locked)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                    child: const Icon(Icons.lock_outline, size: 16, color: Colors.white),
                  ),
                ),
              Positioned(
                left: 14,
                right: 12,
                bottom: 12,
                child: Text(
                  (room['title'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: f,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    shadows: img != null ? const [Shadow(blurRadius: 6, color: Colors.black54)] : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
