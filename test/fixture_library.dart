import 'dart:io';

import 'package:custom_music_player/platform/library_source.dart';

/// The 17-track library `metadata_test.dart` and `ui_test.dart` assert
/// against: three store-bought albums, copied into `test/fixtures/library`
/// by `test/fixtures/sync.sh`. The folder is gitignored, so on a machine
/// where the script has not been run the tests skip instead of failing.
///
/// `MEWSIC_TEST_LIBRARY` points at a copy somewhere else.
const fixtureMissingReason =
    'fixture library not present; run test/fixtures/sync.sh';

DirectoryLibrarySource? fixtureLibrary() {
  final path = Platform.environment['MEWSIC_TEST_LIBRARY'] ??
      '${Directory.current.path}/test/fixtures/library';
  final dir = Directory(path);
  if (!dir.existsSync()) return null;
  final hasAudio = dir
      .listSync(recursive: true)
      .any((e) => e is File && e.path.toLowerCase().endsWith('.m4a'));
  return hasAudio ? DirectoryLibrarySource(dir) : null;
}
