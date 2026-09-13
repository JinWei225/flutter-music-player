import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tag_edit.dart';
import 'tag_writer.dart';

/// Writes iTunes-style metadata into an `.m4a`/`.mp4`/`.m4b`, in place.
///
/// Only the `moov/udta/meta/ilst` item list is rebuilt; every other box is
/// copied byte for byte. The one complication is that changing `ilst` changes
/// the size of `moov`, and when `moov` sits before `mdat` (as it does in
/// store downloads) that would shift the audio and break every chunk offset
/// in `stco`/`co64`. Two ways out, tried in order:
///
///  1. iTunes leaves a `free` box right after `moov` for exactly this reason.
///     If it can absorb the growth (or shrinkage), it does, and nothing after
///     it moves.
///  2. Otherwise the rest of the file shifts, and every chunk offset that
///     points past the old `moov` is adjusted by the difference.
///
/// The result is always written to a temporary file beside the original and
/// renamed over it, so a crash mid-write leaves the song untouched.
class Mp4TagWriter {
  /// The atoms the edit sheet owns. Anything not in this set survives intact.
  static const _managed = {
    '©nam', '©ART', '©alb', 'aART', '©gen', 'gnre', '©day', 'trkn', 'disk',
  };

  /// A `moov` bigger than this is not a music file we should be rewriting.
  static const _maxMoovBytes = 64 * 1024 * 1024;

  static Future<void> write(File file, TagEdit edit) async {
    final raf = await file.open();
    late final Uint8List moovBytes;
    late final _Box moov;
    late final _Box? freeAfter;
    late final int length;
    try {
      length = await raf.length();
      final top = await _topLevel(raf, length);
      final found = _find(top, 'moov');
      if (found == null) throw const TagWriteException('No moov box found');
      moov = found;
      if (moov.size > _maxMoovBytes) {
        throw const TagWriteException('moov box is implausibly large');
      }
      await raf.setPosition(moov.offset);
      moovBytes = await raf.read(moov.size);

      final next = top.indexOf(moov) + 1;
      freeAfter =
          next < top.length && top[next].type == 'free' ? top[next] : null;
    } finally {
      await raf.close();
    }

    final rebuilt = _rebuildMoov(moovBytes, moov.headerLen, edit);
    final delta = rebuilt.length - moovBytes.length;

    // Route 1: let the neighbouring free box soak up the change.
    int? newFreeSize;
    if (freeAfter != null && freeAfter.size - delta >= 8) {
      newFreeSize = freeAfter.size - delta;
    } else if (delta != 0) {
      // Route 2: everything after moov moves.
      _shiftChunkOffsets(rebuilt, moov.headerLen, moov.offset + moov.size, delta);
    }

    final tmp = File('${file.path}.mewsic-tmp');
    final sink = tmp.openWrite();
    try {
      final src = await file.open();
      try {
        await _copy(src, sink, 0, moov.offset);
        sink.add(rebuilt);
        if (newFreeSize != null) {
          sink.add(_header(newFreeSize, 'free'));
          // The free box's own contents are junk; skip the old header and
          // emit however much padding the new size calls for.
          sink.add(Uint8List(newFreeSize - 8));
          await _copy(src, sink, freeAfter!.offset + freeAfter.size, length);
        } else {
          await _copy(src, sink, moov.offset + moov.size, length);
        }
      } finally {
        await src.close();
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await tmp.rename(file.path);
  }

  // --- rebuilding moov ------------------------------------------------------

  static Uint8List _rebuildMoov(Uint8List moov, int headerLen, TagEdit edit) {
    final kids = _children(moov, headerLen, moov.length);
    final out = BytesBuilder();
    var replaced = false;

    for (final k in kids) {
      if (k.type == 'udta' && !replaced) {
        final udta = _rebuildUdta(moov, k, edit);
        if (udta != null) {
          out.add(udta);
          replaced = true;
          continue;
        }
      }
      out.add(Uint8List.sublistView(moov, k.offset, k.offset + k.size));
    }

    if (!replaced) {
      // No udta/meta at all: make the whole chain from scratch.
      out.add(_box('udta', _buildMeta(null, null, edit)));
    }

    return _withHeader(out.takeBytes(), 'moov', headerLen);
  }

  /// Rebuilds [udta] with its `meta/ilst` replaced, or returns null when this
  /// udta carries no `meta` (a trak-style `udta` holding only loudness data).
  static Uint8List? _rebuildUdta(Uint8List buf, _Box udta, TagEdit edit) {
    final kids = _children(buf, udta.offset + udta.headerLen, udta.offset + udta.size);
    final meta = _find(kids, 'meta');
    if (meta == null) return null;

    final out = BytesBuilder();
    for (final k in kids) {
      if (identical(k, meta)) {
        out.add(_buildMeta(buf, meta, edit));
      } else {
        out.add(Uint8List.sublistView(buf, k.offset, k.offset + k.size));
      }
    }
    return _box('udta', out.takeBytes());
  }

  /// Rebuilds a `meta` box around a fresh `ilst`. With no existing [meta],
  /// a minimal one (FullBox header plus an `mdir` handler) is created.
  static Uint8List _buildMeta(Uint8List? buf, _Box? meta, TagEdit edit) {
    final out = BytesBuilder();
    if (buf == null || meta == null) {
      out.add(const [0, 0, 0, 0]);
      out.add(_handler());
      out.add(_box('ilst', _buildIlst(null, null, edit)));
      return _box('meta', out.takeBytes());
    }

    // `meta` is a FullBox (4 bytes of version/flags) unless a writer emitted
    // it bare; mirror whichever this file has.
    var contentStart = meta.offset + meta.headerLen;
    final fullBox = !_looksLikeBox(buf, contentStart, meta.offset + meta.size);
    if (fullBox) {
      out.add(Uint8List.sublistView(buf, contentStart, contentStart + 4));
      contentStart += 4;
    }

    final kids = _children(buf, contentStart, meta.offset + meta.size);
    var wroteIlst = false;
    for (final k in kids) {
      if (k.type == 'ilst') {
        out.add(_box('ilst', _buildIlst(buf, k, edit)));
        wroteIlst = true;
      } else {
        out.add(Uint8List.sublistView(buf, k.offset, k.offset + k.size));
      }
    }
    if (!wroteIlst) out.add(_box('ilst', _buildIlst(null, null, edit)));
    return _box('meta', out.takeBytes());
  }

  /// The new item list: every existing item the edit does not own, followed
  /// by the edited fields.
  static Uint8List _buildIlst(Uint8List? buf, _Box? ilst, TagEdit edit) {
    final out = BytesBuilder();
    int? trackTotal;
    int? discTotal;

    if (buf != null && ilst != null) {
      for (final item
          in _children(buf, ilst.offset + ilst.headerLen, ilst.offset + ilst.size)) {
        if (!_managed.contains(item.type)) {
          out.add(Uint8List.sublistView(buf, item.offset, item.offset + item.size));
          continue;
        }
        // "4 of 6": keep the album's track count even though only the
        // number itself is editable.
        if (item.type == 'trkn') trackTotal = _pairTotal(buf, item);
        if (item.type == 'disk') discTotal = _pairTotal(buf, item);
      }
    }

    void text(String type, String? value) {
      if (value == null) return;
      out.add(_item(type, 1, utf8.encode(value)));
    }

    text('©nam', edit.titleOrNull);
    text('©ART', edit.artistOrNull);
    text('©alb', edit.albumOrNull);
    text('aART', edit.albumArtistOrNull);
    text('©gen', edit.genreOrNull);
    text('©day', edit.yearOrNull);
    if (edit.trackNumber != null) {
      out.add(_item('trkn', 0, _pair(edit.trackNumber!, trackTotal, 8)));
    }
    if (edit.discNumber != null) {
      out.add(_item('disk', 0, _pair(edit.discNumber!, discTotal, 6)));
    }
    return out.takeBytes();
  }

  static int? _pairTotal(Uint8List buf, _Box item) {
    for (final data
        in _children(buf, item.offset + item.headerLen, item.offset + item.size)) {
      if (data.type != 'data') continue;
      final payload = data.offset + data.headerLen + 8;
      if (payload + 6 > data.offset + data.size) return null;
      final total = _u16(buf, payload + 4);
      return total == 0 ? null : total;
    }
    return null;
  }

  /// `trkn`/`disk` payload: 2 reserved bytes, number, total, and for `trkn`
  /// two more reserved bytes.
  static List<int> _pair(int n, int? total, int len) {
    final b = Uint8List(len);
    b[2] = (n >> 8) & 0xff;
    b[3] = n & 0xff;
    if (total != null) {
      b[4] = (total >> 8) & 0xff;
      b[5] = total & 0xff;
    }
    return b;
  }

  /// A metadata handler, needed only when a file has no `meta` box yet.
  static Uint8List _handler() {
    final b = BytesBuilder()
      ..add(const [0, 0, 0, 0]) // version + flags
      ..add(const [0, 0, 0, 0]) // pre_defined
      ..add(ascii.encode('mdir'))
      ..add(ascii.encode('appl'))
      ..add(Uint8List(9)); // reserved + empty name
    return _box('hdlr', b.takeBytes());
  }

  // --- chunk offsets --------------------------------------------------------

  /// Adds [delta] to every `stco`/`co64` entry at or beyond [boundary] (the
  /// end of the old `moov` in the original file).
  static void _shiftChunkOffsets(
      Uint8List moov, int headerLen, int boundary, int delta) {
    final data = ByteData.sublistView(moov);
    for (final trak in _children(moov, headerLen, moov.length)) {
      if (trak.type != 'trak') continue;
      final stbl = _descend(moov, trak, const ['mdia', 'minf', 'stbl']);
      if (stbl == null) continue;
      for (final table
          in _children(moov, stbl.offset + stbl.headerLen, stbl.offset + stbl.size)) {
        if (table.type != 'stco' && table.type != 'co64') continue;
        final wide = table.type == 'co64';
        final base = table.offset + table.headerLen + 4; // past version/flags
        final count = data.getUint32(base);
        final width = wide ? 8 : 4;
        for (var i = 0; i < count; i++) {
          final at = base + 4 + i * width;
          if (at + width > table.offset + table.size) break;
          final old = wide ? data.getUint64(at) : data.getUint32(at);
          if (old < boundary) continue;
          final updated = old + delta;
          if (!wide && updated > 0xffffffff) {
            throw const TagWriteException('Chunk offset overflow');
          }
          if (wide) {
            data.setUint64(at, updated);
          } else {
            data.setUint32(at, updated);
          }
        }
      }
    }
  }

  static _Box? _descend(Uint8List buf, _Box from, List<String> path) {
    var box = from;
    for (final type in path) {
      final next =
          _find(_children(buf, box.offset + box.headerLen, box.offset + box.size), type);
      if (next == null) return null;
      box = next;
    }
    return box;
  }

  // --- box plumbing ---------------------------------------------------------

  static Future<List<_Box>> _topLevel(RandomAccessFile raf, int length) async {
    final boxes = <_Box>[];
    var pos = 0;
    while (pos + 8 <= length) {
      await raf.setPosition(pos);
      final head = await raf.read(16);
      if (head.length < 8) break;
      var size = _u32(head, 0);
      var headerLen = 8;
      if (size == 1) {
        if (head.length < 16) break;
        size = _u64(head, 8);
        headerLen = 16;
      } else if (size == 0) {
        size = length - pos;
      }
      if (size < headerLen || pos + size > length) break;
      boxes.add(_Box(_type(head, 4), pos, size, headerLen));
      pos += size;
    }
    return boxes;
  }

  static List<_Box> _children(Uint8List buf, int start, int end) {
    final boxes = <_Box>[];
    var pos = start;
    while (pos + 8 <= end) {
      var size = _u32(buf, pos);
      var headerLen = 8;
      if (size == 1) {
        if (pos + 16 > end) break;
        size = _u64(buf, pos + 8);
        headerLen = 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < headerLen || pos + size > end) break;
      boxes.add(_Box(_type(buf, pos + 4), pos, size, headerLen));
      pos += size;
    }
    return boxes;
  }

  static bool _looksLikeBox(Uint8List buf, int pos, int end) {
    if (pos + 8 > end) return false;
    final size = _u32(buf, pos);
    if (size < 8 || pos + size > end) return false;
    for (var i = 4; i < 8; i++) {
      final c = buf[pos + i];
      if (!((c >= 0x20 && c <= 0x7e) || c == 0xa9)) return false;
    }
    return true;
  }

  static _Box? _find(List<_Box> boxes, String type) {
    for (final b in boxes) {
      if (b.type == type) return b;
    }
    return null;
  }

  /// An `ilst` item: the 4cc wrapping one `data` box of [payload] tagged
  /// with iTunes' well-known [dataType] (1 == UTF-8 text, 0 == binary).
  static Uint8List _item(String type, int dataType, List<int> payload) {
    final data = BytesBuilder()
      ..add(_u32Bytes(dataType))
      ..add(const [0, 0, 0, 0]) // locale
      ..add(payload);
    return _box(type, _box('data', data.takeBytes()));
  }

  static Uint8List _box(String type, List<int> payload) =>
      _withHeader(payload, type, 8);

  static Uint8List _withHeader(List<int> payload, String type, int headerLen) {
    final size = payload.length + headerLen;
    final out = BytesBuilder();
    if (headerLen == 16) {
      out.add(_u32Bytes(1));
      out.add(_typeBytes(type));
      out.add(_u64Bytes(size));
    } else {
      if (size > 0xffffffff) throw const TagWriteException('Box too large');
      out.add(_header(size, type));
    }
    out.add(payload);
    return out.takeBytes();
  }

  static Uint8List _header(int size, String type) =>
      Uint8List.fromList([..._u32Bytes(size), ..._typeBytes(type)]);

  /// Box types are Latin-1 (the © in `©nam` is a single 0xa9 byte).
  static List<int> _typeBytes(String type) => latin1.encode(type);

  static String _type(Uint8List b, int o) =>
      latin1.decode(b.sublist(o, o + 4));

  static Future<void> _copy(
      RandomAccessFile src, IOSink sink, int start, int end) async {
    const chunk = 1 << 20;
    var pos = start;
    await src.setPosition(pos);
    while (pos < end) {
      final bytes = await src.read((end - pos).clamp(0, chunk));
      if (bytes.isEmpty) throw const TagWriteException('Unexpected end of file');
      sink.add(bytes);
      pos += bytes.length;
    }
  }

  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _u64(Uint8List b, int o) => (_u32(b, o) << 32) | _u32(b, o + 4);

  static List<int> _u32Bytes(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  static List<int> _u64Bytes(int v) =>
      [..._u32Bytes(v >> 32), ..._u32Bytes(v & 0xffffffff)];
}

class _Box {
  final String type;

  /// Offset of the box header (in the file for top-level boxes, in the
  /// `moov` buffer for everything beneath it).
  final int offset;
  final int size;
  final int headerLen;

  const _Box(this.type, this.offset, this.size, this.headerLen);
}
