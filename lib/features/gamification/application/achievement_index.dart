import '../domain/achievements/achievement_catalog.dart';
import '../domain/achievements/achievement_definition.dart';

/// Maps an event kind to just the achievement definitions it can affect.
final class AchievementIndex {
  AchievementIndex(AchievementCatalog catalog)
    : _byEventKind = _buildIndex(catalog.definitions),
      _unknownDefinitions = List<AchievementDefinition>.unmodifiable(
        catalog.definitions.where(
          (definition) => _containsUnknownObjective(definition.objectives),
        ),
      );

  final Map<AchievementEventKind, List<AchievementDefinition>> _byEventKind;
  final List<AchievementDefinition> _unknownDefinitions;

  /// Returns the definitions whose objective graph references [eventKind].
  List<AchievementDefinition> candidatesFor(AchievementEventKind eventKind) =>
      List<AchievementDefinition>.unmodifiable(<AchievementDefinition>{
        ...?_byEventKind[eventKind],
        ..._unknownDefinitions,
      });
}

Map<AchievementEventKind, List<AchievementDefinition>> _buildIndex(
  Iterable<AchievementDefinition> definitions,
) {
  final mutable = <AchievementEventKind, List<AchievementDefinition>>{};
  for (final definition in definitions) {
    for (final eventKind in _eventKindsFor(definition.objectives)) {
      mutable
          .putIfAbsent(eventKind, () => <AchievementDefinition>[])
          .add(definition);
    }
  }
  return Map<AchievementEventKind, List<AchievementDefinition>>.unmodifiable(
    <AchievementEventKind, List<AchievementDefinition>>{
      for (final entry in mutable.entries)
        entry.key: List<AchievementDefinition>.unmodifiable(entry.value),
    },
  );
}

Set<AchievementEventKind> _eventKindsFor(
  Iterable<AchievementObjective> objectives,
) {
  final kinds = <AchievementEventKind>{};
  for (final objective in objectives) {
    switch (objective) {
      case CountAchievementObjective(:final eventKind) ||
          ThresholdAchievementObjective(:final eventKind) ||
          DistinctAchievementObjective(:final eventKind):
        kinds.add(eventKind);
      case SequenceAchievementObjective(:final eventKinds):
        kinds.addAll(eventKinds);
      case CompoundAchievementObjective(:final objectives):
        kinds.addAll(_eventKindsFor(objectives));
      case UnknownAchievementObjective():
        break;
    }
  }
  return kinds;
}

bool _containsUnknownObjective(Iterable<AchievementObjective> objectives) {
  for (final objective in objectives) {
    switch (objective) {
      case UnknownAchievementObjective():
        return true;
      case CompoundAchievementObjective(:final objectives):
        if (_containsUnknownObjective(objectives)) return true;
      case CountAchievementObjective() ||
          ThresholdAchievementObjective() ||
          DistinctAchievementObjective() ||
          SequenceAchievementObjective():
        break;
    }
  }
  return false;
}
