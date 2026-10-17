import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/library/command_search.dart';
import '../../core/library/library_model.dart';
import '../../core/player/player_model.dart';
import '../theme.dart';

// A kew-style prompt: type an artist, album or song and press Enter to play
// it. `shuffle <query>` plays the match shuffled and `next <query>` queues it
// behind the current track; a leading `kew` is accepted out of habit.

/// Desktop matches shown at once; the phone sheet scrolls through more.
const int _kDesktopResults = 8;
const int _kPhoneResults = 30;

(ParsedCommand, List<CommandMatch>) _search(
  BuildContext context,
  String text,
  int limit,
) {
  final command = ParsedCommand.parse(text);
  final albums = context.watch<LibraryModel>().albums;
  return (command, searchLibrary(command.query, albums, limit: limit));
}

/// Plays [match] as [verb] asks.
void runCommand(BuildContext context, CommandVerb verb, CommandMatch match) {
  final player = context.read<PlayerModel>();
  switch (verb) {
    case CommandVerb.play:
      player.playTracks(
        match.tracks,
        startIndex: match.startIndex,
        shuffle: false,
      );
    case CommandVerb.shuffle:
      player.playTracks(match.tracks, shuffle: true);
    case CommandVerb.next:
      // A song queues just itself; an album or artist all of its tracks,
      // in order, behind whatever is playing.
      final tracks = match.kind == MatchKind.song
          ? [match.tracks[match.startIndex]]
          : match.tracks;
      if (!player.hasTrack) {
        player.playTracks(tracks, shuffle: false);
        return;
      }
      for (final t in tracks) {
        player.playNext(t);
      }
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Playing next: ${match.label}'),
            duration: const Duration(seconds: 2),
          ),
        );
  }
}

/// A field with no box: the prompt reads as a bare `❯ _` line. The theme's
/// outlined borders would otherwise apply, since a collapsed decoration
/// only clears the base border.
InputDecoration _bare(String hint, TerminalColors c) => InputDecoration(
  isCollapsed: true,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  hintText: hint,
  hintStyle: TextStyle(color: c.textFaint),
);

String _verbLabel(CommandVerb verb) => switch (verb) {
  CommandVerb.play => 'play',
  CommandVerb.shuffle => 'shuffle',
  CommandVerb.next => 'play next',
};

/// The prompt set into the desktop header line: `❯ _`, with matches in a
/// dropdown underneath while it has text. [focusNode] belongs to the shell,
/// which focuses it on launch and on `/`, and [onFinished] hands focus back
/// to the shell once a command has run or the prompt is dismissed.
class CommandPrompt extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onFinished;

  const CommandPrompt({
    super.key,
    required this.focusNode,
    required this.onFinished,
  });

  @override
  State<CommandPrompt> createState() => _CommandPromptState();
}

class _CommandPromptState extends State<CommandPrompt> {
  final _controller = TextEditingController();
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_sync);
    _controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _onText() {
    _selected = 0;
    _sync();
  }

  /// Shows the dropdown while the prompt is focused and has a query.
  void _sync() {
    final show =
        widget.focusNode.hasFocus &&
        ParsedCommand.parse(_controller.text).query.isNotEmpty;
    if (show) {
      _overlay.show();
    } else {
      _overlay.hide();
    }
    setState(() {});
  }

  void _finish() {
    _controller.clear();
    widget.focusNode.unfocus();
    widget.onFinished();
  }

  void _run(CommandVerb verb, CommandMatch match) {
    runCommand(context, verb, match);
    _finish();
  }

  KeyEventResult _onKey(
    FocusNode node,
    KeyEvent event,
    ParsedCommand command,
    List<CommandMatch> matches,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    // With nothing typed, Space still means play/pause: opening the app and
    // pressing Space resumes the music, as it did before the prompt existed.
    if (key == LogicalKeyboardKey.space && _controller.text.isEmpty) {
      context.read<PlayerModel>().togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_controller.text.isEmpty) {
        _finish();
      } else {
        _controller.clear();
      }
      return KeyEventResult.handled;
    }
    if (matches.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % matches.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected = (_selected - 1 + matches.length) % matches.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _run(command.verb, matches[_selected.clamp(0, matches.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final (command, matches) = _search(
      context,
      _controller.text,
      _kDesktopResults,
    );
    final focused = widget.focusNode.hasFocus;

    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) {
        final width = (MediaQuery.sizeOf(context).width * 0.5).clamp(
          360.0,
          640.0,
        );
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(-8, 8),
            // Taps on the results are not "outside" the prompt.
            child: TextFieldTapRegion(
              child: SizedBox(
                width: width,
                child: CommandResults(
                  command: command,
                  matches: matches,
                  selected: _selected,
                  onPick: (m) => _run(command.verb, m),
                  showKeys: true,
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Focus(
          // Sees keys before the field and the app-wide text shortcuts, so
          // the arrows move the selection rather than the caret.
          onKeyEvent: (node, event) => _onKey(node, event, command, matches),
          canRequestFocus: false,
          skipTraversal: true,
          child: Row(
            children: [
              Text(
                '❯ ',
                style: TextStyle(
                  color: focused ? c.accent : c.textDim,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  onTapOutside: (_) {
                    if (widget.focusNode.hasFocus) _finish();
                  },
                  style: TextStyle(color: c.text),
                  cursorColor: c.accent,
                  cursorWidth: 2,
                  decoration: _bare(
                    focused
                        ? 'artist, album or song  ·  shuffle …  ·  next …'
                        : 'press / to play by name',
                    c,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's prompt: a full-height sheet with the field on top, opened
/// from the top line. There is no hardware keyboard to "just start typing",
/// so it is a deliberate tap away instead of always focused.
class CommandSheet extends StatefulWidget {
  const CommandSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const CommandSheet(),
  );

  @override
  State<CommandSheet> createState() => _CommandSheetState();
}

class _CommandSheetState extends State<CommandSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(CommandVerb verb, CommandMatch match) {
    // Run against the sheet's parent context: the sheet is about to close.
    final navigator = Navigator.of(context);
    runCommand(context, verb, match);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final (command, matches) = _search(
      context,
      _controller.text,
      _kPhoneResults,
    );

    return Material(
      color: c.background,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(
                  children: [
                    Text(
                      '❯ ',
                      style: TextStyle(
                        fontSize: 16,
                        color: c.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: TextStyle(fontSize: 16, color: c.text),
                        cursorColor: c.accent,
                        onSubmitted: (_) {
                          if (matches.isNotEmpty) {
                            _run(command.verb, matches.first);
                          }
                        },
                        decoration: _bare('artist, album or song', c),
                      ),
                    ),
                    Tooltip(
                      message: 'Close',
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Text(
                              '▾',
                              style: TextStyle(fontSize: 16, color: c.text2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: c.border),
              Expanded(
                child: command.query.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'type to play an artist, album or song.\n'
                          'start with "shuffle" to shuffle it, or "next" '
                          'to queue it after the current song.',
                          style: TextStyle(fontSize: 12, color: c.textDim),
                        ),
                      )
                    : SingleChildScrollView(
                        child: CommandResults(
                          command: command,
                          matches: matches,
                          selected: 0,
                          onPick: (m) => _run(command.verb, m),
                          rowHeight: 44,
                          boxed: false,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The match list shared by the desktop dropdown and the phone sheet:
/// `album  NA — NAYEON · 7 tracks          22:27`.
class CommandResults extends StatelessWidget {
  final ParsedCommand command;
  final List<CommandMatch> matches;
  final int selected;
  final ValueChanged<CommandMatch> onPick;
  final double rowHeight;

  /// Draws the raised, accent-bordered box of the desktop dropdown.
  final bool boxed;

  /// Adds the `↑↓ select  enter play  esc close` line.
  final bool showKeys;

  const CommandResults({
    super.key,
    required this.command,
    required this.matches,
    required this.selected,
    required this.onPick,
    this.rowHeight = 30,
    this.boxed = true,
    this.showKeys = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final rows = <Widget>[
      if (matches.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'no match for "${command.query}"',
            style: TextStyle(color: c.textDim),
          ),
        ),
      for (var i = 0; i < matches.length; i++)
        _ResultRow(
          match: matches[i],
          selected: i == selected,
          height: rowHeight,
          onTap: () => onPick(matches[i]),
        ),
      if (showKeys)
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12, color: c.textDim),
              children: [
                TextSpan(
                  text: '↑↓',
                  style: TextStyle(color: c.key),
                ),
                const TextSpan(text: ' select   '),
                TextSpan(
                  text: 'enter',
                  style: TextStyle(color: c.key),
                ),
                TextSpan(text: ' ${_verbLabel(command.verb)}   '),
                TextSpan(
                  text: 'esc',
                  style: TextStyle(color: c.key),
                ),
                const TextSpan(text: ' close'),
              ],
            ),
          ),
        ),
    ];

    final list = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
    if (!boxed) return list;
    return Material(
      color: c.surfaceRaised,
      shape: RoundedRectangleBorder(side: BorderSide(color: c.accent)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: list,
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final CommandMatch match;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  const _ResultRow({
    required this.match,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  String _detail() {
    final count = match.tracks.length;
    String songs(int n) => '$n ${n == 1 ? 'song' : 'songs'}';
    switch (match.kind) {
      case MatchKind.artist:
        final albums = {for (final t in match.tracks) t.albumKey}.length;
        return '${albums == 1 ? '1 album' : '$albums albums'} · ${songs(count)}';
      case MatchKind.album:
        return '— ${match.album!.artist} · ${songs(count)}';
      case MatchKind.song:
        final t = match.tracks[match.startIndex];
        return '— ${t.artist} · ${t.album}';
    }
  }

  TextStyle _labelStyle(TerminalColors c) => TextStyle(
    color: selected ? c.accent : c.text,
    fontWeight: FontWeight.w700,
  );

  /// `NA  — NAYEON · 7 songs` on one line.
  Widget _inline(TerminalColors c) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: match.label, style: _labelStyle(c)),
        TextSpan(
          text: '  ${_detail()}',
          style: TextStyle(color: c.textDim),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  /// The name over `NAYEON · 7 songs`.
  Widget _stacked(TerminalColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        match.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _labelStyle(c),
      ),
      Text(
        _detail().replaceFirst('— ', ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: c.textDim),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final time = match.kind == MatchKind.song
        ? match.tracks[match.startIndex].duration
        : match.totalDuration;

    // A phone row is too narrow for name and detail on one line, so the
    // detail moves underneath, as it does in the phone's track list.
    final twoLine = height >= 44;

    return Material(
      color: selected ? c.selection : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: twoLine ? 5 : 0,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  selected ? '▸' : '',
                  style: TextStyle(color: c.accent),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  match.kind.name,
                  style: TextStyle(fontSize: 12, color: c.textDim),
                ),
              ),
              Expanded(child: twoLine ? _stacked(c) : _inline(c)),
              const SizedBox(width: 12),
              Text(formatDuration(time), style: TextStyle(color: c.textDim)),
            ],
          ),
        ),
      ),
    );
  }
}
