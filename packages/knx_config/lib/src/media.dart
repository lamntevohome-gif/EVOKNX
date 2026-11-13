import 'card_entity.dart';
import 'ha.dart';
import 'project.dart';

/// What a media player of Home Assistant says about itself (title, artist, cover, volume, position…),
/// read from the state and the attributes of its entity.
class HaMedia {
  HaMedia(this.e);
  final HaEntity e;

  // The features of a media player (`supported_features` is a sum of these).
  static const featPause = 1, featSeek = 2, featVolumeSet = 4, featVolumeMute = 8, featPrevious = 16, featNext = 32;
  static const featTurnOn = 128, featTurnOff = 256, featSelectSource = 2048, featStop = 4096, featPlay = 16384;

  String _s(String k) => (e.attributes[k] ?? '').toString().trim();
  double? _n(String k) => e.attributes[k] is num ? (e.attributes[k] as num).toDouble() : double.tryParse((e.attributes[k] ?? '').toString());

  String get state => e.state;
  bool get playing => state == 'playing';
  bool get paused => state == 'paused';
  bool get available => state != 'unavailable' && state != 'unknown';
  bool get off => state == 'off' || state == 'standby';

  String get title => _s('media_title');
  String get artist => _s('media_artist');
  String get album => _s('media_album_name');
  String get source => _s('source');

  /// Artist and album on one line ("Artist · Album").
  String get subtitle => [artist, album].where((x) => x.isNotEmpty).join(' · ');

  /// The cover image path (`/api/media_player_proxy/…`), which changes with the track.
  String get picture => _s('entity_picture');

  double? get duration {
    final d = _n('media_duration');
    return d == null || d <= 0 ? null : d;
  }

  /// The position in the track (seconds) now: Home Assistant gives the position and when it was true.
  double? position(DateTime now) {
    final p = _n('media_position');
    if (p == null) return null;
    var v = p;
    if (playing) {
      final at = DateTime.tryParse(_s('media_position_updated_at'));
      if (at != null) {
        final dt = now.difference(at).inMilliseconds / 1000.0;
        if (dt > 0) v += dt;
      }
    }
    final d = duration;
    if (d != null && v > d) v = d;
    return v < 0 ? 0 : v;
  }

  /// The volume, 0 to 1 (null when the player does not tell).
  double? get volume => _n('volume_level');
  bool get muted => e.attributes['is_volume_muted'] == true;

  int? get features => e.attributes['supported_features'] is num ? (e.attributes['supported_features'] as num).toInt() : null;

  /// Whether the player has a feature. A player that does not list its features is taken to have them all.
  bool supports(int flag) => features == null || (features! & flag) != 0;
}

/// Mm:ss (or h:mm:ss) of a number of seconds.
String mediaTime(double? seconds) {
  if (seconds == null) return '–:––';
  final s = seconds.round().clamp(0, 359999);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(x)}' : '$m:${two(x)}';
}

/// Whether the App needs the connection to Home Assistant: a virtual address, a script that calls a service, or a
/// media player card.
bool haNeeded(Json doc) {
  if (haAddresses(doc).isNotEmpty) return true;
  for (final s in jsonList(doc['scripts'])) {
    if (jsonList(s['steps']).any((st) => st['type'] == 'ha')) return true;
  }
  return allWidgets(doc).any((w) => w['type'] == 'media' || cardEntity(w).isNotEmpty);
}
