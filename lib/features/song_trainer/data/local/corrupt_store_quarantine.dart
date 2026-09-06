import 'dart:io';

import 'package:strumsight/core/logging/app_logger.dart';

/// Isolates a file-backed store whose content could not be decoded, so a
/// corrupt document costs the user that document — never the whole app.
///
/// This is the file-backed twin of the `KeyValueStore` precedent in
/// `lib/core/storage/json_document_store.dart` (§7.4): the bytes are
/// **kept**, never overwritten blind, and the caller carries on with an
/// empty in-memory state. The difference is only the medium — a
/// `JsonDocumentStore` copies the raw string to
/// `StorageKeys.quarantineOf(key)`, while a file store renames the file to
/// `<name>.corrupt-<utc timestamp>` beside it.
///
/// MÉRT hiba (2026-09-06 review, BLOCKER-1): `openAtDirectory` decoded
/// eagerly and let a `FormatException` escape. On the shipped path that
/// exception propagated out of `main`'s composition step, so `runApp` was
/// never called at all — ONE corrupt local file meant a permanently black
/// screen with no way back.
///
/// Returns the quarantine file, or `null` when the rename itself failed
/// (a read-only or full volume) — an unquarantinable file must still not
/// stop the caller from starting empty.
Future<File?> quarantineCorruptStore({
  required File file,
  required String document,
  required Object error,
  required StackTrace stackTrace,
  required AppLogger logger,
  DateTime Function() clock = DateTime.now,
}) async {
  final stamp = clock().toUtc().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
  final target = '${file.path}.corrupt-$stamp';
  try {
    final renamed = await file.rename(target);
    logger.warning(
      'storage.file_document.quarantined',
      error: error,
      stackTrace: stackTrace,
      fields: {'document': document, 'path': renamed.path},
    );
    return renamed;
  } on Object catch (renameError, renameStackTrace) {
    // The bytes could not be moved aside. Report it and start empty anyway
    // — the alternative (rethrow) is the black screen this helper exists
    // to prevent. Nothing is deleted, so the file stays recoverable.
    logger.error(
      'storage.file_document.quarantine_failed',
      error: renameError,
      stackTrace: renameStackTrace,
      fields: {'document': document},
    );
    return null;
  }
}
