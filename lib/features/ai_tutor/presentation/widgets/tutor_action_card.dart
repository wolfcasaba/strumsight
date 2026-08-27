import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/orchestration/action_confirmation_service.dart';
import '../../application/orchestration/tutor_action_validator.dart';
import '../../domain/models/tutor_action.dart';
import 'tutor_source_sheet.dart';

class TutorActionCard extends StatefulWidget {
  const TutorActionCard({
    super.key,
    required this.proposal,
    required this.confirmationService,
    required this.validationContext,
    this.onConfirmationChanged,
  });

  final TutorActionProposal proposal;
  final ActionConfirmationService confirmationService;
  final TutorActionValidationContext Function() validationContext;
  final ValueChanged<ActionConfirmation>? onConfirmationChanged;

  @override
  State<TutorActionCard> createState() => _TutorActionCardState();
}

class _TutorActionCardState extends State<TutorActionCard> {
  late ActionConfirmation _confirmation;
  bool _isConfirming = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _propose();
  }

  @override
  void didUpdateWidget(covariant TutorActionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.proposal, widget.proposal) ||
        !identical(oldWidget.confirmationService, widget.confirmationService)) {
      _propose();
    }
  }

  void _propose() {
    _confirmation = widget.confirmationService.propose(
      widget.proposal,
      context: widget.validationContext(),
    );
    _failed = false;
    _isConfirming = false;
    widget.onConfirmationChanged?.call(_confirmation);
  }

  Future<void> _confirm() async {
    if (_isConfirming ||
        _confirmation.state != ActionConfirmationState.pendingConfirmation) {
      return;
    }
    setState(() {
      _isConfirming = true;
      _failed = false;
    });
    try {
      final result = await widget.confirmationService.confirm(
        _confirmation,
        context: widget.validationContext(),
      );
      if (!mounted) return;
      setState(() {
        _confirmation = result;
        _isConfirming = false;
      });
      widget.onConfirmationChanged?.call(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isConfirming = false;
        _failed = true;
      });
    }
  }

  void _reject() {
    if (_isConfirming) return;
    final rejected = widget.confirmationService.reject(_confirmation);
    if (identical(rejected, _confirmation)) return;
    setState(() => _confirmation = rejected);
    widget.onConfirmationChanged?.call(rejected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = _confirmation.preview;
    final kindLabel = preview == null
        ? l10n.aiTutorActionInvalid
        : tutorActionPreviewLabel(l10n, preview.kind);
    final stateLabel = _stateLabel(l10n);
    final previewTitle = l10n.aiTutorActionPreviewTitle(kindLabel);
    final semanticLabel =
        '$previewTitle. ${l10n.aiTutorActionSemantics(kindLabel, stateLabel)}';

    return Semantics(
      container: true,
      label: semanticLabel,
      child: SingleChildScrollView(
        child: Card(
          key: const ValueKey('tutor-action-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.aiTutorActionPreviewTitle(kindLabel),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (preview != null) ...<Widget>[
                  const SizedBox(height: 12),
                  for (final entry in preview.fields.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        l10n.aiTutorActionParameter(
                          _fieldLabel(l10n, entry.key),
                          _displayValue(l10n, entry.value),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                _statusContent(context, l10n),
                if (_confirmation.state ==
                        ActionConfirmationState.pendingConfirmation &&
                    !_failed) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(l10n.aiTutorActionConfirmationRequired),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      ElevatedButton(
                        key: const ValueKey('tutor-action-confirm'),
                        onPressed: _isConfirming ? null : _confirm,
                        child: Text(
                          _isConfirming
                              ? l10n.aiTutorActionStatePending
                              : l10n.aiTutorActionConfirm,
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('tutor-action-reject'),
                        onPressed: _isConfirming ? null : _reject,
                        child: Text(l10n.aiTutorActionReject),
                      ),
                    ],
                  ),
                ],
                if (_failed) ...<Widget>[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const ValueKey('tutor-action-retry'),
                    onPressed: _isConfirming ? null : _confirm,
                    child: Text(l10n.aiTutorActionRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusContent(BuildContext context, AppLocalizations l10n) {
    if (_failed) {
      return _message(
        context,
        l10n.aiTutorActionFailed,
        Theme.of(context).colorScheme.error,
      );
    }

    switch (_confirmation.state) {
      case ActionConfirmationState.pendingConfirmation:
        return const SizedBox.shrink();
      case ActionConfirmationState.confirmed:
        return _message(
          context,
          l10n.aiTutorActionConfirmed,
          Theme.of(context).colorScheme.primary,
        );
      case ActionConfirmationState.rejected:
        return _message(
          context,
          l10n.aiTutorActionRejected,
          Theme.of(context).colorScheme.secondary,
        );
      case ActionConfirmationState.blocked:
        return _blockedMessage(context, l10n);
    }
  }

  Widget _blockedMessage(BuildContext context, AppLocalizations l10n) {
    final issues = _confirmation.validationIssues;
    if (issues.contains(TutorActionValidationIssue.expired)) {
      return _message(
        context,
        l10n.aiTutorActionStale,
        Theme.of(context).colorScheme.error,
      );
    }
    if (issues.contains(TutorActionValidationIssue.rawRouteForbidden) ||
        issues.contains(TutorActionValidationIssue.unknownAction)) {
      return _message(
        context,
        l10n.aiTutorActionInvalid,
        Theme.of(context).colorScheme.error,
      );
    }
    return _message(
      context,
      l10n.aiTutorActionUnavailable,
      Theme.of(context).colorScheme.error,
    );
  }

  Widget _message(BuildContext context, String text, Color color) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
  );

  String _stateLabel(AppLocalizations l10n) {
    if (_failed) return l10n.aiTutorActionStateFailed;
    return switch (_confirmation.state) {
      ActionConfirmationState.pendingConfirmation =>
        l10n.aiTutorActionStatePending,
      ActionConfirmationState.confirmed => l10n.aiTutorActionStateConfirmed,
      ActionConfirmationState.rejected => l10n.aiTutorActionStateRejected,
      ActionConfirmationState.blocked => l10n.aiTutorActionStateBlocked,
    };
  }

  String _fieldLabel(AppLocalizations l10n, String key) => switch (key) {
    'preferredTempo' => l10n.aiTutorActionFieldPreferredTempo,
    'displayName' => l10n.aiTutorActionFieldDisplayName,
    'planId' => l10n.aiTutorActionFieldPlanId,
    'title' => l10n.aiTutorActionFieldTitle,
    'launchCapability' => l10n.aiTutorActionFieldLaunchCapability,
    _ => l10n.aiTutorActionFieldUnknown(sanitizeTutorDisplayText(key)),
  };

  String _displayValue(AppLocalizations l10n, Object? value) {
    if (value == null) return l10n.aiTutorActionEmptyValue;
    if (value is Map) {
      final entries = value.entries
          .map(
            (entry) =>
                '${sanitizeTutorDisplayText(entry.key.toString())}: '
                '${_displayValue(l10n, entry.value)}',
          )
          .join(', ');
      return sanitizeTutorDisplayText('{$entries}');
    }
    if (value is Iterable) {
      return sanitizeTutorDisplayText(
        value.map((item) => _displayValue(l10n, item)).join(', '),
      );
    }
    return sanitizeTutorDisplayText(value.toString());
  }
}

String tutorActionPreviewLabel(
  AppLocalizations l10n,
  TutorActionPreviewKind kind,
) => switch (kind) {
  TutorActionPreviewKind.profileUpdate => l10n.aiTutorActionProfileUpdate,
  TutorActionPreviewKind.planSave => l10n.aiTutorActionPlanSave,
  TutorActionPreviewKind.sessionLaunch => l10n.aiTutorActionSessionLaunch,
};

/// The tool-action confirmation surface routed through
/// [SsToolConfirmationSheet] (ADR 0287 §1, E13-R29 §3/§5.1) — the
/// pending-state card is a single tap target (§5.3) that opens the sheet;
/// [ActionConfirmationService.confirm] is called ONLY from the sheet's
/// `onConfirm` callback (E13-R29 §0.0/B5's felületi invariáns), never
/// directly from this widget's own button. [TutorActionCard] (above)
/// predates ADR 0287 and is left untouched — its own pinned widget test
/// (`tutor_action_card_test.dart`, outside this round's scope) exercises
/// its existing single-tap-confirms contract directly; this is the
/// separate, additive surface this round introduces for a proposal that
/// must clear the sheet before it can run.
class TutorToolConfirmationCard extends StatefulWidget {
  const TutorToolConfirmationCard({
    super.key,
    required this.proposal,
    required this.confirmationService,
    required this.validationContext,
    this.onConfirmationChanged,
  });

  final TutorActionProposal proposal;
  final ActionConfirmationService confirmationService;
  final TutorActionValidationContext Function() validationContext;
  final ValueChanged<ActionConfirmation>? onConfirmationChanged;

  @override
  State<TutorToolConfirmationCard> createState() =>
      _TutorToolConfirmationCardState();
}

class _TutorToolConfirmationCardState extends State<TutorToolConfirmationCard> {
  late ActionConfirmation _confirmation;
  bool _confirming = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _propose();
  }

  @override
  void didUpdateWidget(covariant TutorToolConfirmationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.proposal, widget.proposal) ||
        !identical(oldWidget.confirmationService, widget.confirmationService)) {
      _propose();
    }
  }

  void _propose() {
    _confirmation = widget.confirmationService.propose(
      widget.proposal,
      context: widget.validationContext(),
    );
    _failed = false;
    _confirming = false;
    widget.onConfirmationChanged?.call(_confirmation);
  }

  Future<void> _confirm() async {
    if (_confirmation.state != ActionConfirmationState.pendingConfirmation) {
      return;
    }
    setState(() {
      _confirming = true;
      _failed = false;
    });
    try {
      final result = await widget.confirmationService.confirm(
        _confirmation,
        context: widget.validationContext(),
      );
      if (!mounted) return;
      setState(() {
        _confirmation = result;
        _confirming = false;
      });
      widget.onConfirmationChanged?.call(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _failed = true;
      });
    }
  }

  Future<void> _openSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final preview = _confirmation.preview;
    if (preview == null) return;
    final kindLabel = tutorActionPreviewLabel(l10n, preview.kind);
    final writesDetail = preview.fields.isEmpty
        ? l10n.aiTutorToolDimensionNothing
        : preview.fields.entries
              .map(
                (entry) =>
                    '${_toolFieldLabel(l10n, entry.key)}: '
                    '${_toolDisplayValue(l10n, entry.value)}',
              )
              .join('\n');
    await SsToolConfirmationSheet.show(
      context,
      actionLabel: kindLabel,
      summary: l10n.aiTutorActionSheetSummary(kindLabel),
      reads: SsToolDimension(
        label: l10n.aiTutorToolDimensionReads,
        detail: l10n.aiTutorActionReadsDetail,
      ),
      writes: SsToolDimension(
        label: l10n.aiTutorToolDimensionWrites,
        detail: writesDetail,
      ),
      leavesDevice: SsToolDimension(
        label: l10n.aiTutorToolDimensionLeavesDevice,
        detail: l10n.aiTutorToolDimensionNothing,
      ),
      recording: SsToolDimension(
        label: l10n.aiTutorToolDimensionRecording,
        detail: l10n.aiTutorToolDimensionNothing,
      ),
      cancelLabel: l10n.aiTutorActionReject,
      // The sheet's own `guardedOnConfirm` (SsToolConfirmationSheet.show)
      // already makes this exactly-once; `_confirm` is a no-op once the
      // state has left `pendingConfirmation` regardless.
      onConfirm: () => unawaited(_confirm()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = _confirmation.preview;

    if (preview == null) {
      return _StatusText(
        text: _blockedText(l10n),
        color: Theme.of(context).colorScheme.error,
      );
    }

    final kindLabel = tutorActionPreviewLabel(l10n, preview.kind);

    switch (_confirmation.state) {
      case ActionConfirmationState.pendingConfirmation:
        return SsCoachActionCard(
          key: const ValueKey('tutor-tool-confirmation-card'),
          l10n: l10n,
          title: kindLabel,
          message: _failed
              ? l10n.aiTutorActionFailed
              : l10n.aiTutorActionConfirmationRequired,
          actionLabel: _confirming
              ? l10n.aiTutorActionStatePending
              : (_failed ? l10n.aiTutorActionRetry : l10n.aiTutorActionReview),
          onAction: _confirming ? () {} : () => unawaited(_openSheet(context)),
        );
      case ActionConfirmationState.confirmed:
        return _StatusText(
          text: l10n.aiTutorActionConfirmed,
          color: Theme.of(context).colorScheme.primary,
        );
      case ActionConfirmationState.rejected:
        return _StatusText(
          text: l10n.aiTutorActionRejected,
          color: Theme.of(context).colorScheme.secondary,
        );
      case ActionConfirmationState.blocked:
        return _StatusText(
          text: _blockedText(l10n),
          color: Theme.of(context).colorScheme.error,
        );
    }
  }

  String _blockedText(AppLocalizations l10n) {
    final issues = _confirmation.validationIssues;
    if (issues.contains(TutorActionValidationIssue.expired)) {
      return l10n.aiTutorActionStale;
    }
    if (issues.contains(TutorActionValidationIssue.rawRouteForbidden) ||
        issues.contains(TutorActionValidationIssue.unknownAction)) {
      return l10n.aiTutorActionInvalid;
    }
    return l10n.aiTutorActionUnavailable;
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _toolFieldLabel(AppLocalizations l10n, String key) => switch (key) {
  'preferredTempo' => l10n.aiTutorActionFieldPreferredTempo,
  'displayName' => l10n.aiTutorActionFieldDisplayName,
  'planId' => l10n.aiTutorActionFieldPlanId,
  'title' => l10n.aiTutorActionFieldTitle,
  'launchCapability' => l10n.aiTutorActionFieldLaunchCapability,
  _ => l10n.aiTutorActionFieldUnknown(sanitizeTutorDisplayText(key)),
};

String _toolDisplayValue(AppLocalizations l10n, Object? value) {
  if (value == null) return l10n.aiTutorActionEmptyValue;
  if (value is Map) {
    final entries = value.entries
        .map(
          (entry) =>
              '${sanitizeTutorDisplayText(entry.key.toString())}: '
              '${_toolDisplayValue(l10n, entry.value)}',
        )
        .join(', ');
    return sanitizeTutorDisplayText('{$entries}');
  }
  if (value is Iterable) {
    return sanitizeTutorDisplayText(
      value.map((item) => _toolDisplayValue(l10n, item)).join(', '),
    );
  }
  return sanitizeTutorDisplayText(value.toString());
}
