import 'dart:io';

import 'mp3_tag_writer.dart';
import 'mp4_tag_writer.dart';
import 'tag_edit.dart';

/// Thrown when a file cannot be rewritten: unsupported format, malformed
/// box tree, or the OS refusing the write.
class TagWriteException implements Exception {
  final String message;

  const TagWriteException(this.message);

  @override
  String toString() => message;
}

/// Saves edited tags into the audio file itself, so the change follows the
/// file to every other device and player rather than living only in this
/// app's memory.
class TagWriter {
  static bool canWrite(String path) {
    final ext = _extension(path);
    return ext == '.m4a' || ext == '.mp4' || ext == '.m4b' || ext == '.mp3';
  }

  static Future<void> write(File file, TagEdit edit) async {
    try {
      switch (_extension(file.path)) {
        case '.m4a':
        case '.mp4':
        case '.m4b':
          await Mp4TagWriter.write(file, edit);
          break;
        case '.mp3':
          await Mp3TagWriter.write(file, edit);
          break;
        default:
          throw TagWriteException(
              'Editing ${_extension(file.path)} files is not supported');
      }
    } on FileSystemException catch (e) {
      throw TagWriteException(_explain(e));
    }
  }

  static String _explain(FileSystemException e) {
    final reason = e.osError?.message;
    if (Platform.isMacOS && (e.osError?.errorCode == 1 || e.osError?.errorCode == 13)) {
      return 'macOS would not let Mewsic change this file. Grant it access '
          'under System Settings > Privacy & Security > Media & Apple Music.';
    }
    if (Platform.isAndroid) {
      return 'Android does not allow this file to be changed from here. '
          'Edit it on a computer and copy it back.';
    }
    return reason == null ? 'Could not write the file' : 'Could not write the file: $reason';
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }
}
