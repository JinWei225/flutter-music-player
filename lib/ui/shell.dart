import 'package:flutter/material.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final medium = width < kMediumBreakpoint;
    final open = _nowPlayingOpen(width, player);

    final body = Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _buildBody(),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  _Sidebar(
                    section: _section,
                    onSelect: _select,
                    compact: medium,
                  ),
                  Expanded(
                    child: medium
                        ? _SlideOver(
                            open: open,
                            onDismiss: _closeNowPlaying,
                            panel: NowPlayingPanel(
                              width: _kPanelWidthMedium,
                              elevated: true,
                              onClose: _closeNowPlaying,
                            ),
                            child: body,
                          )
                        : body,
                  ),
                  if (!medium && open)
                    NowPlayingPanel(
                      width: _kPanelWidthWide,
                      onClose: _closeNowPlaying,
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outline),
            PlayerBar(
              nowPlayingOpen: open,
              onToggleNowPlaying: () => _toggleNowPlaying(width),
            ),
          ],
        ),
      ),
    );
  }

  // --- phone ----------------------------------------------------------------

  Widget _buildCompact() {
    return Scaffold(
      body: SafeArea(bottom: false, child: _buildBody()),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            height: 62,
            selectedIndex: _section == _Section.allSongs ? 0 : 1,
            onDestinationSelected: (i) =>
                _select(i == 0 ? _Section.allSongs : _Section.albums),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'All Songs',
              ),
              NavigationDestination(
                icon: Icon(Icons.album_outlined),
                selectedIcon: Icon(Icons.album_rounded),
                label: 'Albums',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_section == _Section.allSongs) return const AllSongsPage();
    final album = _openAlbum;
    if (album != null) {
      return AlbumDetailPage(
        album: album,
        onBack: () => setState(() => _openAlbum = null),
      );
    }
    return AlbumsPage(onOpenAlbum: (a) => setState(() => _openAlbum = a));
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
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: _duration,
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: open ? 0 : -_kPanelWidthMedium,
            child: panel,
          ),
        ],
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
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);
    final library = context.watch<LibraryModel>();
    final themeController = context.watch<ThemeController>();

    final themeIcon = Icon(
      themeController.isDark
          ? Icons.light_mode_rounded
          : Icons.dark_mode_rounded,
      size: 17,
    );
    final themeLabel = themeController.isDark ? 'Light mode' : 'Dark mode';

    return Container(
      width: compact ? 72 : 216,
      decoration: BoxDecoration(
        color: surfaces.sidebar,
        border: Border(right: BorderSide(color: scheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(0, 22, 0, 16)
                : const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 22),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Text(
                    'Mewsic',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _NavItem(
            icon: Icons.library_music_rounded,
            label: 'All Songs',
            count: library.trackCount,
            selected: section == _Section.allSongs,
            compact: compact,
            onTap: () => onSelect(_Section.allSongs),
          ),
          _NavItem(
            icon: Icons.album_rounded,
            label: 'Albums',
            count: library.albums.length,
            selected: section == _Section.albums,
            compact: compact,
            onTap: () => onSelect(_Section.albums),
          ),
          const Spacer(),
          if (compact)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IconButton(
                onPressed: themeController.toggle,
                icon: themeIcon,
                tooltip: themeLabel,
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextButton.icon(
                onPressed: themeController.toggle,
                icon: themeIcon,
                label: Text(themeLabel),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: scheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size.fromHeight(38),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
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
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(7),
            hoverColor: surfaces.hover,
            child: Tooltip(
              message: label,
              child: SizedBox(
                height: 44,
                child: Icon(icon, size: 20, color: color),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          hoverColor: surfaces.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.onSurface : color,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
