import 'dart:math';

import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icons.dart';
import 'model.dart';
import 'tiles.dart';

const Map<String, Size> kDeviceSize = {'mobile': Size(393, 852), 'tabletP': Size(820, 1180), 'tabletL': Size(1180, 820)};

/// The simulated phone/tablet screen with the editable grid.
class DesignCanvas extends StatelessWidget {
  const DesignCanvas({super.key, required this.d, required this.issues});
  final Designer d;
  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    final doc = d.doc;
    final dev = (doc['activeDev'] as String?) ?? 'mobile';
    final size = kDeviceSize[dev] ?? kDeviceSize['mobile']!;
    final mode = (jsonMap(doc['theme'])['mode'] ?? 'light').toString();
    final dark = mode == 'dark' || (mode == 'system' && Theme.of(context).brightness == Brightness.dark);
    final pal = dark ? AppPalette.dark : AppPalette.light;
    final tablet = dev != 'mobile';
    return LayoutBuilder(
      builder: (context, box) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: FittedBox(
            fit: BoxFit.contain,
            child: Container(
              width: size.width + 22,
              height: size.height + 22,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2226),
                borderRadius: BorderRadius.circular(tablet ? 30 : 48),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tablet ? 20 : 38),
                child: ColoredBox(
                  color: pal.screen,
                  child: _Screen(d: d, pal: pal, issues: issues, size: size, tablet: tablet),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen({required this.d, required this.pal, required this.issues, required this.size, required this.tablet});
  final Designer d;
  final AppPalette pal;
  final List<Issue> issues;
  final Size size;
  final bool tablet;

  @override
  Widget build(BuildContext context) {
    final doc = d.doc;
    final room = d.room;
    final sub = d.sub;
    final floors = floorsOf(doc);
    final floor = d.floor;
    final theme = jsonMap(doc['theme']);
    final now = TimeOfDay.now();
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // status bar
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                children: [
                  Text(
                    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: pal.ink),
                  ),
                  const Spacer(),
                  if (!tablet)
                    Container(
                      width: 92,
                      height: 26,
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
                    ),
                  const Spacer(),
                  Text(
                    '100%',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: pal.ink),
                  ),
                ],
              ),
            ),
          ),
          if (room == null || sub == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_outlined, size: 40, color: pal.muted),
                      const SizedBox(height: 10),
                      Text(
                        'Tầng này chưa có phòng nào',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.ink),
                      ),
                      const SizedBox(height: 6),
                      Text('Bấm “Thêm phòng” ở cột bên trái.', style: TextStyle(color: pal.muted)),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            _header(doc, room, floor, floors.length > 1, theme),
            _roomsBar(doc, room, floor),
            _subNav(room, sub),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                child: _GridArea(d: d, box: sub, groupId: null, pal: pal, issues: issues),
              ),
            ),
          ],
          if (floors.length > 1) _floorBar(floors, floor, tablet),
        ],
      ),
    );
  }

  Widget _header(Json doc, Json room, Json? floor, bool multi, Json theme) {
    final hide = theme['hideTitle'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: hide
                ? Text(
                    multi ? (floor?['title'] ?? '').toString() : '',
                    style: TextStyle(fontSize: tfs(doc, 'crumb') * 1.15, color: pal.muted, fontWeight: FontWeight.w500),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (multi)
                        Text(
                          '${floor?['title'] ?? ''} ›  ',
                          style: TextStyle(fontSize: tfs(doc, 'crumb'), color: pal.muted, fontWeight: FontWeight.w500),
                        ),
                      Flexible(
                        child: Text(
                          (room['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: tfs(doc, 'titleSize'), fontWeight: FontWeight.w600, color: pal.ink),
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: pal.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: pal.tileEdge),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFF2FA36B), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  'KNX',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: pal.panel,
              shape: BoxShape.circle,
              border: Border.all(color: pal.tileEdge),
            ),
            child: Icon(Icons.settings_outlined, size: 17, color: pal.ink),
          ),
        ],
      ),
    );
  }

  Widget _roomsBar(Json doc, Json room, Json? floor) {
    final rs = roomsOf(doc, floor?['id'] as String?);
    final f = tfs(doc, 'roomBar');
    return SizedBox(
      height: f * 2.6 + 8,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        children: [
          for (final r in rs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => d.selectRoom(r['id'] as String),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: f * 1.05),
                  decoration: BoxDecoration(
                    color: r['id'] == room['id'] ? pal.ink : pal.panel,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: r['id'] == room['id'] ? pal.ink : pal.tileEdge),
                  ),
                  child: Row(
                    children: [
                      Icon(iconOf(r['icon'] as String?), size: f * 1.25, color: r['id'] == room['id'] ? pal.screen : pal.muted),
                      SizedBox(width: f * 0.45),
                      Text(
                        (r['title'] ?? '').toString(),
                        style: TextStyle(fontSize: f, fontWeight: FontWeight.w500, color: r['id'] == room['id'] ? pal.screen : pal.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subNav(Json room, Json sub) {
    final ss = subsOf(room);
    final i = ss.indexWhere((x) => x['id'] == sub['id']);
    final f = tfs(d.doc, 'pageTitle');
    Widget arrow(IconData icon, VoidCallback? onTap, String tip) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: onTap == null ? Colors.transparent : pal.panel,
            shape: BoxShape.circle,
            border: Border.all(color: pal.tileEdge),
          ),
          child: Icon(icon, size: 17, color: onTap == null ? pal.lineStrong : pal.ink),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          arrow(Icons.chevron_left, i > 0 ? () => d.stepSub(-1) : null, 'Trang trước'),
          Expanded(
            child: Column(
              children: [
                Text(
                  (sub['title'] ?? '').toString(),
                  style: TextStyle(fontSize: f, fontWeight: FontWeight.w600, color: pal.muted),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var k = 0; k < ss.length; k++)
                      GestureDetector(
                        onTap: () => d.selectSub(room['id'] as String, ss[k]['id'] as String),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: k == i ? 16 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(color: k == i ? pal.ink : pal.lineStrong, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          i < ss.length - 1 ? arrow(Icons.chevron_right, () => d.stepSub(1), 'Trang sau') : arrow(Icons.add, d.addSub, 'Thêm trang trong phòng'),
        ],
      ),
    );
  }

  Widget _floorBar(List<Json> floors, Json? floor, bool tablet) {
    final f = tfs(d.doc, 'floorBar');
    final slots = tablet ? 5 : 3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        height: f * 3.4 + 10,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: pal.panel.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: pal.tileEdge),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 4 * (slots - 1)) / slots;
            return ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (floors.length < slots) SizedBox(width: (c.maxWidth - floors.length * (w + 4)) / 2),
                for (final fl in floors)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () => d.selectFloor(fl['id'] as String),
                      child: Container(
                        width: w,
                        decoration: BoxDecoration(color: fl['id'] == floor?['id'] ? pal.ink : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (fl['showIcon'] != false) ...[
                              Icon(iconOf(fl['icon'] as String? ?? 'stairs'), size: f * 1.3, color: fl['id'] == floor?['id'] ? pal.screen : pal.muted),
                              SizedBox(width: f * 0.45),
                            ],
                            Flexible(
                              child: Text(
                                (fl['title'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: f, fontWeight: FontWeight.w600, color: fl['id'] == floor?['id'] ? pal.screen : pal.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Grid of a subpage or of a grid frame: cells (drop targets) and tiles.
class _GridArea extends StatefulWidget {
  const _GridArea({required this.d, required this.box, required this.groupId, required this.pal, required this.issues});
  final Designer d;
  final Json box;
  final String? groupId;
  final AppPalette pal;
  final List<Issue> issues;

  @override
  State<_GridArea> createState() => _GridAreaState();
}

class _GridAreaState extends State<_GridArea> {
  ({int x, int y, int w, int h, bool ok})? ghost;

  Designer get d => widget.d;

  void _drop(DragItem it, int x, int y) {
    setState(() => ghost = null);
    final err = d.drop(it, widget.groupId, x, y);
    if (err != null) toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.box;
    final pal = widget.pal;
    final c = cols(box), r = rows(box);
    final gap = (c >= 6 || r >= 15) ? 6.0 : 10.0;
    final evo = context.evo;
    return LayoutBuilder(
      builder: (context, bc) {
        final cw = (bc.maxWidth - gap * (c - 1)) / c;
        final ch = (bc.maxHeight - gap * (r - 1)) / r;
        Rect rect(int x, int y, int w, int h) => Rect.fromLTWH(x * (cw + gap), y * (ch + gap), w * cw + (w - 1) * gap, h * ch + (h - 1) * gap);
        final children = <Widget>[];
        // cells
        for (var y = 0; y < r; y++) {
          for (var x = 0; x < c; x++) {
            if (!isFree(box, x, y, 1, 1)) continue;
            final sel = d.cell != null && d.cell!.g == widget.groupId && d.cell!.x == x && d.cell!.y == y;
            final rc = rect(x, y, 1, 1);
            children.add(
              Positioned.fromRect(
                rect: rc,
                child: DragTarget<DragItem>(
                  onWillAcceptWithDetails: (det) {
                    final fp = d.footprint(det.data, widget.groupId, x, y);
                    setState(() => ghost = fp);
                    return true;
                  },
                  onLeave: (_) {},
                  onAcceptWithDetails: (det) => _drop(det.data, x, y),
                  builder: (context, cand, rej) => GestureDetector(
                    onTap: () => d.selectCell(widget.groupId, x, y),
                    child: Container(
                      decoration: BoxDecoration(
                        color: sel ? pal.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(widget.groupId == null ? 14 : 10),
                        border: Border.all(color: sel ? pal.accent : pal.lineStrong.withValues(alpha: 0.6), width: sel ? 1.5 : 1),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }
        // tiles
        for (final w in jsonList(box['widgets'])) {
          final id = w['id'] as String;
          final rc = rect(pi(w, 'x'), pi(w, 'y'), pi(w, 'w'), pi(w, 'h'));
          final flagged = widget.issues.any((i) => i.error && i.widgetId == id);
          final selected = d.widgetId == id;
          final Widget tile = w['type'] == 'group'
              ? _GroupFrame(d: d, w: w, pal: pal, issues: widget.issues, selected: selected)
              : TileView(w: w, pal: pal, gas: jsonList(d.doc['groupAddresses']), selected: selected, flagged: flagged);
          children.add(
            Positioned.fromRect(
              rect: rc,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => d.selectWidget(id),
                child: Draggable<DragItem>(
                  data: DragItem.widget(id),
                  onDragEnd: (_) => setState(() => ghost = null),
                  feedback: Opacity(
                    opacity: 0.85,
                    child: SizedBox(
                      width: rc.width,
                      height: rc.height,
                      child: Material(type: MaterialType.transparency, child: tile),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: tile),
                  child: MouseRegion(cursor: SystemMouseCursors.grab, child: tile),
                ),
              ),
            ),
          );
        }
        final g = ghost;
        if (g != null) {
          children.add(
            Positioned.fromRect(
              rect: rect(g.x, g.y, max(1, g.w), max(1, g.h)),
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: (g.ok ? pal.accent : evo.danger).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: g.ok ? pal.accent : evo.danger, width: 2),
                  ),
                ),
              ),
            ),
          );
        }
        return MouseRegion(
          onExit: (_) {
            if (ghost != null) setState(() => ghost = null);
          },
          child: Stack(clipBehavior: Clip.hardEdge, children: children),
        );
      },
    );
  }
}

class _GroupFrame extends StatelessWidget {
  const _GroupFrame({required this.d, required this.w, required this.pal, required this.issues, required this.selected});
  final Designer d;
  final Json w;
  final AppPalette pal;
  final List<Issue> issues;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final style = (w['gstyle'] ?? 'card').toString();
    final bg = hexColor(w['gbg']);
    final lum = bg == null ? 1.0 : bg.computeLuminance();
    final titleColor = bg == null ? pal.ink : (lum < 0.35 ? Colors.white : const Color(0xFF1B2320));
    final align = switch (w['titleAlign']) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    final gapT = ((w['titleGap'] as num?) ?? 10).toDouble();
    final showTitle = w['showTitle'] != false && (w['label'] ?? '').toString().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg ?? (style == 'card' ? pal.tile : Colors.transparent),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? pal.accent : (style == 'none' ? pal.lineStrong.withValues(alpha: 0.5) : pal.tileEdge), width: selected ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            Text(
              (w['label'] ?? '').toString(),
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w500, color: titleColor),
            ),
            SizedBox(height: gapT),
          ],
          Expanded(
            child: _GridArea(d: d, box: w, groupId: w['id'] as String, pal: pal, issues: issues),
          ),
        ],
      ),
    );
  }
}
