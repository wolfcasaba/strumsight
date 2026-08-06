import 'package:flutter/material.dart';

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
