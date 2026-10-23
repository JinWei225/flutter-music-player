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
import 'terminal_widgets.dart';

/// Whether Now Playing lists the queue or the lyrics under the cover. One
/// choice for the docked panel and the phone sheet, remembered across
/// restarts.
class LyricsToggle extends ChangeNotifier {
  final SettingsStore _settings;
  bool _showLyrics;

  LyricsToggle(this._settings) : _showLyrics = _settings.showLyrics;

  bool get showLyrics => _showLyrics;

  Future<void> show({required bool lyrics}) async {
    if (lyrics == _showLyrics) return;
    _showLyrics = lyrics;
    notifyListeners();
    await _settings.setShowLyrics(lyrics);
  }
}

/// `UP NEXT  LYRICS ──── 3/53`: the heading over the queue, with the lyrics
/// as a second tab. The chosen tab is lit; the queue position only shows
/// while the queue does.
class UpNextTabs extends StatelessWidget {
  /// The queue position, `3/53`.
  final String trailing;

  /// 44 on a phone so each tab is a comfortable tap target.
  final double minHeight;

  const UpNextTabs({super.key, required this.trailing, this.minHeight = 0});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final toggle = context.watch<LyricsToggle>();
    final style = columnHeadingStyle(context);

    Widget tab(String label, {required bool lyrics}) {
      final selected = toggle.showLyrics == lyrics;
      return InkWell(
        onTap: () => toggle.show(lyrics: lyrics),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: style.copyWith(
                  color: selected ? c.accent : c.textDim,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        // The tabs' own padding would push UP NEXT off the left edge the
        // rest of the column lines up on.
        Transform.translate(
          offset: const Offset(-4, 0),
          child: tab('UP NEXT', lyrics: false),
        ),
        tab('LYRICS', lyrics: true),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: c.border)),
        if (!toggle.showLyrics) ...[
          const SizedBox(width: 8),
          Text(trailing, style: style),
        ],
      ],
    );
  }
}

/// The current track's lyrics, filling the space the queue would take.
/// Timed lyrics follow the song: the line being sung is lit and kept in
/// view, and tapping a line jumps there. Plain lyrics just scroll.
class LyricsView extends StatefulWidget {
  final Track track;

  const LyricsView({super.key, required this.track});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// After the listener scrolls by hand, following the song waits this long
  /// so it does not yank the view out from under them.
  static const _manualScrollHold = Duration(seconds: 4);

  /// When lrclib.net could not be reached, it is asked once more after
  /// this long by itself; after that, a tap asks again.
  static const _autoRetryAfter = Duration(seconds: 20);

  final _scroll = ScrollController();
  List<GlobalKey> _lineKeys = const [];
  Future<LyricsLookup>? _lyrics;
  Lyrics? _loaded;
  StreamSubscription<Duration>? _position;
  int _current = -1;
  DateTime? _scrolledByHand;
  Timer? _retry;
  var _autoRetried = false;

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
    _retry?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _load({bool retrying = false}) {
    if (!retrying) _autoRetried = false;
    _retry?.cancel();
    _retry = null;
    _position?.cancel();
    _position = null;
    _loaded = null;
    _current = -1;
    _scrolledByHand = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);

    final future = LyricsStore.instance.forTrack(widget.track, retry: retrying);
    _lyrics = future;
    future.then((lookup) {
      // A newer track may have taken over while this one was loading.
      if (!mounted || _lyrics != future) return;
      final lyrics = lookup.lyrics;
      if (lookup.unavailable && lyrics == null && !_autoRetried) {
        _autoRetried = true;
        _retry = Timer(_autoRetryAfter, () {
          if (mounted) setState(() => _load(retrying: true));
        });
      }
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
    return LayoutBuilder(
      builder: (context, box) => FutureBuilder<LyricsLookup>(
        future: _lyrics,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _Note('looking for lyrics…', color: c.textDim);
          }
          final lyrics = _loaded ?? snap.data?.lyrics;
          if (lyrics == null) {
            if (snap.data?.unavailable ?? false) {
              // Not "none": lrclib.net did not answer, so say that, and
              // let a tap ask again rather than waiting for the next play.
              return InkWell(
                onTap: () => setState(() => _load(retrying: true)),
                child: _Note(
                  "couldn't reach lrclib.net\ntap to try again",
                  color: c.textDim,
                ),
              );
            }
            return _Note('no lyrics found', color: c.textDim);
          }
          if (lyrics.instrumental) {
            return _Note('instrumental', color: c.textDim);
          }
          return _lines(context, lyrics, box.maxHeight);
        },
      ),
    );
  }

  Widget _lines(BuildContext context, Lyrics lyrics, double height) {
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
        padding: EdgeInsets.only(
          top: synced ? height * 0.35 : 6,
          bottom: synced ? height * 0.5 : 6,
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
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: color),
    ),
  );
}
