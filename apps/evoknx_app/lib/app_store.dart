import 'dart:convert';
import 'dart:io';

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';
import 'package:path_provider/path_provider.dart';

/// Everything the App keeps on the phone: the configuration from the Editor
/// and the user's own choices (theme, last room, connection, screen on).
class AppStore extends ChangeNotifier {
  Json? config;

  /// Grows each time a configuration is opened (a new home screen starts).
  int configVersion = 0;

  /// Theme chosen on this phone (null = the project's default theme).
  String? themeMode;
  bool keepScreenOn = false;

  /// Text size chosen in the App (0.8–1.5, 1 = as designed in the Editor).
  /// The phone's own font-size setting is ignored: cards sit on a fixed grid.
  double textScale = 1;
  String? lastRoom, lastSub, connectionId;

  /// Last address typed when receiving from the Editor (e.g. 192.168.1.20:47800).
  String? editorAddress;

  final Map<String, Json> _views = {};

  Future<File> _file(String name) async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}${Platform.pathSeparator}$name');
  }

  Future<void> load() async {
    try {
      final f = await _file('evoknx_config.json');
      if (await f.exists()) {
        final o = jsonDecode(await f.readAsString());
        if (isProject(o)) config = (o as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    try {
      final f = await _file('evoknx_prefs.json');
      if (await f.exists()) {
        final p = jsonDecode(await f.readAsString());
        if (p is Map) {
          themeMode = p['theme'] as String?;
          keepScreenOn = p['keepOn'] == true;
          textScale = ((p['textScale'] as num?) ?? 1).toDouble().clamp(0.8, 1.5).toDouble();
          lastRoom = p['room'] as String?;
          lastSub = p['sub'] as String?;
          connectionId = p['conn'] as String?;
          editorAddress = p['editor'] as String?;
        }
      }
    } catch (_) {}
  }

  Future<void> savePrefs() async {
    try {
      final f = await _file('evoknx_prefs.json');
      await f.writeAsString(
        jsonEncode({
          'theme': themeMode,
          'keepOn': keepScreenOn,
          'textScale': textScale,
          'room': lastRoom,
          'sub': lastSub,
          'conn': connectionId,
          'editor': editorAddress,
        }),
      );
    } catch (_) {}
  }

  /// Picks a configuration file (.json from "Xuất cấu hình", or a .evoknx
  /// project) and keeps it. Returns an error message, '' when cancelled,
  /// or null when loaded.
  Future<String?> importConfig() async {
    final XFile? f;
    try {
      f = await openFile(confirmButtonText: 'Mở');
    } catch (e) {
      return 'Không mở được hộp chọn file: $e';
    }
    if (f == null) return '';
    Object? o;
    try {
      o = jsonDecode(utf8.decode(await f.readAsBytes(), allowMalformed: true));
    } catch (_) {
      return 'File “${f.name}” không phải cấu hình EVOKNX.';
    }
    if (!isProject(o)) return 'File “${f.name}” không phải cấu hình EVOKNX.';
    await adopt((o as Map).cast<String, dynamic>());
    return null;
  }

  /// Keeps a configuration (from a file or received from the Editor).
  Future<void> adopt(Json o) async {
    final doc = exportProject(migrate(o));
    config = doc;
    configVersion++;
    _views.clear();
    lastRoom = null;
    lastSub = null;
    connectionId = null;
    try {
      final file = await _file('evoknx_config.json');
      await file.writeAsString(jsonEncode(doc));
    } catch (_) {}
    await savePrefs();
    notifyListeners();
  }

  String get projectName => (jsonMap(config?['project'])['name'] ?? 'EVOKNX').toString();

  /// Theme in use: the phone's choice, else the project's default.
  String get mode {
    final m = themeMode ?? (jsonMap(config?['theme'])['mode'] ?? 'light').toString();
    return const ['light', 'dark', 'graphite', 'sand', 'ocean'].contains(m) ? m : 'light';
  }

  Future<void> setTheme(String? m) async {
    themeMode = m;
    notifyListeners();
    await savePrefs();
  }

  /// [save] false while the slider is being dragged.
  Future<void> setTextScale(double v, {bool save = true}) async {
    textScale = v.clamp(0.8, 1.5).toDouble();
    notifyListeners();
    if (save) await savePrefs();
  }

  Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn = v;
    notifyListeners();
    await savePrefs();
  }

  /// Card palette with the project's card style (corners, border, shadow…).
  AppPalette get palette {
    final t = jsonMap(config?['theme']);
    double n(String k, double d, double lo, double hi) => ((t[k] as num?) ?? d).toDouble().clamp(lo, hi).toDouble();
    return AppPalette.of(mode).copyWith(
      radius: n('cardRadius', 12, 0, 32),
      border: n('cardBorder', 1, 0, 4),
      shadow: n('cardShadow', 0, 0, 20),
      tileOpacity: n('cardOpacity', 100, 0, 100) / 100,
      edgeOpacity: n('cardEdge', 100, 0, 100) / 100,
    );
  }

  bool hasLayout(String dev) => dev == 'mobile' || jsonMap(config?['devices'])[dev] == true;

  /// The configuration laid out for a device (mobile, tabletP, tabletL).
  Json view(String dev) {
    final c = config!;
    if (dev == 'mobile') return c;
    return _views.putIfAbsent(dev, () {
      final copy = (jsonDecode(jsonEncode(c)) as Map).cast<String, dynamic>();
      swapDevice(copy, dev);
      return copy;
    });
  }

  List<Json> get connections => jsonList(config?['connections']);

  Json? get connection {
    final list = connections;
    return list.where((x) => x['id'] == connectionId).firstOrNull ?? list.firstOrNull;
  }

  Future<void> setConnection(String id) async {
    connectionId = id;
    notifyListeners();
    await savePrefs();
  }

  void remember(String? room, String? sub) {
    if (room == lastRoom && sub == lastSub) return;
    lastRoom = room;
    lastSub = sub;
    savePrefs();
  }
}
