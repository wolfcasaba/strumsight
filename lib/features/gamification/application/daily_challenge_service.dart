import 'dart:math' as math;

import '../../../core/logging/app_logger.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../data/migration/legacy_daily_challenge_adapter.dart';
import '../data/reward_ledger_repository.dart';
import '../domain/quests/challenge_definition.dart';
import '../domain/rewards/reward_ledger_entry.dart';
import '../domain/rewards/reward_reason.dart';

/// Current schema for the persisted [DailyChallengeInstance] envelope.
const int dailyChallengeInstanceSchemaVersion = 1;

/// The current schema version of the [DailyChallengeContentCatalog] snapshot
/// embedded in each [DailyChallengeInstance].
const int dailyChallengeContentCatalogSchemaVersion = 1;

/// Stable storage key for the local daily-challenge completion store.
///
/// The legacy streak domain lives under its own key (`StorageKeys.streak`)
/// and is intentionally left untouched by this round.
const String dailyChallengeStorageKey = 'ss.gamification.daily_challenge_v1';
const String dailyChallengeLegacyStorageKey = 'gamification.daily_challenge_v1';

/// Stable storage key names for the JSON document store.
const String _documentName = 'daily_challenge';
const String _bodyKey = 'data';
const String _instanceKey = 'instance';

/// The deterministic content catalog the generator is allowed to draw from.
///
/// Implementations expose one stable list of installed content IDs per
/// [DailyChallengeType]. The order is preserved so a deterministic seed picks
/// the same item on every device for the same epoch day. The legacy strum
/// pattern is intentionally **absent** from this catalog — it is self-contained
/// and always available (ADR 0387 Decision 4).
abstract interface class DailyChallengeContentCatalog {
  /// The installed chord IDs (used by [ChordChangeChallenge]).
  List<String> installedChordIds();

  /// The installed rhythm content IDs (used by [RhythmChallenge]).
  List<String> installedRhythmIds();

  /// The installed song IDs (used by [SongSectionChallenge]).
  List<String> installedSongIds();

  /// The installed rhythm content IDs usable for timing drills
  /// (used by [TimingChallenge]). Defaults to [installedRhythmIds] when the
  /// implementation has no separate list.
  List<String> installedTimingContentIds() => installedRhythmIds();

  /// A monotonically-increasing version of the underlying content catalog.
  /// The instance pins this value at generation time so an app update during
  /// the day cannot swap the active challenge (ADR 0387 Decision 3).
  int catalogVersion();
}

/// A snapshot of [DailyChallengeContentCatalog] frozen at instance-generation
/// time. Lets the instance survive a catalog mutation without re-picking.
final class DailyChallengeContentCatalogSnapshot {
  DailyChallengeContentCatalogSnapshot({
    required this.schemaVersion,
    required this.catalogVersion,
    required List<String> chordIds,
    required List<String> rhythmIds,
    required List<String> songIds,
    required List<String> timingContentIds,
  }) : _chordIds = List<String>.unmodifiable(chordIds),
       _rhythmIds = List<String>.unmodifiable(rhythmIds),
       _songIds = List<String>.unmodifiable(songIds),
       _timingContentIds = List<String>.unmodifiable(timingContentIds) {
    if (schemaVersion != dailyChallengeContentCatalogSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported',
      );
    }
    if (catalogVersion < 1) {
      throw ArgumentError.value(
        catalogVersion,
        'catalogVersion',
        'must be positive',
      );
    }
  }

  final int schemaVersion;
  final int catalogVersion;
  final List<String> _chordIds;
  final List<String> _rhythmIds;
  final List<String> _songIds;
  final List<String> _timingContentIds;

  List<String> chordIds() => _chordIds;
  List<String> rhythmIds() => _rhythmIds;
  List<String> songIds() => _songIds;
  List<String> timingContentIds() => _timingContentIds;

  bool isAvailable(DailyChallengeType type) {
    return switch (type) {
      DailyChallengeType.strumPattern => true,
      DailyChallengeType.chordChange => _chordIds.length >= 2,
      DailyChallengeType.rhythm => _rhythmIds.isNotEmpty,
      DailyChallengeType.songSection => _songIds.isNotEmpty,
      DailyChallengeType.timing => _timingContentIds.isNotEmpty,
    };
  }

  List<String> idsFor(DailyChallengeType type) => switch (type) {
    DailyChallengeType.strumPattern => const <String>[],
    DailyChallengeType.chordChange => _chordIds,
    DailyChallengeType.rhythm => _rhythmIds,
    DailyChallengeType.songSection => _songIds,
    DailyChallengeType.timing => _timingContentIds,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'chordIds': _chordIds,
    'rhythmIds': _rhythmIds,
    'songIds': _songIds,
    'timingContentIds': _timingContentIds,
  };

  factory DailyChallengeContentCatalogSnapshot.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    return DailyChallengeContentCatalogSnapshot(
      schemaVersion: _requireInt(json, 'schemaVersion'),
      catalogVersion: _requireInt(json, 'catalogVersion'),
      chordIds: _stringList(json, 'chordIds'),
      rhythmIds: _stringList(json, 'rhythmIds'),
      songIds: _stringList(json, 'songIds'),
      timingContentIds: _stringList(json, 'timingContentIds'),
    );
  }
}

extension on DailyChallengeContentCatalog {
  DailyChallengeContentCatalogSnapshot snapshot() =>
      DailyChallengeContentCatalogSnapshot(
        schemaVersion: dailyChallengeContentCatalogSchemaVersion,
        catalogVersion: catalogVersion(),
        chordIds: installedChordIds(),
        rhythmIds: installedRhythmIds(),
        songIds: installedSongIds(),
        timingContentIds: installedTimingContentIds(),
      );
}

/// An immutable, persisted record of one day's generated challenge. The
/// [catalogVersion] is pinned at generation time (ADR 0387 Decision 3) and the
/// [definition] carries the frozen content-catalog snapshot used to draw its
/// content IDs.
final class DailyChallengeInstance {
  DailyChallengeInstance({
    required this.schemaVersion,
    required this.epochDay,
    required this.catalogVersion,
    required DateTime generatedAt,
    required this.definition,
    required this.contentCatalog,
    required this.completion,
  }) : generatedAt = generatedAt.toUtc() {
    if (schemaVersion != dailyChallengeInstanceSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported',
      );
    }
    if (epochDay < 0) {
      throw ArgumentError.value(epochDay, 'epochDay', 'must not be negative');
    }
    if (catalogVersion < 1) {
      throw ArgumentError.value(
        catalogVersion,
        'catalogVersion',
        'must be positive',
      );
    }
  }

  final int schemaVersion;
  final int epochDay;
  final int catalogVersion;
  final DateTime generatedAt;
  final DailyChallengeDefinition definition;
  final DailyChallengeContentCatalogSnapshot contentCatalog;
  final DailyChallengeCompletion? completion;

  /// The deterministic instance identifier. Used as the reward ledger's
  /// `sourceEventId` so the reward is appended exactly once even when the
  /// user replays the challenge (ADR 0387 Decision 2).
  String get instanceId =>
      'daily-challenge:${definition.type.name}:$catalogVersion:$epochDay';

  /// Stable receipt identifier matching the instance. Required by
  /// [RewardLedgerEntry] so a re-issued receipt cannot collide with a stale
  /// one.
  String get completionLedgerId => '$instanceId:completion';

  bool isCompleted() => completion != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'epochDay': epochDay,
    'catalogVersion': catalogVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'definition': definition.toJson(),
    'contentCatalog': contentCatalog.toJson(),
    if (completion != null) 'completion': completion!.toJson(),
  };

  factory DailyChallengeInstance.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    final completionRaw = json['completion'];
    return DailyChallengeInstance(
      schemaVersion: _requireInt(json, 'schemaVersion'),
      epochDay: _requireInt(json, 'epochDay'),
      catalogVersion: _requireInt(json, 'catalogVersion'),
      generatedAt: _requireUtcDate(json, 'generatedAt'),
      definition: DailyChallengeDefinition.fromJson(json['definition']),
      contentCatalog: DailyChallengeContentCatalogSnapshot.fromJson(
        json['contentCatalog'],
      ),
      completion: completionRaw == null
          ? null
          : DailyChallengeCompletion.fromJson(completionRaw),
    );
  }

  DailyChallengeInstance copyWith({DailyChallengeCompletion? completion}) =>
      DailyChallengeInstance(
        schemaVersion: schemaVersion,
        epochDay: epochDay,
        catalogVersion: catalogVersion,
        generatedAt: generatedAt,
        definition: definition,
        contentCatalog: contentCatalog,
        completion: completion ?? this.completion,
      );
}

/// An immutable record that the user has finished the challenge for the day.
/// A second completion on the same day updates the timestamp but does not
/// re-issue the reward (ADR 0387 Decision 2).
final class DailyChallengeCompletion {
  DailyChallengeCompletion({required DateTime completedAt})
    : completedAt = completedAt.toUtc();

  final DateTime completedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'completedAt': completedAt.toUtc().toIso8601String(),
  };

  factory DailyChallengeCompletion.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    return DailyChallengeCompletion(
      completedAt: _requireUtcDate(json, 'completedAt'),
    );
  }
}

/// The persistence boundary for [DailyChallengeInstance]. The local default
/// implementation is below; tests use an in-memory variant.
abstract interface class DailyChallengeCompletionStore {
  /// Returns the stored instance, or null when no challenge has been generated
  /// for the current day yet.
  DailyChallengeInstance? read();

  /// Persists [instance], replacing any previously stored value.
  Future<void> write(DailyChallengeInstance instance);
}

/// The default local storage-backed completion store.
final class LocalDailyChallengeCompletionStore
    implements DailyChallengeCompletionStore {
  LocalDailyChallengeCompletionStore({
    required KeyValueStore store,
    required AppLogger logger,
  }) : _document = JsonDocumentStore(
         store: store,
         logger: logger,
         key: dailyChallengeStorageKey,
         legacyKey: dailyChallengeLegacyStorageKey,
         name: _documentName,
         bodyKey: _bodyKey,
       );

  final JsonDocumentStore _document;
  bool _loaded = false;
  DailyChallengeInstance? _instance;
  Future<void> _writeTail = Future<void>.value();

  @override
  DailyChallengeInstance? read() {
    _ensureLoaded();
    return _instance;
  }

  @override
  Future<void> write(DailyChallengeInstance instance) {
    final scheduled = _writeTail.then((_) => _write(instance));
    _writeTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<void> _write(DailyChallengeInstance instance) async {
    _ensureLoaded();
    _instance = instance;
    await _document.write(<String, Object?>{_instanceKey: instance.toJson()});
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final body = _document.readBody();
    if (body is! Map<String, Object?>) return;
    final raw = body[_instanceKey];
    if (raw == null) return;
    try {
      _instance = DailyChallengeInstance.fromJson(raw);
    } on ArgumentError catch (error, stackTrace) {
      _document.logger.warning(
        'gamification.daily_challenge.entry_isolated',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// The documented outcome of a completion attempt. The same instance is
/// returned every replay; only [rewardAppended] and [completionAt] reflect the
/// current call.
final class DailyChallengeCompletionOutcome {
  const DailyChallengeCompletionOutcome({
    required this.instance,
    required this.rewardAppended,
    required this.completionAt,
  });

  final DailyChallengeInstance instance;
  final bool rewardAppended;
  final DateTime completionAt;
}

/// The deterministic V2 daily-challenge service.
///
/// The service owns the per-day [DailyChallengeInstance] and routes the
/// reward through the append-only ledger so the user can replay the
/// challenge as often as they like but is credited exactly once per day
/// (ADR 0387 Decisions 2 + 5).
final class DailyChallengeService {
  DailyChallengeService({
    required this.contentCatalog,
    required this.completionStore,
    required this.rewardLedger,
    LegacyDailyChallengeAdapter? legacyAdapter,
    this.rewardBaseXp = 25,
    this.rewardPolicyVersion = 1,
    DateTime Function()? clock,
  }) : legacyAdapter = legacyAdapter ?? const LegacyDailyChallengeAdapter(),
       _clock = clock ?? DateTime.now;

  final DailyChallengeContentCatalog contentCatalog;
  final DailyChallengeCompletionStore completionStore;
  final RewardLedgerRepository rewardLedger;
  final LegacyDailyChallengeAdapter legacyAdapter;
  final int rewardBaseXp;
  final int rewardPolicyVersion;
  final DateTime Function() _clock;

  /// The deterministic per-day non-negative seed (ADR 0387 §6.1 — the boundary
  /// belongs to the new epoch day, so the seed is rebuilt only when the day
  /// flips, not when the catalog changes).
  static int seedFor({required int epochDay, required int catalogVersion}) {
    final safeEpoch = epochDay & 0x7fffffff;
    final safeVersion = catalogVersion & 0x7fffffff;
    var hash = 0xcbf29ce484222325 & 0xffffffff;
    const prime = 0x100000001b3;
    const mask = 0xffffffffffffffff;
    for (final byte in <int>[safeEpoch, safeVersion]) {
      hash = ((hash ^ byte) * prime) & mask;
    }
    return hash & 0x7fffffff;
  }

  /// Returns the active instance for [epochDay]. If a stored instance exists
  /// with the same [epochDay] it is returned **unchanged** even when the caller's
  /// [catalogVersion] differs (ADR 0387 Decision 3 — the day already started
  /// with the previous catalog version, mid-day updates cannot swap the
  /// challenge). If no stored instance exists, or the stored instance is for a
  /// different day, a new one is generated.
  Future<DailyChallengeInstance> getOrGenerateInstance({
    required int epochDay,
    required int catalogVersion,
  }) async {
    if (epochDay < 0) {
      throw ArgumentError.value(epochDay, 'epochDay', 'must not be negative');
    }
    if (catalogVersion < 1) {
      throw ArgumentError.value(
        catalogVersion,
        'catalogVersion',
        'must be positive',
      );
    }
    final stored = completionStore.read();
    if (stored != null && stored.epochDay == epochDay) {
      return stored;
    }
    final snapshot = contentCatalog.snapshot();
    final definition = _generateDefinition(
      epochDay: epochDay,
      catalogVersion: catalogVersion,
      catalog: snapshot,
    );
    final instance = DailyChallengeInstance(
      schemaVersion: dailyChallengeInstanceSchemaVersion,
      epochDay: epochDay,
      catalogVersion: catalogVersion,
      generatedAt: _clock(),
      definition: definition,
      contentCatalog: snapshot,
      completion: null,
    );
    await completionStore.write(instance);
    return instance;
  }

  /// Records a completion of [instance] and submits the idempotent reward.
  ///
  /// Multiple completions on the same [instance] keep updating the completion
  /// timestamp, but the underlying reward ledger's `appendIfAbsent` collapses
  /// every replay into a single credit (ADR 0387 Decision 2).
  Future<DailyChallengeCompletionOutcome> complete({
    required DailyChallengeInstance instance,
    DateTime? at,
  }) async {
    final completionAt = (at ?? _clock()).toUtc();
    final updated = instance.copyWith(
      completion: DailyChallengeCompletion(completedAt: completionAt),
    );
    await completionStore.write(updated);

    final rewardEntry = RewardLedgerEntry(
      ledgerId: updated.completionLedgerId,
      sourceEventId: updated.instanceId,
      createdAt: completionAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: rewardPolicyVersion,
      baseXp: rewardBaseXp,
      bonusXp: 0,
      totalXp: rewardBaseXp,
      reasonCodes: const <RewardReason>[RewardReason.questCompleted],
    );
    final rewardAppended = await rewardLedger.appendIfAbsent(rewardEntry);
    return DailyChallengeCompletionOutcome(
      instance: updated,
      rewardAppended: rewardAppended,
      completionAt: completionAt,
    );
  }

  DailyChallengeDefinition _generateDefinition({
    required int epochDay,
    required int catalogVersion,
    required DailyChallengeContentCatalogSnapshot catalog,
  }) {
    // The order is intentionally a stable list: strumPattern last because it
    // is the always-available fallback. The seed mixes the epoch day and the
    // catalog version so two installs on different catalog versions get
    // different non-legacy picks (ADR 0387 Decision 3).
    final order = const <DailyChallengeType>[
      DailyChallengeType.chordChange,
      DailyChallengeType.rhythm,
      DailyChallengeType.songSection,
      DailyChallengeType.timing,
      DailyChallengeType.strumPattern,
    ];

    final available = order.where(catalog.isAvailable).toList(growable: false);
    final seed = seedFor(epochDay: epochDay, catalogVersion: catalogVersion);
    final rng = math.Random(seed);
    final picked = available[rng.nextInt(available.length)];
    return _definitionFor(picked, epochDay, catalogVersion, catalog, rng);
  }

  DailyChallengeDefinition _definitionFor(
    DailyChallengeType type,
    int epochDay,
    int catalogVersion,
    DailyChallengeContentCatalogSnapshot catalog,
    math.Random rng,
  ) {
    switch (type) {
      case DailyChallengeType.strumPattern:
        return legacyAdapter.forDay(epochDay);
      case DailyChallengeType.chordChange:
        final chordIds = catalog.chordIds();
        final firstIndex = rng.nextInt(chordIds.length);
        var secondIndex = rng.nextInt(chordIds.length);
        if (secondIndex == firstIndex) {
          secondIndex = (firstIndex + 1) % chordIds.length;
        }
        return ChordChangeChallenge(
          fromChordId: chordIds[firstIndex],
          toChordId: chordIds[secondIndex],
          beats: 4,
        );
      case DailyChallengeType.rhythm:
        final rhythmIds = catalog.rhythmIds();
        return RhythmChallenge(
          contentId: rhythmIds[rng.nextInt(rhythmIds.length)],
          targetBpm: 80 + rng.nextInt(60),
        );
      case DailyChallengeType.songSection:
        final songIds = catalog.songIds();
        final songId = songIds[rng.nextInt(songIds.length)];
        const sections = <String>['verse', 'chorus', 'bridge', 'intro'];
        return SongSectionChallenge(
          songId: songId,
          sectionId: sections[rng.nextInt(sections.length)],
          repetitions: 2 + rng.nextInt(3),
        );
      case DailyChallengeType.timing:
        final timingIds = catalog.timingContentIds();
        return TimingChallenge(
          contentId: timingIds[rng.nextInt(timingIds.length)],
          targetWindowMs: 80 + rng.nextInt(80),
        );
    }
  }
}

int _requireInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}

DateTime _requireUtcDate(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! String) {
    throw ArgumentError.value(value, field, 'must be a UTC ISO string');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw ArgumentError.value(value, field, 'must be a UTC ISO string');
  }
  return parsed;
}

List<String> _stringList(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw ArgumentError.value(value, field, 'must be a list of strings');
  }
  return List<String>.unmodifiable(value.cast<String>());
}
