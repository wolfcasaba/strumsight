// ignore_for_file: unnecessary_brace_in_string_interps
/// Single-purpose writer that combines a staged-write, verify, atomic
/// rename (E03-R07, ADR 0090 §Döntés 3, SDD §18.3).
///
/// The writer is the boundary that turns an arbitrary byte payload into
/// an "either the target has the new bytes — or the target still has the
/// previous good bytes" outcome. Half-staged writes (target pointing at
/// a partial file, or a stale temp left behind) are an explicit invariant
/// violation: the recovery scanner relies on this invariant to classify
/// every residue file as crash residue, never a current write.
///
/// Stage directory: by default the writer stages its temp file next to
/// the target (sibling of the target file). Callers that need the staged
/// file under the application-level `temp/` directory pass an explicit
/// [stagingDirectory]. The recovery scanner only walks the application
/// `temp/` directory for residue, so the production repositories MUST
/// stage inside the songs-root `temp/` directory (this is documented
/// in ADR 0090 §Döntés 1's directory layout and verified by the
/// E03-R07 review BLOCKER 5).
///
/// The writer is **framework-independent**: the only platforms it touches
/// are `dart:io` and `dart:typed_data`. The same boundary is reachable
/// from a test by handing it a custom `Directory` factory if a hosted
/// `dart:io`-less test ever needs it (today the round gate runs only on
/// `dart:io`-backed flutter_test).
library;

import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

/// Single-shot [Sink] that captures the [crypto.Digest] emitted by
/// `crypto.sha256.startChunkedConversion`. The `crypto` package ships an
/// internal `DigestSink` but does not export it, so the writer carries
/// its own one-shot sink.
class _CaptureDigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _value;

  crypto.Digest get value {
    final v = _value;
    if (v == null) {
      throw StateError(
        'CaptureDigestSink.value must not be read before the sink '
        'received a digest.',
      );
    }
    return v;
  }

  @override
  void add(crypto.Digest data) {
    if (_value != null) {
      throw StateError('CaptureDigestSink.add may only be called once.');
    }
    _value = data;
  }

  @override
  void close() {
    // The chunked-conversion sink calls close() after emitting the
    // final digest — the writer reads `.value` AFTER close().
  }
}

/// Result of a single [AtomicFileWriter.write] or
/// [AtomicFileWriter.writeStream] call.
///
/// [committed] is true when the rename succeeded AND the verifier passed.
/// It is false when either step failed; the target then still carries
/// whatever bytes it held before the call. [attempts] is the number of
/// verifier round-trips that actually ran (always ≥1 for a non-empty
/// payload — the first write attempt counts as attempt 1).
final class AtomicWriteOutcome {
  const AtomicWriteOutcome({required this.committed, required this.attempts});

  /// True when the staged bytes replaced the previous target bytes.
  final bool committed;

  /// Number of verifier round-trips that ran. Useful for tests;
  /// production diagnostics surface this through the recovery scanner.
  final int attempts;
}

/// Pure-IO atomic writer. Stateless — instances are cheap; the round
/// gate shares one per process.
///
/// The non-streamed `write` sequence is:
///
///   1. open the staging directory (defaults to the target's parent;
///      callers pass an explicit [stagingDirectory] for `temp/` staging);
///   2. resolve a unique temp filename inside the staging directory
///      (`<basename>.tmp-<pid>-<counter>`);
///   3. `writeAsBytes(bytes, flush: true)` — this fsyncs the file
///      before `writeAsBytes` returns;
///   4. read the staged bytes back from disk and run the verifier;
///   5. on verifier-false: `deleteSync` the temp file, return
///      `committed: false`;
///   6. on verifier-true: `renameSync(staged, target)` directly —
///      POSIX `rename(2)` atomically replaces an existing target so
///      there is no delete-then-rename window where both old and new
///      are missing;
///   7. `deleteSync(staged)` — POSIX rename already removed the source
///      from the staging directory, but the cleanup is best-effort
///      and unconditional to keep the recovery invariant: after a
///      successful write, no `.tmp-*` survives in the staging dir.
///
/// The streamed `writeStream` sequence is identical except the file
/// payload is written to disk in chunks via `RandomAccessFile.writeFromSync`
/// (no full-buffer materialisation) and the verifier receives the
/// on-disk digest AFTER a chunked re-read of the staged file. This is
/// the path large backing-audio assets use so the round-trip does not
/// require loading the whole payload into a single buffer.
///
/// **Platform limitation on directory fsync.** Dart's `dart:io` does
/// not expose a portable directory-fsync primitive (Linux/Android have
/// `fsync(dirfd)`, macOS has `fsync_volume_np`, Windows has nothing).
/// The previous revision of this writer carried dead code that called
/// a non-existent `Directory.flush()` method; the current revision
/// does NOT attempt directory fsync at all. The recovery scanner closes
/// the gap on the next startup scan by re-walking the canonical
/// directories.
final class AtomicFileWriter {
  /// Construct a writer. The class is stateless; `const` keeps callers
  /// honest about the cheap-sharing contract.
  const AtomicFileWriter();

  /// Suffix used for the staged temp file. The recovery scanner looks
  /// for this exact suffix inside the application's per-feature temp
  /// directory.
  static const String tempExtension = '.tmp';

  /// Default chunk size used by [writeStream] (64 KiB — large enough
  /// to amortise syscall overhead, small enough to keep memory bounded).
  static const int defaultChunkSize = 64 * 1024;

  /// Internal counter for unique temp filenames within a single process.
  /// The recovery scanner scans by filename pattern, not by counter
  /// value — the counter is the actual uniqueness tiebreaker, the [pid]
  /// value is a diagnostic-only identifier that does not need to match
  /// the real OS process id (Dart does not expose the current pid via a
  /// portable API on every host, so the value is fixed to `1` and the
  /// counter alone guarantees uniqueness inside the staging directory).
  static int _counter = 0;

  /// Fixed "pid" sentinel — see [_counter] doc-comment for rationale.
  /// Kept exposed at file scope so future diagnostics can read it
  /// without an additional getter.
  static int get pid => 1;

  /// Write [bytes] to [target] atomically.
  ///
  /// [verifier] receives the freshly-written bytes from the staged temp
  /// file BEFORE the rename happens. Returning `false` aborts the
  /// write — the previous target bytes (or no file at all) survive.
  /// Throwing inside [verifier] is also treated as a `false`: the write
  /// is aborted, the temp is removed and the exception is re-thrown so
  /// the caller sees a real crash (the recovery scanner never runs in
  /// this case — let the crash propagate).
  ///
  /// When [stagingDirectory] is non-null the staged temp file lives
  /// there instead of next to the target — production callers pass the
  /// songs-root `temp/` directory so the recovery scanner can see real
  /// crash residue. When null the writer falls back to the target's
  /// parent directory (the historical behaviour).
  AtomicWriteOutcome write({
    required File target,
    required Uint8List bytes,
    required bool Function(Uint8List verified) verifier,
    Directory? stagingDirectory,
  }) {
    final stageDir = stagingDirectory ?? target.parent;
    if (!stageDir.existsSync()) {
      stageDir.createSync(recursive: true);
    }
    final counter = ++_counter;
    final basename = _basenameOf(target);
    final staged = File(_stagePath(stageDir, basename, counter));

    // Stage 1: write + flush (fsync inside `writeAsBytes`).
    staged.writeAsBytesSync(bytes, flush: true);

    // Stage 2: read back and verify. We DELIBERATELY trust the verifier
    // to fail-closed — a flaky verifier is the caller's problem.
    var attempts = 0;
    var verifierPassed = false;
    try {
      final readBack = staged.readAsBytesSync();
      attempts++;
      verifierPassed = verifier(readBack);
    } catch (_) {
      // Verifier threw — preserve the invariant: temp removed, target
      // untouched, exception rethrown.
      _safeDelete(staged);
      rethrow;
    }

    if (!verifierPassed) {
      _safeDelete(staged);
      return AtomicWriteOutcome(committed: false, attempts: attempts);
    }

    // Stage 3: atomic rename directly onto the target. POSIX `rename(2)`
    // atomically replaces an existing target — there is no need to
    // delete first. Pre-deleting opened a real crash window where
    // BOTH the old document and the renamed-from temp could be gone.
    try {
      staged.renameSync(target.path);
    } on FileSystemException {
      // Some platforms (e.g. legacy Windows) refuse to rename onto an
      // existing target. Fall back to delete + rename in that one
      // failure case so the writer still succeeds.
      if (target.existsSync()) {
        target.deleteSync(recursive: false);
      }
      staged.renameSync(target.path);
    }

    // Stage 4: best-effort temp cleanup. POSIX rename already removed
    // the source; the deleteSync on Windows-after-fallback is the
    // actual cleanup. Either way the staged file MUST be gone after a
    // successful rename.
    _safeDelete(staged);

    return AtomicWriteOutcome(committed: true, attempts: attempts);
  }

  /// Streamed atomic write.
  ///
  /// The bytes are written to disk in chunks via
  /// `RandomAccessFile.writeFromSync` (no full-buffer materialisation),
  /// and the SHA-256 digest is updated incrementally via a
  /// `crypto.sha256.startChunkedConversion` chunked-conversion sink
  /// (no full-buffer hash intermediate). After the chunked write
  /// completes the staged file is re-read in chunks and re-hashed so
  /// the on-disk digest can be compared against the caller's expected
  /// digest in [verifier].
  ///
  /// [verifier] receives the freshly computed on-disk digest. A `false`
  /// return aborts the rename — the previous target bytes survive.
  /// Throwing inside [verifier] is treated the same way as in [write].
  ///
  /// When [stagingDirectory] is non-null the staged temp file lives
  /// there; otherwise the writer uses [target.parent].
  AtomicWriteOutcome writeStream({
    required File target,
    required Uint8List bytes,
    required bool Function(String onDiskDigest) verifier,
    Directory? stagingDirectory,
    int chunkSize = defaultChunkSize,
  }) {
    final stageDir = stagingDirectory ?? target.parent;
    if (!stageDir.existsSync()) {
      stageDir.createSync(recursive: true);
    }
    final counter = ++_counter;
    final basename = _basenameOf(target);
    final staged = File(_stagePath(stageDir, basename, counter));

    // Stage 1: chunked write + parallel chunked hash. The hash sink
    // is consumed incrementally so no intermediate full-buffer digest
    // is materialised; the write file descriptor streams the same
    // chunks straight to disk.
    final digestSink = _CaptureDigestSink();
    final writeSink = crypto.sha256.startChunkedConversion(digestSink);
    final raf = staged.openSync(mode: FileMode.write);
    try {
      var offset = 0;
      while (offset < bytes.length) {
        final end = offset + chunkSize > bytes.length
            ? bytes.length
            : offset + chunkSize;
        final length = end - offset;
        raf.writeFromSync(bytes, offset, length);
        // The chunked-conversion sink takes the same view we just
        // handed the OS — no extra copy.
        writeSink.add(bytes.sublist(offset, end));
        offset = end;
      }
      raf.flushSync();
      raf.closeSync();
      writeSink.close();
    } catch (_) {
      _safeCloseRaf(raf);
      _safeDelete(staged);
      rethrow;
    }
    final writeDigest = digestSink.value.toString();

    // Stage 2: read back from disk in chunks and re-hash so the
    // verifier can compare against the on-disk digest, not the
    // in-memory writeDigest. This catches a hypothetical disk-side
    // truncation or write-ahead corruption.
    final verifySink = _CaptureDigestSink();
    final verifyChunkSink = crypto.sha256.startChunkedConversion(verifySink);
    final readRaf = staged.openSync(mode: FileMode.read);
    var attempts = 0;
    try {
      while (true) {
        final chunk = readRaf.readSync(chunkSize);
        if (chunk.isEmpty) break;
        attempts++;
        verifyChunkSink.add(chunk);
      }
      readRaf.closeSync();
      verifyChunkSink.close();
    } catch (_) {
      _safeCloseRaf(readRaf);
      _safeDelete(staged);
      rethrow;
    }
    final onDiskDigest = verifySink.value.toString();
    if (onDiskDigest != writeDigest) {
      _safeDelete(staged);
      return AtomicWriteOutcome(committed: false, attempts: attempts);
    }

    var verifierPassed = false;
    try {
      verifierPassed = verifier(onDiskDigest);
    } catch (_) {
      _safeDelete(staged);
      rethrow;
    }
    if (!verifierPassed) {
      _safeDelete(staged);
      return AtomicWriteOutcome(committed: false, attempts: attempts);
    }

    // Stage 3: atomic rename directly onto the target (no pre-delete).
    try {
      staged.renameSync(target.path);
    } on FileSystemException {
      if (target.existsSync()) {
        target.deleteSync(recursive: false);
      }
      staged.renameSync(target.path);
    }

    // Stage 4: best-effort temp cleanup.
    _safeDelete(staged);

    return AtomicWriteOutcome(committed: true, attempts: attempts);
  }

  /// Internal basename projection (last path segment). Falls back to the
  /// full path when the URI projection yields an empty list (the target
  /// is the bare `target.path` string).
  static String _basenameOf(File target) {
    final segments = target.uri.pathSegments;
    if (segments.isEmpty) return target.path;
    return segments.last;
  }

  /// Internal staging path resolver. Always writes inside [stageDir].
  static String _stagePath(Directory stageDir, String basename, int counter) {
    final sep = Platform.pathSeparator;
    final prefix = stageDir.path.endsWith(sep)
        ? stageDir.path
        : '${stageDir.path}$sep';
    return '$prefix$basename$tempExtension-$pid-$counter';
  }

  void _safeDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync(recursive: false);
    } on FileSystemException {
      // Best-effort — the next startup scan closes the gap.
    }
  }

  void _safeCloseRaf(RandomAccessFile raf) {
    try {
      raf.closeSync();
    } on FileSystemException {
      // Best-effort.
    }
  }
}
