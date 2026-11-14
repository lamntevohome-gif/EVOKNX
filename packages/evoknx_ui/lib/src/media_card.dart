import 'dart:async';
import 'dart:math' as math;
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

/// The media player card: the cover, the card title, the song, the artist and album, the volume and the buttons
/// (previous, play or pause, next) of one media player of Home Assistant. A button the player does not
/// have is left out. With no [host] (the design view of the Editor) it shows an example.
class MediaCard extends StatefulWidget {
  const MediaCard({super.key, required this.w, required this.pal, this.host, this.sim, this.act});
  final Json w;
  final AppPalette pal;
  final MediaHost? host;

  /// With the source KNX: the state of the card (on, mute, vol) and what a tap does (play, prev, next, mute, preview,
  /// volume). No [act] = the card only shows (the design view of the Editor).
  final Map<String, dynamic>? sim;
  final void Function(String action, [Object? arg])? act;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  StreamSubscription<HaEntity>? _sub;
  Uint8List? _cover;
  String _coverKey = '';
  String _wanted = '';
  double? _vol; // while the volume is being dragged

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
    super.dispose();
  }

  HaMedia? get _media {
    final e = widget.host?.entity(_id);
    return e == null ? null : HaMedia(e);
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

  /// A size that the user set in the settings of the card (null = automatic).
  double? _size(String k) {
    final v = _opts[k];
    return v is num && v > 0 ? v.toDouble() : null;
  }

  Future<void> _call(String service, Map<String, dynamic> data) async {
    if (mediaIsKnx(widget.w)) {
      final act = widget.act;
      if (act == null) return;
      switch (service) {
        case 'media_play':
        case 'media_pause':
          act('play');
        case 'media_next_track':
          act('next');
        case 'media_previous_track':
          act('prev');
        case 'volume_mute':
          act('mute');
        case 'volume_set':
          act('volume', ((data['volume_level'] as num) * 100).round());
        case 'shuffle_set':
          act('shuffle');
        case 'repeat_set':
          act('repeat');
      }
      return;
    }
    final err = await widget.host?.call('media_player.$service', _id, data);
    if (err != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal, w = widget.w;
    final host = widget.host;
    final knx = mediaIsKnx(w);
    HaMedia? m;
    String? note;
    if (knx) {
      m = _knxMedia;
    } else if (host == null) {
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
    if (media != null && host != null && !knx) _loadCover(media);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
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
          : LayoutBuilder(builder: (context, bc) => _body(media, bc, knx ? widget.act == null : host == null, knx)),
    );
  }

  /// What a KNX media player card knows: playing or not, the volume (0–100 %) and mute. There is no title or cover.
  HaMedia get _knxMedia {
    final s = widget.sim ?? const <String, dynamic>{};
    final vol = s['vol'] is num ? (s['vol'] as num).toDouble() : null;
    return HaMedia(
      HaEntity('media_player.knx', s['on'] == true ? 'playing' : 'paused', {
        if (vol != null) 'volume_level': (vol / 100).clamp(0.0, 1.0),
        'is_volume_muted': s['mute'] == true,
        'shuffle': s['shuffle'] == true,
        'repeat': s['repeat'] == true ? 'all' : 'off',
      }),
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

  Widget _body(HaMedia m, BoxConstraints bc, bool demo, bool knx) {
    final pal = widget.pal, w = widget.w;
    final bind = jsonMap(w['bind']);
    final showCover = _opts['cover'] != false;
    final showVolume = _opts['volume'] != false && (knx ? (bind['volume'] != null || bind['volumeSt'] != null) : m.supports(HaMedia.featVolumeSet));
    final showControls = _opts['controls'] != false;
    final wide = bc.maxWidth;
    // The picture is small, in the top right corner.
    final pic = showCover ? (_size('picSize') ?? 64.0).clamp(24.0, math.max(24.0, math.min(wide * 0.4, 200.0))).toDouble() : 0.0;
    final labelSize = fs(w, 'labelSize');
    final dim = !m.available || m.off;
    final ink = dim ? pal.muted : pal.ink;
    final playing = m.playing;

    // On a narrow card the buttons are smaller and closer.
    final compact = wide < 300;
    final pad = compact ? 6.0 : 10.0;
    final btnSize = _size('btnSize') ?? (compact ? 22.0 : 26.0);
    final playSize = _size('playSize') ?? btnSize * 34 / 26;
    Widget btn(IconData icon, VoidCallback? onTap, {double? size, Color? color}) {
      final z = size ?? btnSize;
      return InkResponse(
        onTap: demo ? null : onTap,
        radius: z,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
          child: Icon(icon, size: z, color: color ?? (onTap == null && !demo ? pal.line : pal.ink)),
        ),
      );
    }

    // The sizes of the texts: set in the settings of the card, otherwise from the font size of the card.
    final titleSize = _size('titleSize') ?? labelSize;
    final songSize = _size('songSize') ?? labelSize;
    final detailSize = _size('detailSize') ?? labelSize - 2;

    final cardTitle = (w['label'] ?? '').toString().trim();
    // A KNX card has no song: its name is the line of the song and there is no separate title.
    final showTitle = !knx && cardTitle.isNotEmpty && w['showLabel'] != false;
    final songText = knx
        ? (cardTitle.isNotEmpty ? cardTitle : 'Media player')
        : (m.title.isNotEmpty ? m.title : (m.off ? 'Off' : (m.available ? 'Nothing playing' : 'Unavailable')));
    final lines = <Widget>[
      if (showTitle)
        Text(
          cardTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w400, color: ink, height: 1.2),
        ),
      Text(
        songText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: knx ? titleSize : songSize, fontWeight: showTitle ? FontWeight.w500 : FontWeight.w600, color: ink),
      ),
      if (!knx && m.artist.isNotEmpty)
        Text(
          m.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: detailSize, color: pal.muted),
        ),
    ];

    final thin = SliderTheme.of(context).copyWith(
      trackHeight: _size('volThick') ?? 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: math.max(6.0, (_size('volThick') ?? 3) + 3)),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: pal.accent,
      // The part not dragged yet must show on the card: the muted color, softened.
      inactiveTrackColor: pal.muted.withAlpha(110),
      disabledActiveTrackColor: pal.accent.withAlpha(150),
      disabledInactiveTrackColor: pal.muted.withAlpha(70),
      thumbColor: pal.accent,
    );

    final canMute = knx ? bind['mute'] != null : m.supports(HaMedia.featVolumeMute);
    final canSetVolume = knx ? bind['volume'] != null : true;
    final volIcon = _size('volIcon') ?? (compact ? 18.0 : 20.0);
    final volume = Row(
      children: [
        btn(
          m.muted || (m.volume ?? 1) == 0 ? Icons.volume_off : Icons.volume_up,
          canMute ? () => _call('volume_mute', {'is_volume_muted': !m.muted}) : null,
          size: volIcon,
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ((_size('volWidth') ?? 100) / 100).clamp(0.2, 1.0),
              child: SliderTheme(
                data: thin,
                child: Slider(
                  value: (_vol ?? m.volume ?? 0).clamp(0.0, 1.0).toDouble(),
                  onChanged: demo || !canSetVolume ? null : (v) => setState(() => _vol = v),
                  onChangeEnd: demo || !canSetVolume
                      ? null
                      : (v) {
                          setState(() => _vol = null);
                          _call('volume_set', {'volume_level': double.parse(v.toStringAsFixed(2))});
                        },
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final canPlay = !knx || bind['play'] != null;
    final canPrev = knx ? bind['prev'] != null : m.supports(HaMedia.featPrevious);
    final canNext = knx ? bind['next'] != null : m.supports(HaMedia.featNext);
    // Shuffle and repeat are off unless ticked in the settings; the card shows them only if the player (or the address) has them.
    final canShuffle = _opts['shuffle'] == true && (knx ? bind['shuffle'] != null : m.supports(HaMedia.featShuffle));
    final canRepeat = _opts['repeat'] == true && (knx ? bind['repeat'] != null : m.supports(HaMedia.featRepeat));
    final repeatOn = m.repeat != 'off';
    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (canShuffle)
          btn(Icons.shuffle, () => _call('shuffle_set', {'shuffle': !m.shuffle}), size: btnSize * 0.85, color: m.shuffle ? pal.accent : pal.muted),
        if (canPrev) btn(Icons.skip_previous, () => _call('media_previous_track', {})),
        if (canPlay)
          btn(playing ? Icons.pause_circle : Icons.play_circle, () => _call(playing ? 'media_pause' : 'media_play', {}), size: playSize, color: pal.accent),
        if (canNext) btn(Icons.skip_next, () => _call('media_next_track', {})),
        if (canRepeat)
          btn(
            m.repeat == 'one' ? Icons.repeat_one : Icons.repeat,
            () => _call('repeat_set', {'repeat': m.repeat == 'off' ? 'all' : (m.repeat == 'all' ? 'one' : 'off')}),
            size: btnSize * 0.85,
            color: repeatOn ? pal.accent : pal.muted,
          ),
      ],
    );

    return Stack(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The texts stay out from under the picture.
            Padding(
              padding: EdgeInsets.only(right: showCover ? pic + 8 : 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
            ),
            if (showVolume) ...[const SizedBox(height: 4), volume],
            if (showControls && (canPlay || canPrev || canNext || canShuffle || canRepeat)) ...[const SizedBox(height: 2), controls],
          ],
        ),
        if (showCover) Positioned(top: 0, right: 0, width: pic, height: pic, child: _coverImage(m, pic, demo, knx)),
      ],
    );
  }

  /// The cover. Without a picture (a KNX card has none, a stream of Home Assistant may have none) an equalizer moves
  /// while the music plays.
  Widget _coverImage(HaMedia m, double size, bool demo, bool knx) {
    final pal = widget.pal;
    final bytes = _cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(pal.radius * 0.5),
      child: !knx && bytes != null && !demo
          ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => _noCover(m))
          : _noCover(m),
    );
  }

  Widget _noCover(HaMedia m) => ColoredBox(
    color: widget.pal.panel,
    child: MediaEqualizer(color: widget.pal.accent, playing: m.playing),
  );
}

/// A small moving equalizer: bars that jump while [playing], low and still otherwise. It is drawn by code, so it needs no
/// picture.
class MediaEqualizer extends StatefulWidget {
  const MediaEqualizer({super.key, required this.color, required this.playing});
  final Color color;
  final bool playing;

  @override
  State<MediaEqualizer> createState() => _MediaEqualizerState();
}

class _MediaEqualizerState extends State<MediaEqualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(MediaEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _EqPainter(_c, widget.color, widget.playing), size: Size.infinite);
}

class _EqPainter extends CustomPainter {
  _EqPainter(this.t, this.color, this.playing) : super(repaint: t);
  final Animation<double> t;
  final Color color;
  final bool playing;

  // Each bar moves with its own whole number of waves per cycle and its own start, so the loop has no jump.
  static const _waves = [2, 3, 1, 3, 2];
  static const _start = [0.0, 0.35, 0.7, 0.15, 0.55];
  static const _rest = [0.2, 0.32, 0.24, 0.36, 0.22];

  @override
  void paint(Canvas canvas, Size size) {
    const n = 5;
    final side = math.min(size.width, size.height);
    final box = side * 0.56;
    final gap = box * 0.1;
    final barW = (box - gap * (n - 1)) / n;
    final left = (size.width - box) / 2, bottom = (size.height + box) / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final f = playing ? 0.15 + 0.85 * (0.5 + 0.5 * math.sin(2 * math.pi * (_waves[i] * t.value + _start[i]))) : _rest[i];
      final bh = math.max(barW, box * f);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(left + i * (barW + gap), bottom - bh, barW, bh), Radius.circular(barW / 2));
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) => old.color != color || old.playing != playing;
}
