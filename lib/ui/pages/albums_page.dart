import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_model.dart';
import '../../core/models/album.dart';
import '../widgets/album_art.dart';

class AlbumsPage extends StatelessWidget {
  final ValueChanged<Album> onOpenAlbum;

  const AlbumsPage({super.key, required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryModel>();
    final albums = library.albums;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Albums',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${albums.length} albums',
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: library.isLoading
              ? const Center(child: CircularProgressIndicator())
              : albums.isEmpty
                  ? Center(
                      child: Text(
                        'No albums found',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisSpacing: 22,
                        crossAxisSpacing: 22,
                        // Room for the two text lines below each cover.
                        childAspectRatio: 0.78,
                      ),
                      itemCount: albums.length,
                      itemBuilder: (context, i) => _AlbumTile(
                        album: albums[i],
                        onTap: () => onOpenAlbum(albums[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _AlbumTile extends StatefulWidget {
  final Album album;
  final VoidCallback onTap;

  const _AlbumTile({required this.album, required this.onTap});

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedScale(
                  scale: _hovered ? 1.03 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  child: AlbumArt(
                    size: constraints.maxWidth,
                    radius: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
