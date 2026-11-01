import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Version shown in Settings → Giới thiệu.
const String kEditorVersion = '0.4.0';

/// Editor preferences (stored in the app data folder, not in projects).
class AppSettings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;

  /// Automatic save into the project file, in minutes (0 = off).
  int autosaveMinutes = 5;

  /// Folder suggested by "Lưu thành" for projects that have no file yet.
  String? defaultFolder;

  static const List<int> autosaveChoices = [0, 1, 2, 5, 10];

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}settings.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      themeMode = switch (j['theme']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.light,
      };
      final a = (j['autosaveMinutes'] as num?)?.toInt();
      if (a != null && autosaveChoices.contains(a)) autosaveMinutes = a;
      final dir = j['defaultFolder'];
      if (dir is String && dir.isNotEmpty) defaultFolder = dir;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'theme': themeMode.name, 'autosaveMinutes': autosaveMinutes, 'defaultFolder': defaultFolder}));
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _persist();
  }

  Future<void> setAutosaveMinutes(int m) async {
    autosaveMinutes = autosaveChoices.contains(m) ? m : 5;
    notifyListeners();
    await _persist();
  }

  Future<void> setDefaultFolder(String? path) async {
    defaultFolder = (path == null || path.isEmpty) ? null : path;
    notifyListeners();
    await _persist();
  }
}

final AppSettings appSettings = AppSettings();
