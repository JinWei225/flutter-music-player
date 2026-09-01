import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/library/library_model.dart';
import '../core/models/album.dart';
import '../core/player/player_model.dart';
import 'pages/album_detail_page.dart';
import 'pages/albums_page.dart';
import 'pages/all_songs_page.dart';
import 'theme.dart';
import 'widgets/mini_player.dart';
import 'widgets/player_bar.dart';
import 'widgets/queue_panel.dart';

enum _Section { allSongs, albums }

/// Below this the sidebar and full player bar do not fit, so the phone layout
/// (bottom navigation + mini player) is used instead.
const double kCompactBreakpoint = 700;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Section _section = _Section.allSongs;
  Album? _openAlbum;
  bool _queueOpen = false;

  /// Holds focus for the app so the Space shortcut works without the user
  /// having to click anything first.
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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
        builder: (context, constraints) => constraints.maxWidth < kCompactBreakpoint
            ? _buildCompact()
            : _buildWide(context),
      ),
    );
  }

  // --- desktop / tablet -----------------------------------------------------

  Widget _buildWide(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _Sidebar(section: _section, onSelect: _select),
                Expanded(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _buildBody(),
                  ),
                ),
                if (_queueOpen)
                  QueuePanel(
                    onClose: () => setState(() => _queueOpen = false),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outline),
          PlayerBar(
            queueOpen: _queueOpen,
            onToggleQueue: () {
              setState(() => _queueOpen = !_queueOpen);
              _focusNode.requestFocus();
            },
          ),
        ],
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
    return AlbumsPage(
      onOpenAlbum: (a) => setState(() => _openAlbum = a),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final _Section section;
  final ValueChanged<_Section> onSelect;

  const _Sidebar({required this.section, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);
    final library = context.watch<LibraryModel>();
    final themeController = context.watch<ThemeController>();

    return Container(
      width: 216,
      decoration: BoxDecoration(
        color: surfaces.sidebar,
        border: Border(right: BorderSide(color: scheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Row(
              children: [
                Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 22),
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
            ),
          ),
          _NavItem(
            icon: Icons.library_music_rounded,
            label: 'All Songs',
            count: library.trackCount,
            selected: section == _Section.allSongs,
            onTap: () => onSelect(_Section.allSongs),
          ),
          _NavItem(
            icon: Icons.album_rounded,
            label: 'Albums',
            count: library.albums.length,
            selected: section == _Section.albums,
            onTap: () => onSelect(_Section.albums),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextButton.icon(
              onPressed: themeController.toggle,
              icon: Icon(
                themeController.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                size: 17,
              ),
              label: Text(themeController.isDark ? 'Light mode' : 'Dark mode'),
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
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

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
