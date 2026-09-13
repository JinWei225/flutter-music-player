import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tag_edit.dart';
import 'tag_writer.dart';

/// Writes ID3v2 tags into an `.mp3`, in place.
///
/// The existing tag's frames are kept except for the ones the edit sheet
/// owns, so artwork, lyrics and the like survive. The tag is rewritten in
/// the version the file already uses (v2.3 or v2.4; a v2.2 tag, or a file
/// with none, gets a fresh v2.3). An ID3v1 trailer, if present, is updated
/// as well so a player that only reads that agrees with the rest.
///
/// Written to a temporary file beside the original and renamed over it, so a
/// crash mid-write leaves the song untouched.
class Mp3TagWriter {
  static const _managed = {
    'TIT2', 'TPE1', 'TALB', 'TPE2', 'TCON', 'TYER', 'TDRC', 'TRCK', 'TPOS',
  };

  /// Slack left after the frames so the next small edit need not move the
  /// audio (players that rewrite in place rely on this).
  static const _padding = 1024;

  static const _maxTagBytes = 16 * 1024 * 1024;

  static Future<void> write(File file, TagEdit edit) async {
    final raf = await file.open();
    late final int length;
    late final _ExistingTag existing;
    Uint8List? v1;
    try {
      length = await raf.length();
      existing = await _readExisting(raf, length);
      if (length - existing.totalLength >= 128) {
        await raf.setPosition(length - 128);
        final tail = await raf.read(128);
        if (tail.length == 128 && tail[0] == 0x54 && tail[1] == 0x41 && tail[2] == 0x47) {
          v1 = tail;
        }
      }
    } finally {
      await raf.close();
    }

    final tag = _buildTag(existing, edit);
    final audioEnd = v1 == null ? length : length - 128;

    final tmp = File('${file.path}.mewsic-tmp');
    final sink = tmp.openWrite();
    try {
      sink.add(tag);
      final src = await file.open();
      try {
        var pos = existing.totalLength;
        await src.setPosition(pos);
        while (pos < audioEnd) {
          final bytes = await src.read((audioEnd - pos).clamp(0, 1 << 20));
          if (bytes.isEmpty) throw const TagWriteException('Unexpected end of file');
          sink.add(bytes);
          pos += bytes.length;
        }
      } finally {
        await src.close();
      }
      if (v1 != null) sink.add(_updateV1(v1, edit));
      await sink.flush();
    } finally {
      await sink.close();
    }
    await tmp.rename(file.path);
  }

  // --- reading what is there ------------------------------------------------

  static Future<_ExistingTag> _readExisting(RandomAccessFile raf, int length) async {
    if (length < 10) return _ExistingTag.none();
    await raf.setPosition(0);
    final header = await raf.read(10);
    if (header.length < 10 ||
        header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
      return _ExistingTag.none();
    }

    final major = header[3];
    final flags = header[5];
    final bodySize = _synchsafe(header, 6);
    if (bodySize <= 0 || bodySize > _maxTagBytes || 10 + bodySize > length) {
      return _ExistingTag.none();
    }
    // A v2.4 footer repeats the header after the body.
    final total = 10 + bodySize + (major >= 4 && flags & 0x10 != 0 ? 10 : 0);

    // v2.2 frames use a different layout; rather than convert them, start
    // over. Only the fields the sheet owns are guaranteed to be kept then.
    if (major < 3) return _ExistingTag(3, const [], total);

    await raf.setPosition(10);
    var body = await raf.read(bodySize);
    // v2.3 unsynchronises the whole tag; undo it so the frames parse. (v2.4
    // does it per frame and flags it on the frame, which copies through.)
    if (major == 3 && flags & 0x80 != 0) body = _deunsync(body);

    var pos = 0;
    if (flags & 0x40 != 0 && body.length >= 4) {
      final extSize = major >= 4 ? _synchsafe(body, 0) : _u32(body, 0) + 4;
      if (extSize > 0 && extSize < body.length) pos += extSize;
    }

    final frames = <_Frame>[];
    while (pos + 10 <= body.length) {
      if (body[pos] == 0) break; // padding
      final id = latin1.decode(body.sublist(pos, pos + 4));
      final size = major >= 4 ? _synchsafe(body, pos + 4) : _u32(body, pos + 4);
      final dataStart = pos + 10;
      if (size <= 0 || dataStart + size > body.length) break;
      frames.add(_Frame(
        id,
        body.sublist(pos + 8, pos + 10),
        body.sublist(dataStart, dataStart + size),
      ));
      pos = dataStart + size;
    }
    return _ExistingTag(major, frames, total);
  }

  // --- building the new tag -------------------------------------------------

  static Uint8List _buildTag(_ExistingTag existing, TagEdit edit) {
    final major = existing.major;
    final body = BytesBuilder();

    String? trackTotal;
    String? discTotal;
    for (final f in existing.frames) {
      if (!_managed.contains(f.id)) {
        body.add(_frame(major, f.id, f.flags, f.data));
        continue;
      }
      if (f.id == 'TRCK') trackTotal = _totalOf(f.data);
      if (f.id == 'TPOS') discTotal = _totalOf(f.data);
    }

    void text(String id, String? value) {
      if (value == null) return;
      body.add(_frame(major, id, const [0, 0], _encodeText(major, value)));
    }

    text('TIT2', edit.titleOrNull);
    text('TPE1', edit.artistOrNull);
    text('TALB', edit.albumOrNull);
    text('TPE2', edit.albumArtistOrNull);
    text('TCON', edit.genreOrNull);
    text(major >= 4 ? 'TDRC' : 'TYER', edit.yearOrNull);
    if (edit.trackNumber != null) {
      text('TRCK', _withTotal(edit.trackNumber!, trackTotal));
    }
    if (edit.discNumber != null) {
      text('TPOS', _withTotal(edit.discNumber!, discTotal));
    }
    body.add(Uint8List(_padding));

    final bytes = body.takeBytes();
    if (bytes.length > 0x0fffffff) throw const TagWriteException('Tag too large');
    final out = BytesBuilder()
      ..add(ascii.encode('ID3'))
      ..add([major, 0, 0]) // version, revision, flags
      ..add(_synchsafeBytes(bytes.length))
      ..add(bytes);
    return out.takeBytes();
  }

  static Uint8List _frame(int major, String id, List<int> flags, List<int> data) {
    final out = BytesBuilder()
      ..add(latin1.encode(id))
      ..add(major >= 4 ? _synchsafeBytes(data.length) : _u32Bytes(data.length))
      ..add(flags)
      ..add(data);
    return out.takeBytes();
  }

  /// v2.4 allows UTF-8; v2.3 has to use UTF-16 for anything beyond Latin-1,
  /// and using it always keeps every title round-tripping identically.
  static List<int> _encodeText(int major, String value) {
    if (major >= 4) return [3, ...utf8.encode(value)];
    final units = value.codeUnits;
    final b = Uint8List(1 + 2 + units.length * 2);
    b[0] = 1;
    b[1] = 0xff;
    b[2] = 0xfe; // little-endian BOM
    for (var i = 0; i < units.length; i++) {
      b[3 + i * 2] = units[i] & 0xff;
      b[4 + i * 2] = units[i] >> 8;
    }
    return b;
  }

  /// The "/6" of a "4/6" track frame, so the album's count is not lost.
  static String? _totalOf(Uint8List data) {
    final text = _decodeText(data);
    if (text == null) return null;
    final slash = text.indexOf('/');
    if (slash < 0) return null;
    final total = text.substring(slash + 1).trim();
    return int.tryParse(total) == null ? null : total;
  }

  static String _withTotal(int n, String? total) =>
      total == null ? '$n' : '$n/$total';

  static String? _decodeText(Uint8List data) {
    if (data.length < 2) return null;
    final body = data.sublist(1);
    String text;
    switch (data[0]) {
      case 0:
        text = latin1.decode(body, allowInvalid: true);
        break;
      case 1:
      case 2:
        var bytes = body;
        var little = false;
        if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
          little = true;
          bytes = bytes.sublist(2);
        } else if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
          bytes = bytes.sublist(2);
        }
        final units = <int>[];
        for (var i = 0; i + 1 < bytes.length; i += 2) {
          units.add(little
              ? (bytes[i + 1] << 8) | bytes[i]
              : (bytes[i] << 8) | bytes[i + 1]);
        }
        text = String.fromCharCodes(units);
        break;
      default:
        text = utf8.decode(body, allowMalformed: true);
    }
    final end = text.indexOf('\u0000');
    return end >= 0 ? text.substring(0, end) : text;
  }

  // --- ID3v1 trailer --------------------------------------------------------

  static Uint8List _updateV1(Uint8List old, TagEdit edit) {
    final b = Uint8List.fromList(old);
    void field(int start, int len, String? value) {
      b.fillRange(start, start + len, 0);
      if (value == null) return;
      final units = value.codeUnits;
      for (var i = 0; i < len && i < units.length; i++) {
        b[start + i] = units[i] <= 0xff ? units[i] : 0x3f; // '?'
      }
    }

    field(3, 30, edit.titleOrNull);
    field(33, 30, edit.artistOrNull);
    field(63, 30, edit.albumOrNull);
    field(93, 4, edit.yearOrNull);
    // v1.1: a zero at byte 125 marks byte 126 as the track number.
    final track = edit.trackNumber;
    if (track != null && track <= 0xff) {
      b[125] = 0;
      b[126] = track;
    } else if (b[125] == 0) {
      b[126] = 0;
    }
    final genre = edit.genreOrNull;
    final index = genre == null ? -1 : _id3v1Genres.indexOf(genre);
    b[127] = index < 0 ? 0xff : index;
    return b;
  }

  // --- primitives -----------------------------------------------------------

  static Uint8List _deunsync(Uint8List body) {
    final out = BytesBuilder();
    for (var i = 0; i < body.length; i++) {
      out.addByte(body[i]);
      if (body[i] == 0xff && i + 1 < body.length && body[i + 1] == 0) i++;
    }
    return out.takeBytes();
  }

  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static List<int> _u32Bytes(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  static int _synchsafe(Uint8List b, int o) =>
      ((b[o] & 0x7f) << 21) |
      ((b[o + 1] & 0x7f) << 14) |
      ((b[o + 2] & 0x7f) << 7) |
      (b[o + 3] & 0x7f);

  static List<int> _synchsafeBytes(int v) =>
      [(v >> 21) & 0x7f, (v >> 14) & 0x7f, (v >> 7) & 0x7f, v & 0x7f];
}

class _ExistingTag {
  /// The ID3v2 version to write back in.
  final int major;
  final List<_Frame> frames;

  /// Bytes the old tag occupies at the head of the file (0 when absent).
  final int totalLength;

  const _ExistingTag(this.major, this.frames, this.totalLength);

  factory _ExistingTag.none() => const _ExistingTag(3, [], 0);
}

class _Frame {
  final String id;
  final Uint8List flags;
  final Uint8List data;

  const _Frame(this.id, this.flags, this.data);
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
