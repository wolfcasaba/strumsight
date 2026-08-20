import '../../../core/foundation/json_validation.dart';

/// Schema version shared by every document owned by the gamification store.
const int gamificationStorageSchemaVersion = 1;

/// Maximum number of reward receipts retained for the later inbox UI.
///
/// The bound is inclusive: exactly [inboxRetentionLimit] entries are kept;
/// adding one more evicts only the oldest entry.
const int inboxRetentionLimit = 50;

/// Reserved upper bound for the future migration-state payload.
///
/// This round persists only the versioned placeholder. R09/R10 must keep the
/// actual migration metadata within this bound when they add fields.
const int migrationStateMaxBytes = 4096;

/// Every gamification key belongs here, rather than in individual repository
/// methods or the global core catalogue.
abstract final class GamificationStorageKeys {
  static const String profileSnapshot = 'ss.gamification.profile_snapshot';
  static const String catalogVersion = 'ss.gamification.catalog_version';
  static const String rewardInbox = 'ss.gamification.reward_inbox';
  static const String migrationState = 'ss.gamification.migration_state';

  static const String profileSnapshotLegacy =
      'gamification.profile_snapshot_v1';
  static const String catalogVersionLegacy = 'gamification.catalog_version_v1';
  static const String rewardInboxLegacy = 'gamification.reward_inbox_v1';
  static const String migrationStateLegacy = 'gamification.migration_state_v1';

  static const List<String> all = <String>[
    profileSnapshot,
    catalogVersion,
    rewardInbox,
    migrationState,
  ];
}

/// Persisted input for rebuilding the domain profile with the active curve.
///
/// `LevelProgress` deliberately is not stored: it is derived from [totalXp]
/// by the caller's current `LevelCurve`.
final class GamificationProfileSnapshot {
  const GamificationProfileSnapshot({required this.totalXp})
    : schemaVersion = gamificationStorageSchemaVersion;

  final int schemaVersion;
  final int totalXp;

  factory GamificationProfileSnapshot.fromJson(Map<String, dynamic> json) {
    _requireCurrentSchemaVersion(json);
    return GamificationProfileSnapshot(totalXp: requireInt(json, 'totalXp'));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'totalXp': totalXp,
  };
}

/// Version of the content catalogue used to project gamification state.
final class GamificationCatalogVersion {
  const GamificationCatalogVersion({required this.catalogVersion})
    : schemaVersion = gamificationStorageSchemaVersion;

  final int schemaVersion;
  final int catalogVersion;

  factory GamificationCatalogVersion.fromJson(Map<String, dynamic> json) {
    _requireCurrentSchemaVersion(json);
    return GamificationCatalogVersion(
      catalogVersion: requireInt(json, 'catalogVersion'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
  };
}

/// A bounded, non-blocking reward receipt for a future inbox presentation.
final class GamificationInboxItem {
  GamificationInboxItem({
    required this.id,
    required DateTime createdAt,
    this.viewedAt,
  }) : createdAt = createdAt.toUtc(),
       schemaVersion = gamificationStorageSchemaVersion {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be blank');
    }
  }

  final int schemaVersion;
  final String id;
  final DateTime createdAt;
  final DateTime? viewedAt;

  bool get isViewed => viewedAt != null;

  factory GamificationInboxItem.fromJson(Map<String, dynamic> json) {
    _requireCurrentSchemaVersion(json);
    final viewedAt = json['viewedAt'];
    return GamificationInboxItem(
      id: requireString(json, 'id', maxLength: 128),
      createdAt: requireDateTime(json, 'createdAt'),
      viewedAt: viewedAt == null ? null : requireDateTime(json, 'viewedAt'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    if (viewedAt != null) 'viewedAt': viewedAt!.toUtc().toIso8601String(),
  };
}

/// Versioned placeholder for the migration state contract owned by R09/R10.
final class GamificationMigrationState {
  const GamificationMigrationState()
    : schemaVersion = gamificationStorageSchemaVersion;

  final int schemaVersion;

  factory GamificationMigrationState.fromJson(Map<String, dynamic> json) {
    _requireCurrentSchemaVersion(json);
    return const GamificationMigrationState();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
  };
}

void _requireCurrentSchemaVersion(Map<String, dynamic> json) {
  final version = requireInt(json, 'schemaVersion', min: 1);
  if (version != gamificationStorageSchemaVersion) {
    throw const FormatException('Unsupported gamification storage schema.');
  }
}
