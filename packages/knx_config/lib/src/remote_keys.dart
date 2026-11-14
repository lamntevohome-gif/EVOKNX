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
  final r = remoteSettings(w);
  final own = jsonMap(r['keys'])[key];
  if (own != null && own.toString().trim().isNotEmpty) return own.toString().trim();
  return kRemotePresets[r['preset']]?[key] ?? '';
}

/// The service call that a key of a remote control card makes, or null when the key has no name or no remote is chosen.
HaButtonCall? remoteCall(Json w, String key) {
  final r = remoteSettings(w);
  final entity = r['entity'] as String;
  final cmd = remoteCommand(w, key);
  if (entity.isEmpty || cmd.isEmpty) return null;
  return HaButtonCall('remote.send_command', entity, {'command': cmd, if ((r['device'] as String).isNotEmpty) 'device': r['device']});
}

/// What is wrong with a remote control card (null = nothing).
String? remoteProblem(Json w) {
  final id = remoteSettings(w)['entity'] as String;
  if (id.isEmpty) return 'choose the remote.';
  if (!id.startsWith('remote.') && !id.startsWith('media_player.')) return 'the entity must be a remote (remote.…).';
  return null;
}
