import 'dart:convert';

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
        return GridView.builder(
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
        return SingleChildScrollView(
          padding: EdgeInsets.all(pal.safeMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var g = 0; g < groups.length; g++) ...[
                Padding(
                  key: _keys.putIfAbsent(groups[g].$1['id'] as String, () => GlobalKey()),
                  padding: EdgeInsets.only(top: g == 0 ? 0 : 20, bottom: 10, left: 2),
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
