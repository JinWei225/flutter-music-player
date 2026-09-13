import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_model.dart';
import '../../core/metadata/tag_edit.dart';
import '../../core/metadata/tag_writer.dart';
import '../../core/models/track.dart';
import '../../core/player/player_model.dart';

/// A row's edit callback, or null when the file cannot be rewritten (an
/// Android row without a readable path, or a format the writer does not do).
VoidCallback? editTrackAction(BuildContext context, Track track) {
  final path = track.filePath;
  if (path == null || !TagWriter.canWrite(path)) return null;
  return () => EditTrackInfoDialog.show(context, track);
}

/// Lets the user correct a track's tags. Saving writes them into the audio
/// file itself, so the fix travels with the file to every other device.
class EditTrackInfoDialog extends StatefulWidget {
  final Track track;

  const EditTrackInfoDialog({super.key, required this.track});

  static Future<void> show(BuildContext context, Track track) => showDialog(
        context: context,
        builder: (_) => EditTrackInfoDialog(track: track),
      );

  @override
  State<EditTrackInfoDialog> createState() => _EditTrackInfoDialogState();
}

class _EditTrackInfoDialogState extends State<EditTrackInfoDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _artist = TextEditingController(text: _shown(widget.track.artist));
  late final _album = TextEditingController(text: _shown(widget.track.album));
  late final _albumArtist =
      TextEditingController(text: widget.track.albumArtist);
  late final _genre = TextEditingController(text: widget.track.genre ?? '');
  late final _year = TextEditingController(text: widget.track.year ?? '');
  late final _trackNumber =
      TextEditingController(text: '${widget.track.trackNumber ?? ''}');
  late final _discNumber =
      TextEditingController(text: '${widget.track.discNumber ?? ''}');

  bool _saving = false;
  String? _error;

  /// The "Unknown …" placeholders are the app's, not the file's; the field
  /// starts blank so the user types a name rather than deleting a fake one.
  static String _shown(String value) =>
      value == 'Unknown Artist' || value == 'Unknown Album' ? '' : value;

  @override
  void dispose() {
    for (final c in [
      _title, _artist, _album, _albumArtist, _genre, _year, _trackNumber,
      _discNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final edit = TagEdit(
      title: _title.text,
      artist: _artist.text,
      album: _album.text,
      albumArtist: _albumArtist.text,
      genre: _genre.text,
      year: _year.text,
      trackNumber: _number(_trackNumber.text),
      discNumber: _number(_discNumber.text),
    );

    final library = context.read<LibraryModel>();
    final player = context.read<PlayerModel>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final updated = await library.saveTags(widget.track, edit);
      player.replaceTrack(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(content: Text('Saved to ${updated.fileName}')),
      );
    } on TagWriteException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  static int? _number(String text) {
    final v = int.tryParse(text.trim());
    return v == null || v <= 0 ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Edit Info'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.track.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _field('Title', _title, autofocus: true),
              _field('Artist', _artist),
              _field('Album', _album),
              _field('Album artist', _albumArtist),
              Row(
                children: [
                  Expanded(child: _field('Genre', _genre)),
                  const SizedBox(width: 12),
                  SizedBox(width: 96, child: _field('Year', _year, digits: 4)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _field('Track #', _trackNumber, digits: 3)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Disc #', _discNumber, digits: 2)),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 12.5, color: scheme.error),
                  ),
                ),
              Text(
                'Changes are written into the file, so they show up in every '
                'player and on every device you copy it to.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool autofocus = false,
    int? digits,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          enabled: !_saving,
          keyboardType: digits == null ? null : TextInputType.number,
          inputFormatters: digits == null
              ? null
              : [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(digits),
                ],
          onSubmitted: (_) => _saving ? null : _save(),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
