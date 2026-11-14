import 'ha_commands.dart';
import 'project.dart';

/// The keys of a remote control card, with the name shown in the Editor.
const List<(String, String)> kRemoteKeys = [
  ('up', 'Up'),
  ('down', 'Down'),
  ('left', 'Left'),
  ('right', 'Right'),
  ('ok', 'OK'),
  ('back', 'Back'),
  ('home', 'Home'),
  ('menu', 'Menu'),
  ('volup', 'Volume up'),
  ('voldown', 'Volume down'),
  ('mute', 'Mute'),
  ('playpause', 'Play or pause'),
  ('prev', 'Previous'),
  ('next', 'Next'),
  ('power', 'Power'),
];

/// The names of the keys (the `command` of `remote.send_command`) for some platforms. The names depend on the
/// integration of Home Assistant that makes the remote: check them, and change the ones that differ (a key without a
/// name is left out of the card).
const Map<String, Map<String, String>> kRemotePresets = {
  'Android TV': {
    'up': 'DPAD_UP',
    'down': 'DPAD_DOWN',
    'left': 'DPAD_LEFT',
    'right': 'DPAD_RIGHT',
    'ok': 'DPAD_CENTER',
    'back': 'BACK',
    'home': 'HOME',
    'menu': 'MENU',
    'volup': 'VOLUME_UP',
    'voldown': 'VOLUME_DOWN',
    'mute': 'MUTE',
    'playpause': 'MEDIA_PLAY_PAUSE',
    'prev': 'MEDIA_PREVIOUS',
    'next': 'MEDIA_NEXT',
    'power': 'POWER',
  },
  'Apple TV': {
    'up': 'up',
    'down': 'down',
    'left': 'left',
    'right': 'right',
    'ok': 'select',
    'back': 'menu',
    'home': 'home',
    'menu': 'top_menu',
    'volup': 'volume_up',
    'voldown': 'volume_down',
    'mute': '',
    'playpause': 'play_pause',
    'prev': 'previous',
    'next': 'next',
    'power': 'suspend',
  },
  'Roku': {
    'up': 'up',
    'down': 'down',
    'left': 'left',
    'right': 'right',
    'ok': 'select',
    'back': 'back',
    'home': 'home',
    'menu': 'info',
    'volup': 'volume_up',
    'voldown': 'volume_down',
    'mute': 'volume_mute',
    'playpause': 'play',
    'prev': 'reverse',
    'next': 'forward',
    'power': 'power',
  },
  'Samsung TV': {
    'up': 'KEY_UP',
    'down': 'KEY_DOWN',
    'left': 'KEY_LEFT',
    'right': 'KEY_RIGHT',
    'ok': 'KEY_ENTER',
    'back': 'KEY_RETURN',
    'home': 'KEY_HOME',
    'menu': 'KEY_MENU',
    'volup': 'KEY_VOLUP',
    'voldown': 'KEY_VOLDOWN',
    'mute': 'KEY_MUTE',
    'playpause': 'KEY_PLAY',
    'prev': 'KEY_REWIND',
    'next': 'KEY_FF',
    'power': 'KEY_POWER',
  },
  'Custom': {},
};

/// The settings of a remote control card (`remote`), with their defaults.
Json remoteSettings(Json w) {
  final r = jsonMap(w['remote']);
  return {
    'entity': (r['entity'] ?? '').toString().trim(),
    'preset': (r['preset'] ?? 'Android TV').toString(),
    'device': (r['device'] ?? '').toString().trim(),
    'keys': jsonMap(r['keys']),
    'dpad': r['dpad'] != false,
    'nav': r['nav'] != false,
    'volume': r['volume'] != false,
    'transport': r['transport'] != false,
    'touchpad': r['touchpad'] == true,
    'repeatMs': (r['repeatMs'] as num?)?.toInt() ?? 150,
  };
}

/// The name of a key for the integration ('' = the card has no such key). A name typed on the card wins over the one
/// of the platform.
String remoteCommand(Json w, String key) {
  for (final c in remoteCustom(w)) {
    if (c['id'] == key) return (c['cmd'] ?? '').toString().trim();
  }
  final r = remoteSettings(w);
  final own = jsonMap(r['keys'])[key];
  if (own != null && own.toString().trim().isNotEmpty) return own.toString().trim();
  return kRemotePresets[r['preset']]?[key] ?? '';
}

/// The service call that a key of a remote control card makes, or null when the key has no name or no remote is chosen.
HaButtonCall? remoteCall(Json w, String key) {
  final r = remoteSettings(w);
  final entity = r['entity'] as String;
  // The power keys of the top bar turn the remote on or off.
  if (entity.isNotEmpty && (key == 'poweron' || key == 'poweroff')) return HaButtonCall(key == 'poweron' ? 'remote.turn_on' : 'remote.turn_off', entity, {});
  final cmd = remoteCommand(w, key);
  if (entity.isEmpty || cmd.isEmpty) return null;
  return HaButtonCall('remote.send_command', entity, {'command': cmd, if ((r['device'] as String).isNotEmpty) 'device': r['device']});
}

/// What is wrong with a remote control card (null = nothing).
String? remoteProblem(Json w) {
  if (remoteIsKnx(w)) return null;
  final id = remoteSettings(w)['entity'] as String;
  if (id.isEmpty) return 'choose the remote.';
  if (!id.startsWith('remote.') && !id.startsWith('media_player.')) return 'the entity must be a remote (remote.…).';
  return null;
}

// ======================================================================
// The layout and the sources of a remote control card
// ======================================================================

/// A remote control card whose source is KNX (addresses) and not a remote of Home Assistant.
bool remoteIsKnx(Json w) => w['type'] == 'remote' && w['source'] == 'knx';

/// Changes the source of a remote control card: 'knx' (addresses) or 'ha' (a remote of Home Assistant). What belongs to
/// the other source is forgotten. False when the card already has that source.
bool switchRemoteSource(Json w, String source) {
  if (w['type'] != 'remote' || remoteIsKnx(w) == (source == 'knx')) return false;
  if (source == 'knx') {
    w['source'] = 'knx';
    final r = jsonMap(w['remote']);
    r['entity'] = '';
    w['remote'] = r;
  } else {
    w.remove('source');
    w['bind'] = <String, dynamic>{};
  }
  return true;
}

/// The parts of the card that are placed on its grid (the top bar with the title and the power keys is fixed).
/// "dpad" is the ring (up, down, left, right, OK), "touchpad" is the pad; the others are one key each.
const List<(String, String)> kRemoteElements = [
  ('poweron', 'Power on'),
  ('poweroff', 'Power off'),
  ('dpad', 'Ring (up, down, left, right, OK)'),
  ('touchpad', 'Touchpad'),
  ('back', 'Back'),
  ('home', 'Home'),
  ('menu', 'Menu'),
  ('voldown', 'Volume down'),
  ('mute', 'Mute'),
  ('volup', 'Volume up'),
  ('prev', 'Previous'),
  ('playpause', 'Play or pause'),
  ('next', 'Next'),
];

/// The keys of the ring.
const List<String> kRemoteRing = ['up', 'down', 'left', 'right', 'ok'];

/// The size in cells of the parts that are bigger than one cell.
const Map<String, (int, int)> kRemoteSpan = {'dpad': (3, 3), 'touchpad': (3, 2)};

/// The size in cells of a part: the one chosen in the window that arranges the keys, or the usual one.
(int, int) remoteSpan(Json w, String id) {
  final own = jsonMap(jsonMap(jsonMap(w['remote'])['span'])[id]);
  final d = kRemoteSpan[id] ?? (1, 1);
  final cw = (own['w'] as num?)?.toInt() ?? d.$1, rh = (own['h'] as num?)?.toInt() ?? d.$2;
  return (cw.clamp(1, 6), rh.clamp(1, 8));
}

/// A part of the card on its grid: [id] (an element, or the id of a custom button), the cell (column [c], row [r]) and
/// its size in cells.
class RemoteItem {
  const RemoteItem(this.id, this.c, this.r, this.cw, this.rh);
  final String id;
  final int c, r, cw, rh;
  RemoteItem at(int col, int row) => RemoteItem(id, col, row, cw, rh);
}

/// The custom buttons of the card: {id, label, icon, cmd (the key name for Home Assistant), …}.
List<Json> remoteCustom(Json w) => jsonList(jsonMap(w['remote'])['custom']);

/// The number of columns of the grid (3 to 6).
int remoteCols(Json w) => ((jsonMap(w['remote'])['cols'] as num?)?.toInt() ?? 3).clamp(3, 6);

/// Whether a part is hidden. A card made before the parts could be hidden one by one keeps its group settings.
bool remoteHidden(Json w, String id) {
  final r = jsonMap(w['remote']);
  final own = jsonMap(r['hide'])[id];
  if (own is bool) return own;
  switch (id) {
    case 'poweron':
      return r['topPowerOn'] == false;
    case 'poweroff':
      return r['topPowerOff'] == false;
    case 'dpad':
      return r['dpad'] == false;
    case 'touchpad':
      return r['touchpad'] != true;
    case 'back':
    case 'home':
    case 'menu':
      return r['nav'] == false;
    case 'voldown':
    case 'mute':
    case 'volup':
      return r['volume'] == false;
    case 'prev':
    case 'playpause':
    case 'next':
      return r['transport'] == false;
  }
  return false;
}

/// Whether the top bar shows the title (the power keys are keys of the grid).
bool remoteShowTop(Json w, String part) {
  final v = jsonMap(w['remote'])['top$part'];
  return v != false;
}

/// The parts that are shown, each in its cell. A part keeps the cell it was given (by dragging); a part without one
/// (or whose cell is taken, or outside the grid) takes the first free place, row by row.
List<RemoteItem> remoteItems(Json w) {
  final cols = remoteCols(w);
  final lay = jsonMap(jsonMap(w['remote'])['layout']);
  final ids = [
    for (final e in kRemoteElements)
      if (!remoteHidden(w, e.$1)) e.$1,
    for (final c in remoteCustom(w))
      if (!remoteHidden(w, (c['id'] ?? '').toString())) (c['id'] ?? '').toString(),
  ];
  (int, int) span(String id) {
    final s = remoteSpan(w, id);
    return (s.$1.clamp(1, cols), s.$2);
  }

  final placed = <RemoteItem>[];
  bool free(int c, int r, int cw, int rh) {
    if (c < 0 || r < 0 || c + cw > cols) return false;
    for (final p in placed) {
      if (c < p.c + p.cw && p.c < c + cw && r < p.r + p.rh && p.r < r + rh) return false;
    }
    return true;
  }

  final rest = <String>[];
  for (final id in ids) {
    final l = lay[id];
    final sp = span(id);
    if (l is Map && l['c'] is num && l['r'] is num && free((l['c'] as num).toInt(), (l['r'] as num).toInt(), sp.$1, sp.$2)) {
      placed.add(RemoteItem(id, (l['c'] as num).toInt(), (l['r'] as num).toInt(), sp.$1, sp.$2));
    } else {
      rest.add(id);
    }
  }
  for (final id in rest) {
    final sp = span(id);
    var r = 0;
    while (true) {
      var done = false;
      for (var c = 0; c + sp.$1 <= cols; c++) {
        if (free(c, r, sp.$1, sp.$2)) {
          placed.add(RemoteItem(id, c, r, sp.$1, sp.$2));
          done = true;
          break;
        }
      }
      if (done) break;
      r++;
    }
  }
  // In the order of the parts, so that the result does not depend on who was placed first.
  final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  placed.sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  return placed;
}

/// The size of the icon of a part, in percent of the usual one (100 = usual). Set in the window that arranges the keys.
int remoteScale(Json w, String id) {
  final v = jsonMap(jsonMap(w['remote'])['scale'])[id];
  return v is num ? v.toInt().clamp(40, 300) : 100;
}

/// The background of a key: 'default' (a filled button), 'outline' (only a border) or 'transparent' (nothing).
String remoteKeyBg(Json w, String id) {
  final v = jsonMap(jsonMap(w['remote'])['kbg'])[id];
  return v == 'outline' || v == 'transparent' ? v as String : 'default';
}

/// The size of the button of a key (its background and border) in percent of its cell: 40 to 100, usually 100. A smaller
/// one leaves more space between the buttons.
int remoteBgSize(Json w, String id) {
  final v = jsonMap(jsonMap(w['remote'])['bgsize'])[id];
  return v is num ? v.toInt().clamp(40, 100) : 100;
}

/// The color of the button of a key (a hex color) instead of the usual one; null = the usual one.
String? remoteKeyColor(Json w, String id) {
  final v = jsonMap(jsonMap(w['remote'])['kcolor'])[id];
  return v is String && v.length == 7 && v.startsWith('#') ? v : null;
}

/// The icon (a key of the icon library, an uploaded image too) chosen for a key instead of its usual one; null = the usual
/// one. A custom button keeps its icon in its own entry.
String? remoteKeyIcon(Json w, String id) {
  final v = jsonMap(jsonMap(w['remote'])['icons'])[id];
  return v is String && v.isNotEmpty ? v : null;
}

/// The number of rows the parts need.
int remoteRows(List<RemoteItem> items) => items.fold<int>(1, (m, i) => i.r + i.rh > m ? i.r + i.rh : m);

/// The keys the card uses, each to be sent: the ring (and the pad) give their five keys, a custom button its id; the
/// power keys of the top bar come first when they are shown.
List<String> remoteKeysUsed(Json w) {
  final out = <String>[];
  void add(String k) {
    if (!out.contains(k)) out.add(k);
  }

  for (final i in remoteItems(w)) {
    if (i.id == 'dpad' || i.id == 'touchpad') {
      kRemoteRing.forEach(add);
    } else {
      add(i.id);
    }
  }
  return out;
}

/// The name of a key as the Editor shows it.
String remoteKeyLabel(Json w, String key) {
  if (key == 'poweron') return 'Power on';
  if (key == 'poweroff') return 'Power off';
  for (final k in kRemoteKeys) {
    if (k.$1 == key) return k.$2;
  }
  for (final c in remoteCustom(w)) {
    if (c['id'] == key) {
      final l = (c['label'] ?? '').toString().trim();
      return l.isEmpty ? 'Custom button' : l;
    }
  }
  return key;
}

/// How a KNX remote sends its keys: 'each' = one address for each key, 'single' = one address for all of them (the key is
/// told by the value that is sent).
String remoteKnxMode(Json w) => jsonMap(w['remote'])['knxMode'] == 'single' ? 'single' : 'each';

/// The value a key sends on its address (text for a text address). A key without a value of its own sends 1 with an
/// address of its own, and its number (counted from 1) with the one address of all the keys.
String remoteKnxValue(Json w, String key) {
  final own = (jsonMap(jsonMap(w['remote'])['values'])[key] ?? '').toString().trim();
  if (own.isNotEmpty) return own;
  if (remoteKnxMode(w) == 'each') return '1';
  const base = ['poweron', 'poweroff', 'up', 'down', 'left', 'right', 'ok', 'back', 'home', 'menu', 'volup', 'voldown', 'mute', 'playpause', 'prev', 'next'];
  final i = base.indexOf(key);
  return i < 0 ? '' : '${i + 1}';
}

/// The address field and the value that a key of a KNX remote sends (null = the key sends nothing).
({String slot, String value})? remoteKnxSend(Json w, String key) {
  if (!remoteIsKnx(w)) return null;
  final single = remoteKnxMode(w) == 'single';
  final v = remoteKnxValue(w, key);
  if (v.isEmpty) return null;
  return (slot: single ? 'rk_all' : 'rk_$key', value: v);
}

/// The number of rows of the grid: the one set for the card (at least what the keys need).
int remoteRowCount(Json w, List<RemoteItem> items) {
  final need = remoteRows(items);
  final set = (jsonMap(w['remote'])['rows'] as num?)?.toInt() ?? 0;
  return set > need ? set.clamp(need, 24) : need;
}
