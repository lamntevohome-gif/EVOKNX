import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';

import 'model.dart';

/// Runtime of the cards: what a tap / drag on a card does, the value each
/// card shows, and how values seen on the bus update the cards.
///
/// Same behaviour as the Editor's test mode; the App plugs a real KNX
/// connection into [writer] and feeds bus telegrams to [onBusValue].
class CardEngine extends ChangeNotifier {
  CardEngine(this.doc);

  /// The configuration (project) being shown.
  Json doc;

  /// Per-card state (on, val, pos, sp, mode, fan, ct, rgb…), by card id.
  final Map<String, Map<String, dynamic>> sim = {};
  Map<String, dynamic> st(String id) => sim.putIfAbsent(id, () => <String, dynamic>{});

  /// Sends a value to a group address. Returns an error message or null.
  Future<String?> Function(Json ga, Object value)? writer;

  /// Short messages for the user (missing address, write error…).
  void Function(String message)? onMessage;

  /// Calls a service of Home Assistant (a push button that follows a media player or a remote). An error text, or null.
  Future<String?> Function(String service, String entity, Map<String, dynamic> data)? haCall;

  /// A scene card was pressed (to show its popup).
  void Function(Json card)? onScene;

  /// A web card was pressed.
  void Function(String url)? onOpenUrl;

  Json? gaOf(Json w, String slot) {
    final id = jsonMap(w['bind'])[slot] as String?;
    return id == null ? null : byId(jsonList(doc['groupAddresses']), id);
  }

  /// A card that runs a script does not need an address to write.
  bool runsScript(Json w) => (w['script'] ?? '').toString().isNotEmpty;

  /// What a push button or a scene writes: the text of "Value sent" when its address is a text address
  /// (DPT 16), otherwise a number.
  Object sendValueOf(Json w, String raw, num fallback) {
    if ((gaOf(w, 'write')?['dpt'] ?? '').toString().startsWith('16')) return raw;
    return num.tryParse(raw.replaceAll(',', '.')) ?? fallback;
  }

  void send(Json w, String slot, Object value) {
    final ga = gaOf(w, slot);
    if (ga == null) {
      final sl = slotsFor(w).where((s) => s.key == slot);
      onMessage?.call('${w['label'] ?? ''}: ${sl.isEmpty ? slot : sl.first.label.toLowerCase()} not assigned');
      return;
    }
    writer?.call(ga, value).then((err) {
      if (err != null) onMessage?.call(err);
    });
  }

  /// Pending setpoint of each AC card: − / + taps are gathered and sent once.
  final Map<String, Timer> _spTimers = {};

  @override
  void dispose() {
    for (final t in _spTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  /// Handles a tap / control action on a card.
  void act(Json w, String action, [Object? arg]) {
    final s = st(w['id'] as String);
    switch (w['type']) {
      case 'switch':
        final on = !(s['on'] == true);
        s['on'] = on;
        send(w, 'write', on);
        break;
      case 'dimmer':
        if (action == 'preview') {
          s['val'] = (arg as num).round();
        } else if (action == 'commit') {
          send(w, 'value', ((s['val'] as num?) ?? 0).round());
        } else if (action == 'set') {
          final v = (arg as num).round();
          s['val'] = v;
          send(w, 'value', v);
        } else if (action == 'ct') {
          s['ct'] = arg;
          send(w, 'ctWrite', arg as num);
        } else if (action == 'rgb') {
          s['rgb'] = arg;
          send(w, 'rgbWrite', arg as String);
        } else if (action != 'tune' && action != 'popup') {
          final cur = ((s['val'] as num?) ?? 0) > 0;
          s['val'] = cur ? 0 : 100;
          if (jsonMap(w['bind'])['write'] != null) {
            send(w, 'write', !cur);
          } else {
            send(w, 'value', cur ? 0 : 100);
          }
        }
        break;
      case 'button':
        if (haDirect(w)) {
          final call = haButtonCall(w);
          if (call == null) {
            onMessage?.call('${w['label'] ?? ''}: ${haButtonProblem(w) ?? 'choose the command.'}');
            break;
          }
          (haCall?.call(call.service, call.entity, call.data) ?? Future<String?>.value('Home Assistant is not enabled in the project.')).then((err) {
            if (err != null) onMessage?.call(err);
          });
          break;
        }
        if (gaOf(w, 'write') != null || !runsScript(w)) send(w, 'write', sendValueOf(w, (w['sendValue'] ?? '1').toString(), 1));
        break;
      case 'scene':
        if (gaOf(w, 'write') != null || !runsScript(w)) send(w, 'write', sendValueOf(w, sceneSendValue(w), 0));
        onScene?.call(w);
        break;
      case 'shutter':
        final inv = w['udInvert'] == true;
        if (action == 'up' || action == 'down') {
          final down = action == 'down';
          s['pos'] = down ? 100 : 0;
          send(w, 'upDown', inv ? !down : down);
        } else if (action == 'stop') {
          send(w, 'stop', true);
        } else if (action == 'preview') {
          s['pos'] = (arg as num).round();
        } else if (action == 'commit') {
          send(w, 'position', ((s['pos'] as num?) ?? 0).round());
        } else if (action == 'set') {
          final v = (arg as num).round();
          s['pos'] = v;
          send(w, 'position', v);
        }
        break;
      case 'ac':
        final ac = jsonMap(w['ac']);
        final mn = acMin(ac), mx = acMax(ac), step = acStep(ac);
        if (action == 'plus' || action == 'minus') {
          final sp = double.parse((((s['sp'] as num?) ?? 24) + (action == 'plus' ? step : -step)).clamp(mn, mx).toStringAsFixed(2));
          s['sp'] = sp;
          // Quick taps are gathered: one command shortly after the last tap.
          final id = w['id'] as String;
          _spTimers[id]?.cancel();
          _spTimers[id] = Timer(const Duration(milliseconds: 600), () => send(w, 'setpoint', (st(id)['sp'] as num?) ?? sp));
        } else if (action == 'preview') {
          s['sp'] = acSetpointAt(ac, arg as num);
          s['drag'] = true;
        } else if (action == 'commit') {
          s['drag'] = false;
          send(w, 'setpoint', (s['sp'] as num?) ?? mn);
        } else if (action == 'off') {
          if (s['on'] == true) {
            s['on'] = false;
            send(w, 'power', false);
          }
        } else if (action == 'power') {
          final on = s['on'] != true;
          s['on'] = on;
          send(w, 'power', on);
        } else if (action == 'fan') {
          final k = (arg ?? 'auto').toString();
          s['fan'] = k;
          send(w, 'fan', acFanValue(ac, k));
        } else if (action == 'mode') {
          final k = arg as String;
          if (s['on'] != true) {
            s['on'] = true;
            send(w, 'power', true);
          }
          s['mode'] = k;
          final m = kAcModes.firstWhere((x) => x.key == k);
          if (ac['modeAddr'] == 'separate') {
            send(w, 'mode_$k', true);
          } else {
            send(w, 'mode', (jsonMap(ac['values'])[k] as num?) ?? m.value);
          }
        }
        break;
      case 'remote':
        // A remote control card with KNX addresses: a key sends its value on its own address, or on the one address.
        if (action == 'key') {
          final sd = remoteKnxSend(w, arg as String);
          if (sd == null) {
            onMessage?.call('${w['label'] ?? ''}: ${remoteKeyLabel(w, arg).toLowerCase()} has no value to send');
          } else if (gaOf(w, sd.slot) == null) {
            send(w, sd.slot, 1);
          } else {
            send(w, sd.slot, (gaOf(w, sd.slot)?['dpt'] ?? '').toString().startsWith('16') ? sd.value : (num.tryParse(sd.value.replaceAll(',', '.')) ?? 1));
          }
        }
        break;
      case 'media':
        // A media player card with KNX addresses: play/pause and mute are toggles, volume is 0–100 %.
        if (action == 'play') {
          final on = !(s['on'] == true);
          s['on'] = on;
          send(w, 'play', on);
        } else if (action == 'prev' || action == 'next') {
          send(w, action, true);
        } else if (action == 'mute') {
          final m = !(s['mute'] == true);
          s['mute'] = m;
          send(w, 'mute', m);
        } else if (action == 'shuffle' || action == 'repeat') {
          final on = !(s[action] == true);
          s[action] = on;
          send(w, action, on);
        } else if (action == 'preview') {
          s['vol'] = (arg as num).round();
        } else if (action == 'volume') {
          final v = (arg as num).round();
          s['vol'] = v;
          send(w, 'volume', (v * mediaVolMax(w) / 100).round());
        }
        break;
      case 'link':
      case 'webview':
        final url = (w['url'] ?? '').toString();
        if (url.isNotEmpty) onOpenUrl?.call(url);
        break;
    }
    notifyListeners();
  }

  /// Applies a value seen on the bus to every card bound to that address.
  void onBusValue(String address, Object? value) {
    if (value == null) return;
    String? gid;
    for (final g in jsonList(doc['groupAddresses'])) {
      if (g['address'] == address) gid = g['id'] as String?;
    }
    if (gid == null) return;
    final num? n = value is bool ? (value ? 1 : 0) : (value is num ? value : num.tryParse(value.toString().replaceAll(',', '.')));
    var hit = false;
    for (final w in allCards()) {
      jsonMap(w['bind']).forEach((k, id) {
        if (id != gid) return;
        hit = true;
        final s = st(w['id'] as String);
        switch (w['type']) {
          case 'switch':
            s['on'] = (n ?? 0) != 0;
            break;
          case 'dimmer':
            if (k == 'write') {
              s['val'] = (n ?? 0) != 0 ? (((s['val'] as num?) ?? 0) > 0 ? s['val'] : 100) : 0;
            } else if (k == 'value' || k == 'status') {
              s['val'] = n;
            } else if (k == 'ctWrite' || k == 'ctStatus') {
              s['ct'] = n;
            } else if (k == 'rgbWrite' || k == 'rgbStatus') {
              s['rgb'] = value.toString();
            }
            break;
          case 'value':
            s['val'] = n;
            // The value as received (text too): a card in the number look shows it when it is not a number.
            s['raw'] = value;
            break;
          case 'shutter':
            if (k == 'status' || k == 'position') s['pos'] = n;
            break;
          case 'media':
            if (k == 'play' || k == 'playSt') s['on'] = (n ?? 0) != 0;
            if (k == 'mute' || k == 'muteSt') s['mute'] = (n ?? 0) != 0;
            if (k == 'shuffle' || k == 'shuffleSt') s['shuffle'] = (n ?? 0) != 0;
            if (k == 'repeat' || k == 'repeatSt') s['repeat'] = (n ?? 0) != 0;
            if ((k == 'volume' || k == 'volumeSt') && n != null) s['vol'] = (n * 100 / mediaVolMax(w)).round();
            break;
          case 'ac':
            final ac = jsonMap(w['ac']);
            if (k == 'power' || k == 'powerSt') s['on'] = (n ?? 0) != 0;
            if (k == 'setpoint' || k == 'setpointSt') s['sp'] = n;
            if (k == 'current') s['cur'] = n;
            if (k == 'mode' || k == 'modeSt') {
              for (final m in kAcModes) {
                if (((jsonMap(ac['values'])[m.key] as num?) ?? m.value) == n) s['mode'] = m.key;
              }
            }
            if (k == 'fan' || k == 'fanSt') {
              for (final lv in acFanLevels(ac)) {
                if (acFanValue(ac, lv) == n) s['fan'] = lv;
              }
            }
            if (k.startsWith('mode_') || k.startsWith('modeSt_')) {
              if ((n ?? 0) != 0) {
                s['mode'] = k.substring(k.indexOf('_') + 1);
                s['on'] = true;
              }
            }
            break;
        }
      });
    }
    if (hit) notifyListeners();
  }

  // ------------------------------------------------------------ reminders

  /// Cards that can be on or off and so can remind the person that they were left on.
  static bool canRemind(Json w) => w['type'] == 'switch' || w['type'] == 'dimmer' || w['type'] == 'ac' || w['type'] == 'value';

  /// When a card reminds: 'on' (it is on: remind to turn it off), 'off' (it is off: remind to turn it on) or null.
  /// An older project has remind: true, which means 'on'.
  static String? remindMode(Json w) {
    if (!canRemind(w)) return null;
    final v = w['remind'];
    if (w['type'] == 'value') {
      // A Value card reminds when its number meets a condition: {op: '>' | '<' | '=' | '!=', v: number}.
      if (v is! Map) return null;
      final op = v['op'];
      return (op == '>' || op == '<' || op == '=' || op == '!=') && v['v'] is num ? 'value' : null;
    }
    if (v == true || v == 'on') return 'on';
    if (v == 'off') return 'off';
    return null;
  }

  /// True when the card is on, false when it is off, null while its state is not known yet.
  bool? onState(Json w) {
    final s = st(w['id'] as String);
    switch (w['type']) {
      case 'switch' || 'ac':
        final v = s['on'];
        return v is bool ? v : null;
      case 'dimmer':
        final v = s['val'];
        return v is num ? v > 0 : null;
    }
    return null;
  }

  /// True when the card is on (a card whose state is not known yet is not).
  bool isOn(Json w) => onState(w) == true;

  /// Cards that remind now: the ones set to "When on" that are on, and the ones set to "When off" that are off (a card whose state is
  /// not known yet never reminds), except those dismissed until the App is opened again.
  final Set<String> dismissed = {};
  List<Json> reminders() {
    final out = <Json>[];
    for (final w in allCards()) {
      final mode = remindMode(w);
      if (mode == null) continue;
      final id = w['id'] as String;
      final due = _due(w, mode);
      if (due == true) {
        if (!dismissed.contains(id)) out.add(w);
      } else if (due == false) {
        // The state changed back: if it comes again, it reminds again.
        dismissed.remove(id);
      }
    }
    return out;
  }

  /// Whether the card's reminder is due now; null while its state or value is not known yet.
  bool? _due(Json w, String mode) {
    if (mode == 'value') {
      final n = st(w['id'] as String)['val'];
      if (n is! num) return null;
      final r = jsonMap(w['remind']);
      final x = n.toDouble(), t = (r['v'] as num).toDouble();
      return switch (r['op']) {
        '>' => x > t,
        '<' => x < t,
        '=' => (x - t).abs() < 1e-6,
        _ => (x - t).abs() >= 1e-6,
      };
    }
    final on = onState(w);
    if (on == null) return null;
    return mode == 'on' ? on : !on;
  }

  void dismissReminder(Json w) {
    dismissed.add(w['id'] as String);
    notifyListeners();
  }

  /// Turns a card off (the quick action of a reminder).
  void turnOff(Json w) {
    final s = st(w['id'] as String);
    switch (w['type']) {
      case 'switch':
        if (s['on'] == true) {
          s['on'] = false;
          send(w, 'write', false);
        }
        break;
      case 'dimmer':
        if (((s['val'] as num?) ?? 0) > 0) {
          s['val'] = 0;
          if (jsonMap(w['bind'])['write'] != null) {
            send(w, 'write', false);
          } else {
            send(w, 'value', 0);
          }
        }
        break;
      case 'ac':
        act(w, 'off');
        return;
    }
    notifyListeners();
  }

  /// Turns a card on (the quick action of a reminder to switch something on).
  void turnOn(Json w) {
    final s = st(w['id'] as String);
    switch (w['type']) {
      case 'switch':
        if (s['on'] != true) {
          s['on'] = true;
          send(w, 'write', true);
        }
        break;
      case 'dimmer':
        if (((s['val'] as num?) ?? 0) <= 0) {
          s['val'] = 100;
          if (jsonMap(w['bind'])['write'] != null) {
            send(w, 'write', true);
          } else {
            send(w, 'value', 100);
          }
        }
        break;
      case 'ac':
        if (s['on'] != true) act(w, 'power');
        return;
    }
    notifyListeners();
  }

  /// Where a card is: its room and its page, or null.
  ({Json room, Json sub})? locate(String cardId) {
    for (final r in roomsOf(doc)) {
      for (final sb in subsOf(r)) {
        if (cardsOf(sb).any((w) => w['id'] == cardId)) return (room: r, sub: sb);
      }
    }
    return null;
  }

  /// Addresses to read when the App opens, for the cards that remind (wherever they are).
  List<Json> readsForReminders() => _readsOf(allCards().where((w) => remindMode(w) != null));

  /// Every card of the configuration, cards inside grid frames included.
  Iterable<Json> allCards() sync* {
    for (final r in jsonList(doc['pages'])) {
      for (final sb in subsOf(r)) {
        yield* cardsOf(sb);
      }
    }
  }

  static Iterable<Json> cardsOf(Json sub) sync* {
    for (final w in jsonList(sub['widgets'])) {
      yield w;
      if (w['type'] == 'group') yield* jsonList(w['widgets']);
    }
  }

  /// Addresses to read when a page opens: the status address of each card,
  /// or its main address when it has no status address.
  List<Json> readsFor(Json sub) {
    return _readsOf(cardsOf(sub));
  }

  List<Json> _readsOf(Iterable<Json> cards) {
    const status = {
      'status',
      'ctStatus',
      'rgbStatus',
      'powerSt',
      'setpointSt',
      'modeSt',
      'fanSt',
      'current',
      'playSt',
      'muteSt',
      'volumeSt',
      'shuffleSt',
      'repeatSt',
    };
    const main = {'write', 'value', 'position', 'setpoint', 'power', 'mode', 'fan', 'play', 'mute', 'volume', 'shuffle', 'repeat'};
    final out = <Json>[];
    final seen = <String>{};
    for (final w in cards) {
      if (w['type'] == 'button' || w['type'] == 'scene') continue;
      final b = jsonMap(w['bind']);
      final keys = b.keys.where((k) => status.contains(k) || k.startsWith('modeSt_')).toList();
      final use = keys.isNotEmpty ? keys : b.keys.where(main.contains).toList();
      for (final k in use) {
        final id = b[k];
        if (id is! String || !seen.add(id)) continue;
        final ga = byId(jsonList(doc['groupAddresses']), id);
        if (ga != null) out.add(ga);
      }
    }
    return out;
  }
}
