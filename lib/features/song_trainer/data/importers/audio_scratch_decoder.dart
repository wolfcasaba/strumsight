/// Bytes → PCM, over a decoder that can only read a PATH (K3).
///
/// `MediaExtractor` opens a file, not a buffer (ADR 0535), while the picker
/// deliberately hands out a byte stream and no path — a path would leak a
/// platform value into the application layer. Someone therefore has to put
/// the bytes on disk for the length of one decode, and that someone belongs
/// HERE, next to the decoder it exists for, rather than in the import
/// controller: the controller then owns no `dart:io` at all, which is also
/// what makes the import flow measurable from a widget test (real `dart:io`
/// never completes inside `testWidgets`' fake-async zone).
library;

import 'dart:io';
import 'dart:typed_data';

import '../../../../core/audio/codec/platform_audio_decoder.dart';
import '../../../../core/foundation/app_result.dart';

/// Writes the picked bytes into a scratch file, decodes, then deletes it.
final class AudioScratchDecoder {
  const AudioScratchDecoder({
    required this.workspaceRoot,
    required this.decode,
  });

  /// Resolves the app-owned directory the scratch copy lives in.
  final Future<Directory> Function() workspaceRoot;

  /// The path-taking decoder — the K2 platform decoder in production.
  final Future<AppResult<DecodedPcm>> Function(String path) decode;

  /// Stable scratch file stem. One import runs at a time, so a fixed name
  /// self-overwrites instead of accumulating copies of the user's music.
  static const String scratchName = 'audio-import-scratch';

  Future<AppResult<DecodedPcm>> decodeBytes(
    Uint8List bytes,
    String extension,
  ) async {
    final root = await workspaceRoot();
    await root.create(recursive: true);
    final separator = Platform.pathSeparator;
    final file = File('${root.path}$separator$scratchName.$extension');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await decode(file.path);
    } finally {
      await _deleteQuietly(file);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover scratch file in the app's own temp tree is not worth
      // failing an otherwise-successful import over; the next decode
      // overwrites it under the same name.
    }
  }
}
