import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';
import 'package:path_provider/path_provider.dart';

/// The Editor's own connection to Home Assistant (Connections tab): opened and
/// closed by the user like the KNX bus, closed by itself when the Editor is
/// closed. It is used to list the entities of Home Assistant.
class HaLinkController extends ChangeNotifier {
  HaLinkController() {
    unawaited(_loadSaved());
  }

  HaSession? _s;
  HaConnection state = HaConnection.disconnected;

  /// An error or a short note for the status line.
  String? message;
  String? version;

  /// The entities saved by "Update Entity" (kept on this computer, so they can be chosen without a connection).
  List<HaEntity>? entities;

  /// When the entities were last updated.
  DateTime? entitiesAt;

  /// The services of Home Assistant with their fields (domain → service), loaded when the connection is made.
  Map<String, Map<String, HaService>>? serviceInfo;

  /// The names of the services (domain → names).
  Map<String, List<String>>? get services => serviceInfo == null ? null : {for (final e in serviceInfo!.entries) e.key: (e.value.keys.toList()..sort())};

  bool get connected => state == HaConnection.connected;
  bool get connecting => state == HaConnection.connecting;

  void _set(HaConnection s, [String? msg]) {
    state = s;
    message = msg;
    notifyListeners();
  }

  /// Opens the connection.
  Future<void> connect(String url, String token) async {
    if (connected || connecting) return;
    if (url.trim().isEmpty || token.trim().isEmpty) {
      _set(HaConnection.failed, 'Enter the address and token first.');
      return;
    }
    _set(HaConnection.connecting);
    try {
      final s = await HaSession.open(url.trim(), token.trim());
      _s = s;
      version = s.version;
      // If the connection drops by itself (not closed by the user), say so.
      unawaited(
        s.closed.then((_) {
          if (identical(_s, s)) {
            _s = null;
            _set(HaConnection.failed, 'Home Assistant connection lost. Click Connect to reconnect.');
          }
        }),
      );
      _set(HaConnection.connected);
      unawaited(_loadServices(s));
    } on HaException catch (e) {
      _set(HaConnection.failed, e.message);
    }
  }

  /// Calls a Home Assistant service ("light.turn_on"); used to test a script. An error text, or null.
  Future<String?> callService(String service, String entity, Map<String, dynamic> data) async {
    final s = _s;
    if (s == null || !connected) return 'Connect to Home Assistant first (Connections tab).';
    final i = service.indexOf('.');
    if (i <= 0) return 'The service “$service” is not valid, use the form domain.service.';
    try {
      await s.callServiceRaw(service.substring(0, i), service.substring(i + 1), data, entity);
      return null;
    } on HaException catch (e) {
      return e.message;
    }
  }

  Future<void> _loadServices(HaSession s) async {
    try {
      serviceInfo = await s.getServiceInfo();
      notifyListeners();
    } catch (_) {}
  }

  /// Closes the connection (the list of entities stays).
  Future<void> disconnect() async {
    final s = _s;
    _s = null;
    if (s != null) await s.close();
    if (state != HaConnection.disconnected) _set(HaConnection.disconnected);
  }

  Future<File> _savedFile() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}ha_entities.json');
  }

  Future<void> _loadSaved() async {
    try {
      final f = await _savedFile();
      if (!await f.exists()) return;
      final o = jsonDecode(await f.readAsString());
      if (o is! Map || o['entities'] is! List) return;
      entities = [
        for (final e in o['entities'] as List)
          if (e is Map) HaEntity.fromJson(Map<String, dynamic>.from(e)),
      ];
      entitiesAt = DateTime.tryParse('${o['savedAt']}');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save(List<HaEntity> list) async {
    try {
      final f = await _savedFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'entities': [for (final e in list) e.toJson()],
        }),
      );
    } catch (_) {}
  }

  /// "Update Entity": asks Home Assistant for all its entities and saves them. Null (with [message]) on failure.
  Future<List<HaEntity>?> updateEntities() async {
    final list = await fetchEntities();
    if (list != null) {
      entitiesAt = DateTime.now();
      await _save(list);
      notifyListeners();
    }
    return list;
  }

  /// Asks Home Assistant for all its entities. Null (with [message]) on failure.
  Future<List<HaEntity>?> fetchEntities() async {
    final s = _s;
    if (s == null || !connected) return null;
    try {
      final list = await s.getStates();
      entities = list;
      notifyListeners();
      return list;
    } on HaException catch (e) {
      message = e.message;
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    final s = _s;
    _s = null;
    unawaited(s?.close());
    super.dispose();
  }
}
