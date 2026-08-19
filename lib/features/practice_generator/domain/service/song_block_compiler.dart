/// Compiles per-section song-goal read outcomes into structured
/// [SongGoalBlockDraft]s the planner can consume.
///
/// The compiler is domain-pure (ADR 0255):
///   * it never reads a clock,
///   * it never generates randomness,
///   * it never imports Song Trainer internals,
///   * it never mutates its inputs.
///
/// The compile step answers the "what does this section need?" half of the
/// planning problem: per-section skill targets, per-section prerequisites
/// (skills that must already be on the plan BEFORE the section block —
/// ADR 0264 §4 prerequisite-boost), and a bounded, deterministic minute
/// budget derived from the section's structural span. The phase
/// classification (foundation / integration / simulation) and the
/// target-date gating live in the planner — this layer only translates
/// structural facts into planning inputs.
library;

import '../../data/adapter/song_goal_reader_adapter.dart';

/// One song section, expressed in the practice-planning vocabulary.
///
/// A draft carries the structural facts the planner needs (skill targets,
/// prerequisite skill ids, bounded minute budget, ordered position) but
/// nothing about the song target date or the weekly plan — those belong to
/// [SongGoalPlanner].
final class SongGoalBlockDraft {
  SongGoalBlockDraft({
    required this.sectionView,
    required Iterable<String> targetSkillIds,
    required Iterable<String> prerequisiteSkillIds,
    required this.estimatedMinutes,
  }) : targetSkillIds = List<String>.unmodifiable(targetSkillIds),
       prerequisiteSkillIds = List<String>.unmodifiable(prerequisiteSkillIds) {
    if (estimatedMinutes <= 0) {
      throw ArgumentError.value(
        estimatedMinutes,
        'estimatedMinutes',
        'must be positive',
      );
    }
  }

  /// The reader projection this draft was compiled from.
  final SongGoalSectionView sectionView;

  /// Skills this section trains. The planner tags these as primary focus
  /// candidates on the block.
  final List<String> targetSkillIds;

  /// Skills the section depends on (must already be on the plan). The
  /// planner routes prerequisite blocks strictly BEFORE the section block
  /// (ADR 0264 §4).
  final List<String> prerequisiteSkillIds;

  /// Bounded, deterministic minute budget derived from the section's
  /// measure span. Never zero — a section is, by definition, a non-empty
  /// structural unit.
  final int estimatedMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongGoalBlockDraft &&
          other.sectionView == sectionView &&
          _listEquals(other.targetSkillIds, targetSkillIds) &&
          _listEquals(other.prerequisiteSkillIds, prerequisiteSkillIds) &&
          other.estimatedMinutes == estimatedMinutes;

  @override
  int get hashCode => Object.hash(
    sectionView,
    Object.hashAll(targetSkillIds),
    Object.hashAll(prerequisiteSkillIds),
    estimatedMinutes,
  );
}

/// Caller-fed specification the compiler needs to translate a section
/// into a draft.
///
/// The compiler is a pure function: it does not consult any repository or
/// catalog. The caller (a future wiring round) is responsible for deciding
/// which skill ids a section trains and which skills it depends on.
/// Today the [SongGoalPlanner] calls [compile] with a single, caller-fed
/// [SongGoalBlockSpecProvider].
final class SongGoalBlockSpec {
  SongGoalBlockSpec({
    required Iterable<String> targetSkillIds,
    required Iterable<String> prerequisiteSkillIds,
    required this.estimatedMinutes,
  }) : targetSkillIds = List<String>.unmodifiable(targetSkillIds),
       prerequisiteSkillIds = List<String>.unmodifiable(prerequisiteSkillIds) {
    if (estimatedMinutes <= 0) {
      throw ArgumentError.value(
        estimatedMinutes,
        'estimatedMinutes',
        'must be positive',
      );
    }
  }

  /// The skill ids this section trains. May be empty for a section that
  /// carries no training content — the planner treats it as a "no-target"
  /// block and routes it as supporting material.
  final List<String> targetSkillIds;

  /// Skills the section depends on (must precede the block).
  final List<String> prerequisiteSkillIds;

  /// Caller-supplied minute budget for one run of the block. The compiler
  /// uses this directly so the planner never invents minutes for a
  /// section it cannot size (ADR 0262 §5).
  final int estimatedMinutes;
}

/// Strategy the planner hands to the compiler to look up the
/// section-by-section spec. Pure function — no I/O, no clock, no random.
typedef SongGoalBlockSpecProvider =
    SongGoalBlockSpec? Function(SongGoalSectionView view);

/// Pure compile step for one [SongGoalReadSuccess] outcome.
final class SongBlockCompiler {
  const SongBlockCompiler();

  /// Compile [read] into one [SongGoalBlockDraft] per section.
  ///
  /// Sections whose [SongGoalBlockSpecProvider] returns `null` are
  /// emitted as "unspecified" drafts the planner can route to the
  /// unavailable branch. Sections are emitted in the structural order of
  /// the source document — the planner is the one that decides where
  /// each block lands in the week.
  List<SongGoalBlockDraft> compile({
    required SongGoalReadSuccess read,
    required SongGoalBlockSpecProvider specFor,
  }) {
    final drafts = <SongGoalBlockDraft>[];
    for (final section in read.sections) {
      final spec = specFor(section);
      if (spec == null) {
        drafts.add(
          SongGoalBlockDraft(
            sectionView: section,
            targetSkillIds: const <String>[],
            prerequisiteSkillIds: const <String>[],
            // A positive, explicit "no spec" minute budget — the planner
            // routes the block as a structural placeholder, never as a
            // silent skip (ADR 0318 §Döntés 2).
            estimatedMinutes: 1,
          ),
        );
        continue;
      }
      drafts.add(
        SongGoalBlockDraft(
          sectionView: section,
          targetSkillIds: spec.targetSkillIds,
          prerequisiteSkillIds: spec.prerequisiteSkillIds,
          estimatedMinutes: spec.estimatedMinutes,
        ),
      );
    }
    return List<SongGoalBlockDraft>.unmodifiable(drafts);
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
