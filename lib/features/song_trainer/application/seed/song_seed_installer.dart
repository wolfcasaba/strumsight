/// One-shot, restart-safe installer for the shipped practice songs.
///
/// A fresh install used to open the Song Trainer library on an empty list
/// with no way forward: the user had to import a file before anything in the
/// V2 trainer was reachable. This use case removes that cliff by copying the
/// project-original songs bundled under `assets/songs/` into the SAME
/// [SongRepository] the rest of the feature reads — they are ordinary,
/// editable, deletable documents from the moment they land, not a parallel
/// read-only catalogue.
///
/// "Exactly once" is guaranteed by [SongSeedMarkerStore], not by looking at
/// the repository: a seed id that has been installed once is never installed
/// again, so a user who deletes a seeded song does not get it back on the
/// next launch (the measured failure mode of every "restore the defaults on
/// boot" implementation). A seed whose install FAILED is deliberately left
/// out of the marker so the next launch retries it.
///
/// The installer is framework-independent: it takes an asset loader function
/// rather than importing `rootBundle`, so the provider layer owns the Flutter
/// binding and tests inject a map.
library;

import 'dart:convert';

import '../../../../core/foundation/app_result.dart';
import '../../data/local/song_document_codec.dart';
import '../../data/seed/song_seed_marker_store.dart';
import '../../domain/models/song_document.dart';
import '../../domain/repositories/song_repository.dart';

/// Loads the raw UTF-8 text of a bundled asset. Production wires
/// `rootBundle.loadString`; tests inject a map-backed function.
typedef SongSeedAssetLoader = Future<String> Function(String assetKey);

/// One shipped song: its stable seed id and the asset that carries it.
///
/// [seedId] is deliberately independent of the document's own `id` field so a
/// future re-authoring of a seed can keep the marker entry (and therefore the
/// "never comes back" guarantee) while changing what the document contains.
final class SongSeedDefinition {
  /// Stable constructor.
  const SongSeedDefinition({required this.seedId, required this.assetKey});

  /// Stable identifier recorded in the marker.
  final String seedId;

  /// `pubspec.yaml`-declared asset path of the `SongDocument` JSON.
  final String assetKey;
}

/// The shipped catalogue. Every entry MUST also be declared under
/// `flutter.assets` in `pubspec.yaml` and carry a provenance entry in
/// `tool/ci/check_song_fixture_licenses.dart` (see `assets/songs/README.md`).
const List<SongSeedDefinition> songSeedCatalog = <SongSeedDefinition>[
  SongSeedDefinition(
    seedId: 'seed-harom-akkord-g-c-d',
    assetKey: 'assets/songs/seed-harom-akkord-g-c-d.song.json',
  ),
  SongSeedDefinition(
    seedId: 'seed-blues-shuffle-a',
    assetKey: 'assets/songs/seed-blues-shuffle-a.song.json',
  ),
  SongSeedDefinition(
    seedId: 'seed-keringo-g',
    assetKey: 'assets/songs/seed-keringo-g.song.json',
  ),
];

/// Closed set of reasons a single seed could not be installed. Every value
/// is a stable machine code with a distinct recovery story; none of them
/// carries user content.
abstract final class SongSeedFailureReason {
  /// The declared asset could not be read from the bundle.
  static const String assetUnavailable = 'songSeed.failure.assetUnavailable';

  /// The asset was read but is not a decodable `SongDocument` JSON map.
  static const String decodeFailed = 'songSeed.failure.decodeFailed';

  /// The repository refused the write (validation or I/O).
  static const String repositoryRejected =
      'songSeed.failure.repositoryRejected';

  /// Every seed landed but the marker could not be persisted, so the next
  /// launch would install them again. Reported against the whole run.
  static const String markerWrite = 'songSeed.failure.markerWrite';

  /// The songs directory itself could not be resolved or opened, so the run
  /// never started. Only the user-initiated restore can report this.
  static const String storageUnavailable =
      'songSeed.failure.storageUnavailable';
}

/// One failed seed entry.
final class SongSeedFailure {
  /// Stable constructor.
  const SongSeedFailure({required this.seedId, required this.reason});

  /// Seed id that failed, or `<marker>` for a marker-write failure.
  final String seedId;

  /// One of [SongSeedFailureReason]'s constants.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is SongSeedFailure &&
      other.seedId == seedId &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(seedId, reason);
}

/// Per-run report of [SongSeedInstaller.install].
final class SongSeedOutcome {
  /// Stable constructor.
  const SongSeedOutcome({
    required this.installedSeedIds,
    required this.skippedSeedIds,
    required this.failures,
  });

  /// Seed ids written to the repository by THIS run. Empty on every launch
  /// after the first successful one.
  final List<String> installedSeedIds;

  /// Seed ids the marker already listed, so this run did not touch them.
  final List<String> skippedSeedIds;

  /// Per-seed failures, in catalogue order. Empty on a clean run.
  final List<SongSeedFailure> failures;

  /// Whether the run finished with nothing left to retry.
  bool get isClean => failures.isEmpty;
}

/// Installs the shipped practice songs exactly once per device.
final class SongSeedInstaller {
  /// Stable constructor. [clock] supplies the marker timestamp.
  const SongSeedInstaller({
    required this.repository,
    required this.markerStore,
    required this.assetLoader,
    required this.clock,
    this.catalog = songSeedCatalog,
    this.codec = const SongDocumentCodec(),
  });

  /// The same repository the Library, Editor and Trainer read.
  final SongRepository repository;

  /// "Already installed" marker — the exactly-once guard.
  final SongSeedMarkerStore markerStore;

  /// Asset-bundle boundary.
  final SongSeedAssetLoader assetLoader;

  /// UTC clock for the marker timestamp.
  final DateTime Function() clock;

  /// Catalogue to install. Defaults to [songSeedCatalog].
  final List<SongSeedDefinition> catalog;

  /// Document codec used to decode the bundled JSON.
  final SongDocumentCodec codec;

  /// Runs the boot-path installer. Never throws: every failure mode becomes
  /// an entry in [SongSeedOutcome.failures] so the caller can log it and the
  /// next launch can retry.
  Future<SongSeedOutcome> install() => _run(ignoreMarker: false);

  /// Re-installs the whole catalogue REGARDLESS of the marker.
  ///
  /// This is the only way a deleted seed song comes back, and it is always an
  /// explicit user action (the Library's empty-state CTA) — the boot path
  /// never calls it, which is what keeps "a user-deleted seed stays deleted"
  /// true across launches.
  Future<SongSeedOutcome> restore() => _run(ignoreMarker: true);

  Future<SongSeedOutcome> _run({required bool ignoreMarker}) async {
    final marker = switch (markerStore.load()) {
      SongSeedMarkerLoaded(:final marker) => marker,
      SongSeedMarkerMissing() => SongSeedMarker.empty(),
      SongSeedMarkerCorrupt() => SongSeedMarker.empty(),
    };
    final installed = <String>[];
    final skipped = <String>[];
    final failures = <SongSeedFailure>[];

    for (final definition in catalog) {
      if (!ignoreMarker &&
          marker.installedSeedIds.contains(definition.seedId)) {
        skipped.add(definition.seedId);
        continue;
      }
      final failure = await _installOne(definition);
      if (failure == null) {
        installed.add(definition.seedId);
      } else {
        failures.add(failure);
      }
    }

    if (installed.isNotEmpty) {
      final allIds = <String>{...marker.installedSeedIds, ...installed};
      final next = SongSeedMarker(
        installedSeedIds: allIds,
        installedAt: clock().toUtc(),
      );
      try {
        await markerStore.save(next);
      } catch (_) {
        failures.add(
          const SongSeedFailure(
            seedId: '<marker>',
            reason: SongSeedFailureReason.markerWrite,
          ),
        );
      }
    }

    return SongSeedOutcome(
      installedSeedIds: List<String>.unmodifiable(installed),
      skippedSeedIds: List<String>.unmodifiable(skipped),
      failures: List<SongSeedFailure>.unmodifiable(failures),
    );
  }

  /// Installs one seed, returning `null` on success or the failure entry.
  Future<SongSeedFailure?> _installOne(SongSeedDefinition definition) async {
    final String raw;
    try {
      raw = await assetLoader(definition.assetKey);
    } catch (_) {
      return SongSeedFailure(
        seedId: definition.seedId,
        reason: SongSeedFailureReason.assetUnavailable,
      );
    }
    final SongDocument document;
    try {
      document = codec.decode(utf8.encode(raw));
    } catch (_) {
      return SongSeedFailure(
        seedId: definition.seedId,
        reason: SongSeedFailureReason.decodeFailed,
      );
    }
    final result = await repository.create(document);
    if (result case Failure(:final error)) {
      // A document already present under the same id means a previous run
      // wrote it and then failed to persist the marker. That is "installed",
      // not a failure — otherwise the retry loop could never converge.
      if (error.code == SongRepositoryErrorCode.alreadyExists) return null;
      return SongSeedFailure(
        seedId: definition.seedId,
        reason: SongSeedFailureReason.repositoryRejected,
      );
    }
    return null;
  }
}
