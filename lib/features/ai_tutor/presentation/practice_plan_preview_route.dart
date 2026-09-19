/// The composition around `PracticePlanPreviewScreen` (R9).
///
/// The screen itself is pure: it is handed a [PracticePlanDraft] and reports
/// edits back. Until this file existed nothing in `lib/**` ever handed it
/// one, so the screen was unreachable and its "accept" actions had nowhere
/// to go. This route closes both halves:
///
/// * it PRODUCES a real draft from the on-device exercise catalog
///   ([TutorPracticePlanProducer]), and
/// * it PERSISTS an accepted plan through the Practice Generator's public
///   API (`LocalPracticePlanRepository.activateAndReport`), reporting the
///   outcome instead of swallowing it.
///
/// Deliberately not a `*_screen.dart`: this is composition around an
/// existing screen, not a new one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/foundation/app_result.dart';
import '../../../l10n/app_localizations.dart';
import '../../practice_generator/public.dart'
    show
        AdaptivePracticePlan,
        PracticeCatalogSnapshot,
        localPracticePlanRepositoryProvider,
        practiceCatalogSnapshotProvider,
        practiceGeneratorClockProvider;
import '../application/planning/tutor_practice_plan_producer.dart';
import '../domain/models/practice_plan_draft.dart';
import 'providers/tutor_plan_providers.dart';
import 'screens/practice_plan_preview_screen.dart';

/// Hosts [PracticePlanPreviewScreen] with a real draft and a real sink.
class PracticePlanPreviewRoute extends ConsumerStatefulWidget {
  const PracticePlanPreviewRoute({super.key});

  @override
  ConsumerState<PracticePlanPreviewRoute> createState() =>
      _PracticePlanPreviewRouteState();
}

class _PracticePlanPreviewRouteState
    extends ConsumerState<PracticePlanPreviewRoute> {
  AppResult<TutorPracticePlanProposal>? _proposal;
  Duration? _length;
  String? _title;
  PracticeCatalogSnapshot? _catalog;
  bool _saving = false;

  /// Recomputes the proposal only when one of its inputs actually changed.
  ///
  /// The screen keeps its own edited copy and compares drafts by identity
  /// (`didUpdateWidget`), so handing it a freshly built draft on every
  /// rebuild would silently discard the student's edits.
  void _refreshProposal({
    required PracticeCatalogSnapshot catalog,
    required Duration length,
    required String title,
    required String rationale,
  }) {
    final unchanged =
        _proposal != null &&
        _length == length &&
        _title == title &&
        _catalog == catalog;
    if (unchanged) return;
    _length = length;
    _title = title;
    _catalog = catalog;
    final producer = ref.read(tutorPracticePlanProducerProvider);
    _proposal = producer.propose(
      catalog: catalog,
      targetDuration: length,
      title: title,
      rationale: rationale,
    );
  }

  Future<void> _accept(PracticePlanDraft draft) async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final producer = ref.read(tutorPracticePlanProducerProvider);
    final compiled = producer.compileActivePlan(
      draft: draft,
      catalog: ref.read(practiceCatalogSnapshotProvider),
      now: ref.read(practiceGeneratorClockProvider)(),
    );

    if (compiled case Failure<AdaptivePracticePlan>(:final error)) {
      _report(messenger, _planErrorLabel(l10n, error.code));
      setState(() => _saving = false);
      return;
    }

    final repository = ref.read(localPracticePlanRepositoryProvider);
    final saved = await repository.activateAndReport(compiled.valueOrNull!);
    if (!mounted) return;
    if (saved.isFailure) {
      _report(messenger, l10n.tutorPlanSaveFailed);
    } else {
      _report(messenger, l10n.tutorPlanSaved);
    }
    setState(() => _saving = false);
  }

  void _report(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _planErrorLabel(AppLocalizations l10n, String code) => switch (code) {
    tutorPlanCatalogEmptyCode => l10n.tutorPlanCatalogEmpty,
    _ => l10n.tutorPlanNotBuildable,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final length = ref.watch(tutorPlanLengthProvider);
    final catalog = ref.watch(practiceCatalogSnapshotProvider);
    _refreshProposal(
      catalog: catalog,
      length: length,
      title: l10n.tutorPlanDraftTitle(length.inMinutes),
      rationale: l10n.tutorPlanDraftRationale,
    );

    final proposal = _proposal!;
    if (proposal case Success<TutorPracticePlanProposal>(:final value)) {
      return PracticePlanPreviewScreen(
        draft: value.draft,
        validationContext: value.validationContext,
        onSave: (accepted) => unawaited(_accept(accepted)),
        onStart: (accepted) => unawaited(_accept(accepted)),
      );
    }
    final code = proposal.failureOrNull?.code ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTutorPlanActionTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _planErrorLabel(l10n, code),
            key: const ValueKey('tutor-plan-unavailable'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
