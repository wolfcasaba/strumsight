/// Native JSON exchange files always use this extension.
const String nativeJsonFileExtension = '.strumsight-song.json';

/// Produces a portable native-export filename from untrusted display text.
///
/// The original [SongId] is deliberately not an input: filenames are a UI
/// projection and must never rewrite document identity.
String sanitizeNativeExportFilename(String raw) =>
    '${_safeStem(raw)}$nativeJsonFileExtension';

/// Removes path components and platform-reserved filename characters while
/// retaining the display extension for the exchange document provenance.
String scrubNativeSourceDisplayName(String raw) {
  final basename = _basename(raw);
  if (basename.toLowerCase().endsWith(nativeJsonFileExtension)) {
    return '${_safeStem(basename)}$nativeJsonFileExtension';
  }
  final dot = basename.lastIndexOf('.');
  if (dot <= 0 || dot == basename.length - 1) return _safeStem(basename);
  return '${_safeStem(basename.substring(0, dot))}${basename.substring(dot)}';
}

String _safeStem(String raw) {
  final basename = _basename(raw);
  final withoutExtension = _removeExtension(basename);
  final buffer = StringBuffer();
  var previousSeparator = true;
  for (final rune in withoutExtension.runes) {
    final isAsciiLetter =
        (rune >= 0x41 && rune <= 0x5a) || (rune >= 0x61 && rune <= 0x7a);
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isSafePunctuation = rune == 0x2d || rune == 0x5f || rune == 0x2e;
    if (isAsciiLetter || isDigit || isSafePunctuation) {
      buffer.writeCharCode(rune);
      previousSeparator = false;
    } else if (!previousSeparator) {
      buffer.write('-');
      previousSeparator = true;
    }
  }
  var result = buffer.toString().replaceFirst(RegExp(r'^[.\-]+'), '');
  result = result.replaceFirst(RegExp(r'[.\-]+$'), '');
  if (result.isEmpty || _windowsReservedStem(result)) return 'song';
  return result.length <= 96 ? result : result.substring(0, 96);
}

String _basename(String raw) {
  final slash = raw.lastIndexOf('/');
  final backslash = raw.lastIndexOf('\\');
  final separator = slash > backslash ? slash : backslash;
  return separator < 0 ? raw : raw.substring(separator + 1);
}

String _removeExtension(String basename) {
  if (basename.toLowerCase().endsWith(nativeJsonFileExtension)) {
    return basename.substring(
      0,
      basename.length - nativeJsonFileExtension.length,
    );
  }
  final dot = basename.lastIndexOf('.');
  return dot <= 0 ? basename : basename.substring(0, dot);
}

bool _windowsReservedStem(String value) {
  final upper = value.toUpperCase();
  return upper == 'CON' ||
      upper == 'PRN' ||
      upper == 'AUX' ||
      upper == 'NUL' ||
      RegExp(r'^COM[1-9]$').hasMatch(upper) ||
      RegExp(r'^LPT[1-9]$').hasMatch(upper);
}
