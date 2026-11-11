import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';

import 'app_store.dart';

/// Takes a project file (.evoknx) that is shared to the App ("Chia sẻ →
/// EvoKNX" from Zalo, Drive, a file manager…) or opened with it. The Android
/// side (MainActivity.kt) copies the file to the cache and tells Dart its path.
class ShareIntake {
  ShareIntake(this.store, this.navigator);
  final AppStore store;
  final GlobalKey<NavigatorState> navigator;

  static const MethodChannel _ch = MethodChannel('evoknx/share');
  bool _busy = false;

  /// Starts listening (App already open) and picks up the file the App was
  /// started with (App was closed).
  void start() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'sharedFile' && call.arguments is String) await _take(call.arguments as String);
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final path = await _ch.invokeMethod<String>('initialFile');
        if (path != null) await _take(path);
      } on MissingPluginException {
        // Not the Android build: nothing to do.
      } catch (_) {}
    });
  }

  void _say(String text) {
    final ctx = navigator.currentContext;
    if (ctx != null) ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _take(String path) async {
    if (_busy) return;
    _busy = true;
    try {
      Object? o;
      try {
        o = jsonDecode(utf8.decode(await File(path).readAsBytes(), allowMalformed: true));
      } catch (_) {
        _say('File chia sẻ không phải dự án EvoKNX (.evoknx).');
        return;
      }
      if (!isProject(o)) {
        _say('File chia sẻ không phải dự án EvoKNX (.evoknx).');
        return;
      }
      final doc = (o as Map).cast<String, dynamic>();
      final name = (jsonMap(doc['project'])['name'] ?? 'EvoKNX').toString();
      final exists = store.hasProfileNamed(name);
      final ctx = navigator.currentContext;
      if (ctx == null) return;
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: Text(exists ? 'Thay thế hồ sơ “$name”?' : 'Thêm hồ sơ “$name”?'),
          content: Text(exists ? 'Đã có hồ sơ cùng tên. Cấu hình mới sẽ thay thế cấu hình cũ của hồ sơ đó.' : 'Hồ sơ mới sẽ được thêm và mở ngay.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(exists ? 'Thay thế' : 'Thêm')),
          ],
        ),
      );
      if (ok != true) return;
      final replaced = await store.adopt(doc);
      _say(replaced ? 'Đã cập nhật hồ sơ “$name”.' : 'Đã thêm hồ sơ “$name”.');
    } finally {
      _busy = false;
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}
