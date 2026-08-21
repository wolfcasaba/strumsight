import '../domain/achievements/achievement_catalog.dart';
import '../domain/achievements/achievement_definition.dart';

/// A typed event-kind and metric route in the achievement candidate index.
final class AchievementMetricIndexKey {
  const AchievementMetricIndexKey({
    required this.eventKind,
    required this.metric,
  });

  final AchievementEventKind eventKind;
  final AchievementMetric metric;

  @override
  bool operator ==(Object other) =>
      other is AchievementMetricIndexKey &&
      eventKind == other.eventKind &&
      metric == other.metric;

  @override
  int get hashCode => Object.hash(eventKind, metric);
}

/// A typed event-kind and distinctness-dimension route in the candidate index.
final class AchievementDimensionIndexKey {
  const AchievementDimensionIndexKey({
    required this.eventKind,
    required this.dimension,
  });

  final AchievementEventKind eventKind;
  final AchievementDistinctDimension dimension;

  @override
  bool operator ==(Object other) =>
      other is AchievementDimensionIndexKey &&
      eventKind == other.eventKind &&
      dimension == other.dimension;

  @override
  int get hashCode => Object.hash(eventKind, dimension);
}

/// Maps event kinds plus their metric/dimension routes to affected definitions.
final class AchievementIndex {
  AchievementIndex(AchievementCatalog catalog)
    : _byEventKind = _buildEventKindIndex(catalog.definitions),
      _byMetric = _buildMetricIndex(catalog.definitions),
      _byDimension = _buildDimensionIndex(catalog.definitions),
      _unknownDefinitions = List<AchievementDefinition>.unmodifiable(
        catalog.definitions.where(
          (definition) => _containsUnknownObjective(definition.objectives),
        ),
      );

  final Map<AchievementEventKind, List<AchievementDefinition>> _byEventKind;
  final Map<AchievementMetricIndexKey, List<AchievementDefinition>> _byMetric;
  final Map<AchievementDimensionIndexKey, List<AchievementDefinition>>
  _byDimension;
  final List<AchievementDefinition> _unknownDefinitions;

  /// Returns every definition whose objective graph references [eventKind].
  List<AchievementDefinition> candidatesForEvent(
    AchievementEventKind eventKind,
  ) => List<AchievementDefinition>.unmodifiable(<AchievementDefinition>{
    ...?_byEventKind[eventKind],
    ..._unknownDefinitions,
  });

  /// Returns definitions on the exact [eventKind] and [metric] evidence route.
  List<AchievementDefinition> candidatesForMetric(
    AchievementEventKind eventKind,
    AchievementMetric metric,
  ) => List<AchievementDefinition>.unmodifiable(<AchievementDefinition>{
    ...?_byMetric[AchievementMetricIndexKey(
      eventKind: eventKind,
      metric: metric,
    )],
  });

  /// Returns definitions on the exact [eventKind] and [dimension] evidence route.
  List<AchievementDefinition> candidatesForDimension(
    AchievementEventKind eventKind,
    AchievementDistinctDimension dimension,
  ) => List<AchievementDefinition>.unmodifiable(<AchievementDefinition>{
    ...?_byDimension[AchievementDimensionIndexKey(
      eventKind: eventKind,
      dimension: dimension,
    )],
  });
}

Map<AchievementEventKind, List<AchievementDefinition>> _buildEventKindIndex(
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
  return _freezeIndex(mutable);
}

Map<AchievementMetricIndexKey, List<AchievementDefinition>> _buildMetricIndex(
  Iterable<AchievementDefinition> definitions,
) {
  final mutable = <AchievementMetricIndexKey, List<AchievementDefinition>>{};
  for (final definition in definitions) {
    for (final route in _metricRoutesFor(definition.objectives)) {
      mutable
          .putIfAbsent(route, () => <AchievementDefinition>[])
          .add(definition);
    }
  }
  return _freezeIndex(mutable);
}

Map<AchievementDimensionIndexKey, List<AchievementDefinition>>
_buildDimensionIndex(Iterable<AchievementDefinition> definitions) {
  final mutable = <AchievementDimensionIndexKey, List<AchievementDefinition>>{};
  for (final definition in definitions) {
    for (final route in _dimensionRoutesFor(definition.objectives)) {
      mutable
          .putIfAbsent(route, () => <AchievementDefinition>[])
          .add(definition);
    }
  }
  return _freezeIndex(mutable);
}

Map<T, List<AchievementDefinition>> _freezeIndex<T>(
  Map<T, List<AchievementDefinition>> mutable,
) => Map<T, List<AchievementDefinition>>.unmodifiable(
  <T, List<AchievementDefinition>>{
    for (final entry in mutable.entries)
      entry.key: List<AchievementDefinition>.unmodifiable(entry.value),
  },
);

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

Set<AchievementMetricIndexKey> _metricRoutesFor(
  Iterable<AchievementObjective> objectives,
) {
  final routes = <AchievementMetricIndexKey>{};
  for (final objective in objectives) {
    switch (objective) {
      case ThresholdAchievementObjective(:final eventKind, :final metric):
        routes.add(
          AchievementMetricIndexKey(eventKind: eventKind, metric: metric),
        );
      case CompoundAchievementObjective(:final objectives):
        routes.addAll(_metricRoutesFor(objectives));
      case CountAchievementObjective() ||
          DistinctAchievementObjective() ||
          SequenceAchievementObjective() ||
          UnknownAchievementObjective():
        break;
    }
  }
  return routes;
}

Set<AchievementDimensionIndexKey> _dimensionRoutesFor(
  Iterable<AchievementObjective> objectives,
) {
  final routes = <AchievementDimensionIndexKey>{};
  for (final objective in objectives) {
    switch (objective) {
      case DistinctAchievementObjective(:final eventKind, :final dimension):
        routes.add(
          AchievementDimensionIndexKey(
            eventKind: eventKind,
            dimension: dimension,
          ),
        );
      case CompoundAchievementObjective(:final objectives):
        routes.addAll(_dimensionRoutesFor(objectives));
      case CountAchievementObjective() ||
          ThresholdAchievementObjective() ||
          SequenceAchievementObjective() ||
          UnknownAchievementObjective():
        break;
    }
  }
  return routes;
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
