import 'card_entity.dart';
import 'ha.dart';
import 'project.dart';

/// A parameter of a command (a field of the service call of Home Assistant).
class HaParam {
  const HaParam(
    this.field,
    this.label, {
    this.kind = 'text',
    this.required = false,
    this.options = const [],
    this.suggest = '',
    this.scale = 1,
    this.min,
    this.max,
    this.initial,
    this.hint = '',
  });

  /// The name of the field in the service data.
  final String field, label;

  /// text, number, int (a whole number) or choice (one of [options]).
  final String kind;
  final bool required;
  final List<String> options;

  /// The attribute of the entity that lists the usual values ("source_list").
  final String suggest;

  /// The number is multiplied by this before it is sent (a volume in % becomes 0–1).
  final double scale;
  final num? min, max;
  final String? initial;
  final String hint;
}

/// A command that a push button can send to a media player or a remote.
class HaCommand {
  const HaCommand(this.key, this.label, this.service, {this.features = const [], this.params = const [], this.fixed = const {}, this.needs = ''});
  final String key, label;

  /// The service of Home Assistant ("media_player.media_pause").
  final String service;

  /// The player has the command when it has one of these features (empty = always).
  final List<int> features;
  final List<HaParam> params;

  /// Data that is always sent.
  final Map<String, dynamic> fixed;

  /// An attribute that the entity must list (or the feature bit for activities) for the command to be offered.
  final String needs;
}

const List<HaCommand> kMediaCommands = [
  HaCommand('turn_on', 'Turn on', 'media_player.turn_on', features: [128]),
  HaCommand('turn_off', 'Turn off', 'media_player.turn_off', features: [256]),
  HaCommand('toggle', 'Turn on or off', 'media_player.toggle', features: [128, 256]),
  HaCommand('play', 'Play', 'media_player.media_play', features: [16384]),
  HaCommand('pause', 'Pause', 'media_player.media_pause', features: [1]),
  HaCommand('play_pause', 'Play or pause', 'media_player.media_play_pause', features: [16384, 1]),
  HaCommand('stop', 'Stop', 'media_player.media_stop', features: [4096]),
  HaCommand('next', 'Next track', 'media_player.media_next_track', features: [32]),
  HaCommand('previous', 'Previous track', 'media_player.media_previous_track', features: [16]),
  HaCommand(
    'volume_set',
    'Set the volume',
    'media_player.volume_set',
    features: [4],
    params: [HaParam('volume_level', 'Volume (%)', kind: 'number', required: true, scale: 0.01, min: 0, max: 100, hint: '0–100')],
  ),
  HaCommand('volume_up', 'Volume up', 'media_player.volume_up', features: [4, 1024]),
  HaCommand('volume_down', 'Volume down', 'media_player.volume_down', features: [4, 1024]),
  HaCommand('mute', 'Mute', 'media_player.volume_mute', features: [8], fixed: {'is_volume_muted': true}),
  HaCommand('unmute', 'Unmute', 'media_player.volume_mute', features: [8], fixed: {'is_volume_muted': false}),
  HaCommand(
    'seek',
    'Seek',
    'media_player.media_seek',
    features: [2],
    params: [HaParam('seek_position', 'Position (seconds)', kind: 'number', required: true, min: 0)],
  ),
  HaCommand(
    'select_source',
    'Select source',
    'media_player.select_source',
    features: [2048],
    params: [HaParam('source', 'Source', required: true, suggest: 'source_list', hint: 'HDMI 2')],
  ),
  HaCommand(
    'select_sound_mode',
    'Select sound mode',
    'media_player.select_sound_mode',
    features: [65536],
    params: [HaParam('sound_mode', 'Sound mode', required: true, suggest: 'sound_mode_list', hint: 'Movie')],
  ),
  HaCommand('shuffle_on', 'Shuffle on', 'media_player.shuffle_set', features: [32768], fixed: {'shuffle': true}),
  HaCommand('shuffle_off', 'Shuffle off', 'media_player.shuffle_set', features: [32768], fixed: {'shuffle': false}),
  HaCommand(
    'repeat',
    'Set repeat',
    'media_player.repeat_set',
    features: [262144],
    params: [
      HaParam('repeat', 'Repeat', kind: 'choice', required: true, options: ['off', 'all', 'one'], initial: 'all'),
    ],
  ),
  HaCommand(
    'play_media',
    'Play media',
    'media_player.play_media',
    features: [512],
    params: [
      HaParam('media_content_id', 'Content (address, name or code)', required: true),
      HaParam(
        'media_content_type',
        'Type',
        kind: 'choice',
        required: true,
        options: ['music', 'playlist', 'channel', 'url', 'video', 'tvshow', 'episode', 'app'],
        initial: 'music',
      ),
    ],
  ),
  HaCommand('clear_playlist', 'Clear the playlist', 'media_player.clear_playlist', features: [8192]),
];

const List<HaCommand> kRemoteCommands = [
  HaCommand(
    'send_command',
    'Send a command (key)',
    'remote.send_command',
    params: [
      HaParam('command', 'Command (key)', required: true, hint: 'DPAD_UP'),
      HaParam('device', 'Device (if the remote has several)'),
      HaParam('num_repeats', 'Repeats', kind: 'int', min: 1, max: 100, hint: '1'),
      HaParam('delay_secs', 'Delay between repeats (seconds)', kind: 'number', min: 0),
      HaParam('hold_secs', 'Hold time (seconds)', kind: 'number', min: 0),
    ],
  ),
  HaCommand(
    'start_activity',
    'Start an activity',
    'remote.turn_on',
    needs: 'activity',
    params: [HaParam('activity', 'Activity', required: true, suggest: 'activity_list')],
  ),
  HaCommand('turn_on', 'Turn on', 'remote.turn_on'),
  HaCommand('turn_off', 'Turn off', 'remote.turn_off'),
  HaCommand('toggle', 'Turn on or off', 'remote.toggle'),
];

List<HaCommand> haCommandTable(String domain) => domain == 'media_player' ? kMediaCommands : (domain == 'remote' ? kRemoteCommands : const []);

HaCommand? haCommandByKey(String domain, String key) {
  for (final c in haCommandTable(domain)) {
    if (c.key == key) return c;
  }
  return null;
}

/// The commands that this entity has, from its `supported_features` (all of them when it lists none, or when [all]).
List<HaCommand> haCommandsFor(HaEntity e, {bool all = false}) {
  final table = haCommandTable(e.domain);
  if (all) return table;
  final f = e.attributes['supported_features'] is num ? (e.attributes['supported_features'] as num).toInt() : null;
  return [
    for (final c in table)
      if (_has(e, c, f)) c,
  ];
}

bool _has(HaEntity e, HaCommand c, int? f) {
  if (c.needs == 'activity') {
    // A remote with activities (a list of them, or the feature bit 4).
    final list = e.attributes['activity_list'];
    return (list is List && list.isNotEmpty) || (f != null && (f & 4) != 0) || (f == null && list == null);
  }
  return c.features.isEmpty || f == null || c.features.any((x) => (f & x) != 0);
}

/// The usual values of a text parameter, from the entity ("source_list").
List<String> haParamSuggestions(HaEntity? e, HaParam p) {
  final l = p.suggest.isEmpty ? null : e?.attributes[p.suggest];
  return l is List ? [for (final x in l) x.toString()] : const [];
}

/// The data of the service call for [c] with the values of [params]; an error text when one is wrong or missing.
(Map<String, dynamic>?, String?) haCommandData(HaCommand c, Map<String, dynamic> params) {
  final data = <String, dynamic>{...c.fixed};
  for (final p in c.params) {
    var raw = params[p.field];
    if (raw == null || raw.toString().trim().isEmpty) raw = p.initial;
    if (raw == null || raw.toString().trim().isEmpty) {
      if (p.required) return (null, 'Fill in “${p.label}”.');
      continue;
    }
    final t = raw.toString().trim();
    switch (p.kind) {
      case 'number':
      case 'int':
        final n = num.tryParse(t.replaceAll(',', '.'));
        if (n == null) return (null, '“${p.label}” must be a number.');
        if ((p.min != null && n < p.min!) || (p.max != null && n > p.max!)) {
          return (null, '“${p.label}” must be between ${p.min ?? '…'} and ${p.max ?? '…'}.');
        }
        data[p.field] = p.kind == 'int' ? n.toInt() : (p.scale == 1 ? n : double.parse((n * p.scale).toStringAsFixed(4)));
      case 'choice':
        if (!p.options.contains(t)) return (null, '“${p.label}” must be one of: ${p.options.join(', ')}.');
        data[p.field] = t;
      default:
        data[p.field] = t;
    }
  }
  return (data, null);
}

/// A push button that follows a media player or a remote calls a service of Home Assistant directly (no address).
class HaButtonCall {
  const HaButtonCall(this.service, this.entity, this.data);
  final String service, entity;
  final Map<String, dynamic> data;
}

/// The command chosen on a push button, or null.
HaCommand? haButtonCommand(Json w) {
  final id = cardEntity(w);
  if (id.isEmpty) return null;
  final h = jsonMap(w['ha']);
  return haCommandByKey(id.split('.').first, (h['action'] ?? '').toString());
}

/// What is wrong with the command of a push button (null = nothing).
String? haButtonProblem(Json w) {
  final c = haButtonCommand(w);
  if (c == null) return 'choose the command.';
  final r = haCommandData(c, jsonMap(jsonMap(w['ha'])['params']));
  final m = r.$2;
  return m == null ? null : m[0].toLowerCase() + m.substring(1);
}

/// The service call of a push button, or null when the command is missing or wrong.
HaButtonCall? haButtonCall(Json w) {
  final c = haButtonCommand(w);
  if (c == null) return null;
  final r = haCommandData(c, jsonMap(jsonMap(w['ha'])['params']));
  final data = r.$1;
  return data == null ? null : HaButtonCall(c.service, cardEntity(w), data);
}

/// A copy of the Home Assistant settings of a card that can be changed.
Map<String, dynamic> _ha(Json w) => w['ha'] is Map ? Map<String, dynamic>.from(w['ha'] as Map) : <String, dynamic>{};

/// Chooses the command of a push button (its parameters start empty).
void setButtonCommand(Json w, String key) {
  final h = _ha(w);
  h['action'] = key;
  h['params'] = <String, dynamic>{};
  w['ha'] = h;
}

/// Sets (or, with an empty value, clears) a parameter of the command of a push button.
void setButtonParam(Json w, String field, Object? value) {
  final h = _ha(w);
  final p = h['params'] is Map ? Map<String, dynamic>.from(h['params'] as Map) : <String, dynamic>{};
  if (value == null || value.toString().isEmpty) {
    p.remove(field);
  } else {
    p[field] = value;
  }
  h['params'] = p;
  w['ha'] = h;
}

/// Whether the commands are filtered by the features of the entity (a button can show them all).
bool haShowAll(Json w) => jsonMap(w['ha'])['all'] == true;

void setButtonShowAll(Json w, bool v) {
  final h = _ha(w);
  if (v) {
    h['all'] = true;
  } else {
    h.remove('all');
  }
  w['ha'] = h;
}
