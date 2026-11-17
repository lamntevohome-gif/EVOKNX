import 'dart:async';

import 'package:evoknx_ui/evoknx_ui.dart' show Text;
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

import 'app_store.dart';

/// "Receive from computer": while on, the phone can be found by the Editor and takes a configuration it sends, after the person
/// accepts. The mode is off each time the App starts; it can switch itself off after a successful transfer.
class ReceiveMode extends ChangeNotifier {
  ReceiveMode(this.store, this.navigator);
  final AppStore store;
  final GlobalKey<NavigatorState> navigator;

  LanReceiver? _rx;
  String? error;
  String? lastDone;

  bool get on => _rx != null;
  String get phoneName => _rx?.name ?? '';
  int get port => _rx?.port ?? 0;

  Future<void> setOn(bool v) async {
    if (v == on) return;
    if (!v) {
      final r = _rx;
      _rx = null;
      notifyListeners();
      await r?.stop();
      return;
    }
    error = null;
    lastDone = null;
    final r = LanReceiver(_offer);
    final e = await r.start();
    if (e != null) {
      error = e;
      notifyListeners();
      return;
    }
    _rx = r;
    notifyListeners();
  }

  Future<bool> _offer(String from, Json config) async {
    final ctx = navigator.currentContext;
    if (ctx == null) return false;
    final name = (jsonMap(config['project'])['name'] ?? 'EvoKNX').toString();
    final exists = store.hasProfileNamed(name);
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text('Receive from “$from”?'),
        content: Text(
          exists
              ? 'The computer wants to send the profile “$name”. A profile with this name already exists: it will be replaced by the new configuration.'
              : 'The computer wants to send the profile “$name”. It will be added and opened right away.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Decline')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(exists ? 'Replace' : 'Accept')),
        ],
      ),
    );
    if (ok != true) return false;
    final replaced = await store.adopt(config);
    lastDone = replaced ? 'The profile “$name” was updated.' : 'Added the profile “$name”.';
    final c2 = navigator.currentContext;
    if (c2 != null) ScaffoldMessenger.maybeOf(c2)?.showSnackBar(SnackBar(content: Text(lastDone!)));
    notifyListeners();
    // Let the answer reach the computer before the port closes.
    if (store.receiveOffAfter) Future<void>.delayed(const Duration(seconds: 1), () => setOn(false));
    return true;
  }
}

/// The one receive mode of the App (set in main).
late ReceiveMode receiveMode;
