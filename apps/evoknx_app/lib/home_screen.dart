import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter, TileMode;

import 'dart:math' show max;

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart' show KnxConnectionState;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_store.dart';
import 'knx_link.dart';
import 'popups.dart';
import 'settings_screen.dart';
import 'web_card.dart';

/// Main screen: floors › rooms › pages with the cards, controlling KNX.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final KnxLink knx = KnxLink(widget.store);
  late final CardEngine engine = CardEngine(widget.store.config!);
  late final AppLifecycleListener _life;

  /// Link to Home Assistant (null when the project does not use it).
  HaBridge? ha;
  PageController? _pages;
  String? floorId, roomId;
  int page = 0;
  String _dev = 'mobile';

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final doc = store.config!;
    final rooms = roomsOf(doc);
    final last = rooms.where((r) => r['id'] == store.lastRoom).firstOrNull ?? rooms.firstOrNull;
    roomId = last?['id'] as String?;
    floorId = last?['floorId'] as String? ?? floorsOf(doc).firstOrNull?['id'] as String?;
    if (last != null) {
      final i = subsOf(last).indexWhere((s) => s['id'] == store.lastSub);
      page = i < 0 ? 0 : i;
    }
    _pages = PageController(initialPage: page);
    // Virtual addresses (main group 32) go to Home Assistant, the others to the KNX bus.
    final cfg = haSettings(doc), haGas = haAddresses(doc);
    final url = (cfg['url'] ?? '').toString().trim(), token = (cfg['token'] ?? '').toString().trim();
    if (cfg['enabled'] == true && url.isNotEmpty && token.isNotEmpty && haGas.isNotEmpty) {
      final b = HaBridge(url: url, token: token, addresses: haGas);
      b.onValue = engine.onBusValue;
      b.onState = () {
        if (mounted) setState(() {});
      };
      ha = b;
      b.start();
    }
    engine.writer = (ga, v) => isHaAddress(ga) ? (ha?.write(ga, v) ?? Future<String?>.value('Home Assistant chưa được bật trong dự án.')) : knx.write(ga, v);
    engine.onMessage = _toast;
    engine.onScene = (w) => showScenePopup(context, w, store.palette);
    engine.onOpenUrl = (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    knx.onValue = engine.onBusValue;
    knx.addListener(_onKnx);
    engine.addListener(_rebuild);
    store.addListener(_rebuild);
    _grace = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _graceOver = true);
    });
    _life = AppLifecycleListener(onResume: () => _connect(), onHide: () => knx.disconnect());
    _applyWakelock();
    _connect();
  }

  @override
  void dispose() {
    _life.dispose();
    knx.removeListener(_onKnx);
    engine.removeListener(_rebuild);
    store.removeListener(_rebuild);
    knx.disconnect(notify: false);
    ha?.stop();
    _grace?.cancel();
    _pages?.dispose();
    _floorScroll.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool _wasConnected = false;
  void _onKnx() {
    if (knx.connected && !_wasConnected) _readPage();
    _wasConnected = knx.connected;
    _rebuild();
  }

  /// The project uses the KNX bus when it has real (non-virtual) group addresses.
  bool get _usesKnx => jsonList(doc['groupAddresses']).any((g) => g['ha'] is! Map);

  /// Opens the KNX connection (and Home Assistant starts on its own). Nothing is
  /// announced: the cards simply work once connected.
  Future<void> _connect() async {
    if (!_usesKnx) return;
    await knx.connect();
  }

  /// The red bar only appears when the bus is still not reachable well after
  /// the App was opened (never while it is connecting or reconnecting).
  bool _graceOver = false;
  Timer? _grace;

  void _applyWakelock() {
    try {
      WakelockPlus.toggle(enable: store.keepScreenOn);
    } catch (_) {}
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
  }

  Json get doc => store.view(_dev);
  Json? get room => roomsOf(doc).where((r) => r['id'] == roomId).firstOrNull;
  Json? get sub {
    final subs = room == null ? const <Json>[] : subsOf(room!);
    return subs.isEmpty ? null : subs[page.clamp(0, subs.length - 1)];
  }

  void _readPage() {
    final s = sub;
    if (s != null) knx.readAll(engine.readsFor(s));
  }

  void _goRoom(String id) {
    if (id == roomId) return;
    setState(() {
      roomId = id;
      page = 0;
      _pages?.dispose();
      _pages = PageController();
    });
    store.remember(roomId, sub?['id'] as String?);
    _readPage();
  }

  void _goFloor(String id) {
    final rooms = roomsOf(doc, id);
    setState(() => floorId = id);
    if (rooms.isNotEmpty) {
      _goRoom(rooms.first['id'] as String);
    } else {
      // A floor without rooms: show the empty screen, not the previous room.
      setState(() {
        roomId = null;
        page = 0;
      });
    }
  }

  /// Phone, or tablet portrait / landscape when the project has that layout.
  String _deviceFor(Size size, Orientation o) {
    if (size.shortestSide < 600) return 'mobile';
    if (o == Orientation.landscape && store.hasLayout('tabletL')) return 'tabletL';
    if (store.hasLayout('tabletP')) return 'tabletP';
    return 'mobile';
  }

  /// Bottom sheet to switch between the houses (profiles) on this phone.
  Future<void> _openProfiles(AppPalette pal) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.screen,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
              child: Text(
                'Chuyển hồ sơ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.sInk),
              ),
            ),
            for (final pf in store.profiles)
              ListTile(
                leading: Icon(pf.id == store.activeId ? Icons.home : Icons.home_outlined, color: pf.id == store.activeId ? pal.accent : pal.sMuted),
                title: Text(
                  pf.name,
                  style: TextStyle(color: pal.sInk, fontWeight: pf.id == store.activeId ? FontWeight.w700 : FontWeight.w500),
                ),
                trailing: pf.id == store.activeId ? Icon(Icons.check, color: pal.accent) : null,
                onTap: () {
                  Navigator.pop(c);
                  if (pf.id != store.activeId) store.switchProfile(pf.id);
                },
              ),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: pal.sMuted),
              title: Text('Quản lý hồ sơ', style: TextStyle(color: pal.sMuted)),
              onTap: () {
                Navigator.pop(c);
                _openSettings();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(store: store, knx: knx, ha: ha),
      ),
    );
    _applyWakelock();
    engine.doc = store.view(_dev);
    if (!knx.connected) _connect();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Text and icons follow the screen width on Android (iOS unchanged).
    EvoScale.k = store.uiScaleFor(mq.size);
    final dev = _deviceFor(mq.size, mq.orientation);
    if (dev != _dev) {
      _dev = dev;
      engine.doc = store.view(dev);
    }
    engine.doc = doc;
    final pal0 = store.palette;
    final s = sub;
    final bg = pageBackground(s, pal0);
    final pal = pal0.copyWith(onScreenInk: bg?.ink, onScreenMuted: bg?.muted);
    final d = doc;
    final floors = floorsOf(d);
    final rooms = roomsOf(d, floorId);
    final r = room;
    final subs = r == null ? const <Json>[] : subsOf(r);
    final floor = floors.where((f) => f['id'] == floorId).firstOrNull;

    return Scaffold(
      backgroundColor: pal.screen,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: bg == null
                  ? const SizedBox.expand(key: ValueKey('bg-none'))
                  : ClipRect(
                      key: ValueKey('bg-${s?['id']}'),
                      child: ImageFiltered(
                        enabled: bg.blur > 0,
                        imageFilter: ImageFilter.blur(sigmaX: bg.blur, sigmaY: bg.blur, tileMode: TileMode.clamp),
                        child: DecoratedBox(decoration: bg.decoration, child: const SizedBox.expand()),
                      ),
                    ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _banner(pal),
                _header(d, pal, floor, r, floors.length > 1),
                if (rooms.length > 1) _roomsBar(d, pal, rooms),
                if (r != null && subs.length > 1) _pageNav(subs, pal),
                Expanded(
                  child: r == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.meeting_room_outlined, size: 48, color: pal.sMuted),
                                const SizedBox(height: 12),
                                Text(
                                  'Phòng chưa được tạo',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.sInk),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tầng này chưa có phòng nào.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14, color: pal.sMuted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : PageView.builder(
                          key: ValueKey('pages-$roomId-$_dev'),
                          controller: _pages,
                          itemCount: subs.length,
                          onPageChanged: (i) {
                            setState(() => page = i);
                            store.remember(roomId, sub?['id'] as String?);
                            _readPage();
                          },
                          itemBuilder: (context, i) => Padding(padding: EdgeInsets.all(pal.safeMargin), child: _grid(subs[i], null, pal)),
                        ),
                ),
                if (floors.length > 1) _floorBar(d, pal, floors),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- chrome

  Widget _banner(AppPalette pal) {
    // No notice while connecting; only a bus that stays unreachable is shown.
    if (!_usesKnx || knx.connected || !_graceOver || knx.state != KnxConnectionState.disconnected) return const SizedBox.shrink();
    final bad = knx.state == KnxConnectionState.disconnected;
    return Material(
      color: bad ? pal.danger : pal.panel,
      child: InkWell(
        onTap: _connect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (!bad) SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent)),
              if (bad) const Icon(Icons.wifi_off, size: 16, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(bad ? '${knx.statusText} · Chạm để thử lại' : knx.statusText, style: TextStyle(fontSize: 13, color: bad ? Colors.white : pal.ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Tầng 1 › Phòng 1" on one row (floor shown only when there are several),
  /// settings button on the right: as in the Editor preview.
  Widget _header(Json d, AppPalette pal, Json? floor, Json? r, bool multi) {
    final hide = jsonMap(d['theme'])['hideTitle'] == true && r != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: hide
                ? Text(
                    multi ? (floor?['title'] ?? '').toString() : '',
                    style: TextStyle(fontSize: tfs(d, 'crumb') * 1.15, color: pal.sMuted, fontWeight: FontWeight.w500),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (multi && r != null)
                        Text(
                          '${floor?['title'] ?? ''} ›  ',
                          style: TextStyle(fontSize: tfs(d, 'crumb'), color: pal.sMuted, fontWeight: FontWeight.w500),
                        ),
                      Flexible(
                        child: Text(
                          // No room on this floor: the floor name is the title.
                          (r?['title'] ?? floor?['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: tfs(d, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
                        ),
                      ),
                    ],
                  ),
          ),
          if (store.profiles.length > 1) ...[
            Tooltip(
              message: 'Chuyển hồ sơ',
              child: DecoratedBox(
                decoration: flatDecoration(pal, pal.chipFill, circle: true),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openProfiles(pal),
                    child: SizedBox(width: 40, height: 40, child: Icon(Icons.home_work_outlined, size: 20, color: pal.ink)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          DecoratedBox(
            decoration: flatDecoration(pal, pal.chipFill, circle: true),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openSettings,
                child: SizedBox(width: 40, height: 40, child: Icon(Icons.settings_outlined, size: 20, color: pal.ink)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomsBar(Json d, AppPalette pal, List<Json> rooms) {
    final f = tfs(d, 'roomBar');
    return SizedBox(
      height: f * 2.6 + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final r = rooms[i];
          final on = r['id'] == roomId;
          return DecoratedBox(
            decoration: flatDecoration(pal, on ? pal.chipSel : pal.chipFill, radius: BorderRadius.circular(40), glow: on ? pal.chipSel : null),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => _goRoom(r['id'] as String),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: f * 1.1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isNoIcon(r['icon'] as String?)) ...[
                        iconWidget(r['icon'] as String?, f * 1.25, on ? pal.onChipSel : pal.muted),
                        SizedBox(width: f * 0.45),
                      ],
                      Text(
                        (r['title'] ?? '').toString(),
                        style: TextStyle(fontSize: f, fontWeight: FontWeight.w500, color: on ? pal.onChipSel : pal.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Page navigation under the rooms bar, as in the Editor preview: the page
  /// name and dots in the middle, and (when "Mũi tên chuyển trang" is on in
  /// Tổng quan) a button on each side. Swiping the cards also changes the page.
  Widget _pageNav(List<Json> subs, AppPalette pal) {
    final f = tfs(doc, 'pageTitle');
    final arrows = jsonMap(doc['theme'])['pageArrows'] != false;
    final title = (sub?['title'] ?? '').toString();
    void go(int to) {
      final pc = _pages;
      if (pc == null || !pc.hasClients) return;
      pc.animateToPage(to.clamp(0, subs.length - 1).toInt(), duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    }

    Widget arrow(IconData icon, bool enabled, VoidCallback onTap, String tip) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: enabled ? pal.chipFill : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: pal.tileEdge),
          ),
          child: Icon(icon, size: 19, color: enabled ? pal.ink : pal.lineStrong),
        ),
      ),
    );
    final dots = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var k = 0; k < subs.length; k++)
          GestureDetector(
            onTap: () => go(k),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              width: k == page ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(color: k == page ? pal.sInk : pal.sMuted.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(3)),
            ),
          ),
      ],
    );
    // Centred (vertically) between the rooms bar and the cards: the space above
    // is the 6 px left under the rooms bar plus this top padding, the space
    // below is the page's safe margin around the cards: both are [m].
    final m = pal.safeMargin;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, max(0.0, m - 6), 14, 0),
      child: Row(
        children: [
          if (arrows) arrow(Icons.chevron_left, page > 0, () => go(page - 1), 'Trang trước'),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: f, fontWeight: FontWeight.w600, color: pal.sMuted),
                  ),
                dots,
              ],
            ),
          ),
          if (arrows) arrow(Icons.chevron_right, page < subs.length - 1, () => go(page + 1), 'Trang sau'),
        ],
      ),
    );
  }

  final ScrollController _floorScroll = ScrollController();
  String? _floorShown;

  /// Floor bar: [slots] floors visible at a time (3 on a phone, 5 on a
  /// tablet); more floors scroll sideways. A floor can hide its icon.
  Widget _floorBar(Json d, AppPalette pal, List<Json> floors) {
    final f = tfs(d, 'floorBar');
    final slots = _dev == 'mobile' ? 3 : 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Container(
        height: max(48.0, f * 2.4 + 14),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Color.lerp(pal.screen, pal.ink, 0.07),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: pal.tileEdge),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 4 * (slots - 1)) / slots;
            // Bring the selected floor into view when it changes.
            if (_floorShown != floorId) {
              _floorShown = floorId;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_floorScroll.hasClients) return;
                final i = floors.indexWhere((x) => x['id'] == floorId);
                if (i < 0) return;
                final target = (i * (w + 4) - (c.maxWidth - w) / 2).clamp(0.0, _floorScroll.position.maxScrollExtent).toDouble();
                if ((target - _floorScroll.offset).abs() > 1)
                  _floorScroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
              });
            }
            return ListView(
              controller: _floorScroll,
              scrollDirection: Axis.horizontal,
              children: [
                if (floors.length < slots) SizedBox(width: (c.maxWidth - floors.length * (w + 4)) / 2),
                for (final fl in floors)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () => _goFloor(fl['id'] as String),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: w,
                        decoration: flatDecoration(
                          pal,
                          fl['id'] == floorId ? pal.chipSel : pal.chipFill,
                          radius: BorderRadius.circular(26),
                          glow: fl['id'] == floorId ? pal.chipSel : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (fl['showIcon'] != false && !isNoIcon(fl['icon'] as String?)) ...[
                              iconWidget(fl['icon'] as String? ?? 'stairs', f * 1.25, fl['id'] == floorId ? pal.onChipSel : pal.muted),
                              SizedBox(width: f * 0.45),
                            ],
                            Flexible(
                              child: Text(
                                (fl['title'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: f, fontWeight: FontWeight.w600, color: fl['id'] == floorId ? pal.onChipSel : pal.ink),
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

  // ----------------------------------------------------------------- cards

  /// A page (or the inside of a grid frame) laid out on its grid.
  Widget _grid(Json box, Json? frame, AppPalette basePal) {
    final c = cols(box), r = rows(box);
    final gap = (c >= 6 || r >= 15) ? 6.0 : 10.0;
    // A shadow never grows past about 1.5 gaps, so it does not fall on the next card.
    final pal = basePal.copyWith(shadowCap: gap * 1.5);
    final gas = jsonList(doc['groupAddresses']);
    return LayoutBuilder(
      builder: (context, bc) {
        final cw = (bc.maxWidth - gap * (c - 1)) / c;
        final ch = (bc.maxHeight - gap * (r - 1)) / r;
        final shown = [
          for (final w in jsonList(box['widgets']))
            if (pi(w, 'x') + pi(w, 'w') <= c && pi(w, 'y') + pi(w, 'h') <= r) w,
        ];
        Positioned place(Json w, Widget child) => Positioned(
          left: pi(w, 'x') * (cw + gap),
          top: pi(w, 'y') * (ch + gap),
          width: pi(w, 'w') * cw + (pi(w, 'w') - 1) * gap,
          height: pi(w, 'h') * ch + (pi(w, 'h') - 1) * gap,
          child: child,
        );
        // Does the card have a body (and so a shadow)? A frame only with the
        // "card" style; other cards unless their background is off.
        bool hasBody(Json w) {
          if (w['type'] == 'group') return (w['gstyle'] ?? 'card') == 'card';
          final bg = jsonMap(w['style'])['bg'];
          return bg != 'outline' && bg != 'transparent';
        }

        return Stack(
          // Not clipped: the page keeps a safe margin around the grid, where the
          // shadows of the outer cards are drawn.
          clipBehavior: Clip.none,
          children: [
            // One layer with every shadow, under all the cards.
            for (final w in shown)
              if (hasBody(w))
                place(
                  w,
                  CardShadow(radius: w['type'] == 'group' ? pal.radius + 2 : pal.radius, pal: pal, glow: tileGlowColor(w, pal, engine.st(w['id'] as String))),
                ),
            for (final w in shown) place(w, w['type'] == 'group' ? _frame(w, pal) : _card(w, pal, gas)),
          ],
        );
      },
    );
  }

  Widget _frame(Json w, AppPalette pal) {
    final style = (w['gstyle'] ?? 'card').toString();
    final title = (w['label'] ?? '').toString();
    final showTitle = w['showTitle'] != false && title.isNotEmpty;
    final align = switch (w['titleAlign']) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: style == 'card'
          ? raisedDecoration(
              pal,
              pal.fill(pal.tile),
              radius: BorderRadius.circular(pal.radius + 2),
              lift: pal.cardLift,
              border: pal.border <= 0 ? Border.fromBorderSide(BorderSide.none) : Border.all(color: pal.edge, width: pal.border),
              shadow: false,
            )
          : BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(pal.radius + 2),
              border: style == 'none' || pal.border <= 0 ? null : Border.all(color: pal.edge, width: pal.border),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: Text(title, textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis, style: evoLabelStyle(w, style == 'card' ? pal.ink : pal.sInk)),
            ),
          Expanded(child: _grid(w, w, pal)),
        ],
      ),
    );
  }

  Widget _card(Json w, AppPalette pal, List<Json> gas) {
    final id = w['id'] as String;
    final type = w['type'] as String? ?? '';
    if (type == 'webview') return WebCard(w: w, pal: pal);
    final tile = TileView(w: w, pal: pal, gas: gas, sim: engine.st(id), act: (a, [x]) => _act(w, a, x));
    final tap = const ['switch', 'dimmer', 'ac', 'button', 'scene', 'link'].contains(type) || (type == 'camera' && jsonMap(w['cam'])['view'] == 'button');
    if (!tap) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _act(w, 'tap', null),
      child: PressEffect(radius: pal.radius, dark: (hexColor(jsonMap(w['style'])['bg']) ?? pal.tile).computeLuminance() < 0.35, child: tile),
    );
  }

  void _act(Json w, String action, Object? arg) {
    final type = w['type'];
    // Tapping an AC card switches it on or off, like the dimmer.
    if (type == 'ac' && action == 'tap') action = 'power';
    if (action == 'tune' && type == 'dimmer') {
      showDimmerSheet(context, engine, w, store.palette);
      return;
    }
    if (action == 'popup' && type == 'ac') {
      showAcControls(context, engine, w, store.palette, jsonList(doc['groupAddresses']));
      return;
    }
    if (type == 'camera') {
      if (jsonMap(w['cam'])['view'] == 'button') showCamera(context, w);
      return;
    }
    if (type == 'link') {
      final u = webUri(w['url']);
      if (u == null) {
        _toast('Thẻ này chưa có địa chỉ web.');
      } else if (w['openIn'] == 'external') {
        launchUrl(u, mode: LaunchMode.externalApplication);
      } else {
        openWebPage(context, (w['label'] ?? '').toString(), u, store.palette);
      }
      return;
    }
    engine.act(w, action, arg);
  }
}

// ------------------------------------------------------------------- page bg

class PageBg {
  const PageBg(this.decoration, this.ink, this.muted, this.blur);
  final BoxDecoration decoration;
  final Color ink, muted;
  final double blur;
}

final Map<String, MemoryImage> _images = {};

/// Background of a page (colour or image with brightness, opacity, blur),
/// as designed in the Editor. Null = the theme background.
PageBg? pageBackground(Json? sub, AppPalette pal) {
  final b = jsonMap(sub?['bg']);
  final mode = (b['mode'] ?? 'default').toString();
  if (mode != 'color' && mode != 'image') return null;
  final legacyDim = (b['dim'] as num?)?.toDouble();
  final br = ((b['bright'] as num?)?.toDouble() ?? (legacyDim != null ? 100 - legacyDim : 100)).clamp(20, 150).toDouble();
  final op = (((b['opacity'] as num?) ?? 100).toDouble().clamp(0, 100)) / 100;
  final textMode = (b['text'] ?? 'auto').toString();
  ({Color ink, Color muted}) text(bool darkBg) {
    final dark = textMode == 'light' || (textMode == 'auto' && darkBg);
    return dark ? (ink: Colors.white, muted: Colors.white.withValues(alpha: 0.75)) : (ink: const Color(0xFF1B2320), muted: const Color(0xFF55605C));
  }

  Color shade(Color c) => br < 100 ? Color.lerp(c, Colors.black, (100 - br) / 100)! : Color.lerp(c, Colors.white, (br - 100) / 100)!;
  if (mode == 'color') {
    final c = shade(hexColor(b['color']) ?? pal.screen).withValues(alpha: op);
    final tx = text(Color.alphaBlend(c, pal.screen).computeLuminance() < 0.35);
    return PageBg(BoxDecoration(color: c), tx.ink, tx.muted, 0);
  }
  final data = (b['image'] ?? '').toString();
  final i = data.indexOf('base64,');
  if (i <= 0) return null;
  var img = _images[data];
  if (img == null) {
    try {
      img = MemoryImage(base64Decode(data.substring(i + 7)));
      if (_images.length > 20) _images.clear();
      _images[data] = img;
    } catch (_) {
      return null;
    }
  }
  final blur = ((b['blur'] as num?) ?? 0).toDouble().clamp(0, 20).toDouble();
  final overlay = br < 100 ? Colors.black.withValues(alpha: (100 - br) / 100) : Colors.white.withValues(alpha: (br - 100) / 100);
  final tx = text(op >= 0.5 ? br <= 80 : pal.screen.computeLuminance() < 0.35);
  return PageBg(
    BoxDecoration(
      image: DecorationImage(image: img, fit: BoxFit.cover, opacity: op, colorFilter: ColorFilter.mode(overlay, BlendMode.srcOver)),
    ),
    tx.ink,
    tx.muted,
    blur,
  );
}
