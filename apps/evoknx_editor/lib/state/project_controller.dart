import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';

/// Holds the open project, file path, undo/redo history and autosave.
class ProjectController extends ChangeNotifier {
  Json doc = newProject('Dự án mới');
  String? path;
  bool dirty = false;
  List<String> recent = [];

  final List<String> _undo = [];
  final List<String> _redo = [];
  String? _lastCoalesce;
  DateTime _lastCoalesceAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _autosaveTimer;
  Timer? _fileAutosaveTimer;

  /// When the project file was last written (manually or automatically).
  DateTime? savedAt;
  bool lastSaveWasAuto = false;
  Directory? _dataDir;

  /// Session (crash-recovery) file. Windows opened by double-clicking a
  /// project get their own session file so several windows never collide.
  String _sessionName = 'autosave.evoknx';

  static const _typeGroup = XTypeGroup(label: 'Dự án EVOKNX', extensions: ['evoknx', 'json']);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get fileName => path?.split(Platform.pathSeparator).last;
  String get projectName => (jsonMap(doc['project'])['name'] as String?) ?? 'Dự án mới';
  List<Json> get connections => jsonList(doc['connections']);
  List<Json> get groupAddresses => jsonList(doc['groupAddresses']);
  Json? gaById(String? id) {
    if (id == null) return null;
    for (final g in groupAddresses) {
      if (g['id'] == id) return g;
    }
    return null;
  }

  Json? gaByAddress(String address) {
    for (final g in groupAddresses) {
      if (g['address'] == address) return g;
    }
    return null;
  }

  Future<void> init({String? openPath}) async {
    appSettings.addListener(_configureFileAutosave);
    _configureFileAutosave();
    if (openPath != null) _sessionName = 'autosave-${openPath.toLowerCase().hashCode.toUnsigned(32).toRadixString(16)}.evoknx';
    try {
      _dataDir = await getApplicationSupportDirectory();
      if (openPath != null) {
        final rf = File('${_dataDir!.path}${Platform.pathSeparator}recent.json');
        if (await rf.exists()) recent = (jsonDecode(await rf.readAsString()) as List).cast<String>();
        final po = jsonDecode(await File(openPath).readAsString());
        if (po is Map && isProject(po)) {
          doc = migrate(po.cast<String, dynamic>());
          path = openPath;
          dirty = false;
          _remember(openPath);
          return;
        }
      }
      final r = File('${_dataDir!.path}${Platform.pathSeparator}recent.json');
      if (await r.exists()) recent = (jsonDecode(await r.readAsString()) as List).cast<String>();
      final a = File('${_dataDir!.path}${Platform.pathSeparator}$_sessionName');
      if (await a.exists()) {
        final o = jsonDecode(await a.readAsString());
        if (o is Map && o['doc'] is Map && isProject(o['doc'])) {
          doc = migrate((o['doc'] as Map).cast<String, dynamic>());
          path = o['path'] as String?;
          dirty = o['dirty'] == true;
          return;
        }
      }
    } catch (_) {}
    doc = _starter('Dự án mới');
  }

  Json _starter(String name) {
    final d = newProject(name);
    final f = jsonList(d['floors']).first;
    (d['pages'] as List).add(makeRoom('Phòng khách', floorId: f['id'] as String));
    return d;
  }

  // -------------------------------------------------------------- editing

  /// Applies [fn] to the document with undo support. Calls with the same
  /// [coalesce] key within 1.5 s share a single undo step (typing).
  void mutate(void Function(Json doc) fn, {String? coalesce}) {
    final now = DateTime.now();
    final merge = coalesce != null && coalesce == _lastCoalesce && now.difference(_lastCoalesceAt) < const Duration(milliseconds: 1500);
    if (!merge) {
      _undo.add(jsonEncode(doc));
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    _lastCoalesce = coalesce;
    _lastCoalesceAt = now;
    fn(doc);
    dirty = true;
    _changed();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(jsonEncode(doc));
    doc = (jsonDecode(_undo.removeLast()) as Map).cast<String, dynamic>();
    _lastCoalesce = null;
    dirty = true;
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(jsonEncode(doc));
    doc = (jsonDecode(_redo.removeLast()) as Map).cast<String, dynamic>();
    _lastCoalesce = null;
    dirty = true;
    _changed();
  }

  void _changed() {
    notifyListeners();
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), _autosave);
  }

  Future<void> _autosave() async {
    final d = _dataDir;
    if (d == null) return;
    try {
      await File('${d.path}${Platform.pathSeparator}$_sessionName').writeAsString(jsonEncode({'path': path, 'dirty': dirty, 'doc': doc}));
    } catch (_) {}
  }

  // -------------------------------------------------------------- files

  /// (Re)starts the periodic save into the project file.
  void _configureFileAutosave() {
    _fileAutosaveTimer?.cancel();
    final m = appSettings.autosaveMinutes;
    if (m <= 0) return;
    _fileAutosaveTimer = Timer.periodic(Duration(minutes: m), (_) async {
      if (path == null || !dirty) return;
      final ok = await _writeTo(path!);
      if (ok) {
        lastSaveWasAuto = true;
        notifyListeners();
      }
    });
  }

  Future<bool> _writeTo(String p) async {
    try {
      await File(p).writeAsString(const JsonEncoder.withIndent('  ').convert(doc));
      path = p;
      dirty = false;
      savedAt = DateTime.now();
      _remember(p);
      _changed();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asks for a location (Save As). Returns the chosen path or null.
  Future<String?> _askLocation() async {
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [_typeGroup],
      suggestedName: path != null ? fileName! : '${_slug(projectName)}.evoknx',
      initialDirectory: path != null ? File(path!).parent.path : appSettings.defaultFolder,
      confirmButtonText: 'Lưu',
    );
    if (loc == null) return null;
    return loc.path.toLowerCase().endsWith('.evoknx') ? loc.path : '${loc.path}.evoknx';
  }

  /// Saves before closing the window. Returns true when the project is safe
  /// to close (saved), false when the user cancelled or saving failed.
  Future<bool> saveForClose() async {
    final p = path ?? await _askLocation();
    if (p == null) return false;
    return _writeTo(p);
  }

  /// Replaces the project with a newly created document (undoable).
  void replaceDocument(Json d) {
    mutate((_) {});
    doc = migrate(d);
    path = null;
    dirty = true;
    savedAt = null;
    _changed();
  }

  void newDocument(String name) {
    mutate((_) {});
    doc = _starter(name);
    path = null;
    dirty = true;
    _changed();
  }

  /// Opens a project file. Returns an error message or null.
  Future<String?> open([String? filePath]) async {
    String? p = filePath;
    if (p == null) {
      final f = await openFile(acceptedTypeGroups: const [_typeGroup], confirmButtonText: 'Mở');
      if (f == null) return null;
      p = f.path;
    }
    try {
      final o = jsonDecode(await File(p).readAsString());
      if (!isProject(o)) return 'File không đúng định dạng dự án EVOKNX.';
      mutate((_) {});
      doc = migrate((o as Map).cast<String, dynamic>());
      path = p;
      dirty = false;
      _remember(p);
      _changed();
      return null;
    } catch (e) {
      return 'Không mở được file: $e';
    }
  }

  Future<String?> save({bool saveAs = false}) async {
    var p = path;
    if (p == null || saveAs) {
      p = await _askLocation();
      if (p == null) return null;
    }
    final ok = await _writeTo(p);
    lastSaveWasAuto = false;
    return ok ? 'Đã lưu ${p.split(Platform.pathSeparator).last}' : 'Không lưu được file. Kiểm tra quyền ghi của thư mục.';
  }

  /// Exports the configuration file for the mobile/tablet app.
  Future<String?> exportConfig() async {
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Cấu hình App', extensions: ['json']),
      ],
      suggestedName: '${_slug(projectName)}-config.json',
      confirmButtonText: 'Xuất',
    );
    if (loc == null) return null;
    mutate((d) {
      final p = jsonMap(d['project']);
      p['revision'] = ((p['revision'] as num?) ?? 0) + 1;
      p['updatedAt'] = DateTime.now().toIso8601String();
      d['menu'] = {'style': 'grid', 'items': jsonList(d['pages']).map((r) => r['id']).toList()};
    });
    final out = exportProject(doc);
    final file = loc.path.toLowerCase().endsWith('.json') ? loc.path : '${loc.path}.json';
    await File(file).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    return 'Đã xuất cấu hình ${file.split(Platform.pathSeparator).last}';
  }

  void _remember(String p) {
    recent.remove(p);
    recent.insert(0, p);
    if (recent.length > 8) recent = recent.sublist(0, 8);
    final d = _dataDir;
    if (d != null) {
      File('${d.path}${Platform.pathSeparator}recent.json').writeAsString(jsonEncode(recent)).catchError((_) => File(''));
    }
  }

  String _slug(String s) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    final r = b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return r.isEmpty ? 'du-an' : r;
  }

  // -------------------------------------------------------------- ETS

  Future<({EtsResult? result, String? error, String? fileName})> pickEts() async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ETS', extensions: ['knxproj', 'csv', 'xml', 'txt']),
      ],
      confirmButtonText: 'Nhập',
    );
    if (f == null) return (result: null, error: null, fileName: null);
    try {
      final bytes = await f.readAsBytes();
      return (result: parseEts(bytes, fileName: f.name), error: null, fileName: f.name);
    } on EtsException catch (e) {
      return (result: null, error: e.message, fileName: f.name);
    } catch (e) {
      return (result: null, error: 'Không đọc được file: $e', fileName: f.name);
    }
  }
}
