import 'package:flutter/material.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_definition.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_progress.dart';
import 'package:strumsight/features/gamification/presentation/widgets/achievement_tile.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/l10n/app_localizations.dart';

enum AchievementListFilter { all, unlocked, inProgress, category }

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    super.key,
    required this.definitions,
    required this.progressByAchievement,
    required this.onAchievementSelected,
  });

  final List<AchievementDefinition> definitions;
  final Map<String, AchievementProgress> progressByAchievement;
  final ValueChanged<String> onAchievementSelected;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  AchievementListFilter _filter = AchievementListFilter.all;
  AchievementCategory? _category;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = _visibleDefinitions();
    return GamificationThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.achievementsTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip(
                    key: const Key('achievement-filter-all'),
                    label: l10n.achievementFilterAll,
                    filter: AchievementListFilter.all,
                  ),
                  _filterChip(
                    key: const Key('achievement-filter-unlocked'),
                    label: l10n.achievementFilterUnlocked,
                    filter: AchievementListFilter.unlocked,
                  ),
                  _filterChip(
                    key: const Key('achievement-filter-in-progress'),
                    label: l10n.achievementFilterInProgress,
                    filter: AchievementListFilter.inProgress,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(l10n.achievementFilterCategory),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _filterableCategories
                    .map(
                      (category) => ChoiceChip(
                        key: Key(
                          'achievement-filter-category-${category.name}',
                        ),
                        label: Text(
                          localizedAchievementCategory(l10n, category),
                        ),
                        selected:
                            _filter == AchievementListFilter.category &&
                            _category == category,
                        onSelected: (_) => setState(() {
                          _filter = AchievementListFilter.category;
                          _category = category;
                        }),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              if (visible.isEmpty)
                _EmptyAchievementsState()
              else
                for (final definition in visible) ...[
                  AchievementTile(
                    definition: definition,
                    progress: widget.progressByAchievement[definition.id],
                    onSelected: widget.onAchievementSelected,
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }

  ChoiceChip _filterChip({
    required Key key,
    required String label,
    required AchievementListFilter filter,
  }) => ChoiceChip(
    key: key,
    label: Text(label),
    selected: _filter == filter,
    onSelected: (_) => setState(() {
      _filter = filter;
      _category = null;
    }),
  );

  List<AchievementDefinition> _visibleDefinitions() => widget.definitions
      .where((definition) {
        final progress = widget.progressByAchievement[definition.id];
        final unlocked = achievementIsUnlocked(progress);
        if (definition.hidden && !unlocked) {
          return _filter == AchievementListFilter.all;
        }
        return switch (_filter) {
          AchievementListFilter.all => true,
          AchievementListFilter.unlocked => unlocked,
          AchievementListFilter.inProgress =>
            !unlocked && (progress?.value ?? 0) > 0,
          AchievementListFilter.category => definition.category == _category,
        };
      })
      .toList(growable: false);
}

const _filterableCategories = <AchievementCategory>[
  AchievementCategory.consistency,
  AchievementCategory.practice,
  AchievementCategory.songs,
  AchievementCategory.rhythm,
  AchievementCategory.chords,
  AchievementCategory.technique,
  AchievementCategory.analysis,
  AchievementCategory.exploration,
  AchievementCategory.personalBest,
];

class _EmptyAchievementsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.emoji_events_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              l10n.achievementEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.achievementEmptyBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
