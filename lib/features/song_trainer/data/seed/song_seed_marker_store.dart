/// Atomic, file-based persistence for the seed-song installation marker.
///
/// The store is the "seeded exactly once" guard behind the shipped practice
/// songs (`assets/songs/`, see that directory's README). It deliberately
/// mirrors `SongMigrationVersionStore` — same layout inside the songs root,
/// same [AtomicFileWriter] temp→verify→rename pipeline, same three-state load
/// result — so the two boot-time markers cannot drift apart in behaviour.
///
/// The marker records the seed ids the installer has ALREADY put into the
/// repository, not the ids currently on disk. That distinction is the whole
/// point: a user who deletes a seeded song must never get it back on the next
/// launch, and a seed whose install failed must be retried on the next launch.
///
/// The store deals in a [SongSeedMarker] value object only. It never imports
/// a Riverpod provider, a Flutter binding, or `SharedPreferences`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../local/atomic_file_writer.dart';

/// Reserved subdirectory inside the songs root that owns the seed marker.
const String songSeedDirectoryName = 'seed';

/// File name of the seed marker. Versioned by name so a future shape change
/// can live next to it without overwriting the user's current marker.
const String songSeedStateFileName = 'state.json';

/// Persisted record of which seed songs have already been installed.
@immutable
final class SongSeedMarker {
  /// Stable constructor.
  const SongSeedMarker({
    required this.installedSeedIds,
    required this.installedAt,
  });

  /// Stable constructor for a fresh install (no marker on disk yet).
  factory SongSeedMarker.empty() =>
      const SongSeedMarker(installedSeedIds: <String>{}, installedAt: null);

  /// Seed ids the installer has already written to the repository in some
  /// prior run. These are NEVER re-installed — a deleted seed stays deleted.
  final Set<String> installedSeedIds;

  /// UTC timestamp of the most recent successful marker write. `null` until
  /// the first seed lands.
  final DateTime? installedAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongSeedMarker) return false;
    if (other.installedAt != installedAt) return false;
    if (other.installedSeedIds.length != installedSeedIds.length) return false;
    return other.installedSeedIds.containsAll(installedSeedIds);
  }

  @override
  int get hashCode {
    final sorted = installedSeedIds.toList()..sort();
    return Object.hash(Object.hashAll(sorted), installedAt);
  }
}

/// Result envelope returned by [SongSeedMarkerStore.load].
sealed class SongSeedMarkerLoad {
  const SongSeedMarkerLoad();
}

/// A valid marker was loaded from disk.
final class SongSeedMarkerLoaded extends SongSeedMarkerLoad {
  const SongSeedMarkerLoaded(this.marker);

  final SongSeedMarker marker;
}

/// No marker file exists yet — this is a fresh install.
final class SongSeedMarkerMissing extends SongSeedMarkerLoad {
  const SongSeedMarkerMissing();
}

/// The marker file exists but its contents are unrecognised. Treated as
/// "nothing installed yet" so the user always ends up with the catalogue,
/// never with a silently skipped library.
final class SongSeedMarkerCorrupt extends SongSeedMarkerLoad {
  const SongSeedMarkerCorrupt();
}

/// File-based, atomic [SongSeedMarker] persistence.
final class SongSeedMarkerStore {
  SongSeedMarkerStore._({
    required this.file,
    required this.writer,
    required this.stagingDirectory,
  });

  /// Open a marker store for [songsRoot], creating the seed subdirectory and
  /// the shared `temp/` staging directory when either is missing.
  factory SongSeedMarkerStore.open({
    required Directory songsRoot,
    AtomicFileWriter writer = const AtomicFileWriter(),
  }) {
    final seedDir = Directory('${songsRoot.path}/$songSeedDirectoryName')
      ..createSync(recursive: true);
    final stagingDir = Directory('${songsRoot.path}/temp')
      ..createSync(recursive: true);
    return SongSeedMarkerStore._(
      file: File('${seedDir.path}/$songSeedStateFileName'),
      writer: writer,
      stagingDirectory: stagingDir,
    );
  }

  /// Path of the marker file on disk.
  final File file;

  /// Atomic writer reused across runs.
  final AtomicFileWriter writer;

  /// Directory inside the songs-root `temp/` the writer stages into.
  final Directory stagingDirectory;

  /// Load the current marker from disk.
  SongSeedMarkerLoad load() {
    if (!file.existsSync()) return const SongSeedMarkerMissing();
    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(utf8.decode(file.readAsBytesSync()));
      if (parsed is! Map<String, dynamic>) {
        return const SongSeedMarkerCorrupt();
      }
      decoded = parsed;
    } catch (_) {
      return const SongSeedMarkerCorrupt();
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema != 1) return const SongSeedMarkerCorrupt();
    final installedRaw = decoded['installedSeedIds'];
    if (installedRaw is! List) return const SongSeedMarkerCorrupt();
    final installedAtRaw = decoded['installedAt'];
    final installedAt = switch (installedAtRaw) {
      null => null,
      final String value => DateTime.tryParse(value)?.toUtc(),
      _ => null,
    };
    return SongSeedMarkerLoaded(
      SongSeedMarker(
        installedSeedIds: <String>{
          for (final entry in installedRaw)
            if (entry is String && entry.isNotEmpty) entry,
        },
        installedAt: installedAt,
      ),
    );
  }

  /// Persist [marker] to disk atomically.
  ///
  /// On a verifier failure or a write refusal the marker on disk is left
  /// untouched and the exception bubbles — the installer records that as a
  /// failure and retries on the next launch.
  Future<void> save(SongSeedMarker marker) async {
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'installedSeedIds': marker.installedSeedIds.toList()..sort(),
      'installedAt': marker.installedAt?.toUtc().toIso8601String(),
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final outcome = writer.write(
      target: file,
      bytes: Uint8List.fromList(bytes),
      stagingDirectory: stagingDirectory,
      verifier: (Uint8List verified) {
        final parsed = jsonDecode(utf8.decode(verified));
        if (parsed is! Map<String, dynamic>) return false;
        return parsed['schemaVersion'] == 1;
      },
    );
    if (!outcome.committed) {
      throw const FileSystemException(
        'AtomicFileWriter refused to commit the seed marker.',
      );
    }
  }
}

/// Test-only path projection — mirrors `songMigrationStateFileFor` so a test
/// can assert on the marker location without constructing a store.
@visibleForTesting
File songSeedStateFileFor(Directory songsRoot) {
  return File(
    '${songsRoot.path}/$songSeedDirectoryName/$songSeedStateFileName',
  );
}
