import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/lyrics/lyrics.dart';
import '../../core/models/track.dart';
import '../../core/player/player_model.dart';
import '../../platform/lyrics_store.dart';
import '../../platform/settings_store.dart';
import '../theme.dart';

/// Whether Now Playing shows lyrics in place of the cover. One switch for
/// the docked panel and the phone sheet, remembered across restarts.
class LyricsToggle extends ChangeNotifier {
  final SettingsStore _settings;
  bool _visible;

  LyricsToggle(this._settings) : _visible = _settings.showLyrics;

  bool get visible => _visible;

  Future<void> toggle() async {
    _visible = !_visible;
    notifyListeners();
    await _settings.setShowLyrics(_visible);
  }
}

/// `¶`, the lyrics switch: accent while lyrics are showing. JetBrains Mono
/// has no musical note, and the pilcrow reads as "text".
class LyricsToggleButton extends StatelessWidget {
  /// Sized to sit in a panel's top border beside its `×`, rather than as a
  /// 44px tap target.
  final bool inBorder;

  const LyricsToggleButton({super.key, this.inBorder = false});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final toggle = context.watch<LyricsToggle>();
    return Tooltip(
      message: toggle.visible ? 'Show artwork' : 'Show lyrics',
      child: InkWell(
        onTap: toggle.toggle,
        child: inBorder
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '¶',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    color: toggle.visible ? c.accent : c.textDim,
                  ),
                ),
              )
            : SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(
                    '¶',
                    style: TextStyle(
                      fontSize: 16,
                      color: toggle.visible ? c.accent : c.text2,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The current track's lyrics in a bordered box the size the cover would
/// take. Timed lyrics follow the song: the line being sung is lit and kept
/// in view, and tapping a line jumps there. Plain lyrics just scroll.
class LyricsView extends StatefulWidget {
  final Track track;
  final double width;
  final double height;

  const LyricsView({
    super.key,
    required this.track,
    required this.width,
    required this.height,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// After the listener scrolls by hand, following the song waits this long
  /// so it does not yank the view out from under them.
  static const _manualScrollHold = Duration(seconds: 4);

  final _scroll = ScrollController();
  List<GlobalKey> _lineKeys = const [];
  Future<Lyrics?>? _lyrics;
  Lyrics? _loaded;
  StreamSubscription<Duration>? _position;
  int _current = -1;
  DateTime? _scrolledByHand;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    final a = old.track;
    final b = widget.track;
    if (a != b || a.title != b.title || a.artist != b.artist) _load();
  }

  @override
  void dispose() {
    _position?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    _position?.cancel();
    _position = null;
    _loaded = null;
    _current = -1;
    _scrolledByHand = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);

    final future = LyricsStore.instance.forTrack(widget.track);
    _lyrics = future;
    future.then((lyrics) {
      // A newer track may have taken over while this one was loading.
      if (!mounted || _lyrics != future) return;
      setState(() {
        _loaded = lyrics;
        _lineKeys = [
          for (var i = 0; i < (lyrics?.lines.length ?? 0); i++) GlobalKey(),
        ];
      });
      if (lyrics != null && lyrics.isSynced) {
        _position = context.read<PlayerModel>().positionStream.listen(_follow);
      }
    });
  }

  void _follow(Duration position) {
    final lyrics = _loaded;
    if (lyrics == null) return;
    final line = lyrics.lineAt(position);
    if (line == _current) return;
    setState(() => _current = line);
    final held = _scrolledByHand;
    if (held != null && DateTime.now().difference(held) < _manualScrollHold) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(line));
  }

  /// Scrolls the lyrics box -- only it, never the sheet or panel around
  /// it, which `Scrollable.ensureVisible` would move too -- so [line] sits
  /// a little above the middle.
  void _reveal(int line) {
    if (!mounted || line < 0 || line >= _lineKeys.length) return;
    if (!_scroll.hasClients) return;
    final box = _lineKeys[line].currentContext?.findRenderObject();
    if (box == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _scroll.position;
    final target = viewport
        .getOffsetToReveal(box, 0.4)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(border: Border.all(color: c.border)),
      child: FutureBuilder<Lyrics?>(
        future: _lyrics,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _Note('looking for lyrics…', color: c.textDim);
          }
          final lyrics = _loaded ?? snap.data;
          if (lyrics == null) {
            return _Note('no lyrics found', color: c.textDim);
          }
          if (lyrics.instrumental) {
            return _Note('instrumental', color: c.textDim);
          }
          return _lines(context, lyrics);
        },
      ),
    );
  }

  Widget _lines(BuildContext context, Lyrics lyrics) {
    final c = TerminalColors.of(context);
    final synced = lyrics.isSynced;
    final player = context.read<PlayerModel>();

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _scrolledByHand = DateTime.now();
        return false;
      },
      child: SingleChildScrollView(
        controller: _scroll,
        // Room above and below so the first and last lines can sit level
        // with the middle, where the sung line is kept.
        padding: EdgeInsets.fromLTRB(
          14,
          synced ? widget.height * 0.35 : 12,
          14,
          synced ? widget.height * 0.5 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lyrics.lines.length; i++)
              _Line(
                key: i < _lineKeys.length ? _lineKeys[i] : null,
                text: lyrics.lines[i].text,
                color: !synced
                    ? c.text
                    : i == _current
                    ? c.accent
                    : i < _current
                    ? c.textDim
                    : c.text2,
                bold: synced && i == _current,
                onTap: synced
                    ? () {
                        _scrolledByHand = null;
                        player.seek(lyrics.lines[i].time!);
                      }
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(switch (lyrics.source) {
                LyricsSource.file => 'lyrics · .lrc file',
                LyricsSource.embedded => 'lyrics · from the song file',
                LyricsSource.lrclib => 'lyrics · lrclib.net',
              }, style: TextStyle(fontSize: 11, color: c.textFaint)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String text;
  final Color color;
  final bool bold;
  final VoidCallback? onTap;

  const _Line({
    super.key,
    required this.text,
    required this.color,
    required this.bold,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        // A gap between verses in timed lyrics; a stanza break in plain.
        text.isEmpty ? (onTap == null ? '' : '…') : text,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
    if (onTap == null) return SizedBox(width: double.infinity, child: line);
    return InkWell(
      onTap: onTap,
      child: SizedBox(width: double.infinity, child: line),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final Color color;

  const _Note(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Center(
    child: Text(text, style: TextStyle(color: color)),
  );
}
