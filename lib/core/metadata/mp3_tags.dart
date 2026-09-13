import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'raw_tags.dart';

/// Reads ID3v2 (v2.2/v2.3/v2.4) tags, falling back to an ID3v1 trailer, and
/// derives duration from a Xing/Info/VBRI header or a constant-bitrate estimate.
class Mp3TagParser {
  /// Guards against a corrupt size field asking us to read the whole disk.
  static const _maxTagBytes = 16 * 1024 * 1024;

  static Future<RawTags?> parse(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final tags = RawTags();

      final id3v2Size = await _readId3v2(raf, length, tags);
      if (tags.fieldCount == 0) {
        final v1 = await _readId3v1(raf, length);
        if (v1 != null) tags.backfillFrom(v1);
      }

      tags.duration ??= await _duration(raf, length, id3v2Size);
      return tags;
    } on FileSystemException {
      return null;
    } finally {
      await raf.close();
    }
  }

  // --- ID3v2 ----------------------------------------------------------------

  /// Returns the total byte length of the ID3v2 block (0 when absent), which
  /// is also where the first MPEG audio frame begins.
  static Future<int> _readId3v2(RandomAccessFile raf, int length, RawTags out) async {
    if (length < 10) return 0;
    final header = await _readAt(raf, 0, 10);
    if (header.length < 10) return 0;
    if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) return 0; // "ID3"

    final major = header[3];
    final flags = header[5];
    final bodySize = _synchsafe(header, 6);
    if (bodySize <= 0 || bodySize > _maxTagBytes || 10 + bodySize > length) return 0;

    final body = await _readAt(raf, 10, bodySize);
    var pos = 0;

    // Skip an extended header when present.
    if (flags & 0x40 != 0 && body.length >= 4) {
      final extSize = major >= 4 ? _synchsafe(body, 0) : _u32(body, 0) + 4;
      if (extSize > 0 && extSize < body.length) pos += extSize;
    }

    final idLen = major <= 2 ? 3 : 4;
    final sizeLen = major <= 2 ? 3 : 4;
    final flagLen = major <= 2 ? 0 : 2;
    final headerLen = idLen + sizeLen + flagLen;

    while (pos + headerLen <= body.length) {
      final id = String.fromCharCodes(body.sublist(pos, pos + idLen));
      if (id.codeUnitAt(0) == 0) break; // padding

      int frameSize;
      if (major <= 2) {
        frameSize = (body[pos + 3] << 16) | (body[pos + 4] << 8) | body[pos + 5];
      } else if (major >= 4) {
        frameSize = _synchsafe(body, pos + 4);
      } else {
        frameSize = _u32(body, pos + 4);
      }

      final dataStart = pos + headerLen;
      if (frameSize <= 0 || dataStart + frameSize > body.length) break;
      final data = body.sublist(dataStart, dataStart + frameSize);

      _applyFrame(id, data, out);
      pos = dataStart + frameSize;
    }

    return 10 + bodySize;
  }

  static void _applyFrame(String id, Uint8List data, RawTags out) {
    switch (id) {
      case 'TIT2':
      case 'TT2':
        out.title ??= _decodeText(data);
        break;
      case 'TPE1':
      case 'TP1':
        out.artist ??= _decodeText(data);
        break;
      case 'TALB':
      case 'TAL':
        out.album ??= _decodeText(data);
        break;
      case 'TPE2':
      case 'TP2':
        out.albumArtist ??= _decodeText(data);
        break;
      case 'TCON':
      case 'TCO':
        out.genre ??= _decodeGenre(_decodeText(data));
        break;
      case 'TRCK':
      case 'TRK':
        out.trackNumber ??= _leadingInt(_decodeText(data));
        break;
      case 'TPOS':
      case 'TPA':
        out.discNumber ??= _leadingInt(_decodeText(data));
        break;
      case 'TYER': // v2.3 year
      case 'TYE':
      case 'TDRC': // v2.4 recording time, e.g. "2024-03-10T12:00:00"
        final v = _decodeText(data);
        if (v != null && v.length >= 4) {
          out.year ??= v.substring(0, 4);
          out.rawDate ??= v;
        }
        break;
    }
  }

  /// ID3 text frames lead with an encoding byte; strings may be null-padded
  /// and v2.4 allows multiple null-separated values (we take the first).
  static String? _decodeText(Uint8List data) {
    if (data.isEmpty) return null;
    final encoding = data[0];
    final body = data.sublist(1);
    if (body.isEmpty) return null;

    String text;
    switch (encoding) {
      case 0: // ISO-8859-1
        text = latin1.decode(body, allowInvalid: true);
        break;
      case 1: // UTF-16 with BOM
        text = _decodeUtf16(body, null);
        break;
      case 2: // UTF-16BE, no BOM
        text = _decodeUtf16(body, Endian.big);
        break;
      default: // 3 == UTF-8
        text = utf8.decode(body, allowMalformed: true);
    }

    final end = text.indexOf('\u0000');
    if (end >= 0) text = text.substring(0, end);
    text = text.trim();
    return text.isEmpty ? null : text;
  }

  static String _decodeUtf16(Uint8List body, Endian? forced) {
    var bytes = body;
    var endian = forced ?? Endian.big;
    if (forced == null && bytes.length >= 2) {
      if (bytes[0] == 0xff && bytes[1] == 0xfe) {
        endian = Endian.little;
        bytes = bytes.sublist(2);
      } else if (bytes[0] == 0xfe && bytes[1] == 0xff) {
        endian = Endian.big;
        bytes = bytes.sublist(2);
      }
    }
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(endian == Endian.big
          ? (bytes[i] << 8) | bytes[i + 1]
          : (bytes[i + 1] << 8) | bytes[i]);
    }
    return String.fromCharCodes(units);
  }

  /// TCON may be a bare number, "(17)", or "(17)Rock" referencing ID3v1 genres.
  static String? _decodeGenre(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^\((\d+)\)(.*)$').firstMatch(raw);
    if (match != null) {
      final rest = match.group(2)!.trim();
      if (rest.isNotEmpty) return rest;
      return _genreName(int.parse(match.group(1)!)) ?? raw;
    }
    final n = int.tryParse(raw);
    if (n != null) return _genreName(n) ?? raw;
    return raw;
  }

  static String? _genreName(int id) =>
      id >= 0 && id < _id3v1Genres.length ? _id3v1Genres[id] : null;

  static int? _leadingInt(String? s) {
    if (s == null) return null;
    final m = RegExp(r'\d+').firstMatch(s);
    if (m == null) return null;
    final v = int.tryParse(m.group(0)!);
    return (v == null || v == 0) ? null : v;
  }

  // --- ID3v1 ----------------------------------------------------------------

  static Future<RawTags?> _readId3v1(RandomAccessFile raf, int length) async {
    if (length < 128) return null;
    final b = await _readAt(raf, length - 128, 128);
    if (b.length < 128) return null;
    if (b[0] != 0x54 || b[1] != 0x41 || b[2] != 0x47) return null; // "TAG"

    String? field(int start, int len) {
      var end = start + len;
      while (end > start && (b[end - 1] == 0 || b[end - 1] == 0x20)) {
        end--;
      }
      if (end <= start) return null;
      return latin1.decode(b.sublist(start, end), allowInvalid: true).trim();
    }

    final tags = RawTags()
      ..title = field(3, 30)
      ..artist = field(33, 30)
      ..album = field(63, 30)
      ..year = field(93, 4)
      ..genre = _genreName(b[127]);

    // ID3v1.1 stores the track number in the last two comment bytes.
    if (b[125] == 0 && b[126] != 0) tags.trackNumber = b[126];
    return tags;
  }

  // --- duration -------------------------------------------------------------

  static const _bitrateV1L3 = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
  ];
  static const _bitrateV2L3 = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
  ];
  static const _sampleRates = [44100, 48000, 32000, 0];

  static Future<Duration?> _duration(
      RandomAccessFile raf, int length, int audioStart) async {
    // Scan a window for the first frame sync; some files pad before audio.
    final windowLen = (length - audioStart).clamp(0, 64 * 1024);
    if (windowLen < 4) return null;
    final win = await _readAt(raf, audioStart, windowLen);

    for (var i = 0; i + 4 <= win.length; i++) {
      if (win[i] != 0xff || (win[i + 1] & 0xe0) != 0xe0) continue;

      final versionBits = (win[i + 1] >> 3) & 0x03;
      final layerBits = (win[i + 1] >> 1) & 0x03;
      if (versionBits == 1 || layerBits == 0) continue; // reserved

      final bitrateIndex = (win[i + 2] >> 4) & 0x0f;
      final rateIndex = (win[i + 2] >> 2) & 0x03;
      if (bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) continue;

      final isMpeg1 = versionBits == 3;
      final kbps = (isMpeg1 ? _bitrateV1L3 : _bitrateV2L3)[bitrateIndex];
      var sampleRate = _sampleRates[rateIndex];
      if (kbps == 0 || sampleRate == 0) continue;
      if (versionBits == 2) sampleRate ~/= 2; // MPEG 2
      if (versionBits == 0) sampleRate ~/= 4; // MPEG 2.5

      final samplesPerFrame = isMpeg1 ? 1152 : 576;

      // Xing/Info (VBR) frame count lives at a channel-mode-dependent offset.
      final channelMode = (win[i + 3] >> 6) & 0x03;
      final xingOffset = i + 4 + (isMpeg1 ? (channelMode == 3 ? 17 : 32) : (channelMode == 3 ? 9 : 17));
      final frames = _xingFrameCount(win, xingOffset) ?? _vbriFrameCount(win, i + 4 + 32);
      if (frames != null && frames > 0) {
        final seconds = frames * samplesPerFrame / sampleRate;
        return Duration(microseconds: (seconds * 1000000).round());
      }

      // Constant-bitrate estimate over the remaining audio bytes.
      final audioBytes = length - (audioStart + i);
      if (audioBytes <= 0) return null;
      final seconds = audioBytes * 8 / (kbps * 1000);
      return Duration(microseconds: (seconds * 1000000).round());
    }
    return null;
  }

  static int? _xingFrameCount(Uint8List b, int offset) {
    if (offset < 0 || offset + 12 > b.length) return null;
    final tag = String.fromCharCodes(b.sublist(offset, offset + 4));
    if (tag != 'Xing' && tag != 'Info') return null;
    final flags = _u32(b, offset + 4);
    if (flags & 0x01 == 0) return null; // no frame count present
    return _u32(b, offset + 8);
  }

  static int? _vbriFrameCount(Uint8List b, int offset) {
    if (offset < 0 || offset + 20 > b.length) return null;
    if (String.fromCharCodes(b.sublist(offset, offset + 4)) != 'VBRI') return null;
    return _u32(b, offset + 14);
  }

  // --- primitives -----------------------------------------------------------

  static Future<Uint8List> _readAt(RandomAccessFile raf, int pos, int len) async {
    if (len <= 0) return Uint8List(0);
    await raf.setPosition(pos);
    return raf.read(len);
  }

  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// ID3 sizes use 7 bits per byte so the audio decoder never sees a false sync.
  static int _synchsafe(Uint8List b, int o) =>
      ((b[o] & 0x7f) << 21) |
      ((b[o + 1] & 0x7f) << 14) |
      ((b[o + 2] & 0x7f) << 7) |
      (b[o + 3] & 0x7f);
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
