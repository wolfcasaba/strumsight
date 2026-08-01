/// One tappable card representing a [PracticeDefinition] in the Hub list
/// (E02-R12, A1/A8).
///
/// The card is a pure presentation widget: it reads a definition, renders
/// its display text + a localized mode label, and exposes an `onTap`. It
/// carries no business logic — no scoring, no matcher, no clock — and the
/// A9 guard asserts this. The semantic label and the tap action are on
/// the same node (the r130 lesson: a label without a tap action is a
/// half-broken control).
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_definition.dart';
import '../../domain/model/practice_mode.dart';

/// The localized human label for a [PracticeMode] (SDD §22.3). The enum's
/// `code` is the persisted identifier; the user-facing label is here.
String practiceModeLabel(AppLocalizations l10n, PracticeMode mode) {
  switch (mode) {
    case PracticeMode.strumPattern:
      return l10n.practiceHubModeStrumPattern;
    case PracticeMode.chordChanges:
      return l10n.practiceHubModeChordChanges;
    case PracticeMode.chordProgression:
      return l10n.practiceHubModeChordProgression;
    case PracticeMode.rhythmOnly:
      return l10n.practiceHubModeRhythmOnly;
    case PracticeMode.freePractice:
      return l10n.practiceHubModeFreePractice;
  }
}

/// The display title of a [PracticeDefinition] for the Hub list.
///
/// The domain contract is `displayTitle ?? l10n(titleKey)`. The catalog
/// shipped today declares only `titleKey`; the ARB has no practice keys
/// in this round. To avoid showing an empty cell, fall back to the
/// definition's stable id as a last resort. The id is always present and
/// is part of the persisted contract.
String practiceDefinitionDisplayTitle(
  AppLocalizations l10n,
  PracticeDefinition definition,
) {
  final display = definition.displayTitle;
  if (display != null && display.trim().isNotEmpty) return display;
  // Title-key lookup is best-effort: a missing key returns a blank string,
  // which would render an empty card. Fall through to the stable id.
  final localized = _lookupLocalized(l10n, definition.titleKey);
  if (localized != null && localized.isNotEmpty) return localized;
  return definition.id;
}

/// Best-effort lookup of an ARB key on the [AppLocalizations] instance.
/// The generated class has a getter per declared key — we cannot enumerate
/// them at runtime, so we use a small switch over the keys this app
/// actually uses. Anything else returns `null` (and the caller falls back
/// to the id).
String? _lookupLocalized(AppLocalizations l10n, String key) {
  switch (key) {
    case 'practiceCatalogQuarterDownstrokesTitle':
      return l10n.practiceCatalogQuarterDownstrokesTitle;
    case 'practiceCatalogAlternatingEighthsTitle':
      return l10n.practiceCatalogAlternatingEighthsTitle;
    case 'practiceCatalogFolkPatternTitle':
      return l10n.practiceCatalogFolkPatternTitle;
    case 'practiceCatalogGToDChangesTitle':
      return l10n.practiceCatalogGToDChangesTitle;
    case 'practiceCatalogEmToCChangesTitle':
      return l10n.practiceCatalogEmToCChangesTitle;
    case 'practiceCatalogCGAmFProgressionTitle':
      return l10n.practiceCatalogCGAmFProgressionTitle;
    case 'practiceCatalogFirstWaltzTitle':
      return l10n.practiceCatalogFirstWaltzTitle;
    case 'practiceCatalogSyncopatedUpsTitle':
      return l10n.practiceCatalogSyncopatedUpsTitle;
    case 'practiceCatalogRhythmOnlyQuartersTitle':
      return l10n.practiceCatalogRhythmOnlyQuartersTitle;
    case 'practiceCatalogFreePracticeTemplateTitle':
      return l10n.practiceCatalogFreePracticeTemplateTitle;
    case 'practiceSourceDailyChallengeTitle':
      return l10n.practiceSourceDailyChallengeTitle;
    case 'practiceSourceLessonTitle':
      return l10n.practiceSourceLessonTitle;
    case 'practiceSourceSongTitle':
      return l10n.practiceSourceSongTitle;
    case 'practiceSourceAnalyzeTitle':
      return l10n.practiceSourceAnalyzeTitle;
  }
  return null;
}

/// A tappable card showing one [PracticeDefinition]. The semantic node
/// exposes BOTH the title and the tap action in a single accessibility
/// boundary (the r130 B1 lesson: a label without a tap is half-broken).
class PracticeModeCard extends StatelessWidget {
  const PracticeModeCard({
    super.key,
    required this.definition,
    required this.onTap,
  });

  final PracticeDefinition definition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = practiceDefinitionDisplayTitle(l10n, definition);
    final modeLabel = practiceModeLabel(l10n, definition.mode);

    return Semantics(
      container: true,
      button: true,
      label: l10n.practiceHubOpenSetup(title),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              // ExcludeSemantics blocks the descendant Text from being
              // merged into the parent label — see _HubCard for the
              // full justification.
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    const _CardGlyph(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            modeLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardGlyph extends StatelessWidget {
  const _CardGlyph();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_outlined, size: 22, color: color),
    );
  }
}
