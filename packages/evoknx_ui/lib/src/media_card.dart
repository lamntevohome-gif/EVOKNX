import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import 'icons.dart';
import 'look.dart';
import 'model.dart';
import 'tiles.dart';

/// What the media player card needs from the place where it runs (the App, or the Editor in Live Mode).
abstract class MediaHost {
  /// The last known state of an entity of Home Assistant (null = not known yet).
  HaEntity? entity(String id);

  /// The entities whose state changes.
  Stream<HaEntity> get changes;

  /// Whether Home Assistant is connected.
  bool get connected;

  /// Calls a service ("media_player.media_pause"). An error text, or null.
  Future<String?> call(String service, String entity, Map<String, dynamic> data);

  /// The cover image of a media player, or null.
  Future<Uint8List?> thumbnail(String entity);
}

/// The media player card: the cover, the title, the artist and album, the progress of the track, the buttons
/// (previous, play or pause, next) and the volume of one media player of Home Assistant. A button the player does not
/// have is left out. With no [host] (the design view of the Editor) it shows an example.
class MediaCard extends StatefulWidget {
  const MediaCard({super.key, required this.w, required this.pal, this.host});
  final Json w;
  final AppPalette pal;
  final MediaHost? host;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  StreamSubscription<HaEntity>? _sub;
  Timer? _tick;
  Uint8List? _cover;
  String _coverKey = '';
  String _wanted = '';
  double? _vol; // while the volume is being dragged
  double? _seek; // while the progress is being dragged

  Json get _opts => jsonMap(widget.w['media']);
  String get _id => (_opts['entity'] ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(MediaCard old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host) _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.host?.changes.listen((e) {
      if (e.id == _id && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  HaMedia? get _media {
    final e = widget.host?.entity(_id);
    return e == null ? null : HaMedia(e);
  }

  /// The progress runs by itself once a second while a track plays.
  void _ensureTick(bool run) {
    if (run && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _seek == null) setState(() {});
      });
    } else if (!run && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  /// Fetches the cover when the track (its picture) changes.
  void _loadCover(HaMedia m) {
    final key = m.picture;
    if (key == _coverKey || key == _wanted) return;
    _wanted = key;
    if (key.isEmpty) {
      _cover = null;
      _coverKey = '';
      return;
    }
    widget.host?.thumbnail(_id).then((bytes) {
      if (!mounted || _wanted != key) return;
      if (bytes == null) {
        // No image (yet): try again in a few seconds.
        Timer(const Duration(seconds: 6), () {
          if (mounted && _wanted == key) setState(() => _wanted = '');
        });
        return;
      }
      setState(() {
        _cover = bytes;
        _coverKey = key;
      });
    });
  }

  Future<void> _call(String service, Map<String, dynamic> data) async {
    final err = await widget.host?.call('media_player.$service', _id, data);
    if (err != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal, w = widget.w;
    final host = widget.host;
    HaMedia? m;
    String? note;
    if (host == null) {
      m = _example;
    } else if (_id.isEmpty) {
      note = 'Choose the media player in the settings of the card.';
    } else if (!host.connected && host.entity(_id) == null) {
      note = 'Waiting for Home Assistant…';
    } else {
      m = _media;
      if (m == null) note = 'No media player “$_id” in Home Assistant.';
    }
    final media = m;
    if (media != null && host != null) {
      _loadCover(media);
      _ensureTick(media.playing && _opts['progress'] != false);
    } else {
      _ensureTick(false);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: raisedDecoration(
        pal,
        pal.fill(pal.tile),
        radius: BorderRadius.circular(pal.radius),
        lift: pal.cardLift,
        border: pal.border <= 0 ? Border.fromBorderSide(BorderSide.none) : Border.all(color: pal.edge, width: pal.border),
        shadow: false,
      ),
      child: media == null
          ? Center(
              child: Text(
                note ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fs(w, 'labelSize') - 1, color: pal.muted),
              ),
            )
          : LayoutBuilder(builder: (context, bc) => _body(media, bc, host == null)),
    );
  }

  HaMedia get _example => HaMedia(
    HaEntity('media_player.example', 'playing', {
      'media_title': 'Song title',
      'media_artist': 'Artist',
      'media_album_name': 'Album',
      'media_duration': 225,
      'media_position': 83,
      'volume_level': 0.5,
    }),
  );

  Widget _body(HaMedia m, BoxConstraints bc, bool demo) {
    final pal = widget.pal, w = widget.w;
    final showCover = _opts['cover'] != false;
    final showProgress = _opts['progress'] != false;
    final showVolume = _opts['volume'] != false && m.supports(HaMedia.featVolumeSet);
    final showControls = _opts['controls'] != false;
    final h = bc.maxHeight, wide = bc.maxWidth;
    // The cover is a square as high as the card, but not more than 42% of its width.
    var cover = 0.0;
    if (showCover) {
      cover = h.isFinite ? h : 96.0;
      if (cover > wide * 0.42) cover = wide * 0.42;
      if (cover < 36) cover = 36;
    }
    final labelSize = fs(w, 'labelSize');
    final dim = !m.available || m.off;
    final ink = dim ? pal.muted : pal.ink;
    final dur = m.duration;
    final pos = _seek ?? m.position(DateTime.now().toUtc());
    final canSeek = !demo && m.supports(HaMedia.featSeek) && dur != null;
    final playing = m.playing;

    Widget btn(IconData icon, VoidCallback? onTap, {double size = 26, bool main = false}) => InkResponse(
      onTap: demo ? null : onTap,
      radius: size,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Icon(icon, size: size, color: onTap == null && !demo ? pal.line : (main ? pal.accent : pal.ink)),
      ),
    );

    final title = Text(
      m.title.isNotEmpty ? m.title : (m.off ? 'Off' : (m.available ? 'Nothing playing' : 'Unavailable')),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: labelSize + 1, fontWeight: FontWeight.w600, color: ink),
    );
    final sub = m.subtitle.isEmpty
        ? null
        : Text(
            m.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: labelSize - 2, color: pal.muted),
          );

    final thin = SliderTheme.of(context).copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: pal.accent,
      inactiveTrackColor: pal.line,
      thumbColor: pal.accent,
    );

    final info = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        if (sub != null) ...[const SizedBox(height: 1), sub],
        if (showProgress && dur != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: thin,
                  child: Slider(
                    value: ((pos ?? 0) / dur).clamp(0.0, 1.0).toDouble(),
                    onChanged: canSeek ? (v) => setState(() => _seek = v * dur) : null,
                    onChangeEnd: canSeek
                        ? (v) {
                            final to = v * dur;
                            setState(() => _seek = null);
                            _call('media_seek', {'seek_position': to});
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${mediaTime(pos)} / ${mediaTime(dur)}',
                style: TextStyle(fontSize: labelSize - 3, color: pal.muted),
              ),
            ],
          ),
        ],
        if (showControls || showVolume) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              if (showControls) ...[
                if (m.supports(HaMedia.featPrevious)) btn(Icons.skip_previous, () => _call('media_previous_track', {})),
                btn(playing ? Icons.pause_circle : Icons.play_circle, () => _call(playing ? 'media_pause' : 'media_play', {}), size: 34, main: true),
                if (m.supports(HaMedia.featNext)) btn(Icons.skip_next, () => _call('media_next_track', {})),
              ],
              if (showVolume) ...[
                const Spacer(),
                btn(
                  m.muted || (m.volume ?? 1) == 0 ? Icons.volume_off : Icons.volume_up,
                  m.supports(HaMedia.featVolumeMute) ? () => _call('volume_mute', {'is_volume_muted': !m.muted}) : null,
                  size: 20,
                ),
                SizedBox(
                  width: 96,
                  child: SliderTheme(
                    data: thin,
                    child: Slider(
                      value: (_vol ?? m.volume ?? 0).clamp(0.0, 1.0).toDouble(),
                      onChanged: demo ? null : (v) => setState(() => _vol = v),
                      onChangeEnd: demo
                          ? null
                          : (v) {
                              setState(() => _vol = null);
                              _call('volume_set', {'volume_level': double.parse(v.toStringAsFixed(2))});
                            },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );

    return Row(
      children: [
        if (showCover) ...[SizedBox(width: cover, height: cover, child: _coverImage(m, cover, demo)), const SizedBox(width: 12)],
        Expanded(child: info),
      ],
    );
  }

  Widget _coverImage(HaMedia m, double size, bool demo) {
    final pal = widget.pal;
    final bytes = _cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(pal.radius * 0.6),
      child: bytes != null && !demo
          ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => _noCover(size))
          : _noCover(size),
    );
  }

  Widget _noCover(double size) => ColoredBox(
    color: widget.pal.panel,
    child: Center(child: iconWidget('music', size * 0.45, widget.pal.muted)),
  );
}
