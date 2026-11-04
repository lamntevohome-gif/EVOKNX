import 'dart:convert';
import 'dart:ui' show ImageFilter, TileMode;

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
    engine.writer = knx.write;
    engine.onMessage = _toast;
    engine.onScene = (w) => showScenePopup(context, w, store.palette);
    engine.onOpenUrl = (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    knx.onValue = engine.onBusValue;
    knx.addListener(_onKnx);
    engine.addListener(_rebuild);
    store.addListener(_rebuild);
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
    _pages?.dispose();
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

  Future<void> _connect() async {
    await knx.connect();
  }

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
    if (rooms.isNotEmpty) _goRoom(rooms.first['id'] as String);
  }

  /// Phone, or tablet portrait / landscape when the project has that layout.
  String _deviceFor(Size size, Orientation o) {
    if (size.shortestSide < 600) return 'mobile';
    if (o == Orientation.landscape && store.hasLayout('tabletL')) return 'tabletL';
    if (store.hasLayout('tabletP')) return 'tabletP';
    return 'mobile';
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(store: store, knx: knx),
      ),
    );
    _applyWakelock();
    engine.doc = store.view(_dev);
    if (!knx.connected) _connect();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
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
                _header(d, pal, floor, r),
                if (rooms.length > 1) _roomsBar(d, pal, rooms),
                Expanded(
                  child: r == null
                      ? Center(
                          child: Text('Cấu hình chưa có phòng nào.', style: TextStyle(color: pal.sMuted)),
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
                          itemBuilder: (context, i) => Padding(padding: const EdgeInsets.fromLTRB(14, 6, 14, 6), child: _grid(subs[i], null, pal)),
                        ),
                ),
                if (subs.length > 1) _pageDots(subs, pal),
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
    if (knx.connected) return const SizedBox.shrink();
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

  Widget _header(Json d, AppPalette pal, Json? floor, Json? r) {
    final hide = jsonMap(d['theme'])['hideTitle'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (floor != null)
                  Text(
                    '${floor['title'] ?? ''} ›',
                    style: TextStyle(fontSize: tfs(d, 'crumb'), color: pal.sMuted, fontWeight: FontWeight.w500),
                  ),
                if (!hide && r != null)
                  Text(
                    (r['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: tfs(d, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
                  ),
              ],
            ),
          ),
          Material(
            color: pal.panel,
            shape: CircleBorder(side: BorderSide(color: pal.tileEdge)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openSettings,
              child: SizedBox(width: 40, height: 40, child: Icon(Icons.settings_outlined, size: 20, color: pal.ink)),
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
          return Material(
            color: on ? pal.ink : pal.panel,
            shape: StadiumBorder(side: BorderSide(color: on ? pal.ink : pal.tileEdge)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _goRoom(r['id'] as String),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: f * 1.1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget(r['icon'] as String?, f * 1.25, on ? pal.screen : pal.muted),
                    SizedBox(width: f * 0.45),
                    Text(
                      (r['title'] ?? '').toString(),
                      style: TextStyle(fontSize: f, fontWeight: FontWeight.w500, color: on ? pal.screen : pal.ink),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageDots(List<Json> subs, AppPalette pal) {
    final title = (sub?['title'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Column(
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(fontSize: tfs(doc, 'pageTitle'), fontWeight: FontWeight.w600, color: pal.sMuted),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var k = 0; k < subs.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: k == page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: k == page ? pal.sInk : pal.sMuted.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(3)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _floorBar(Json d, AppPalette pal, List<Json> floors) {
    final f = tfs(d, 'floorBar');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Container(
        height: f * 2.4 + 14,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: pal.panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: pal.tileEdge),
        ),
        child: Row(
          children: [
            for (final fl in floors)
              Expanded(
                child: GestureDetector(
                  onTap: () => _goFloor(fl['id'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: fl['id'] == floorId ? pal.ink : Colors.transparent, borderRadius: BorderRadius.circular(40)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        iconWidget(fl['icon'] as String? ?? 'stairs', f * 1.25, fl['id'] == floorId ? pal.screen : pal.muted),
                        SizedBox(width: f * 0.4),
                        Flexible(
                          child: Text(
                            (fl['title'] ?? '').toString(),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: f, fontWeight: FontWeight.w500, color: fl['id'] == floorId ? pal.screen : pal.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- cards

  /// A page (or the inside of a grid frame) laid out on its grid.
  Widget _grid(Json box, Json? frame, AppPalette pal) {
    final c = cols(box), r = rows(box);
    final gap = (c >= 6 || r >= 15) ? 6.0 : 10.0;
    final gas = jsonList(doc['groupAddresses']);
    return LayoutBuilder(
      builder: (context, bc) {
        final cw = (bc.maxWidth - gap * (c - 1)) / c;
        final ch = (bc.maxHeight - gap * (r - 1)) / r;
        return Stack(
          children: [
            for (final w in jsonList(box['widgets']))
              if (pi(w, 'x') + pi(w, 'w') <= c && pi(w, 'y') + pi(w, 'h') <= r)
                Positioned(
                  left: pi(w, 'x') * (cw + gap),
                  top: pi(w, 'y') * (ch + gap),
                  width: pi(w, 'w') * cw + (pi(w, 'w') - 1) * gap,
                  height: pi(w, 'h') * ch + (pi(w, 'h') - 1) * gap,
                  child: w['type'] == 'group' ? _frame(w, pal) : _card(w, pal, gas),
                ),
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
      decoration: BoxDecoration(
        color: style == 'card' ? pal.fill(pal.tile) : Colors.transparent,
        borderRadius: BorderRadius.circular(pal.radius + 2),
        border: style == 'none' || pal.border <= 0 ? null : Border.all(color: pal.edge, width: pal.border),
        boxShadow: style == 'card' ? pal.shadows : const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: Text(
                title,
                textAlign: align,
                style: TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w600, color: style == 'card' ? pal.ink : pal.sInk),
              ),
            ),
          Expanded(child: _grid(w, w, pal)),
        ],
      ),
    );
  }

  Widget _card(Json w, AppPalette pal, List<Json> gas) {
    final id = w['id'] as String;
    final type = w['type'] as String? ?? '';
    final tile = TileView(w: w, pal: pal, gas: gas, sim: engine.st(id), act: (a, [x]) => _act(w, a, x));
    final tap = const ['switch', 'dimmer', 'button', 'scene', 'link', 'webview'].contains(type) || (type == 'camera' && jsonMap(w['cam'])['view'] == 'button');
    if (!tap) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _act(w, 'tap', null),
      child: PressEffect(radius: pal.radius, dark: (hexColor(jsonMap(w['style'])['bg']) ?? pal.tile).computeLuminance() < 0.35, child: tile),
    );
  }

  void _act(Json w, String action, Object? arg) {
    final type = w['type'];
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
