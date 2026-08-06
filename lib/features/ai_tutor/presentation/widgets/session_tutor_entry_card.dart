import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/context/tutor_context_snapshot.dart';

enum SessionTutorEntryAvailability {
  available,
  deterministicFallback,
  deletedResult,
  versionMismatch,
}

/// Immutable handoff from a result surface into an editable tutor chat draft.
final class SessionTutorEntryRequest {
  const SessionTutorEntryRequest({
    required this.contextSnapshot,
    required this.prefilledQuestion,
  });

  final TutorContextSnapshot contextSnapshot;
  final String prefilledQuestion;
}

class SessionTutorEntryCard extends StatefulWidget {
  const SessionTutorEntryCard({
    super.key,
    required this.availability,
    required this.contextSnapshot,
    required this.prefilledQuestion,
    this.onOpenTutor,
    this.onOpenDeterministicDebrief,
    this.onStartSuggestedPractice,
  });

  final SessionTutorEntryAvailability availability;
  final TutorContextSnapshot? contextSnapshot;
  final String prefilledQuestion;
  final ValueChanged<SessionTutorEntryRequest>? onOpenTutor;
  final VoidCallback? onOpenDeterministicDebrief;
  final VoidCallback? onStartSuggestedPractice;

  @override
  State<SessionTutorEntryCard> createState() => _SessionTutorEntryCardState();
}

class _SessionTutorEntryCardState extends State<SessionTutorEntryCard> {
  late final TextEditingController _questionController;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.prefilledQuestion);
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  void _openTutor() {
    final snapshot = widget.contextSnapshot;
    final onOpenTutor = widget.onOpenTutor;
    if (snapshot == null || onOpenTutor == null) return;
    onOpenTutor(
      SessionTutorEntryRequest(
        contextSnapshot: snapshot,
        prefilledQuestion: _questionController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('session-tutor-entry-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (widget.availability) {
          SessionTutorEntryAvailability.available => _available(l10n),
          SessionTutorEntryAvailability.deterministicFallback =>
            _deterministicFallback(l10n),
          SessionTutorEntryAvailability.deletedResult => _message(
            l10n.aiTutorSessionDeletedResult,
          ),
          SessionTutorEntryAvailability.versionMismatch => _message(
            l10n.aiTutorSessionVersionMismatch,
          ),
        },
      ),
    );
  }

  Widget _available(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(l10n.aiTutorSessionEntryTitle),
      const SizedBox(height: 8),
      Text(l10n.aiTutorSessionEntryBody),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('session-tutor-question'),
        controller: _questionController,
        decoration: InputDecoration(
          labelText: l10n.aiTutorSessionQuestionLabel,
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('session-tutor-open'),
        onPressed: _openTutor,
        child: Text(l10n.aiTutorSessionOpen),
      ),
      if (widget.onStartSuggestedPractice != null) ...<Widget>[
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('session-tutor-practice'),
          onPressed: widget.onStartSuggestedPractice,
          child: Text(l10n.aiTutorSessionSuggestedPractice),
        ),
      ],
    ],
  );

  Widget _deterministicFallback(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(l10n.aiTutorSessionConsentOff),
      const SizedBox(height: 12),
      FilledButton.tonal(
        key: const ValueKey('session-tutor-deterministic'),
        onPressed: widget.onOpenDeterministicDebrief,
        child: Text(l10n.aiTutorSessionDeterministicDebrief),
      ),
    ],
  );

  Widget _message(String text) => Text(text);
}
