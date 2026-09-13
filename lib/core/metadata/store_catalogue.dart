import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What the iTunes Store knows about an album a file was bought from.
///
/// The catalogue is the authority for the names a purchase should have
/// carried, so it beats every local guess: it has the real punctuation that
/// iTunes strips from filenames (`Can’t` becomes `Can_t` on disk) and each
/// track's own artist credit, which album-mates cannot supply.
class StoreAlbum {
  final int id;
  final String name;
  final String artist;
  final String? genre;
  final String? releaseDate;

  /// A thumbnail URL; see [ItunesCatalogue.artwork] for the full-size image.
  final String? artworkUrl;

  /// Keyed by track ID (`cnID`).
  final Map<int, StoreTrack> tracks;

  const StoreAlbum({
    required this.id,
    required this.name,
    required this.artist,
    required this.tracks,
    this.genre,
    this.releaseDate,
    this.artworkUrl,
  });
}

class StoreTrack {
  final int id;
  final String title;
  final String artist;
  final int? trackNumber;
  final int? discNumber;
  final String? genre;
  final String? releaseDate;

  const StoreTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.trackNumber,
    this.discNumber,
    this.genre,
    this.releaseDate,
  });
}

/// A source of album information, so the repairer can be tested without
/// the network.
abstract class StoreCatalogue {
  /// The album with store ID [albumId], or null when the store has no such
  /// album (withdrawn, or an ID that was never one).
  Future<StoreAlbum?> album(int albumId, {int? storefrontId});

  /// Full-size cover art for [album], or null when none can be fetched.
  Future<Uint8List?> artwork(StoreAlbum album);
}

/// The public iTunes Search API. No account or key is needed; the IDs a
/// purchase carries (`plID`, `cnID`, `sfID`) are exactly its identifiers.
///
/// Results are cached per album for the life of the instance, so a folder of
/// tracks costs one request plus one artwork download.
class ItunesCatalogue implements StoreCatalogue {
  final HttpClient _http;

  /// Artwork edge in pixels. 1200 is what the store serves for its own
  /// full-size covers; ~400 KB as JPEG, well within the padding iTunes
  /// leaves in a file.
  final int artworkSize;

  final _albums = <int, Future<StoreAlbum?>>{};
  final _artwork = <int, Future<Uint8List?>>{};

  ItunesCatalogue({HttpClient? http, this.artworkSize = 1200})
      : _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  static const _maxArtworkBytes = 12 * 1024 * 1024;

  @override
  Future<StoreAlbum?> album(int albumId, {int? storefrontId}) =>
      _albums.putIfAbsent(albumId, () => _lookupAlbum(albumId, storefrontId));

  @override
  Future<Uint8List?> artwork(StoreAlbum album) =>
      _artwork.putIfAbsent(album.id, () => _fetchArtwork(album));

  Future<StoreAlbum?> _lookupAlbum(int albumId, int? storefrontId) async {
    final country = storefrontId == null ? null : storefrontCountry[storefrontId];
    // The album may not be sold in the guessed store; the default (US)
    // catalogue is the widest net.
    final found = country == null ? null : await _lookup(albumId, country);
    return found ?? await _lookup(albumId, null);
  }

  Future<StoreAlbum?> _lookup(int albumId, String? country) async {
    final uri = Uri.https('itunes.apple.com', '/lookup', {
      'id': '$albumId',
      'entity': 'song',
      'limit': '200',
      'country': ?country,
    });
    final body = await _getText(uri);
    if (body == null) return null;

    final json = jsonDecode(body);
    if (json is! Map || json['results'] is! List) return null;
    final results = (json['results'] as List).whereType<Map>().toList();

    Map? collection;
    final tracks = <int, StoreTrack>{};
    for (final r in results) {
      switch (r['wrapperType']) {
        case 'collection':
          collection ??= r;
          break;
        case 'track':
          final id = _int(r['trackId']);
          final title = _text(r['trackName']);
          final artist = _text(r['artistName']);
          if (id == null || title == null || artist == null) continue;
          tracks[id] = StoreTrack(
            id: id,
            title: title,
            artist: artist,
            trackNumber: _int(r['trackNumber']),
            discNumber: _int(r['discNumber']),
            genre: _text(r['primaryGenreName']),
            releaseDate: _text(r['releaseDate']),
          );
          break;
      }
    }
    if (collection == null) return null;
    final name = _text(collection['collectionName']);
    final artist = _text(collection['artistName']);
    if (name == null || artist == null) return null;

    return StoreAlbum(
      id: albumId,
      name: name,
      artist: artist,
      genre: _text(collection['primaryGenreName']),
      releaseDate: _text(collection['releaseDate']),
      artworkUrl: _text(collection['artworkUrl100']),
      tracks: tracks,
    );
  }

  Future<Uint8List?> _fetchArtwork(StoreAlbum album) async {
    final thumb = album.artworkUrl;
    if (thumb == null) return null;
    // The API hands out a 100px thumbnail whose URL encodes the size; the
    // same path serves any edge length.
    final full = thumb.replaceFirst(
        RegExp(r'/\d+x\d+[a-z]*\.(jpg|png)$'), '/${artworkSize}x${artworkSize}bb.jpg');
    final bytes = await _getBytes(Uri.parse(full)) ??
        (full == thumb ? null : await _getBytes(Uri.parse(thumb)));
    if (bytes == null || bytes.isEmpty || bytes.length > _maxArtworkBytes) return null;
    return bytes;
  }

  Future<String?> _getText(Uri uri) async {
    final bytes = await _getBytes(uri);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List?> _getBytes(Uri uri) async {
    try {
      final request = await _http.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'mewsic-tagfix/1.0');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        builder.add(chunk);
        if (builder.length > _maxArtworkBytes) {
          throw const CatalogueException('Response too large');
        }
      }
      return builder.takeBytes();
    } on CatalogueException {
      rethrow;
    } catch (e) {
      throw CatalogueException('Could not reach $uri: $e');
    }
  }

  void close() => _http.close(force: true);

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
}

/// Raised for network trouble, as opposed to "the store has no such album",
/// which is a null result. Callers should carry on without the catalogue.
class CatalogueException implements Exception {
  final String message;

  const CatalogueException(this.message);

  @override
  String toString() => message;
}

/// iTunes storefront IDs (`sfID`) to the two-letter country the Search API
/// takes. Not exhaustive; an unknown storefront just means the default
/// catalogue is asked.
const storefrontCountry = <int, String>{
  143441: 'US', 143442: 'FR', 143443: 'DE', 143444: 'GB', 143445: 'AT',
  143446: 'BE', 143447: 'FI', 143448: 'GR', 143449: 'IE', 143450: 'IT',
  143451: 'LU', 143452: 'NL', 143453: 'PT', 143454: 'ES', 143455: 'CA',
  143456: 'SE', 143457: 'NO', 143458: 'DK', 143459: 'CH', 143460: 'AU',
  143461: 'NZ', 143462: 'JP', 143463: 'HK', 143464: 'SG', 143465: 'CN',
  143466: 'KR', 143467: 'IN', 143468: 'MX', 143469: 'RU', 143470: 'TW',
  143471: 'VN', 143472: 'ZA', 143473: 'MY', 143474: 'PH', 143475: 'TH',
  143476: 'ID', 143477: 'PK', 143478: 'PL', 143479: 'SA', 143480: 'TR',
  143481: 'AE', 143482: 'HU', 143483: 'CL', 143484: 'NP', 143485: 'PA',
  143486: 'LK', 143487: 'RO', 143489: 'CZ', 143491: 'IL', 143492: 'UA',
  143493: 'KW', 143494: 'HR', 143495: 'CR', 143496: 'SK', 143497: 'LB',
  143498: 'QA', 143499: 'SI', 143501: 'CO', 143502: 'VE', 143503: 'BR',
  143504: 'GT', 143505: 'AR', 143506: 'SV', 143507: 'PE', 143508: 'DO',
  143509: 'EC', 143510: 'HN', 143511: 'JM', 143512: 'NI', 143513: 'PY',
  143514: 'UY', 143515: 'MO', 143516: 'EG', 143517: 'KZ', 143518: 'EE',
  143519: 'LV', 143520: 'LT', 143521: 'MT', 143523: 'MD', 143524: 'AM',
  143526: 'BG', 143528: 'JO', 143529: 'KE', 143530: 'MK', 143533: 'MU',
  143536: 'TN', 143537: 'UG', 143556: 'NG', 143560: 'BH', 143563: 'OM',
  143566: 'GH', 143568: 'AZ', 143569: 'BY', 143570: 'BO', 143573: 'IS',
  143581: 'TZ', 143582: 'TT', 143583: 'UZ', 143591: 'CY', 143593: 'GE',
};
