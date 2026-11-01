import 'dart:convert';
import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';
import 'icons.dart';
import 'model.dart';
import 'tiles.dart';

const Map<String, Size> kDeviceSize = {'mobile': Size(393, 852), 'tabletP': Size(820, 1180), 'tabletL': Size(1180, 820)};

double tabletScale(Json doc) {
  final v = (jsonMap(doc['theme'])['tabletScale'] as num?)?.toInt() ?? 120;
  return (v >= 100 && v <= 150 ? v : 120) / 100;
}

String greeting(Json sp) {
  if (sp['greetMode'] == 'custom') return (sp['greet'] ?? 'Chào mừng về nhà').toString();
  final h = DateTime.now().hour;
  final g = h >= 5 && h < 11
      ? 'Chào buổi sáng'
      : h >= 11 && h < 13
      ? 'Chào buổi trưa'
      : h >= 13 && h < 18
      ? 'Chào buổi chiều'
      : 'Chào buổi tối';
  final owner = (sp['owner'] ?? '').toString().trim();
  return owner.isEmpty ? g : '$g, $owner';
}

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
    final mode = d.previewTheme ?? (jsonMap(doc['theme'])['mode'] ?? 'light').toString();
    final base = AppPalette.of(mode);
    final bg = screenBackground(doc, base);
    final pal = base.copyWith(onScreenInk: bg.ink, onScreenMuted: bg.muted);
    final tablet = dev != 'mobile';
    final scale = tablet ? tabletScale(doc) : 1.0;
    final logical = Size(size.width / scale, size.height / scale);
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
            child: DecoratedBox(
              decoration: bg.decoration,
              child: FittedBox(
                child: SizedBox(
                  width: logical.width,
                  height: logical.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ScrollConfiguration(
                          behavior: const _DragScroll(),
                          child: _Screen(d: d, pal: pal, issues: issues, size: logical, dev: dev),
                        ),
                      ),
                      if (d.appSettingsOpen)
                        Positioned.fill(
                          child: _AppSettingsSheet(d: d, pal: pal),
                        ),
                      if (d.splashPreview) Positioned.fill(child: _Splash(d: d)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final sp = jsonMap(d.doc['splash']);
    final bg = hexColor(sp['bg']) ?? const Color(0xFF1B2320);
    final fg = bg.computeLuminance() < 0.35 ? Colors.white : const Color(0xFF1B2320);
    final logo = (sp['logo'] ?? '').toString();
    Widget mark;
    if (logo.startsWith('data:image/png;base64,')) {
      mark = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230, maxHeight: 200),
        child: Image.memory(base64Decode(logo.substring(22)), fit: BoxFit.contain),
      );
    } else if (logo.startsWith('data:image/')) {
      mark = Text('Logo SVG (hiển thị trên App)', style: TextStyle(color: fg.withValues(alpha: 0.7)));
    } else {
      mark = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(color: Color(0xFFEE9B2A), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            'EVOKNX',
            style: TextStyle(color: fg, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: d.skipSplash,
      child: Container(
        color: bg,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            mark,
            const SizedBox(height: 20),
            Text(
              greeting(sp),
              textAlign: TextAlign.center,
              style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w500),
            ),
            if ((sp['sub'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(sp['sub'].toString(), style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen({required this.d, required this.pal, required this.issues, required this.size, required this.dev});
  final Designer d;
  final AppPalette pal;
  final List<Issue> issues;
  final Size size;
  final String dev;

  bool get tablet => dev != 'mobile';

  @override
  Widget build(BuildContext context) {
    final doc = d.doc;
    final room = d.room;
    final sub = d.sub;
    final floors = floorsOf(doc);
    final floor = d.floor;
    final theme = jsonMap(doc['theme']);
    final now = TimeOfDay.now();
    final statusBar = SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(
          children: [
            Text(
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: pal.sInk),
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
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: pal.sInk),
            ),
          ],
        ),
      ),
    );
    final empty = Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home_outlined, size: 40, color: pal.sMuted),
              const SizedBox(height: 10),
              Text(
                'Tầng này chưa có phòng nào',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.sInk),
              ),
              const SizedBox(height: 6),
              Text('Bấm “Thêm phòng” ở cột bên trái.', style: TextStyle(color: pal.sMuted)),
            ],
          ),
        ),
      ),
    );
    Widget grid(Json room, Json s) => Expanded(
      child: _PagedGrid(key: ValueKey<String>('pg-${room['id']}'), d: d, room: room, pal: pal, issues: issues),
    );

    if (dev == 'tabletL') {
      return SizedBox(
        width: size.width,
        height: size.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statusBar,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sidebar(doc, room, floors.length > 1),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (room == null || sub == null)
                          empty
                        else ...[
                          _header(doc, room, floor, floors.length > 1, theme, pill: false),
                          _pageTabs(room, sub),
                          grid(room, sub),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statusBar,
          if (room == null || sub == null)
            empty
          else ...[
            _header(doc, room, floor, floors.length > 1, theme),
            _roomsBar(doc, room, floor),
            tablet ? _pageTabs(room, sub) : _subNav(room, sub),
            grid(room, sub),
          ],
          if (floors.length > 1) _floorBar(floors, floor),
        ],
      ),
    );
  }

  Widget _pill() => Container(
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
          decoration: BoxDecoration(color: d.live && d.bus?.connected != true ? const Color(0xFFD9463B) : const Color(0xFF2FA36B), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          'KNX',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.ink),
        ),
      ],
    ),
  );

  Widget _gear() => GestureDetector(
    onTap: () => d.toggleAppSettings(true),
    child: MouseRegion(cursor: SystemMouseCursors.click, child: _gearIcon()),
  );

  Widget _gearIcon() => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: pal.panel,
      shape: BoxShape.circle,
      border: Border.all(color: pal.tileEdge),
    ),
    child: Icon(Icons.settings_outlined, size: 17, color: pal.ink),
  );

  Widget _header(Json doc, Json room, Json? floor, bool multi, Json theme, {bool pill = true}) {
    final hide = theme['hideTitle'] == true && dev != 'tabletL';
    return Padding(
      padding: EdgeInsets.fromLTRB(18, dev == 'tabletL' ? 10 : 6, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: hide
                ? Text(
                    multi ? (floor?['title'] ?? '').toString() : '',
                    style: TextStyle(fontSize: tfs(doc, 'crumb') * 1.15, color: pal.sMuted, fontWeight: FontWeight.w500),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (multi)
                        Text(
                          '${floor?['title'] ?? ''} ›  ',
                          style: TextStyle(fontSize: tfs(doc, 'crumb'), color: pal.sMuted, fontWeight: FontWeight.w500),
                        ),
                      Flexible(
                        child: Text(
                          (room['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: tfs(doc, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
                        ),
                      ),
                    ],
                  ),
          ),
          if (pill) ...[_pill(), const SizedBox(width: 8), _gear()],
        ],
      ),
    );
  }

  Widget _sidebar(Json doc, Json? room, bool multi) {
    final now = DateTime.now();
    const days = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];
    return Container(
      width: 230,
      margin: const EdgeInsets.fromLTRB(14, 4, 0, 14),
      decoration: BoxDecoration(
        color: pal.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.tileEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: pal.ink, height: 1),
                ),
                const SizedBox(height: 6),
                Text('${days[now.weekday - 1]}, ${now.day}/${now.month}', style: TextStyle(fontSize: 13, color: pal.muted)),
                const SizedBox(height: 8),
                Text(
                  greeting(jsonMap(doc['splash'])),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: pal.ink),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: pal.tileEdge),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final f in floorsOf(doc)) ...[
                  if (multi)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                      child: Row(
                        children: [
                          if (f['showIcon'] != false) ...[iconWidget(f['icon'] as String? ?? 'stairs', 14, pal.muted), const SizedBox(width: 6)],
                          Text(
                            (f['title'] ?? '').toString(),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.muted),
                          ),
                        ],
                      ),
                    ),
                  for (final r in roomsOf(doc, f['id'] as String?))
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => d.selectRoom(r['id'] as String),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: r['id'] == room?['id'] ? pal.ink : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            iconWidget(r['icon'] as String?, 20, r['id'] == room?['id'] ? pal.screen : pal.muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                (r['title'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, color: r['id'] == room?['id'] ? pal.screen : pal.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: pal.tileEdge),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [_pill(), const Spacer(), _gear()]),
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
                      iconWidget(r['icon'] as String?, f * 1.25, r['id'] == room['id'] ? pal.screen : pal.muted),
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

  Widget _pageTabs(Json room, Json sub) {
    final ss = subsOf(room);
    if (ss.length < 2 && d.test) return const SizedBox(height: 4);
    final f = tfs(d.doc, 'pageTitle');
    return SizedBox(
      height: f * 2.6 + 12,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          for (final s in ss)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => d.selectSub(room['id'] as String, s['id'] as String),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: f * 1.2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s['id'] == sub['id'] ? pal.ink : pal.panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: s['id'] == sub['id'] ? pal.ink : pal.tileEdge),
                  ),
                  child: Text(
                    (s['title'] ?? '').toString(),
                    style: TextStyle(fontSize: f * 1.05, fontWeight: FontWeight.w500, color: s['id'] == sub['id'] ? pal.screen : pal.muted),
                  ),
                ),
              ),
            ),
          if (!d.test)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: d.addSub,
              child: Container(
                width: f * 2.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: pal.lineStrong),
                ),
                child: Icon(Icons.add, size: 16, color: pal.accent),
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
    final dots = Row(
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
              decoration: BoxDecoration(color: k == i ? pal.sInk : pal.sMuted.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(3)),
            ),
          ),
      ],
    );
    final title = Text(
      (sub['title'] ?? '').toString(),
      style: TextStyle(fontSize: f, fontWeight: FontWeight.w600, color: pal.sMuted),
    );
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
    if (d.test) {
      if (ss.length < 2) return const SizedBox(height: 4);
      final arrows = jsonMap(d.doc['theme'])['pageArrows'] != false;
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(
          children: [
            if (arrows) arrow(Icons.chevron_left, i > 0 ? () => d.stepSub(-1) : null, 'Trang trước'),
            Expanded(child: Column(children: [title, const SizedBox(height: 5), dots])),
            if (arrows) arrow(Icons.chevron_right, i < ss.length - 1 ? () => d.stepSub(1) : null, 'Trang sau'),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          arrow(Icons.chevron_left, i > 0 ? () => d.stepSub(-1) : null, 'Trang trước'),
          Expanded(child: Column(children: [title, const SizedBox(height: 5), dots])),
          i < ss.length - 1 ? arrow(Icons.chevron_right, () => d.stepSub(1), 'Trang sau') : arrow(Icons.add, d.addSub, 'Thêm trang trong phòng'),
        ],
      ),
    );
  }

  Widget _floorBar(List<Json> floors, Json? floor) {
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
                              iconWidget(fl['icon'] as String? ?? 'stairs', f * 1.3, fl['id'] == floor?['id'] ? pal.screen : pal.muted),
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
  const _GridArea({super.key, required this.d, required this.box, required this.groupId, required this.pal, required this.issues});
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

  /// How much the phone preview is scaled on screen, so the drag feedback
  /// (drawn in the overlay, unscaled) keeps the same size as the tile.
  double _screenScale() {
    final rb = context.findRenderObject();
    if (rb is! RenderBox || !rb.attached) return 1;
    final a = rb.localToGlobal(Offset.zero), b = rb.localToGlobal(const Offset(100, 0));
    final k = (b.dx - a.dx) / 100;
    return k > 0 ? k : 1;
  }

  void _drop(DragItem it, int x, int y) {
    setState(() => ghost = null);
    final err = d.drop(it, widget.groupId, x, y);
    if (err != null) toast(context, err);
  }

  Future<void> _testAct(Json w, String action, Object? arg) async {
    if (action == 'tune') {
      await showDialog<void>(
        context: context,
        builder: (c) => _TuneDialog(d: d, w: w),
      );
      return;
    }
    d.act(w, action == 'tap' ? (w['type'] == 'dimmer' ? 'toggle' : 'tap') : action, arg);
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.box;
    final pal = widget.pal;
    final test = d.test;
    final c = cols(box), r = rows(box);
    final gap = (c >= 6 || r >= 15) ? 6.0 : 10.0;
    final evo = context.evo;
    final gas = jsonList(d.doc['groupAddresses']);
    return LayoutBuilder(
      builder: (context, bc) {
        final cw = (bc.maxWidth - gap * (c - 1)) / c;
        final ch = (bc.maxHeight - gap * (r - 1)) / r;
        Rect rect(int x, int y, int w, int h) => Rect.fromLTWH(x * (cw + gap), y * (ch + gap), w * cw + (w - 1) * gap, h * ch + (h - 1) * gap);
        final children = <Widget>[];
        if (!test) {
          for (var y = 0; y < r; y++) {
            for (var x = 0; x < c; x++) {
              if (!isFree(box, x, y, 1, 1)) continue;
              final sel = d.cell != null && d.cell!.g == widget.groupId && d.cell!.x == x && d.cell!.y == y;
              children.add(
                Positioned.fromRect(
                  rect: rect(x, y, 1, 1),
                  child: DragTarget<DragItem>(
                    onWillAcceptWithDetails: (det) {
                      setState(() => ghost = d.footprint(det.data, widget.groupId, x, y));
                      return true;
                    },
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
        }
        for (final w in jsonList(box['widgets'])) {
          final id = w['id'] as String;
          final rc = rect(pi(w, 'x'), pi(w, 'y'), pi(w, 'w'), pi(w, 'h'));
          final flagged = !test && widget.issues.any((i) => i.error && i.widgetId == id);
          final selected = !test && d.widgetId == id;
          final Widget tile = w['type'] == 'group'
              ? _GroupFrame(d: d, w: w, pal: pal, issues: widget.issues, selected: selected)
              : TileView(
                  w: w,
                  pal: pal,
                  gas: gas,
                  sim: d.sim[id] ?? const {},
                  selected: selected,
                  flagged: flagged,
                  act: test ? (a, [arg]) => _testAct(w, a, arg) : null,
                );
          if (test) {
            children.add(
              Positioned.fromRect(
                rect: rc,
                child: w['type'] == 'group' || w['type'] == 'value'
                    ? tile
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _testAct(w, 'tap', null),
                        child: MouseRegion(cursor: SystemMouseCursors.click, child: tile),
                      ),
              ),
            );
            continue;
          }
          children.add(
            Positioned.fromRect(
              rect: rc,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => d.selectWidget(id),
                child: Draggable<DragItem>(
                  data: DragItem.widget(id),
                  onDragEnd: (_) => setState(() => ghost = null),
                  feedback: Builder(
                    builder: (_) {
                      final k = _screenScale();
                      return Opacity(
                        opacity: 0.85,
                        child: SizedBox(
                          width: rc.width * k,
                          height: rc.height * k,
                          child: FittedBox(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: rc.width,
                              height: rc.height,
                              child: Material(type: MaterialType.transparency, child: tile),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: tile),
                  child: MouseRegion(cursor: SystemMouseCursors.grab, child: tile),
                ),
              ),
            ),
          );
        }
        final g = ghost;
        if (g != null && !test) {
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
    final titleColor = bg == null ? pal.ink : (bg.computeLuminance() < 0.35 ? Colors.white : const Color(0xFF1B2320));
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
        border: Border.all(
          color: selected ? pal.accent : (style == 'none' ? (d.test ? Colors.transparent : pal.lineStrong.withValues(alpha: 0.5)) : pal.tileEdge),
          width: selected ? 2 : 1,
        ),
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

/// Slider sheet for dimmers (brightness, colour temperature, RGB) and
/// shutters (position) in test mode.
class _TuneDialog extends StatefulWidget {
  const _TuneDialog({required this.d, required this.w});
  final Designer d;
  final Json w;
  @override
  State<_TuneDialog> createState() => _TuneDialogState();
}

class _TuneDialogState extends State<_TuneDialog> {
  late final Map<String, dynamic> s = widget.d.st(widget.w['id'] as String);

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final dim = w['type'] == 'dimmer';
    final f = jsonMap(w['features']);
    final tw = jsonMap(w['tw']);
    final ctMin = ((tw['min'] as num?) ?? 2700).toDouble(), ctMax = ((tw['max'] as num?) ?? 6500).toDouble();
    final val = ((dim ? s['val'] : s['pos']) as num? ?? 0).toDouble();
    const swatches = ['#FFFFFF', '#FFB347', '#FF5E5E', '#FF4FA3', '#9B6BFF', '#4D8DFF', '#36C5D6', '#3DCB7A', '#F5E663'];
    return AlertDialog(
      title: Text((w['label'] ?? '').toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(dim ? 'Độ sáng: ${val.round()}%' : (w['shStyle'] == 'curtain' ? 'Mở ${100 - val.round()}%' : 'Đóng ${val.round()}%')),
            Slider(
              value: val.clamp(0.0, 100.0),
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => dim ? s['val'] = v.round() : s['pos'] = v.round()),
              onChangeEnd: (v) => widget.d.act(w, 'set', v.round()),
            ),
            if (!dim)
              Wrap(
                spacing: 6,
                children: [
                  for (final p in [0, 25, 50, 75, 100])
                    OutlinedButton(
                      onPressed: () {
                        setState(() => s['pos'] = p);
                        widget.d.act(w, 'set', p);
                      },
                      child: Text('$p%'),
                    ),
                ],
              ),
            if (dim && f['tw'] == true) ...[
              const SizedBox(height: 8),
              Text('Nhiệt độ màu: ${((s['ct'] as num?) ?? ctMin).round()} K'),
              Slider(
                value: (((s['ct'] as num?) ?? ctMin).toDouble()).clamp(ctMin, ctMax),
                min: ctMin,
                max: ctMax,
                onChanged: (v) => setState(() => s['ct'] = (v / 50).round() * 50),
                onChangeEnd: (v) => widget.d.act(w, 'ct', (v / 50).round() * 50),
              ),
            ],
            if (dim && f['rgb'] == true) ...[
              const SizedBox(height: 8),
              const Text('Màu'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hx in swatches)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        setState(() => s['rgb'] = hx);
                        widget.d.act(w, 'rgb', hx);
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: hexColor(hx),
                          shape: BoxShape.circle,
                          border: Border.all(color: s['rgb'] == hx ? Colors.black : const Color(0x33000000), width: s['rgb'] == hx ? 2 : 1),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Xong'))],
    );
  }
}

/// Lets horizontal bars (rooms, pages, floors) be dragged with the mouse,
/// like swiping on the phone.
class _DragScroll extends MaterialScrollBehavior {
  const _DragScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// Pages of a room in a PageView: follows the mouse/finger while dragging,
/// snaps to the nearest page, and animates when the page is changed from
/// the dots, tabs, arrow buttons, keyboard or the structure tree.
class _PagedGrid extends StatefulWidget {
  const _PagedGrid({super.key, required this.d, required this.room, required this.pal, required this.issues});
  final Designer d;
  final Json room;
  final AppPalette pal;
  final List<Issue> issues;

  @override
  State<_PagedGrid> createState() => _PagedGridState();
}

class _PagedGridState extends State<_PagedGrid> {
  late final PageController _pc = PageController(initialPage: _index());
  bool _animating = false;

  int _index() {
    final ss = subsOf(widget.room);
    final i = ss.indexWhere((x) => x['id'] == widget.d.sub?['id']);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant _PagedGrid old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync() async {
    if (!mounted || !_pc.hasClients) return;
    final target = _index();
    final cur = _pc.page ?? target.toDouble();
    if ((cur - target).abs() < 0.01 || _animating) return;
    // Only animate when the change did not come from the user's own drag.
    if (_pc.position.isScrollingNotifier.value) return;
    _animating = true;
    await _pc.animateToPage(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    _animating = false;
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ss = subsOf(widget.room);
    return PageView.builder(
      controller: _pc,
      itemCount: ss.length,
      physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
      onPageChanged: (i) {
        if (_animating || i < 0 || i >= ss.length) return;
        if (ss[i]['id'] != widget.d.sub?['id']) widget.d.selectSub(widget.room['id'] as String, ss[i]['id'] as String);
      },
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
        child: _GridArea(key: ValueKey<String>('ga-${ss[i]['id']}'), d: widget.d, box: ss[i], groupId: null, pal: widget.pal, issues: widget.issues),
      ),
    );
  }
}

/// Screen background (default, colour or image) and the text colours that
/// stay readable on it.
class ScreenBg {
  const ScreenBg(this.decoration, this.ink, this.muted);
  final BoxDecoration decoration;
  final Color ink, muted;
}

String? _bgData;
MemoryImage? _bgImage;

ScreenBg screenBackground(Json doc, AppPalette base) {
  final t = jsonMap(doc['theme']);
  final mode = (t['bgMode'] ?? 'default').toString();
  final textMode = (t['bgText'] ?? 'auto').toString();
  const light = Color(0xFFFFFFFF);
  const darkInk = Color(0xFF1B2320);
  ({Color ink, Color muted}) text(bool darkBg) {
    final d = textMode == 'light' || (textMode == 'auto' && darkBg);
    if (textMode == 'auto' && mode == 'default') return (ink: base.ink, muted: base.muted);
    return d ? (ink: light, muted: light.withValues(alpha: 0.75)) : (ink: darkInk, muted: const Color(0xFF55605C));
  }

  if (mode == 'color') {
    final c = hexColor(t['bgColor']) ?? base.screen;
    final tx = text(c.computeLuminance() < 0.35);
    return ScreenBg(BoxDecoration(color: c), tx.ink, tx.muted);
  }
  if (mode == 'image') {
    final data = (t['bgImage'] ?? '').toString();
    final i = data.indexOf('base64,');
    if (i > 0) {
      if (_bgData != data) {
        try {
          _bgImage = MemoryImage(base64Decode(data.substring(i + 7)));
          _bgData = data;
        } catch (_) {
          _bgImage = null;
          _bgData = null;
        }
      }
      final dim = (((t['bgDim'] as num?) ?? 30).toDouble().clamp(0, 80)) / 100;
      final img = _bgImage;
      if (img != null) {
        final tx = text(dim >= 0.25 || base.screen.computeLuminance() < 0.35);
        return ScreenBg(
          BoxDecoration(
            color: Colors.black,
            image: DecorationImage(
              image: img,
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: dim), BlendMode.srcOver),
            ),
          ),
          tx.ink,
          tx.muted,
        );
      }
    }
  }
  final tx = text(base.screen.computeLuminance() < 0.35);
  return ScreenBg(BoxDecoration(color: base.screen), tx.ink, tx.muted);
}

/// The App's settings screen, opened from the gear button in the preview.
class _AppSettingsSheet extends StatelessWidget {
  const _AppSettingsSheet({required this.d, required this.pal});
  final Designer d;
  final AppPalette pal;

  static const _themes = [('light', 'Sáng'), ('dark', 'Tối'), ('graphite', 'Xám than'), ('sand', 'Kem')];

  @override
  Widget build(BuildContext context) {
    final doc = d.doc;
    final projMode = (jsonMap(doc['theme'])['mode'] ?? 'light').toString();
    final cur = d.previewTheme ?? projMode;
    final online = d.bus?.connected == true && d.live;
    Widget card(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: pal.muted),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: pal.tile,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: pal.tileEdge),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[children[i], if (i < children.length - 1) Divider(height: 1, indent: 16, color: pal.line)],
              ],
            ),
          ),
        ],
      ),
    );
    Widget row(Widget leading, String text, {String? sub, Widget? trailing, VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: TextStyle(fontSize: 15, color: pal.ink)),
                  if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 12.5, color: pal.muted))],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => FractionalTranslation(translation: Offset(0, t), child: child),
      child: Container(
        color: pal.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 38),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cài đặt',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: pal.ink),
                    ),
                  ),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => d.toggleAppSettings(false),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: pal.panel,
                        shape: BoxShape.circle,
                        border: Border.all(color: pal.tileEdge),
                      ),
                      child: Icon(Icons.close, size: 18, color: pal.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  card('Tài khoản', [
                    row(
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: pal.accentSoft,
                        child: Icon(Icons.person_outline, color: pal.accent, size: 20),
                      ),
                      'Chưa đăng nhập',
                      sub: 'Tài khoản và phân quyền người dùng sẽ có trong bản sau',
                    ),
                  ]),
                  card('Giao diện', [
                    for (final (k, n) in _themes)
                      row(
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppPalette.of(k).screen,
                            shape: BoxShape.circle,
                            border: Border.all(color: pal.lineStrong),
                          ),
                        ),
                        n,
                        sub: k == projMode ? 'Mặc định của dự án' : null,
                        trailing: k == cur ? Icon(Icons.check, color: pal.accent, size: 20) : null,
                        onTap: () => d.setPreviewTheme(k == projMode ? null : k),
                      ),
                  ]),
                  card('Kết nối KNX', [
                    for (final c in jsonList(doc['connections']))
                      row(
                        Icon(Icons.router_outlined, color: pal.muted, size: 22),
                        (c['name'] ?? 'Kết nối').toString(),
                        sub: '${c['host'] ?? ''}:${c['port'] ?? 3671}${c['natMode'] == true ? ' · NAT' : ''}',
                        trailing: Text(online ? 'Đã kết nối' : 'Giả lập', style: TextStyle(fontSize: 12.5, color: online ? pal.accent : pal.muted)),
                      ),
                  ]),
                  card('Giới thiệu', [
                    row(Icon(Icons.info_outline, color: pal.muted, size: 22), 'EVOKNX', sub: 'Phiên bản 1.0 · © ${DateTime.now().year} Evohome'),
                    row(
                      Icon(Icons.home_work_outlined, color: pal.muted, size: 22),
                      (jsonMap(doc['project'])['name'] ?? '').toString(),
                      sub: 'Cấu hình phiên bản ${jsonMap(doc['project'])['revision'] ?? 0}',
                    ),
                  ]),
                  Text(
                    'Đây là bản xem trước. Lựa chọn giao diện ở đây chỉ để thử, không đổi cài đặt của dự án; trên App mỗi người dùng tự chọn giao diện riêng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: pal.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
