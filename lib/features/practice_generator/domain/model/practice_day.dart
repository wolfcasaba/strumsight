/// One immutable local-calendar day in an adaptive practice plan.
library;

import '../id/planner_ids.dart';
import 'practice_block.dart';
import 'weekly_availability.dart';

final class PracticeDay {
  PracticeDay({
    required this.id,
    required this.localDate,
    required this.status,
    required this.timeBudget,
    required Iterable<PracticeBlock> blocks,
    required Iterable<String> primaryFocusSkillIds,
    required Iterable<String> reasonCodes,
  }) : blocks = List<PracticeBlock>.unmodifiable(blocks),
       primaryFocusSkillIds = _codes(
         primaryFocusSkillIds,
         'primaryFocusSkillIds',
       ),
       reasonCodes = _codes(reasonCodes, 'reasonCodes') {
    if (timeBudget <= Duration.zero) {
      throw ArgumentError.value(timeBudget, 'timeBudget', 'must be positive');
    }
    final ids = <BlockId>{};
    if (!this.blocks.every((block) => ids.add(block.id))) {
      throw ArgumentError.value(blocks, 'blocks', 'must have unique IDs');
    }
  }

  final DayId id;
  final LocalDate localDate;
  final PracticeItemStatus status;
  final Duration timeBudget;
  final List<PracticeBlock> blocks;
  final List<String> primaryFocusSkillIds;
  final List<String> reasonCodes;

  bool canTransitionTo(PracticeItemStatus next) => switch (status) {
    PracticeItemStatus.planned =>
      next == PracticeItemStatus.ready ||
          next == PracticeItemStatus.inProgress ||
          next == PracticeItemStatus.substituted ||
          next == PracticeItemStatus.unavailable ||
          next == PracticeItemStatus.skipped ||
          next == PracticeItemStatus.expired,
    PracticeItemStatus.ready =>
      next == PracticeItemStatus.inProgress ||
          next == PracticeItemStatus.substituted ||
          next == PracticeItemStatus.unavailable ||
          next == PracticeItemStatus.skipped ||
          next == PracticeItemStatus.expired,
    PracticeItemStatus.inProgress =>
      next == PracticeItemStatus.completed ||
          next == PracticeItemStatus.skipped ||
          next == PracticeItemStatus.substituted ||
          next == PracticeItemStatus.unavailable,
    PracticeItemStatus.completed ||
    PracticeItemStatus.skipped ||
    PracticeItemStatus.substituted ||
    PracticeItemStatus.unavailable ||
    PracticeItemStatus.expired => false,
  };

  PracticeDay transitionTo(PracticeItemStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError(
        'Cannot transition day $id from ${status.code} to ${next.code}',
      );
    }
    return PracticeDay(
      id: id,
      localDate: localDate,
      status: next,
      timeBudget: timeBudget,
      blocks: blocks,
      primaryFocusSkillIds: primaryFocusSkillIds,
      reasonCodes: reasonCodes,
    );
  }

  /// Replaces future content; a completed day is immutable within a revision.
  PracticeDay replaceContent({
    Duration? timeBudget,
    Iterable<PracticeBlock>? blocks,
    Iterable<String>? primaryFocusSkillIds,
    Iterable<String>? reasonCodes,
  }) {
    if (status == PracticeItemStatus.completed) {
      throw StateError('Completed day $id cannot be modified in this revision');
    }
    return PracticeDay(
      id: id,
      localDate: localDate,
      status: status,
      timeBudget: timeBudget ?? this.timeBudget,
      blocks: blocks ?? this.blocks,
      primaryFocusSkillIds: primaryFocusSkillIds ?? this.primaryFocusSkillIds,
      reasonCodes: reasonCodes ?? this.reasonCodes,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.toJson(),
    'localDate': <String, int>{
      'year': localDate.year,
      'month': localDate.month,
      'day': localDate.day,
    },
    'status': status.code,
    'timeBudgetMicros': timeBudget.inMicroseconds,
    'blocks': [for (final block in blocks) block.toJson()],
    'primaryFocusSkillIds': primaryFocusSkillIds,
    'reasonCodes': reasonCodes,
  };

  static PracticeDay fromJson(
    Map<String, Object?> json, {
    required ExerciseCandidateResolver resolveCandidate,
  }) {
    final date = _object(json['localDate'], 'localDate');
    final rawBlocks = _list(json['blocks'], 'blocks');
    return PracticeDay(
      id: DayId.fromJson(json['id']),
      localDate: LocalDate(
        _integer(date['year'], 'localDate.year'),
        _integer(date['month'], 'localDate.month'),
        _integer(date['day'], 'localDate.day'),
      ),
      status: PracticeItemStatus.fromCode(_text(json['status'], 'status')),
      timeBudget: Duration(
        microseconds: _integer(json['timeBudgetMicros'], 'timeBudgetMicros'),
      ),
      blocks: [
        for (final block in rawBlocks)
          PracticeBlock.fromJson(
            _object(block, 'blocks[]'),
            resolveCandidate: resolveCandidate,
          ),
      ],
      primaryFocusSkillIds: _textList(
        json['primaryFocusSkillIds'],
        'primaryFocusSkillIds',
      ),
      reasonCodes: _textList(json['reasonCodes'], 'reasonCodes'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeDay &&
          id == other.id &&
          localDate == other.localDate &&
          status == other.status &&
          timeBudget == other.timeBudget &&
          _sameList(blocks, other.blocks) &&
          _sameList(primaryFocusSkillIds, other.primaryFocusSkillIds) &&
          _sameList(reasonCodes, other.reasonCodes);

  @override
  int get hashCode => Object.hash(
    id,
    localDate,
    status,
    timeBudget,
    Object.hashAll(blocks),
    Object.hashAll(primaryFocusSkillIds),
    Object.hashAll(reasonCodes),
  );
}

List<String> _codes(Iterable<String> values, String name) {
  final result = values
      .map((value) => _text(value, name))
      .toList(growable: false);
  if (result.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
  return List<String>.unmodifiable(result);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) {
    throw ArgumentError.value(value, name, 'must be an object');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String name) {
  if (value is! List) {
    throw ArgumentError.value(value, name, 'must be a list');
  }
  return List<Object?>.from(value);
}

String _text(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must be a non-empty String');
  }
  return value.trim();
}

int _integer(Object? value, String name) {
  if (value is! num || value.toInt() != value) {
    throw ArgumentError.value(value, name, 'must be an integer');
  }
  return value.toInt();
}

List<String> _textList(Object? value, String name) {
  if (value is! List) {
    throw ArgumentError.value(value, name, 'must be a list');
  }
  return [for (final item in value) _text(item, name)];
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
