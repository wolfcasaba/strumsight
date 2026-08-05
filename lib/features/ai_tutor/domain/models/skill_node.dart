/// The normalized integer scale used for skill scores and confidence.
const int skillBasisPointScale = 10000;

/// The inclusive length limit for a stable skill identifier.
const int maxSkillIdLength = 128;

/// Stable exception emitted when a [SkillId] is invalid.
class SkillIdValidationException implements Exception {
  SkillIdValidationException._(this.code);

  /// One of [SkillIdValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SkillIdValidationException($code)';
}

/// Stable machine-readable codes emitted by [SkillId] validation.
abstract final class SkillIdValidationCode {
  static const String empty = 'skillId.empty';
  static const String tooLong = 'skillId.tooLong';
}

/// A provider-neutral identifier for a measurable guitar skill.
final class SkillId {
  SkillId(String raw) : value = _normalizeSkillId(raw);

  /// The trimmed, stable identifier value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SkillId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SkillId($value)';
}

/// One immutable taxonomy node and its recommendation-only prerequisites.
final class SkillNode {
  SkillNode({required this.id, required List<SkillId> prerequisiteIds})
    : prerequisiteIds = List<SkillId>.unmodifiable(prerequisiteIds);

  final SkillId id;
  final List<SkillId> prerequisiteIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillNode &&
          other.id == id &&
          _skillIdListsEqual(other.prerequisiteIds, prerequisiteIds);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(prerequisiteIds));
}

/// Stable exception emitted when a [SkillTaxonomy] is structurally invalid.
class SkillTaxonomyValidationException implements Exception {
  SkillTaxonomyValidationException._(this.code);

  /// One of [SkillTaxonomyValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SkillTaxonomyValidationException($code)';
}

/// Stable machine-readable codes emitted by taxonomy validation.
abstract final class SkillTaxonomyValidationCode {
  static const String schemaVersionOutOfRange =
      'skillTaxonomy.schemaVersion.outOfRange';
  static const String duplicateSkillId = 'skillTaxonomy.skillId.duplicate';
  static const String selfPrerequisite = 'skillTaxonomy.prerequisite.self';
  static const String unknownPrerequisite =
      'skillTaxonomy.prerequisite.unknown';
  static const String prerequisiteCycle = 'skillTaxonomy.prerequisite.cycle';
}

/// Immutable, versioned graph that classifies skills without provider types.
final class SkillTaxonomy {
  SkillTaxonomy({required this.schemaVersion, required List<SkillNode> nodes})
    : nodes = List<SkillNode>.unmodifiable(nodes) {
    _validate();
  }

  /// The initial, deterministic skill taxonomy used by the tutor domain.
  static final SkillTaxonomy initial = SkillTaxonomy(
    schemaVersion: 1,
    nodes: <SkillNode>[
      SkillNode(
        id: SkillId('rhythm.pulse'),
        prerequisiteIds: const <SkillId>[],
      ),
      SkillNode(
        id: SkillId('rhythm.onBeatAccuracy'),
        prerequisiteIds: <SkillId>[SkillId('rhythm.pulse')],
      ),
      SkillNode(
        id: SkillId('rhythm.offBeatAccuracy'),
        prerequisiteIds: <SkillId>[SkillId('rhythm.onBeatAccuracy')],
      ),
      SkillNode(
        id: SkillId('rhythm.subdivisionEighth'),
        prerequisiteIds: <SkillId>[SkillId('rhythm.onBeatAccuracy')],
      ),
      SkillNode(
        id: SkillId('rhythm.subdivisionSixteenth'),
        prerequisiteIds: <SkillId>[SkillId('rhythm.offBeatAccuracy')],
      ),
      SkillNode(
        id: SkillId('strum.downStroke'),
        prerequisiteIds: const <SkillId>[],
      ),
      SkillNode(
        id: SkillId('strum.upStroke'),
        prerequisiteIds: const <SkillId>[],
      ),
      SkillNode(
        id: SkillId('strum.directionPattern'),
        prerequisiteIds: <SkillId>[
          SkillId('strum.downStroke'),
          SkillId('strum.upStroke'),
        ],
      ),
      SkillNode(
        id: SkillId('chord.shapeClarity'),
        prerequisiteIds: const <SkillId>[],
      ),
      SkillNode(
        id: SkillId('chord.changeSpeed'),
        prerequisiteIds: <SkillId>[SkillId('chord.shapeClarity')],
      ),
      SkillNode(
        id: SkillId('chord.progressionAccuracy'),
        prerequisiteIds: <SkillId>[SkillId('chord.changeSpeed')],
      ),
      SkillNode(
        id: SkillId('chord.barreFoundation'),
        prerequisiteIds: <SkillId>[SkillId('chord.shapeClarity')],
      ),
      SkillNode(
        id: SkillId('pitch.singleNoteAccuracy'),
        prerequisiteIds: const <SkillId>[],
      ),
      SkillNode(
        id: SkillId('pitch.noteDuration'),
        prerequisiteIds: <SkillId>[SkillId('pitch.singleNoteAccuracy')],
      ),
      SkillNode(
        id: SkillId('song.sectionConsistency'),
        prerequisiteIds: const <SkillId>[],
      ),
      SkillNode(
        id: SkillId('song.fullRunConsistency'),
        prerequisiteIds: <SkillId>[SkillId('song.sectionConsistency')],
      ),
      SkillNode(
        id: SkillId('practice.consistency'),
        prerequisiteIds: const <SkillId>[],
      ),
      SkillNode(
        id: SkillId('practice.focus'),
        prerequisiteIds: <SkillId>[SkillId('practice.consistency')],
      ),
    ],
  );

  final int schemaVersion;
  final List<SkillNode> nodes;

  /// Looks up a node without making a missing skill an ambient failure.
  SkillNode? nodeFor(SkillId id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  void _validate() {
    if (schemaVersion < 1) {
      throw SkillTaxonomyValidationException._(
        SkillTaxonomyValidationCode.schemaVersionOutOfRange,
      );
    }

    final nodesById = <SkillId, SkillNode>{};
    for (final node in nodes) {
      if (nodesById.containsKey(node.id)) {
        throw SkillTaxonomyValidationException._(
          SkillTaxonomyValidationCode.duplicateSkillId,
        );
      }
      nodesById[node.id] = node;
    }

    for (final node in nodes) {
      for (final prerequisiteId in node.prerequisiteIds) {
        if (prerequisiteId == node.id) {
          throw SkillTaxonomyValidationException._(
            SkillTaxonomyValidationCode.selfPrerequisite,
          );
        }
        if (!nodesById.containsKey(prerequisiteId)) {
          throw SkillTaxonomyValidationException._(
            SkillTaxonomyValidationCode.unknownPrerequisite,
          );
        }
      }
    }

    final completed = <SkillId>{};
    final visiting = <SkillId>{};
    for (final node in nodes) {
      _visit(node.id, nodesById, completed, visiting);
    }
  }

  void _visit(
    SkillId id,
    Map<SkillId, SkillNode> nodesById,
    Set<SkillId> completed,
    Set<SkillId> visiting,
  ) {
    if (completed.contains(id)) return;
    if (!visiting.add(id)) {
      throw SkillTaxonomyValidationException._(
        SkillTaxonomyValidationCode.prerequisiteCycle,
      );
    }
    for (final prerequisiteId in nodesById[id]!.prerequisiteIds) {
      _visit(prerequisiteId, nodesById, completed, visiting);
    }
    visiting.remove(id);
    completed.add(id);
  }
}

String _normalizeSkillId(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    throw SkillIdValidationException._(SkillIdValidationCode.empty);
  }
  if (normalized.length > maxSkillIdLength) {
    throw SkillIdValidationException._(SkillIdValidationCode.tooLong);
  }
  return normalized;
}

bool _skillIdListsEqual(List<SkillId> left, List<SkillId> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
