import '../domain/quests/quest_definition.dart';
import '../domain/quests/quest_objective.dart';

/// Capability values supplied by the caller for daily quest generation.
enum QuestCapability { camera, account, cloud }

/// A catalog candidate for daily quest generation.
final class DailyQuestCatalogEntry {
  DailyQuestCatalogEntry({
    required this.id,
    required this.objective,
    required this.reward,
    Set<QuestCapability> requiredCapabilities = const <QuestCapability>{},
    required this.isShort,
    required this.isRestEligible,
  }) : requiredCapabilities = Set<QuestCapability>.unmodifiable(
         requiredCapabilities,
       ) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be lower snake case');
    }
    if (objective is UnknownQuestObjective) {
      throw ArgumentError.value(objective, 'objective', 'must be supported');
    }
  }

  final String id;
  final QuestObjective objective;
  final QuestReward reward;
  final Set<QuestCapability> requiredCapabilities;
  final bool isShort;
  final bool isRestEligible;
}

/// Catalog candidates supplied to a daily quest generator.
final class DailyQuestCatalog {
  DailyQuestCatalog({required List<DailyQuestCatalogEntry> entries})
    : entries = List<DailyQuestCatalogEntry>.unmodifiable(entries) {
    final ids = entries.map((entry) => entry.id).toSet();
    if (ids.length != entries.length) {
      throw ArgumentError.value(entries, 'entries', 'must have unique IDs');
    }
  }

  const DailyQuestCatalog.empty() : entries = const <DailyQuestCatalogEntry>[];

  final List<DailyQuestCatalogEntry> entries;
}

/// Creates the local catalog used when composition has no tailored catalog.
DailyQuestCatalog defaultDailyQuestCatalog() => DailyQuestCatalog(
  entries: <DailyQuestCatalogEntry>[
    _entry('daily_rhythm', 'rhythm', isShort: true),
    _entry('daily_chords', 'chords'),
    _entry(
      'daily_camera',
      'camera',
      requiredCapabilities: const <QuestCapability>{QuestCapability.camera},
    ),
    _entry(
      'daily_account',
      'account',
      requiredCapabilities: const <QuestCapability>{QuestCapability.account},
    ),
    _entry(
      'daily_cloud',
      'cloud',
      requiredCapabilities: const <QuestCapability>{QuestCapability.cloud},
    ),
    _entry('daily_recovery', 'recovery', isShort: true, isRestEligible: true),
  ],
);

DailyQuestCatalogEntry _entry(
  String id,
  String skillTag, {
  Set<QuestCapability> requiredCapabilities = const <QuestCapability>{},
  bool isShort = false,
  bool isRestEligible = false,
}) => DailyQuestCatalogEntry(
  id: id,
  objective: SkillTagQuestObjective(skillTag),
  reward: QuestReward(baseXp: 10, bonusXp: 0, policyVersion: 1),
  requiredCapabilities: requiredCapabilities,
  isShort: isShort,
  isRestEligible: isRestEligible,
);
