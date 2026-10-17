import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/library/library_model.dart';
import '../core/models/album.dart';
import '../core/player/player_model.dart';
import 'breakpoints.dart';
import 'pages/album_detail_page.dart';
import 'pages/albums_page.dart';
import 'pages/all_songs_page.dart';
import 'theme.dart';
import 'widgets/mini_player.dart';
import 'widgets/now_playing_panel.dart';
import 'widgets/player_bar.dart';
import 'widgets/terminal_panel.dart';
import 'widgets/terminal_widgets.dart';

enum _Section { allSongs, albums }

/// Slide-over width on medium layouts; docked width above them.
const double _kPanelWidthMedium = 320;
const double _kPanelWidthWide = 340;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Section _section = _Section.allSongs;
  Album? _openAlbum;

  /// Null until the user toggles it, at which point their choice sticks.
  /// Until then the panel follows [_nowPlayingOpen]'s default.
  bool? _nowPlayingChoice;

  /// Holds focus for the app so the Space shortcut works without the user
  /// having to click anything first.
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Open by default only where it does not crowd the library, and only once
  /// there is something to show.
  bool _nowPlayingOpen(double width, PlayerModel player) =>
      _nowPlayingChoice ?? (width >= kExpandedBreakpoint && player.hasTrack);

  void _toggleNowPlaying(double width) {
    final player = context.read<PlayerModel>();
    setState(() {
      _nowPlayingChoice = !_nowPlayingOpen(width, player);
    });
    _focusNode.requestFocus();
  }

  void _closeNowPlaying() {
    setState(() => _nowPlayingChoice = false);
    _focusNode.requestFocus();
  }

  void _select(_Section section) {
    setState(() {
      _section = section;
      // Leaving and re-entering Albums should land on the grid, not the last
      // album the user happened to open.
      if (section == _Section.albums) _openAlbum = null;
    });
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    context.read<PlayerModel>().togglePlayPause();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < kCompactBreakpoint
            ? _buildCompact()
            : _buildWide(context, constraints.maxWidth),
      ),
    );
  }

  // --- desktop / tablet -----------------------------------------------------

  Widget _buildWide(BuildContext context, double width) {
    final player = context.watch<PlayerModel>();
    final medium = width < kMediumBreakpoint;
    final open = _nowPlayingOpen(width, player);
    final album = _section == _Section.albums ? _currentOpenAlbum() : null;

    // Panels sit 16 apart; a panel's label rides up into the gap above it,
    // so vertical gaps are measured to the border, not the widget's top.
    const gap = 16.0;
    const vGap = gap - TerminalPanel.labelInset;

    final main = TerminalPanel(
      title: switch (_section) {
        _Section.allSongs => 'all songs',
        _Section.albums when album != null =>
          'albums / ${album.name.toLowerCase()}',
        _Section.albums => 'albums',
      },
      highlighted: true,
      child: _buildBody(),
    );

    final panels = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(section: _section, onSelect: _select, compact: medium),
        const SizedBox(width: gap),
        Expanded(child: main),
        if (!medium && open) ...[
          const SizedBox(width: gap),
          NowPlayingPanel(width: _kPanelWidthWide, onClose: _closeNowPlaying),
        ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(gap, 14, gap, 0),
              child: _HeaderLine(path: _path(album)),
            ),
            const SizedBox(height: vGap),
            Expanded(
              child: medium
                  ? _SlideOver(
                      open: open,
                      onDismiss: _closeNowPlaying,
                      panel: NowPlayingPanel(
                        width: _kPanelWidthMedium,
                        onClose: _closeNowPlaying,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: gap),
                        child: panels,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: gap),
                      child: panels,
                    ),
            ),
            const SizedBox(height: vGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: gap),
              child: PlayerBar(
                nowPlayingOpen: open,
                onToggleNowPlaying: () => _toggleNowPlaying(width),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(gap, 8, gap, 10),
              child: _StatusLine(),
            ),
          ],
        ),
      ),
    );
  }

  /// The breadcrumb in the header line, as if the library were a folder.
  String _path(Album? album) => switch (_section) {
    _Section.allSongs => '~/Music',
    _Section.albums when album != null =>
      '~/Music/albums/${pathSlug(album.name)}',
    _Section.albums => '~/Music/albums',
  };

  // --- phone ----------------------------------------------------------------

  Widget _buildCompact() {
    return Scaffold(
      body: SafeArea(bottom: false, child: _buildBody()),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          _PhoneTabs(section: _section, onSelect: _select),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_section == _Section.allSongs) return const AllSongsPage();
    final album = _currentOpenAlbum();
    if (album != null) {
      return AlbumDetailPage(
        album: album,
        onBack: () => setState(() => _openAlbum = null),
      );
    }
    return AlbumsPage(onOpenAlbum: (a) => setState(() => _openAlbum = a));
  }

  /// The open album as the library now has it. Editing a track's tags
  /// regroups the albums, so the object opened earlier can go stale -- or,
  /// if the album was renamed out from under the page, vanish, in which case
  /// the list is shown instead.
  Album? _currentOpenAlbum() {
    final opened = _openAlbum;
    if (opened == null) return null;
    for (final a in context.watch<LibraryModel>().albums) {
      if (a.key == opened.key) return a;
    }
    return null;
  }
}

/// Panel that slides in from the right over [child], behind a scrim that
/// dismisses it. Both stay in the tree so the motion can animate.
class _SlideOver extends StatelessWidget {
  final bool open;
  final VoidCallback onDismiss;
  final Widget panel;
  final Widget child;

  const _SlideOver({
    required this.open,
    required this.onDismiss,
    required this.panel,
    required this.child,
  });

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return PopScope(
      // The Android back gesture closes the panel before it leaves the app.
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onDismiss();
      },
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          child,
          IgnorePointer(
            ignoring: !open,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: _duration,
              child: GestureDetector(
                onTap: onDismiss,
                child: Container(color: c.background.withValues(alpha: 0.7)),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: _duration,
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            // Lines up with the window's outer padding when open.
            right: open ? 16 : -_kPanelWidthMedium,
            child: panel,
          ),
        ],
      ),
    );
  }
}

/// `mewsic ~/Music/albums            17 songs · 3 albums`
class _HeaderLine extends StatelessWidget {
  final String path;

  const _HeaderLine({required this.path});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final library = context.watch<LibraryModel>();
    return DefaultTextStyle.merge(
      style: TextStyle(color: c.textDim),
      child: Row(
        children: [
          Text(
            'mewsic',
            style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          Text(
            '${library.trackCount} songs · ${library.albums.length} albums',
          ),
        ],
      ),
    );
  }
}

/// `PLAYING  repeat list  shuffle off       space play/pause  right-click …`
class _StatusLine extends StatelessWidget {
  const _StatusLine();

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();

    final (badge, badgeColor) = player.isPlaying
        ? ('PLAYING', c.ok)
        : player.hasTrack
        ? ('PAUSED', c.accent)
        : ('STOPPED', c.textDim);
    final repeat = switch (player.repeat) {
      RepeatMode.off => 'off',
      RepeatMode.all => 'list',
      RepeatMode.one => 'one',
    };

    TextSpan setting(String name, String value) => TextSpan(
      text: '$name ',
      children: [TextSpan(text: value, style: TextStyle(color: c.text))],
    );
    TextSpan hint(String key, String action) => TextSpan(
      children: [
        TextSpan(text: key, style: TextStyle(color: c.key)),
        TextSpan(text: ' $action'),
      ],
    );
    const gap = TextSpan(text: '   ');

    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: 12, color: c.textDim),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Container(
              color: badgeColor,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                badge,
                style: TextStyle(
                  color: c.background,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    setting('repeat', repeat),
                    gap,
                    setting('shuffle', player.shuffle ? 'on' : 'off'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            // Key hints are the first thing to go when space runs out.
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    hint('space', 'play/pause'),
                    if (constraints.maxWidth >= 720) ...[
                      gap,
                      hint('right-click', 'track menu'),
                    ],
                  ],
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final _Section section;
  final ValueChanged<_Section> onSelect;

  /// Icons only, for widths where the labels would crowd the library.
  final bool compact;

  const _Sidebar({
    required this.section,
    required this.onSelect,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final library = context.watch<LibraryModel>();
    final themeController = context.watch<ThemeController>();
    final themeLabel = themeController.isDark ? 'Light mode' : 'Dark mode';

    return SizedBox(
      width: compact ? 72 : 200,
      child: TerminalPanel(
        title: compact ? null : 'library',
        padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NavItem(
              icon: Icons.library_music_sharp,
              label: 'All Songs',
              count: library.trackCount,
              selected: section == _Section.allSongs,
              compact: compact,
              onTap: () => onSelect(_Section.allSongs),
            ),
            const SizedBox(height: 2),
            _NavItem(
              icon: Icons.album_sharp,
              label: 'Albums',
              count: library.albums.length,
              selected: section == _Section.albums,
              compact: compact,
              onTap: () => onSelect(_Section.albums),
            ),
            const Spacer(),
            if (compact)
              IconButton(
                onPressed: themeController.toggle,
                icon: const ThemeGlyph(size: 18),
                tooltip: themeLabel,
                color: c.textDim,
              )
            else
              InkWell(
                onTap: themeController.toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      ThemeGlyph(color: c.textDim),
                      const SizedBox(width: 8),
                      Text(
                        themeLabel.toLowerCase(),
                        style: TextStyle(color: c.textDim),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;

  /// Title case; shown lowercase, and kept as is for the rail's tooltip.
  final String label;
  final int count;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);

    if (compact) {
      return Material(
        color: selected ? c.selection : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Tooltip(
            message: label,
            child: SizedBox(
              height: 44,
              child: Icon(
                icon,
                size: 20,
                color: selected ? c.accent : c.text2,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: selected ? c.selection : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: selected ? c.accent : c.text2),
            child: Row(
              children: [
                // Two cells either way, so the labels line up.
                Text(selected ? '▸ ' : '  '),
                Expanded(
                  child: Text(
                    label.toLowerCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(color: selected ? c.accent : c.textDim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's two section tabs, `songs` / `albums`, in place of a Material
/// navigation bar.
class _PhoneTabs extends StatelessWidget {
  final _Section section;
  final ValueChanged<_Section> onSelect;

  const _PhoneTabs({required this.section, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);

    Widget tab(String label, _Section target) {
      final selected = section == target;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: selected ? c.selection : Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(target),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? c.accent : c.textDim,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            tab('songs', _Section.allSongs),
            const SizedBox(width: 8),
            tab('albums', _Section.albums),
          ],
        ),
      ),
    );
  }
}
