import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/debrief_fact.dart';
import '../../domain/models/student_profile.dart';
import '../../domain/models/tutor_source_ref.dart';

/// Presentation-only provenance values used by tutor evidence widgets.
enum TutorEvidenceKind { measured, trend, knowledge, inference }

TutorEvidenceKind evidenceKindForDebriefProvenance(
  DebriefFactProvenance provenance,
) => switch (provenance) {
  DebriefFactProvenance.measuredFact => TutorEvidenceKind.measured,
  DebriefFactProvenance.computedTrend => TutorEvidenceKind.trend,
};

TutorEvidenceKind evidenceKindForSource(TutorSourceRef source) {
  return TutorEvidenceKind.knowledge;
}

TutorEvidenceKind? evidenceKindForProfileProvenance(
  StudentProfileFieldProvenance provenance,
) => switch (provenance) {
  StudentProfileFieldProvenance.practiceInferred ||
  StudentProfileFieldProvenance.songInferred => TutorEvidenceKind.inference,
  StudentProfileFieldProvenance.userExplicit ||
  StudentProfileFieldProvenance.settingsImported ||
  StudentProfileFieldProvenance.systemDefault => null,
};

String tutorEvidenceLabel(AppLocalizations l10n, TutorEvidenceKind kind) =>
    switch (kind) {
      TutorEvidenceKind.measured => l10n.aiTutorEvidenceMeasured,
      TutorEvidenceKind.trend => l10n.aiTutorEvidenceTrend,
      TutorEvidenceKind.knowledge => l10n.aiTutorEvidenceKnowledge,
      TutorEvidenceKind.inference => l10n.aiTutorEvidenceInference,
    };

IconData tutorEvidenceIcon(TutorEvidenceKind kind) => switch (kind) {
  TutorEvidenceKind.measured => Icons.analytics_outlined,
  TutorEvidenceKind.trend => Icons.trending_up,
  TutorEvidenceKind.knowledge => Icons.menu_book_outlined,
  TutorEvidenceKind.inference => Icons.psychology_alt_outlined,
};

Color tutorEvidenceColor(BuildContext context, TutorEvidenceKind kind) {
  final scheme = Theme.of(context).colorScheme;
  return switch (kind) {
    TutorEvidenceKind.measured => scheme.primary,
    TutorEvidenceKind.trend => scheme.tertiary,
    TutorEvidenceKind.knowledge => scheme.secondary,
    TutorEvidenceKind.inference => scheme.error,
  };
}

class TutorEvidenceChip extends StatelessWidget {
  const TutorEvidenceChip({super.key, required this.kind, this.onPressed});

  final TutorEvidenceKind kind;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = tutorEvidenceLabel(l10n, kind);
    final color = tutorEvidenceColor(context, kind);
    final onColor = switch (kind) {
      TutorEvidenceKind.measured => Theme.of(context).colorScheme.onPrimary,
      TutorEvidenceKind.trend => Theme.of(context).colorScheme.onTertiary,
      TutorEvidenceKind.knowledge => Theme.of(context).colorScheme.onSecondary,
      TutorEvidenceKind.inference => Theme.of(context).colorScheme.onError,
    };

    return Semantics(
      container: true,
      button: onPressed != null,
      label: l10n.aiTutorEvidenceChipSemantics(label),
      child: ActionChip(
        key: const ValueKey('tutor-evidence-chip'),
        onPressed: onPressed,
        backgroundColor: color,
        avatar: Icon(tutorEvidenceIcon(kind), color: onColor, size: 18),
        label: Text(label),
        labelStyle: TextStyle(color: onColor),
      ),
    );
  }
}
