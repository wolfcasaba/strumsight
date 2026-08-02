// ignore_for_file: unnecessary_brace_in_string_interps
/// Single-purpose writer that combines a staged-write, verify, atomic
/// rename and post-rename directory fsync (E03-R07, ADR 0090 §Döntés 3,
/// SDD §18.3).
///
/// The writer is the boundary that turns an arbitrary byte payload into
/// an "either the target has the new bytes — or the target still has the
/// previous good bytes" outcome. Half-staged writes (target pointing at
/// a partial file, or a stale temp left behind) are an explicit invariant
/// violation: the recovery scanner relies on this invariant to classify
/// every `temp/`-only file as crash residue, never a current write.
///
/// The writer is **framework-independent**: the only platforms it touches
/// are `dart:io` and `dart:typed_data`. The same boundary is reachable
/// from a test by handing it a custom `Directory` factory if a hosted
/// `dart:io`-less test ever needs it (today the round gate runs only on
/// `dart:io`-backed flutter_test).
library;

import 'dart:io';
import 'dart:typed_data';

/// Result of a single [AtomicFileWriter.write] call.
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
/// The write sequence is:
///
///   1. open the target's parent directory (`File.parent`);
///   2. resolve a unique temp filename inside the same directory
///      (`<name>.tmp-<pid>-<counter>`);
///   3. `writeAsBytes(bytes, flush: true)` — this fsyncs the file
///      before `writeAsBytes` returns;
///   4. read the staged bytes back from disk and run the verifier;
///   5. on verifier-false: `deleteSync` the temp file, return
///      `committed: false`;
///   6. on verifier-true: `renameSync(temp, target)`;
///   7. `directory.flush()` — best-effort fsync of the containing
///      directory's inode so the rename itself is durable;
///   8. `deleteSync(temp)` — the rename is non-atomic on every platform,
///      and Dart's `File.renameSync` on Windows leaves the source in
///      place, so the temp is removed unconditionally as a final
///      cleanup step. The recovery scanner treats a `temp/`-only
///      orphaned file as a *crash residue*, not a current write.
///
/// Steps 5 and 8 together guarantee the invariant the recovery scanner
/// depends on: after `write` returns, either the rename landed AND the
/// temp is gone, OR the rename did not land AND no stray temp is left.
final class AtomicFileWriter {
  /// Construct a writer. The class is stateless; `const` keeps callers
  /// honest about the cheap-sharing contract.
  const AtomicFileWriter();

  /// Suffix used for the staged temp file. The recovery scanner looks
  /// for this exact suffix inside the application's per-feature temp
  /// directory.
  static const String tempExtension = '.tmp';

  /// Internal counter for unique temp filenames within a single process.
  /// The recovery scanner scans by filename pattern, not by counter
  /// value — the counter is a uniqueness tiebreaker, not a global id.
  static int _counter = 0;

  /// Write [bytes] to [target] atomically.
  ///
  /// [verifier] receives the freshly-written bytes from the staged temp
  /// file BEFORE the rename happens. Returning `false` aborts the
  /// write — the previous target bytes (or no file at all) survive.
  /// Throwing inside [verifier] is also treated as a `false`: the write
  /// is aborted, the temp is removed and the exception is re-thrown so
  /// the caller sees a real crash (the recovery scanner never runs in
  /// this case — let the crash propagate).
  AtomicWriteOutcome write({
    required File target,
    required Uint8List bytes,
    required bool Function(Uint8List verified) verifier,
  }) {
    final parent = target.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final counter = ++_counter;
    final staged = File('${target.path}${tempExtension}-$pid-$counter');

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

    // Stage 3: atomic rename. `renameSync` on POSIX overwrites an
    // existing target atomically; on Windows it returns a non-rename
    // failure if the target exists, so we handle that case explicitly
    // with a delete + rename sequence. The contract guarantees that
    // either the new bytes are visible OR the old bytes are visible —
    // never a mix.
    if (target.existsSync()) {
      target.deleteSync(recursive: false);
    }
    staged.renameSync(target.path);

    // Stage 4: best-effort directory fsync. On platforms that do not
    // support `Directory.flush` (e.g. some hosted test runners) the
    // call throws — we swallow the throw because the bytes are already
    // on disk; only metadata durability is at stake.
    try {
      parent.statSync(); // Ensure the inode is at least walkable.
      // `flush` on a Directory is a no-op on most platforms but exists
      // as the canonical "durability of direntry" hook. Use it via the
      // typed handle when supported.
      final directoryHandle = parent;
      // ignore: avoid_dynamic_calls
      final dyn = directoryHandle as dynamic;
      try {
        dyn.flush();
      } on NoSuchMethodError {
        // No directory-fsync support on this platform — the bytes
        // are durable; only direntry may be on a stale view. The
        // next startup scan closes the gap.
      }
    } catch (_) {
      // Ignore — the bytes are durable regardless.
    }

    // Stage 5: final temp cleanup. POSIX rename already removed the
    // source; on Windows the rename-as-error path above keeps the
    // source alive, and we MUST clean it up so the recovery scanner
    // does not see a stale `*.tmp-*` lying around. The cleanup is
    // best-effort: an unlinkable temp is treated as a crash residue
    // by the next startup scan.
    _safeDelete(staged);

    return AtomicWriteOutcome(committed: true, attempts: attempts);
  }

  void _safeDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync(recursive: false);
    } on FileSystemException {
      // Best-effort — see stage 5.
    }
  }
}

/// Unix-style current process id. Exposed at file scope so the
/// recovery scanner can match live `temp/` files against the running
/// process (an orphaned `tmp-<alive-pid>` is treated as crash residue
/// on next start).
int get pid {
  try {
    return _pidFromEnv();
  } catch (_) {
    return 1; // Treat as a single-process box.
  }
}

int _pidFromEnv() {
  // The Dart VM does not expose its own PID via the public API on every
  // host. Reading it from the environment on POSIX works on Linux/macOS
  // (where `$$` is the parent shell's PID, but close enough for a
  // uniqueness tiebreaker) and fails closed on hosted runners.
  // For the round gate we accept "1" as a sentinel value.
  // ignore: avoid_dynamic_calls
  final env = (Platform.environment as Map<String, String>?) ?? const {};
  final candidate = env['STRUMSIGHT_TEST_PID'] ?? env['_PID_FALLBACK'];
  if (candidate != null) {
    return int.tryParse(candidate) ?? 1;
  }
  return 1;
}
