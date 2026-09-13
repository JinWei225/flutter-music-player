// ignore_for_file: avoid_print -- a command-line tool talks through stdout.

// Completes the tags of store purchases that arrive without names.
//
// Standalone: this is a plain Dart program that shares the app's tag code
// but needs neither the app nor Flutter to run. Build it once with
// `dart build cli -t bin/tagfix.dart` and keep `bundle/bin/tagfix` (or run
// packaging/install_tagfix_macos.sh, which also registers it to run at login).
//
//   mewsic-tagfix check [folder]     report what is missing and how it would be filled
//   mewsic-tagfix fix   [folder]     write the missing names into the files
//   mewsic-tagfix watch [folder]     keep running; fix new files as they arrive
//
//   --dry-run   with fix/watch: report only, change nothing
//   --quiet     with watch: log only when something is written
//   --offline   do not ask the iTunes Store; use only what is on disk
//
// [folder] defaults to the Apple Music library on macOS
// (~/Music/Music/Media.localized/Music) and ~/Music elsewhere.

import 'dart:async';
import 'dart:io';

import 'package:custom_music_player/core/metadata/store_catalogue.dart';
import 'package:custom_music_player/core/metadata/tag_repair.dart';
import 'package:custom_music_player/core/metadata/tag_writer.dart';

Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final words = args.where((a) => !a.startsWith('--')).toList();
  final command = words.isEmpty ? 'check' : words.first;
  final root = Directory(words.length > 1 ? words[1] : _defaultRoot());
  final dryRun = flags.contains('--dry-run');
  final quiet = flags.contains('--quiet');
  final catalogue = flags.contains('--offline') ? null : ItunesCatalogue();
  final repairer = TagRepairer(
    catalogue: catalogue,
    onWarning: (m) => stderr.writeln('${_stamp()} store unreachable, continuing offline: $m'),
  );

  if (flags.contains('--help') || command == 'help') {
    _usage();
    return;
  }
  if (!await root.exists()) {
    stderr.writeln('No such folder: ${root.path}');
    exitCode = 2;
    return;
  }

  try {
    switch (command) {
      case 'check':
        exitCode = await _fixTree(repairer, root, dryRun: true) ? 0 : 1;
        break;
      case 'fix':
        await _fixTree(repairer, root, dryRun: dryRun);
        break;
      case 'watch':
        await _watch(repairer, root, dryRun: dryRun, quiet: quiet);
        break;
      default:
        _usage();
        exitCode = 2;
    }
  } on FileSystemException catch (e) {
    stderr.writeln(_explainAccess(e, root));
    exitCode = 3;
  } finally {
    catalogue?.close();
  }
}

/// Repairs everything under [root]. Returns true when nothing needed doing.
Future<bool> _fixTree(TagRepairer repairer, Directory root, {required bool dryRun}) async {
  final repairs = await repairer.planTree(root);
  if (repairs.isEmpty) {
    print('All files under ${root.path} have their names.');
    return true;
  }
  for (final r in repairs) {
    await _report(r, dryRun: dryRun);
  }
  print(dryRun
      ? '${repairs.length} file(s) would be completed. Run `fix` to write them.'
      : '${repairs.length} file(s) completed.');
  return false;
}

/// Watches [root] and repairs each album folder a short while after files
/// stop appearing in it -- the Music app writes a purchase progressively, and
/// album-mates are needed to complete one another, so the folder is handled
/// as a unit once it has gone quiet.
Future<void> _watch(TagRepairer repairer, Directory root,
    {required bool dryRun, required bool quiet}) async {
  const settle = Duration(seconds: 15);
  final pending = <String, Timer>{};

  Future<void> handle(String folder) async {
    pending.remove(folder);
    final dir = Directory(folder);
    if (!await dir.exists()) return;
    try {
      final repairs = await repairer.planFolder(dir, root: root);
      if (repairs.isEmpty) {
        if (!quiet) print('${_stamp()} ${_short(folder, root)}: nothing missing');
        return;
      }
      for (final r in repairs) {
        await _report(r, dryRun: dryRun);
      }
    } on FileSystemException catch (e) {
      stderr.writeln('${_stamp()} ${_explainAccess(e, root)}');
    }
  }

  // Start with whatever arrived while we were not running.
  await _fixTree(repairer, root, dryRun: dryRun);
  print('${_stamp()} watching ${root.path}');

  await for (final event in root.watch(recursive: true)) {
    if (event.type == FileSystemEvent.delete) continue;
    final path = event.path;
    if (!TagWriter.canWrite(path)) continue;
    final folder = File(path).parent.path;
    pending[folder]?.cancel();
    pending[folder] = Timer(settle, () => handle(folder));
  }
}

Future<void> _report(TagRepair r, {required bool dryRun}) async {
  final what = r.filled.join(', ');
  if (dryRun) {
    print('  ${r.fileName}: $what');
    return;
  }
  try {
    await r.apply();
    print('${_stamp()} wrote ${r.fileName}: $what');
  } on TagWriteException catch (e) {
    stderr.writeln('${_stamp()} FAILED ${r.fileName}: $e');
  }
}

String _defaultRoot() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  final sep = Platform.pathSeparator;
  final music = '$home${sep}Music';
  if (!Platform.isMacOS) return music;
  final apple = '$music/Music/Media.localized/Music';
  return Directory(apple).existsSync() ? apple : music;
}

String _explainAccess(FileSystemException e, Directory root) {
  if (Platform.isMacOS) {
    return 'macOS is blocking access to ${root.path} (${e.osError?.message}).\n'
        'Allow the program that runs mewsic-tagfix (Terminal, or mewsic-tagfix '
        'itself when started at login) under System Settings > Privacy & '
        'Security > Media & Apple Music, then run it again.';
  }
  return 'Cannot read ${root.path}: ${e.osError?.message ?? e.message}';
}

String _short(String path, Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

String _stamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
}

void _usage() {
  print('''
mewsic-tagfix -- complete the tags of store purchases that arrive without names

  mewsic-tagfix check [folder]   report what is missing and how it would be filled
  mewsic-tagfix fix   [folder]   write the missing names into the files
  mewsic-tagfix watch [folder]   keep running; fix new files as they arrive

  --dry-run   with fix/watch: report only, change nothing
  --quiet     with watch: log only when something is written
  --offline   do not ask the iTunes Store; use only what is on disk

Names are filled, never overwritten, from: the file's own sort-order atoms,
the iTunes Store (looked up by the IDs the purchase carries -- also the
source of cover art for files that have none), album-mates sharing those
IDs, the Artist/Album folder layout, and the filename. Everything else in
the file -- store IDs, dates, lyrics -- is left exactly as it was.

[folder] defaults to ${_defaultRoot()}''');
}
