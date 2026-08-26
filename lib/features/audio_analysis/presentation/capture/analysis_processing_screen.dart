// Processing Stage (SDD Ch13 Kör 26, UI-36, ADR 0285).
//
// Hosts the existing, previously-orphan `AnalysisProgressView` (brief
// §0.0/B2) instead of re-implementing its "no fake percent" contract. This
// screen adds exactly one thing on top: a deterministic phase-step readout
// (`AnalysisProgressPhase.values.indexOf(phase)` — real enum position, never
// a synthetic number) so the user still sees real progress when a stage
// supplies no unit counts (brief §6.1 "a szakasz szakasz-szintű haladást ad").

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/analysis_state.dart';
import '../../domain/analysis_capability.dart';
import '../../domain/analysis_document.dart';
import '../../domain/analysis_progress.dart';
import '../analysis_progress_view.dart';
import '../widgets/labels_adapter.dart';

/// Hosts one V2 [AnalysisState] and translates it into the processing UI:
/// honest phase progress, idempotent cancellation, and a named degraded
/// reason instead of a silent slowdown.
final class AnalysisProcessingScreen extends StatefulWidget {
  const AnalysisProcessingScreen({
    required this.state,
    required this.onCancel,
    this.onRestart,
    this.onViewResult,
    super.key,
  });

  final AnalysisState state;
  final VoidCallback onCancel;
  final VoidCallback? onRestart;
  final void Function(AnalysisDocument document)? onViewResult;

  @override
  State<AnalysisProcessingScreen> createState() =>
      _AnalysisProcessingScreenState();
}

class _AnalysisProcessingScreenState extends State<AnalysisProcessingScreen> {
  // The run id we already forwarded a cancel for. A second tap on the SAME
  // run is a no-op; a later run (a fresh, different id) can be cancelled
  // again (brief §5.3 — idempotent, not "cancel forever").
  String? _cancelledForRunId;

  void _handleCancel(String runId) {
    if (_cancelledForRunId == runId) return;
    _cancelledForRunId = runId;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisProcessingTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (state) {
            AnalysisIdle() ||
            AnalysisAcquiringInput() ||
            AnalysisRecording() ||
            AnalysisValidating() => const _IndeterminateBody(),
            AnalysisAnalyzing(:final phase) when phase == null =>
              const _IndeterminateBody(),
            AnalysisAnalyzing(
              :final runId,
              :final phase,
              :final completedUnits,
              :final totalUnits,
            ) =>
              _AnalyzingBody(
                phase: phase!,
                completedUnits: completedUnits,
                totalUnits: totalUnits,
                onCancel: () => _handleCancel(runId),
                alreadyCancelled: _cancelledForRunId == runId,
              ),
            AnalysisCompleted(:final document) => _CompletedBody(
              onViewResult: widget.onViewResult == null
                  ? null
                  : () => widget.onViewResult!(document),
            ),
            AnalysisDegradedCompleted(:final document) => _DegradedBody(
              document: document,
              onViewResult: widget.onViewResult == null
                  ? null
                  : () => widget.onViewResult!(document),
            ),
            AnalysisCancelled() => _CancelledBody(onRestart: widget.onRestart),
            AnalysisPermissionDenied() => _MessageBody(
              key: const Key('analysis-processing-permission-denied'),
              title: l10n.analysisProcessingPermissionDeniedTitle,
              onRestart: widget.onRestart,
            ),
            AnalysisInputError(:final failure) => _MessageBody(
              key: const Key('analysis-processing-input-error'),
              title: l10n.analysisProcessingErrorTitle,
              detail: failure.code,
              onRestart: widget.onRestart,
            ),
            AnalysisError(:final failure) => _MessageBody(
              key: const Key('analysis-processing-error'),
              title: l10n.analysisProcessingErrorTitle,
              detail: failure.code,
              onRestart: widget.onRestart,
            ),
          },
        ),
      ),
    );
  }
}

final class _IndeterminateBody extends StatelessWidget {
  const _IndeterminateBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.analysisProcessingStarting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.analysisProcessingStarting,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.analysisProcessingStartingDescription),
          const SizedBox(height: 12),
          const LinearProgressIndicator(
            key: Key('analysis-processing-starting-bar'),
          ),
        ],
      ),
    );
  }
}

final class _AnalyzingBody extends StatelessWidget {
  const _AnalyzingBody({
    required this.phase,
    required this.completedUnits,
    required this.totalUnits,
    required this.onCancel,
    required this.alreadyCancelled,
  });

  final AnalysisProgressPhase phase;
  final int? completedUnits;
  final int? totalUnits;
  final VoidCallback onCancel;
  final bool alreadyCancelled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = AnalysisProgressPhase.values.indexOf(phase) + 1;
    final total = AnalysisProgressPhase.values.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisProcessingStepIndicator(index, total),
          key: const Key('analysis-processing-step'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        AnalysisProgressView(
          phase: phase,
          completedUnits: completedUnits,
          totalUnits: totalUnits,
          onCancel: alreadyCancelled ? () {} : onCancel,
        ),
      ],
    );
  }
}

final class _CompletedBody extends StatelessWidget {
  const _CompletedBody({required this.onViewResult});

  final VoidCallback? onViewResult;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisProcessingCompletedTitle,
          key: const Key('analysis-processing-completed-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (onViewResult != null)
          FilledButton(
            key: const Key('analysis-processing-view-result'),
            onPressed: onViewResult,
            child: Text(l10n.analysisProcessingViewResult),
          ),
      ],
    );
  }
}

final class _DegradedBody extends StatelessWidget {
  const _DegradedBody({required this.document, required this.onViewResult});

  final AnalysisDocument document;
  final VoidCallback? onViewResult;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = AppLocalizationsOverviewLabels(l10n);
    final reasons = <CapabilityUnavailableReason>{
      for (final capability in document.capabilities)
        if (capability.status == CapabilityStatus.unavailable &&
            capability.reason != null)
          capability.reason!,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisProcessingDegradedTitle,
          key: const Key('analysis-processing-degraded-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(l10n.analysisProcessingDegradedDescription),
        const SizedBox(height: 8),
        for (final reason in reasons)
          Padding(
            key: Key('analysis-processing-degraded-reason-${reason.name}'),
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• ${labels.unavailableReason(reason)}'),
          ),
        const SizedBox(height: 12),
        if (onViewResult != null)
          FilledButton(
            key: const Key('analysis-processing-view-result'),
            onPressed: onViewResult,
            child: Text(l10n.analysisProcessingViewResult),
          ),
      ],
    );
  }
}

final class _CancelledBody extends StatelessWidget {
  const _CancelledBody({required this.onRestart});

  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisProcessingCancelledTitle,
          key: const Key('analysis-processing-cancelled-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (onRestart != null) ...<Widget>[
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('analysis-processing-restart'),
            onPressed: onRestart,
            child: Text(l10n.analysisProcessingRestart),
          ),
        ],
      ],
    );
  }
}

final class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.title,
    this.detail,
    required this.onRestart,
    super.key,
  });

  final String title;
  final String? detail;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (detail != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (onRestart != null) ...<Widget>[
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('analysis-processing-restart'),
            onPressed: onRestart,
            child: Text(l10n.analysisProcessingRestart),
          ),
        ],
      ],
    );
  }
}
