import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'raw_tags.dart';

/// Reads iTunes/MPEG-4 metadata (`.m4a`, `.mp4`, `.m4b`) straight from the box
/// tree, without loading the whole file into memory.
///
/// Two details matter for files bought from the iTunes Store:
///
///  * iTunes writes an **empty** `udta/meta/ilst` inside every `trak`, plus the
///    real one at `moov` level. A parser that takes the first `ilst` it finds
///    reports blank titles. Only `moov`'s direct `udta` children are read here.
///  * The `moov` box is often written *after* `mdat`, so the tree must be
///    walked by box size rather than assumed to start near byte zero.
class Mp4TagParser {
  static const _title = '©nam';
  static const _artist = '©ART';
  static const _album = '©alb';
  static const _albumArtist = 'aART';
  static const _year = '©day';
  static const _genreText = '©gen';

  // Sort-order variants. Normally these hold alternate sorting forms
  // ("Beatles, The"), but some store downloads ship *only* these, with no
  // ©nam/©ART/©alb at all -- Android's own media scanner reports such files as
  // "<unknown>". Used strictly as a fallback so a real tag always wins.
  static const _sortTitle = 'sonm';
  static const _sortArtist = 'soar';
  static const _sortAlbum = 'soal';
  static const _sortAlbumArtist = 'soaa';

  // iTunes Store catalogue IDs. Some purchases arrive with nothing *but*
  // these (no ©nam/©ART/©alb, not even the sort variants); the IDs are then
  // the only link between such a track and the rest of its album.
  static const _storeTrackId = 'cnID';
  static const _storeArtistId = 'atID';
  static const _storeAlbumId = 'plID';

  /// Container boxes whose children we may need to descend into.
  static const _maxBoxes = 4096;

  static Future<RawTags?> parse(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final moov = _find(await _children(raf, 0, length), 'moov');
      if (moov == null) return null;

      final moovKids = await _children(raf, moov.start, moov.end);
      final tags = RawTags()..duration = await _duration(raf, _find(moovKids, 'mvhd'));

      // Only `moov`'s own `udta` children -- never a `trak`'s decoy copy.
      RawTags? best;
      for (final udta in moovKids.where((b) => b.type == 'udta')) {
        final meta = _find(await _children(raf, udta.start, udta.end), 'meta');
        if (meta == null) continue;
        final contentStart = await _metaContentStart(raf, meta);
        final ilst = _find(await _children(raf, contentStart, meta.end), 'ilst');
        if (ilst == null) continue;
        final found = await _readIlst(raf, ilst);
        if (best == null || found.fieldCount > best.fieldCount) best = found;
      }

      if (best != null) tags.backfillFrom(best);
      return tags;
    } on FileSystemException {
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Returns the embedded cover image bytes (`covr`), or null when the file
  /// carries none. Read separately from [parse] because artwork is only needed
  /// for the track being shown, not for every file in a library scan.
  static Future<Uint8List?> readArtwork(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final moov = _find(await _children(raf, 0, length), 'moov');
      if (moov == null) return null;

      for (final udta
          in (await _children(raf, moov.start, moov.end))
              .where((b) => b.type == 'udta')) {
        final meta = _find(await _children(raf, udta.start, udta.end), 'meta');
        if (meta == null) continue;
        final contentStart = await _metaContentStart(raf, meta);
        final ilst = _find(await _children(raf, contentStart, meta.end), 'ilst');
        if (ilst == null) continue;

        for (final item in await _children(raf, ilst.start, ilst.end)) {
          if (item.type != 'covr') continue;
          for (final data in await _children(raf, item.start, item.end)) {
            if (data.type != 'data') continue;
            final head = await _readAt(raf, data.start, 8);
            if (head.length < 8) continue;
            // 13 == JPEG, 14 == PNG.
            final wellKnownType = _u32(head, 0) & 0xffffff;
            if (wellKnownType != 13 && wellKnownType != 14) continue;
            final len = data.end - (data.start + 8);
            if (len <= 0 || len > _maxArtworkBytes) continue;
            return await _readAt(raf, data.start + 8, len);
          }
        }
      }
      return null;
    } on FileSystemException {
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Guards against a corrupt length pulling a huge read into memory.
  static const _maxArtworkBytes = 12 * 1024 * 1024;

  // --- box tree -------------------------------------------------------------

  static Future<List<_Box>> _children(RandomAccessFile raf, int start, int end) async {
    final boxes = <_Box>[];
    var pos = start;
    while (pos + 8 <= end && boxes.length < _maxBoxes) {
      final header = await _readAt(raf, pos, 8);
      if (header.length < 8) break;
      var size = _u32(header, 0);
      final type = _type(header, 4);
      var headerLen = 8;

      if (size == 1) {
        // 64-bit `largesize` follows the type.
        final ext = await _readAt(raf, pos + 8, 8);
        if (ext.length < 8) break;
        size = _u64(ext, 0);
        headerLen = 16;
      } else if (size == 0) {
        size = end - pos; // box runs to the end of its parent
      }

      if (size < headerLen || pos + size > end) break;
      boxes.add(_Box(type, pos + headerLen, pos + size));
      pos += size;
    }
    return boxes;
  }

  static _Box? _find(List<_Box> boxes, String type) {
    for (final b in boxes) {
      if (b.type == type) return b;
    }
    return null;
  }

  /// `meta` is specified as a FullBox (4 bytes of version/flags before its
  /// children) but some writers emit it as a plain container. Probe for a
  /// sane child header at offset 0 and fall back to offset 4.
  static Future<int> _metaContentStart(RandomAccessFile raf, _Box meta) async {
    if (await _looksLikeBox(raf, meta.start, meta.end)) return meta.start;
    return meta.start + 4;
  }

  static Future<bool> _looksLikeBox(RandomAccessFile raf, int pos, int end) async {
    if (pos + 8 > end) return false;
    final h = await _readAt(raf, pos, 8);
    if (h.length < 8) return false;
    final size = _u32(h, 0);
    if (size < 8 || pos + size > end) return false;
    for (var i = 4; i < 8; i++) {
      final c = h[i];
      final printable = (c >= 0x20 && c <= 0x7e) || c == 0xa9;
      if (!printable) return false;
    }
    return true;
  }

  // --- movie header ---------------------------------------------------------

  static Future<Duration?> _duration(RandomAccessFile raf, _Box? mvhd) async {
    if (mvhd == null || mvhd.end - mvhd.start < 20) return null;
    final b = await _readAt(raf, mvhd.start, 32);
    if (b.isEmpty) return null;

    int timescale;
    int units;
    if (b[0] == 0) {
      if (b.length < 20) return null;
      timescale = _u32(b, 12);
      units = _u32(b, 16);
    } else {
      if (b.length < 32) return null;
      timescale = _u32(b, 20);
      units = _u64(b, 24);
    }
    if (timescale <= 0 || units <= 0) return null;
    return Duration(microseconds: (units * 1000000 / timescale).round());
  }

  // --- item list ------------------------------------------------------------

  static Future<RawTags> _readIlst(RandomAccessFile raf, _Box ilst) async {
    final tags = RawTags();
    final sort = RawTags();
    for (final item in await _children(raf, ilst.start, ilst.end)) {
      for (final data in await _children(raf, item.start, item.end)) {
        if (data.type != 'data') continue;
        // data box: 4 bytes version+flags, 4 bytes locale, then payload.
        final head = await _readAt(raf, data.start, 8);
        if (head.length < 8) continue;
        final wellKnownType = _u32(head, 0) & 0xffffff;
        final payloadLen = data.end - (data.start + 8);
        if (payloadLen <= 0 || payloadLen > 1 << 22) continue;
        final payload = await _readAt(raf, data.start + 8, payloadLen);

        switch (item.type) {
          case 'trkn':
            if (payload.length >= 4) tags.trackNumber = _nonZero(_u16(payload, 2));
            break;
          case 'disk':
            if (payload.length >= 4) tags.discNumber = _nonZero(_u16(payload, 2));
            break;
          case 'gnre':
            // Numeric ID3v1 genre; only used if no free-text genre shows up.
            if (payload.length >= 2 && tags.genre == null) {
              final id = _u16(payload, 0) - 1;
              if (id >= 0 && id < _id3v1Genres.length) tags.genre = _id3v1Genres[id];
            }
            break;
          case _storeTrackId:
            tags.storeTrackId = _nonZero(_bigEndian(payload));
            break;
          case _storeArtistId:
            tags.storeArtistId = _nonZero(_bigEndian(payload));
            break;
          case _storeAlbumId:
            tags.storeAlbumId = _nonZero(_bigEndian(payload));
            break;
          default:
            // Type 1 is UTF-8 text; everything else here (artwork, ints) is
            // not something we surface.
            if (wellKnownType != 1) break;
            final text = utf8.decode(payload, allowMalformed: true).trim();
            if (text.isEmpty) break;
            switch (item.type) {
              case _title:
                tags.title = text;
                break;
              case _artist:
                tags.artist = text;
                break;
              case _album:
                tags.album = text;
                break;
              case _albumArtist:
                tags.albumArtist = text;
                break;
              case _year:
                tags.year = text.length >= 4 ? text.substring(0, 4) : text;
                tags.rawDate = text;
                break;
              case _genreText:
                tags.genre = text;
                break;
              case _sortTitle:
                sort.title = text;
                break;
              case _sortArtist:
                sort.artist = text;
                break;
              case _sortAlbum:
                sort.album = text;
                break;
              case _sortAlbumArtist:
                sort.albumArtist = text;
                break;
            }
        }
      }
    }

    // Only fills fields the real atoms did not provide.
    tags.namesFromSortAtoms = (tags.title == null && sort.title != null) ||
        (tags.artist == null && sort.artist != null) ||
        (tags.album == null && sort.album != null);
    tags.backfillFrom(sort);
    return tags;
  }

  // --- primitives -----------------------------------------------------------

  static Future<Uint8List> _readAt(RandomAccessFile raf, int pos, int len) async {
    if (len <= 0) return Uint8List(0);
    await raf.setPosition(pos);
    return raf.read(len);
  }

  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _u64(Uint8List b, int o) => (_u32(b, o) << 32) | _u32(b, o + 4);

  /// Whole-payload integer: the store IDs are written as 4 or 8 bytes.
  static int _bigEndian(Uint8List b) {
    if (b.isEmpty || b.length > 8) return 0;
    var v = 0;
    for (final byte in b) {
      v = (v << 8) | byte;
    }
    return v;
  }

  static String _type(Uint8List b, int o) =>
      String.fromCharCodes(b.sublist(o, o + 4));

  static int? _nonZero(int v) => v == 0 ? null : v;
}

class _Box {
  final String type;

  /// Offset of the box's payload (past size/type/largesize).
  final int start;

  /// Offset one past the end of the box.
  final int end;

  const _Box(this.type, this.start, this.end);
}

const _id3v1Genres = <String>[
  'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge',
  'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B',
  'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
  'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient',
  'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical',
  'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
  'Alt. Rock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
  'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave',
  'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream',
  'Southern Rock', 'Comedy', 'Cult', 'Gangsta Rap', 'Top 40', 'Christian Rap',
  'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave', 'Psychedelic',
  'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal', 'Acid Punk', 'Acid Jazz',
  'Polka', 'Retro', 'Musical', 'Rock & Roll', 'Hard Rock',
];
