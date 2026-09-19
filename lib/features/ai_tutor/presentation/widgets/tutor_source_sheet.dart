import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/tutor_source_ref.dart';
import 'tutor_evidence_chip.dart';

String sanitizeTutorDisplayText(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (_isControlRune(rune)) {
      buffer.write(' ');
    } else if (rune == 60) {
      buffer.write('‹');
    } else if (rune == 62) {
      buffer.write('›');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _isControlRune(int rune) =>
    (rune >= 0 && rune <= 31) ||
    rune == 127 ||
    (rune >= 0x202a && rune <= 0x202e) ||
    (rune >= 0x2066 && rune <= 0x2069);

class TutorSourceSheet extends StatelessWidget {
  const TutorSourceSheet({
    super.key,
    required this.kind,
    this.source,
    this.evidenceId,
    this.metric,
    this.trendWindow,
    this.sourceTitle,
  });

  factory TutorSourceSheet.forSource(TutorSourceRef source) =>
      TutorSourceSheet(kind: TutorEvidenceKind.knowledge, source: source);

  /// The sheet a `TutorSourceBlock` inside a chat bubble opens (M13,
  /// R33).
  ///
  /// A rendered source block carries only a display title and a
  /// reference string — NOT the full [TutorSourceRef] the retrieval
  /// layer produces. Fabricating a `TutorSourceRef` here would invent a
  /// locale, a topic, a knowledge version and a chunk hash the message
  /// never carried, so the block's two real fields get their own path
  /// instead.
  factory TutorSourceSheet.forSourceBlock({
    required String title,
    required String reference,
  }) => TutorSourceSheet(
    kind: TutorEvidenceKind.knowledge,
    sourceTitle: title,
    evidenceId: reference,
  );

  final TutorEvidenceKind kind;
  final TutorSourceRef? source;
  final String? evidenceId;
  final String? metric;
  final String? trendWindow;

  /// Display title of the source block that opened this sheet, when the
  /// caller has no [TutorSourceRef]. Rendered with the SAME
  /// `aiTutorSourceTitle` string the [source] section uses.
  final String? sourceTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = tutorEvidenceLabel(l10n, kind);
    final color = tutorEvidenceColor(context, kind);
    final source = this.source;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(tutorEvidenceIcon(kind), color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.aiTutorEvidenceDetailsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.aiTutorSourceClose,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.aiTutorEvidenceDetailsKind(label)),
            const SizedBox(height: 12),
            Text(_bodyForKind(l10n, kind)),
            if (kind == TutorEvidenceKind.inference) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.aiTutorEvidenceInferenceWarning,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (sourceTitle != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                l10n.aiTutorSourceTitle(sanitizeTutorDisplayText(sourceTitle!)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            if (evidenceId != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                l10n.aiTutorEvidenceReference(
                  sanitizeTutorDisplayText(evidenceId!),
                ),
              ),
            ],
            if (metric != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.aiTutorEvidenceMetric(sanitizeTutorDisplayText(metric!)),
              ),
            ],
            if (trendWindow != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.aiTutorEvidenceTrendWindow(
                  sanitizeTutorDisplayText(trendWindow!),
                ),
              ),
            ],
            if (kind == TutorEvidenceKind.knowledge &&
                source != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                l10n.aiTutorSourceTitle(sanitizeTutorDisplayText(source.title)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.aiTutorSourceTopic(sanitizeTutorDisplayText(source.topic)),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.aiTutorSourceLocale(
                  sanitizeTutorDisplayText(source.locale),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.aiTutorSourceVersion(
                  source.knowledgeVersion,
                  source.chunkId,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _bodyForKind(AppLocalizations l10n, TutorEvidenceKind kind) =>
      switch (kind) {
        TutorEvidenceKind.measured => l10n.aiTutorEvidenceMeasuredBody,
        TutorEvidenceKind.trend => l10n.aiTutorEvidenceTrendBody,
        TutorEvidenceKind.knowledge => l10n.aiTutorEvidenceKnowledgeBody,
        TutorEvidenceKind.inference => l10n.aiTutorEvidenceInferenceBody,
      };
}

Future<void> showTutorSourceSheet(
  BuildContext context,
  TutorSourceSheet sheet,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => sheet,
  );
}
