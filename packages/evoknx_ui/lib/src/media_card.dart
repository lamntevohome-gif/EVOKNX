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
    final w = widget.w;
    final (pal, noBorder) = cardPalette(w, widget.pal);
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
        border: pal.border <= 0 || noBorder ? Border.fromBorderSide(BorderSide.none) : Border.all(color: pal.edge, width: pal.border),
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
          : LayoutBuilder(builder: (context, bc) => _body(media, bc, knx ? widget.act == null : host == null, knx, pal)),
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

  Widget _body(HaMedia m, BoxConstraints bc, bool demo, bool knx, AppPalette pal) {
    final w = widget.w;
    final bind = jsonMap(w['bind']);
    final showCover = _opts['cover'] != false;
    final showVolume = _opts['volume'] != false && (knx ? (bind['volume'] != null || bind['volumeSt'] != null) : m.supports(HaMedia.featVolumeSet));
    final showControls = _opts['controls'] != false;
    final wide = bc.maxWidth;
    // The picture is small, in the top right corner.
    var pic = showCover ? (_size('picSize') ?? 64.0).clamp(24.0, math.max(24.0, math.min(wide * 0.4, 200.0))).toDouble() : 0.0;
    final labelSize = fs(w, 'labelSize');
    final dim = !m.available || m.off;
    final ink = dim ? pal.muted : pal.ink;
    final playing = m.playing;

    // On a narrow card the buttons are smaller and closer.
    final compact = wide < 300;
    final pad = compact ? 6.0 : 10.0;
    var btnSize = _size('btnSize') ?? (compact ? 22.0 : 26.0);
    var playSize = _size('playSize') ?? btnSize * 34 / 26;
    Widget btn(IconData icon, VoidCallback? onTap, {double? size, Color? color, double? h}) {
      final z = size ?? btnSize;
      return InkResponse(
        onTap: demo ? null : onTap,
        radius: z,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: h ?? pad, vertical: 2),
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
    var volIcon = _size('volIcon') ?? (compact ? 18.0 : 20.0);
    // The space between the rows (the lines of text keep half of it).
    var gap = (_size('rowGap') ?? 8.0).clamp(0.0, 60.0).toDouble();

    // A card that is lower than its rows need gets lower rows (the space between them first, then the picture, then the
    // buttons); the width is not touched. A narrower card only makes the buttons closer (above) and the picture smaller.
    if (bc.maxHeight.isFinite) {
      final textsH = (showTitle ? titleSize * 1.4 : 0) + (knx ? titleSize : songSize) * 1.4 + (!knx && m.artist.isNotEmpty ? detailSize * 1.4 : 0);
      double need(double g, double p, double k) {
        final topH = math.max(textsH + g / 2 * (lines.length - 1), showCover ? p : 0.0);
        final volH = showVolume ? math.max(volIcon * k + 6, 26.0) : 0.0;
        final ctlH = showControls ? playSize * k + 8 : 0.0;
        return topH + volH + ctlH + (showVolume && showControls ? g : 0.0) + 4;
      }

      final avail = bc.maxHeight;
      var g = gap, p = pic, k = 1.0;
      if (need(g, p, k) > avail) g = 0;
      if (showCover && need(g, p, k) > avail) p = math.max(24.0, p - (need(g, p, k) - avail));
      while (need(g, p, k) > avail && k > 0.5) {
        k -= 0.1;
      }
      gap = g;
      pic = p;
      btnSize *= k;
      playSize *= k;
      volIcon *= k;
    }

    // The first and the last column of the volume row and of the row of buttons have the same width, so the mute button is
    // right over the shuffle button and the value of the volume over the repeat button.
    final sideW = math.max(volIcon, btnSize * 0.85) + 2 * pad;
    final volNow = (_vol ?? m.volume ?? 0).clamp(0.0, 1.0).toDouble();
    final volText = knx && mediaVolMax(w) == 255 ? '${(volNow * 255).round()}' : '${(volNow * 100).round()}%';
    final volume = Row(
      children: [
        SizedBox(
          width: sideW,
          child: Center(
            child: btn(
              m.muted || (m.volume ?? 1) == 0 ? Icons.volume_off : Icons.volume_up,
              canMute ? () => _call('volume_mute', {'is_volume_muted': !m.muted}) : null,
              size: volIcon,
              h: 0,
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ((_size('volWidth') ?? 100) / 100).clamp(0.2, 1.0),
              child: SliderTheme(
                data: thin,
                child: Slider(
                  value: volNow,
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
        SizedBox(
          width: sideW,
          child: Center(
            child: Text(
              volText,
              maxLines: 1,
              style: TextStyle(fontSize: math.max(11.0, detailSize), color: pal.muted, fontFeatures: const [FontFeature.tabularFigures()]),
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
    // Previous, play and next are spread evenly between the two side columns.
    final controls = Row(
      children: [
        SizedBox(
          width: sideW,
          child: canShuffle
              ? Center(
                  child: btn(
                    Icons.shuffle,
                    () => _call('shuffle_set', {'shuffle': !m.shuffle}),
                    size: btnSize * 0.85,
                    color: m.shuffle ? pal.accent : pal.muted,
                    h: 0,
                  ),
                )
              : null,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (canPrev) btn(Icons.skip_previous, () => _call('media_previous_track', {}), h: 0),
              if (canPlay)
                btn(
                  playing ? Icons.pause_circle : Icons.play_circle,
                  () => _call(playing ? 'media_pause' : 'media_play', {}),
                  size: playSize,
                  color: pal.accent,
                  h: 0,
                ),
              if (canNext) btn(Icons.skip_next, () => _call('media_next_track', {}), h: 0),
            ],
          ),
        ),
        SizedBox(
          width: sideW,
          child: canRepeat
              ? Center(
                  child: btn(
                    m.repeat == 'one' ? Icons.repeat_one : Icons.repeat,
                    () => _call('repeat_set', {'repeat': m.repeat == 'off' ? 'all' : (m.repeat == 'all' ? 'one' : 'off')}),
                    size: btnSize * 0.85,
                    color: repeatOn ? pal.accent : pal.muted,
                    h: 0,
                  ),
                )
              : null,
        ),
      ],
    );

    final hasControls = showControls && (canPlay || canPrev || canNext || canShuffle || canRepeat);
    // The title, the song, the artist and the picture stay at the top; the volume and the buttons stay at the bottom.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++) ...[if (i > 0) SizedBox(height: gap / 2), lines[i]],
                ],
              ),
            ),
            if (showCover) ...[const SizedBox(width: 8), SizedBox(width: pic, height: pic, child: _coverImage(m, pic, demo, knx, pal))],
          ],
        ),
        const Spacer(),
        if (showVolume) volume,
        if (showVolume && hasControls) SizedBox(height: gap),
        if (hasControls) controls,
      ],
    );
  }

  /// The cover. Without a picture (a KNX card has none, a stream of Home Assistant may have none) an equalizer moves
  /// while the music plays.
  Widget _coverImage(HaMedia m, double size, bool demo, bool knx, AppPalette pal) {
    final bytes = _cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(pal.radius * 0.5),
      child: !knx && bytes != null && !demo
          ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => _noCover(m, pal))
          : _noCover(m, pal),
    );
  }

  Widget _noCover(HaMedia m, AppPalette pal) => ColoredBox(
    color: pal.panel,
    child: MediaEqualizer(color: pal.accent, playing: m.playing),
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
