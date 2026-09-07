import '../../../l10n/app_localizations.dart';
import '../domain/model/practice_category.dart';

/// Localized label for one [PracticeCategory].
///
/// Mirrors `practiceModeLabel`'s shape (a plain function, not a widget) so
/// both the Practice Area Hub's category chips and the catalog list's own
/// heading resolve the SAME string — the chip and the screen it opens can
/// never disagree about a category's name. Reuses the already-shipped
/// `practiceAreaHubCategory*` keys instead of adding a second set.
String practiceCategoryLabel(AppLocalizations l10n, PracticeCategory category) {
  switch (category) {
    case PracticeCategory.warmup:
      return l10n.practiceAreaHubCategoryWarmup;
    case PracticeCategory.chords:
      return l10n.practiceAreaHubCategoryChords;
    case PracticeCategory.rhythm:
      return l10n.practiceAreaHubCategoryRhythm;
    case PracticeCategory.scales:
      return l10n.practiceAreaHubCategoryScales;
    case PracticeCategory.technique:
      return l10n.practiceAreaHubCategoryTechnique;
  }
}
