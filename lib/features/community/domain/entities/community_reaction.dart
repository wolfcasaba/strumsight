/// Community post reactions (E09-R05, ADR 0399 §1, SDD §14.1).
///
/// The first-version allowlist has four positive reactions
/// (`support`, `celebrate`, `inspiring`, `helpful`); `downvote`-style
/// negative reactions are explicitly out of scope (SDD §14.1, brief
/// §0.0 D1). The wire decoder returns `null` for unknown values so the
/// data layer can fall back to a stripped-tombstone rather than a
/// thrown exception (A3).
library;

/// The reaction kinds the Community MVP supports.
///
/// The wire-string form is `name`. The [reactionKindFromWire] helper
/// returns `null` for any unrecognized string — that is the cell that
/// the A3 row in the §6.1 measure-matrix asserts on.
enum ReactionKind {
  support('support'),
  celebrate('celebrate'),
  inspiring('inspiring'),
  helpful('helpful');

  const ReactionKind(this.wireValue);

  final String wireValue;
}

/// Decode a wire string into a [ReactionKind].
///
/// Returns `null` if the wire string is `null`, empty or unknown; the
/// caller decides whether to discard, count under a `_other` bucket,
/// or surface as an error.
ReactionKind? reactionKindFromWire(String? wire) {
  if (wire == null || wire.isEmpty) return null;
  for (final kind in ReactionKind.values) {
    if (kind.wireValue == wire) return kind;
  }
  return null;
}

/// The wire-string form for the given [ReactionKind].
String reactionKindToWire(ReactionKind kind) => kind.wireValue;

/// A single reaction recorded by one viewer on one post.
///
/// The relationship between viewer and post is owned by the Kör 6
/// repository (one (post, viewer) pair ⇒ one current reaction), so
/// this entity does NOT embed a viewer identifier — only the reaction
/// itself plus the timestamp the Kör 11/13 server read-path returned.
final class CommunityReaction {
  factory CommunityReaction({
    required ReactionKind kind,
    required DateTime createdAt,
  }) {
    return CommunityReaction._(kind: kind, createdAt: createdAt);
  }

  /// Decode a record whose `kind` field is opaque on the wire. Returns
  /// `null` if the wire string is not a recognized [ReactionKind] —
  /// the data-layer call site chooses whether to swallow, log or
  /// rethrow (A3).
  static CommunityReaction? fromWire({
    required String? kind,
    required DateTime createdAt,
  }) {
    final parsed = reactionKindFromWire(kind);
    if (parsed == null) return null;
    return CommunityReaction(kind: parsed, createdAt: createdAt);
  }

  const CommunityReaction._({required this.kind, required this.createdAt});

  final ReactionKind kind;
  final DateTime createdAt;

  CommunityReaction copyWith({ReactionKind? kind, DateTime? createdAt}) {
    return CommunityReaction._(
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityReaction &&
      other.kind == kind &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(kind, createdAt);
}
