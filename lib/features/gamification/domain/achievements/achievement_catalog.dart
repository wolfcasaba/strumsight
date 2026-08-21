import 'achievement_definition.dart';

/// Locale key sets supplied by the composition layer or a test, never read by domain I/O.
final class AchievementLocalizedKeys {
  AchievementLocalizedKeys({
    required Set<String> english,
    required Set<String> hungarian,
  }) : english = Set<String>.unmodifiable(english),
       hungarian = Set<String>.unmodifiable(hungarian);

  final Set<String> english;
  final Set<String> hungarian;
}

/// Stable validation codes for catalog evidence and diagnostics.
enum AchievementCatalogValidationCode {
  catalogSizeOutOfRange,
  duplicateId,
  unknownObjective,
  missingTierPrerequisite,
  tierCycle,
  missingLocalizationKey,
  contentVersionNotIncreased,
}

/// Typed result of validating one catalog.
final class AchievementCatalogValidationReport {
  AchievementCatalogValidationReport(
    Iterable<AchievementCatalogValidationCode> codes,
  ) : codes = Set<AchievementCatalogValidationCode>.unmodifiable(codes);

  final Set<AchievementCatalogValidationCode> codes;

  bool get isValid => codes.isEmpty;
}

/// Immutable, versioned collection of achievement definitions.
final class AchievementCatalog {
  AchievementCatalog({
    required this.contentVersion,
    required List<AchievementDefinition> definitions,
  }) : definitions = List<AchievementDefinition>.unmodifiable(definitions) {
    if (contentVersion < 1) {
      throw ArgumentError.value(
        contentVersion,
        'contentVersion',
        'must be positive',
      );
    }
  }

  final int contentVersion;
  final List<AchievementDefinition> definitions;

  AchievementCatalogValidationReport validate({
    required AchievementLocalizedKeys localizedKeys,
    AchievementCatalog? previousCatalog,
  }) {
    final codes = <AchievementCatalogValidationCode>{};
    if (definitions.length < 20 || definitions.length > 30) {
      codes.add(AchievementCatalogValidationCode.catalogSizeOutOfRange);
    }

    final ids = <String>{};
    for (final definition in definitions) {
      if (!ids.add(definition.id)) {
        codes.add(AchievementCatalogValidationCode.duplicateId);
      }
      if (_hasUnknownObjective(definition.objectives)) {
        codes.add(AchievementCatalogValidationCode.unknownObjective);
      }
      for (final key in <String>[
        definition.titleKey,
        definition.descriptionKey,
        definition.accessibilityDescriptionKey,
      ]) {
        if (!localizedKeys.english.contains(key) ||
            !localizedKeys.hungarian.contains(key)) {
          codes.add(AchievementCatalogValidationCode.missingLocalizationKey);
        }
      }
    }

    final definitionsById = <String, AchievementDefinition>{
      for (final definition in definitions) definition.id: definition,
    };
    for (final definition in definitions) {
      for (final prerequisiteId in definition.tierPrerequisiteIds) {
        if (!definitionsById.containsKey(prerequisiteId)) {
          codes.add(AchievementCatalogValidationCode.missingTierPrerequisite);
        }
      }
    }
    if (_containsTierCycle(definitionsById)) {
      codes.add(AchievementCatalogValidationCode.tierCycle);
    }

    if (previousCatalog != null &&
        previousCatalog.definitions.length != definitions.length &&
        contentVersion <= previousCatalog.contentVersion) {
      codes.add(AchievementCatalogValidationCode.contentVersionNotIncreased);
    }
    return AchievementCatalogValidationReport(codes);
  }
}

bool _hasUnknownObjective(Iterable<AchievementObjective> objectives) {
  for (final objective in objectives) {
    switch (objective) {
      case UnknownAchievementObjective():
        return true;
      case CompoundAchievementObjective(:final objectives):
        if (_hasUnknownObjective(objectives)) return true;
      case CountAchievementObjective() ||
          ThresholdAchievementObjective() ||
          DistinctAchievementObjective() ||
          SequenceAchievementObjective():
        break;
    }
  }
  return false;
}

bool _containsTierCycle(Map<String, AchievementDefinition> definitionsById) {
  final visiting = <String>{};
  final visited = <String>{};

  bool visit(String id) {
    if (!visited.add(id)) return false;
    visiting.add(id);
    for (final prerequisiteId in definitionsById[id]!.tierPrerequisiteIds) {
      if (!definitionsById.containsKey(prerequisiteId)) continue;
      if (visiting.contains(prerequisiteId) || visit(prerequisiteId)) {
        return true;
      }
    }
    visiting.remove(id);
    return false;
  }

  return definitionsById.keys.any(visit);
}
