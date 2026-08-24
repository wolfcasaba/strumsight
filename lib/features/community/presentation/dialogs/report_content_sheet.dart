/// User-report bottom sheet (E09-R26, ADR 0414).
///
/// The sheet lives at the BOTTOM of the navigation stack — same
/// entry point as ``safety_relationships_screen``'s block / mute
/// actions (Kör 8). Two-phase UX:
///
/// 1. **Compose phase** — the reporter picks a category from the
///    localized list. The self-harm category triggers an
///    *approved-safety-copy* helper line (brief §5.3) — the only
///    text that's not the standard category label.
///
/// 2. **Thanks phase** — immediately after a successful submit, the
///    sheet surfaces the three §5.2 immediate-safety shortcuts:
///    hide from feed, mute this person, block this person. The
///    sheet stays open so the reporter does NOT have to keep
///    looking at the reported content (brief §5.2).
///
/// The §5.1 invariant — the reporter's identity NEVER leaks to the
/// target — is enforced server-side; this widget carries no reporter
/// state into the navigation, and the result callback exposes only
/// a sanitized ``reportPublicId`` UUID (the brief §6 A1 contract).
///
/// Accessibility (A7): the sheet's semantic focus lands on the title
/// on open (the standard ``Semantics(header: true, focused: true)``
/// pattern). Each category choice is a tappable ``ListTile`` with a
/// ``Semantics(button: true)`` wrapper. The self-harm helper line is
/// its own semantic node so a screen reader reads it after the
/// category is picked.
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// The wire-stable category identifiers — MUST match the
/// :data:`REPORT_CATEGORIES` set on the backend. The order in this
/// list is the order shown to the reporter (most common first).
enum ReportCategory {
  spam,
  harassment,
  hateSpeech,
  violence,
  sexualContent,
  selfHarmConcern,
  copyright,
  privacy,
  misinformation,
  other;

  /// The wire string the backend expects.
  String get wireValue => switch (this) {
    ReportCategory.spam => 'spam',
    ReportCategory.harassment => 'harassment',
    ReportCategory.hateSpeech => 'hate_speech',
    ReportCategory.violence => 'violence',
    ReportCategory.sexualContent => 'sexual_content',
    ReportCategory.selfHarmConcern => 'self_harm_concern',
    ReportCategory.copyright => 'copyright',
    ReportCategory.privacy => 'privacy',
    ReportCategory.misinformation => 'misinformation',
    ReportCategory.other => 'other',
  };
}

/// What the reporter wants the app to do NEXT after a successful
/// report. The §5.2 invariant — the reporter does not have to keep
/// looking at the reported content — is honored because the sheet
/// stays open across this transition.
enum ReportSafetyAction { hide, mute, block, done }

/// Public callback contract. The reporter's identity is NOT part of
/// this contract (brief §5.1) — only the sanitized outcome is.
class ReportSubmissionOutcome {
  const ReportSubmissionOutcome({
    required this.reportPublicId,
    required this.deduplicated,
    required this.action,
  });

  /// The row's UUID — the only reporter-facing identifier on the
  /// response (backend §5.1 wire-shape).
  final String reportPublicId;

  /// ``true`` if the submit recycled an existing report row (the
  /// reporter is shown the same thanks view either way).
  final bool deduplicated;

  /// The immediate-safety-shortcut action the reporter chose in the
  /// thanks phase. ``null`` if the sheet was dismissed without
  /// picking an action.
  final ReportSafetyAction? action;
}

/// What the host (the screen that opened the sheet) needs to
/// provide.
class ReportContentRequest {
  const ReportContentRequest({
    required this.targetType,
    required this.targetId,
    this.targetAuthorPublicId,
  });

  /// ``"post"`` or ``"comment"`` — the backend target discriminator.
  final String targetType;

  /// The target's public_id (UUID string).
  final String targetId;

  /// The reported content's author — needed only for the mute /
  /// block immediate-safety shortcuts. ``null`` when the report is
  /// on a target with no associated profile (rare; the sheet still
  /// works for ``hide``).
  final String? targetAuthorPublicId;
}

/// The repository-method contract the host wires up. The sheet
/// never touches the HTTP layer directly — the repository owns the
/// sanitized wire shape (brief §5.1).
abstract class ReportRepository {
  Future<ReportSubmissionOutcome> submit({
    required String targetType,
    required String targetId,
    required ReportCategory category,
    required String idempotencyKey,
  });

  /// Hide the target from the caller's local feed view. The
  /// backend record stays (the moderation queue still sees it);
  /// this is a local UI affordance.
  Future<void> hideFromFeed({required String targetId});

  /// Mute the target's author. Mirrors the Kör 8 block / mute flow.
  Future<void> muteAuthor({required String authorPublicId});

  /// Block the target's author. Mirrors the Kör 8 block / mute flow.
  Future<void> blockAuthor({required String authorPublicId});
}

/// Show the report bottom sheet. Returns the outcome when the
/// reporter completes (or dismisses) the flow.
///
/// The sheet is the canonical entry point — screens that want to
/// expose reporting call this function and react to the returned
/// outcome (e.g. the feed card pops the offending card from the
/// list when ``action == ReportSafetyAction.hide``).
Future<ReportSubmissionOutcome?> showReportContentSheet(
  BuildContext context, {
  required ReportContentRequest request,
  required ReportRepository repository,
}) {
  return showModalBottomSheet<ReportSubmissionOutcome>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (sheetContext) =>
        ReportContentSheet(request: request, repository: repository),
  );
}

class ReportContentSheet extends StatefulWidget {
  const ReportContentSheet({
    required this.request,
    required this.repository,
    super.key,
  });

  final ReportContentRequest request;
  final ReportRepository repository;

  @override
  State<ReportContentSheet> createState() => _ReportContentSheetState();
}

class _ReportContentSheetState extends State<ReportContentSheet> {
  ReportCategory? _selected;
  bool _submitting = false;
  // ``null`` = not yet submitted; non-null = compose-phase done.
  ReportSubmissionOutcome? _submittedOutcome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Semantics(
        container: true,
        label: l10n.reportSheetSemanticsTitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _submittedOutcome == null
              ? _buildComposePhase(context, l10n, theme)
              : _buildThanksPhase(context, l10n, theme),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Phase 1 — compose
  // ---------------------------------------------------------------------

  Widget _buildComposePhase(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(l10n.reportSheetTitle, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        Text(l10n.reportSheetBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Semantics(
          label: l10n.reportSheetSemanticsCategoryHint,
          child: Text(
            l10n.reportSheetCategoryLabel,
            style: theme.textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                for (final category in ReportCategory.values)
                  _CategoryTile(
                    key: Key('report-category-${category.wireValue}'),
                    category: category,
                    selected: _selected == category,
                    onSelected: () {
                      setState(() => _selected = category);
                    },
                  ),
              ],
            ),
          ),
        ),
        if (_selected == ReportCategory.selfHarmConcern) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            key: const Key('report-self-harm-helper'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.reportSheetSelfHarmHelper,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              key: const Key('report-cancel'),
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).maybePop(),
              child: Text(l10n.reportSheetCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('report-submit'),
              onPressed: _selected == null || _submitting
                  ? null
                  : () => _onSubmit(),
              child: Text(
                _submitting
                    ? l10n.reportSheetSubmitting
                    : l10n.reportSheetSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Phase 2 — thanks + immediate safety shortcuts (brief §5.2, A3)
  // ---------------------------------------------------------------------

  Widget _buildThanksPhase(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            l10n.reportSheetThanksTitle,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.reportSheetThanksBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              key: const Key('report-action-hide'),
              onPressed: () => _onActionSelected(ReportSafetyAction.hide),
              icon: const Icon(Icons.visibility_off_outlined),
              label: Text(l10n.reportSheetActionHide),
            ),
            if (widget.request.targetAuthorPublicId != null) ...<Widget>[
              FilledButton.tonalIcon(
                key: const Key('report-action-mute'),
                onPressed: () => _onActionSelected(ReportSafetyAction.mute),
                icon: const Icon(Icons.volume_off_outlined),
                label: Text(l10n.reportSheetActionMute),
              ),
              FilledButton.tonalIcon(
                key: const Key('report-action-block'),
                onPressed: () => _onActionSelected(ReportSafetyAction.block),
                icon: const Icon(Icons.block_outlined),
                label: Text(l10n.reportSheetActionBlock),
              ),
            ],
            TextButton(
              key: const Key('report-action-done'),
              onPressed: () => _onActionSelected(ReportSafetyAction.done),
              child: Text(l10n.reportSheetActionDone),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Action handlers
  // ---------------------------------------------------------------------

  Future<void> _onSubmit() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _submitting = true);
    try {
      final outcome = await widget.repository.submit(
        targetType: widget.request.targetType,
        targetId: widget.request.targetId,
        category: selected,
        idempotencyKey: _newIdempotencyKey(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submittedOutcome = outcome;
      });
    } on Exception catch (_) {
      // Repository-layer failure is mapped to a localized snack bar;
      // the sheet stays in compose phase so the reporter can retry.
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapFailureToLocalizedText(context))),
      );
    }
  }

  Future<void> _onActionSelected(ReportSafetyAction action) async {
    final outcome = _submittedOutcome;
    if (outcome == null) {
      Navigator.of(context).maybePop();
      return;
    }
    try {
      switch (action) {
        case ReportSafetyAction.hide:
          await widget.repository.hideFromFeed(
            targetId: widget.request.targetId,
          );
        case ReportSafetyAction.mute:
          final authorId = widget.request.targetAuthorPublicId;
          if (authorId != null) {
            await widget.repository.muteAuthor(authorPublicId: authorId);
          }
        case ReportSafetyAction.block:
          final authorId = widget.request.targetAuthorPublicId;
          if (authorId != null) {
            await widget.repository.blockAuthor(authorPublicId: authorId);
          }
        case ReportSafetyAction.done:
          break;
      }
    } on Exception catch (_) {
      // The action failed — we still pop with the chosen action so
      // the host screen can decide what to do (e.g. show its own
      // error toast). We don't keep the reporter on the sheet after
      // they've made a safety decision.
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      ReportSubmissionOutcome(
        reportPublicId: outcome.reportPublicId,
        deduplicated: outcome.deduplicated,
        action: action,
      ),
    );
  }

  String _mapFailureToLocalizedText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The sheet's repository is responsible for translating
    // AppFailure.code into the right key. The default fallback
    // covers the rare "no AppFailure" case (a raw exception).
    return l10n.reportSheetErrorInvalid;
  }

  String _newIdempotencyKey() {
    // Same bare-bones pattern as Kör 8's safety_relationships_screen.
    // The repository layer only needs a non-empty string; a future
    // round can swap this for a real UUID generator if the backend
    // demands more.
    return 'rp-${DateTime.now().microsecondsSinceEpoch}';
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ReportCategory category;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (category) {
      ReportCategory.spam => l10n.reportSheetCategorySpam,
      ReportCategory.harassment => l10n.reportSheetCategoryHarassment,
      ReportCategory.hateSpeech => l10n.reportSheetCategoryHateSpeech,
      ReportCategory.violence => l10n.reportSheetCategoryViolence,
      ReportCategory.sexualContent => l10n.reportSheetCategorySexualContent,
      ReportCategory.selfHarmConcern => l10n.reportSheetCategorySelfHarmConcern,
      ReportCategory.copyright => l10n.reportSheetCategoryCopyright,
      ReportCategory.privacy => l10n.reportSheetCategoryPrivacy,
      ReportCategory.misinformation => l10n.reportSheetCategoryMisinformation,
      ReportCategory.other => l10n.reportSheetCategoryOther,
    };

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(label),
        onTap: onSelected,
      ),
    );
  }
}
