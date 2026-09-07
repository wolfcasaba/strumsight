/// Community post composer screen (E09-R12, brief §1 / §6 / §6.1).
///
/// The screen is a pure projection of [PostComposerState]: every
/// interactive widget calls into the controller, every visible label
/// reads from the controller's state. The screen owns no
/// composer-domain state of its own (the form draft lives in the
/// controller — A3 / A5 invariance).
///
/// **Layout (top → bottom):**
///
/// 1. The body text-field (multi-line, plain text, max
///    ``kCommunityPostBodyMaxLength`` characters per the Kör 11
///    server-side validator).
/// 2. The audience selector — three chips (public / followers /
///    private); the selected chip is highlighted.
/// 3. The share-preview toggle panel — every flag default-off
///    (brief §5.1 / A7); the user explicitly opts into each.
/// 4. The publish button — disabled while ``isSubmitting`` is true
///    (A3) and on a body-empty + artifact-empty composer (the
///    controller rejects those submits in [_draftFromState]).
/// 5. The status banner — explicit visible state per
///    [PostComposerStatus].
///
/// **Strings (R20, audit M8):** every user-facing label on this
/// screen now comes from [AppLocalizations]
/// (``communityComposer*`` in
/// ``lib/l10n/features/community_{en,hu}.arb``). Until this round
/// the labels were Hungarian ``const`` literals in this file, so an
/// English build rendered a Hungarian composer — measured on the
/// shipped development APK, where ``communityWritesEnabled`` is on.
///
/// **Média placeholder (brief §3 / Kör 18):** the composer ships a
/// stub "Attach media" placeholder button that does NOT upload
/// anything yet — it is the explicit Kör 12 boundary. The button is
/// wired to surface a non-fatal snackbar so the user sees the
/// affordance and knows it is "later" rather than broken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/post_composer_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';
import '../widgets/community_theme_scope.dart';

/// The composer route. The entry-point that pushes this route
/// supplies the [ShareArtifact.toJson] of the artifact the user is
/// sharing by overriding [composerSourceArtifactProvider] before
/// pushing the route (the §10 route wiring).
class PostComposerScreen extends ConsumerStatefulWidget {
  const PostComposerScreen({super.key});

  @override
  ConsumerState<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends ConsumerState<PostComposerScreen> {
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postComposerControllerProvider);
    final l10n = AppLocalizations.of(context);

    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.communityComposerTitle),
          actions: <Widget>[
            IconButton(
              tooltip: l10n.communityComposerDiscard,
              icon: const Icon(Icons.delete_outline),
              onPressed: state.value?.isSubmitting ?? false
                  ? null
                  : () => ref
                        .read(postComposerControllerProvider.notifier)
                        .discard(),
            ),
          ],
        ),
        body: state.when(
          data: (composerState) => _ComposerBody(
            state: composerState,
            bodyController: _bodyController,
            onBodyChanged: (value) => ref
                .read(postComposerControllerProvider.notifier)
                .updateBody(value.isEmpty ? null : value),
            onAudienceChanged: (audience) => ref
                .read(postComposerControllerProvider.notifier)
                .updateAudience(audience),
            onToggleField: (flag, value) {
              final preview = composerState.sharePreview;
              ref
                  .read(postComposerControllerProvider.notifier)
                  .setSharePreviewFlag(
                    includeChordTimeline: flag == _PreviewFlag.chordTimeline
                        ? value
                        : preview.includeChordTimeline,
                    includeStrumPattern: flag == _PreviewFlag.strumPattern
                        ? value
                        : preview.includeStrumPattern,
                    includeTempo: flag == _PreviewFlag.tempo
                        ? value
                        : preview.includeTempo,
                    includeStreakDays: flag == _PreviewFlag.streakDays
                        ? value
                        : preview.includeStreakDays,
                    includeBestScore: flag == _PreviewFlag.bestScore
                        ? value
                        : preview.includeBestScore,
                  );
            },
            onSubmit: () =>
                ref.read(postComposerControllerProvider.notifier).submit(),
            onAttachMediaPressed: _onAttachMediaPressed,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
        ),
      ),
    );
  }

  void _onAttachMediaPressed() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.communityComposerMediaLater),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

enum _PreviewFlag { chordTimeline, strumPattern, tempo, streakDays, bestScore }

class _ComposerBody extends StatelessWidget {
  const _ComposerBody({
    required this.state,
    required this.bodyController,
    required this.onBodyChanged,
    required this.onAudienceChanged,
    required this.onToggleField,
    required this.onSubmit,
    required this.onAttachMediaPressed,
  });

  final PostComposerState state;
  final TextEditingController bodyController;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<CommunityAudience> onAudienceChanged;
  final void Function(_PreviewFlag flag, bool value) onToggleField;
  final VoidCallback onSubmit;
  final VoidCallback onAttachMediaPressed;

  @override
  Widget build(BuildContext context) {
    // Sync the text controller with the controller's body the first
    // time the data arrives. Subsequent edits flow through the
    // controller (onBodyChanged), not back into the controller via
    // the text controller — this is the §5.3 invariant: the body
    // the user sees is the body the controller persists.
    if (bodyController.text != (state.body ?? '')) {
      final selection = bodyController.selection;
      bodyController.value = TextEditingValue(
        text: state.body ?? '',
        selection:
            selection.isValid && selection.end <= (state.body ?? '').length
            ? selection
            : const TextSelection.collapsed(offset: 0),
      );
    }

    final l10n = AppLocalizations.of(context);
    final canSubmit =
        !state.isSubmitting &&
        state.status != PostComposerStatus.submitting &&
        (state.body != null && state.body!.isNotEmpty);
    final showBanner =
        state.status == PostComposerStatus.submitting ||
        state.status == PostComposerStatus.success ||
        state.status == PostComposerStatus.failure;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Klub-kontextus (E17-R11). A sáv CSAK akkor jelenik meg,
                  // ha a szerkesztőt egy klubból nyitották: a poszt akkor
                  // nem a globális feedbe, hanem a klubéba megy, és ezt a
                  // felhasználónak látnia kell, mielőtt közzétesz.
                  if (state.clubId != null) ...<Widget>[
                    _ClubTargetBanner(label: l10n.communityComposerClubTarget),
                    const SizedBox(height: 16),
                  ],
                  _SectionLabel(label: l10n.communityComposerBodyLabel),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyController,
                    enabled: !state.isSubmitting,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: kCommunityPostBodyMaxLength,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: l10n.communityComposerBodyHint,
                    ),
                    onChanged: onBodyChanged,
                  ),
                  const SizedBox(height: 16),
                  SsButton(
                    variant: SsButtonVariant.secondary,
                    icon: Icons.attach_file,
                    label: l10n.communityComposerAttachMedia,
                    onPressed: state.isSubmitting ? null : onAttachMediaPressed,
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel(label: l10n.communityComposerAudienceLabel),
                  const SizedBox(height: 8),
                  _AudienceSelector(
                    audience: state.audience,
                    enabled: !state.isSubmitting,
                    onChanged: onAudienceChanged,
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel(label: l10n.communityComposerPreviewLabel),
                  const SizedBox(height: 8),
                  _SharePreviewPanel(
                    preview: state.sharePreview,
                    enabled: !state.isSubmitting,
                    onToggleField: onToggleField,
                  ),
                ],
              ),
            ),
          ),
          if (showBanner)
            _StatusBanner(status: state.status, error: state.lastError),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SsButton(
              onPressed: canSubmit ? onSubmit : null,
              loading: state.status == PostComposerStatus.submitting,
              label: l10n.communityComposerPublish,
            ),
          ),
        ],
      ),
    );
  }
}

/// A klub-célt kimondó sáv a szerkesztő tetején.
///
/// Külön widget, hogy a `Key` stabil azonosítót adjon a widget-tesztnek
/// (a felirat fordítás-függő, a kulcs nem).
class _ClubTargetBanner extends StatelessWidget {
  const _ClubTargetBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('composer-club-target'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.groups_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(label, style: theme.textTheme.titleSmall);
  }
}

class _AudienceSelector extends StatelessWidget {
  const _AudienceSelector({
    required this.audience,
    required this.enabled,
    required this.onChanged,
  });

  final CommunityAudience audience;
  final bool enabled;
  final ValueChanged<CommunityAudience> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsChoice<CommunityAudience>(
      style: SsChoiceStyle.chip,
      value: audience,
      options: [
        for (final value in CommunityAudience.values)
          SsChoiceOption<CommunityAudience>(
            value: value,
            label: _audienceLabel(l10n, value),
          ),
      ],
      onChanged: enabled ? (value) => _onSelected(context, value) : null,
    );
  }

  /// ADR 0291 §2 — a `public` pick is held behind a spelled-out
  /// irreversibility confirmation (brief §6.1 "above threshold" cell); the
  /// other two audiences apply immediately, same as before.
  void _onSelected(BuildContext context, CommunityAudience value) {
    if (value != CommunityAudience.public) {
      onChanged(value);
      return;
    }
    final l = AppLocalizations.of(context);
    showCommunityConfirmationSheet(
      context,
      title: l.communityPublicConfirmTitle,
      consequence: l.communityPublicConfirmBody,
      confirmLabel: l.communityPublicConfirmCta,
      cancelLabel: l.communityPublicConfirmCancel,
      onConfirm: () => onChanged(value),
    );
  }

  String _audienceLabel(AppLocalizations l10n, CommunityAudience value) {
    switch (value) {
      case CommunityAudience.public:
        return l10n.communityComposerAudiencePublic;
      case CommunityAudience.followers:
        return l10n.communityComposerAudienceFollowers;
      case CommunityAudience.private:
        return l10n.communityComposerAudiencePrivate;
    }
  }
}

class _SharePreviewPanel extends StatelessWidget {
  const _SharePreviewPanel({
    required this.preview,
    required this.enabled,
    required this.onToggleField,
  });

  final SharePreview preview;
  final bool enabled;
  final void Function(_PreviewFlag flag, bool value) onToggleField;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        SsSwitchRow(
          label: l10n.communityComposerPreviewChordTimeline,
          value: preview.includeChordTimeline,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.chordTimeline, v)
              : null,
        ),
        SsSwitchRow(
          label: l10n.communityComposerPreviewStrumPattern,
          value: preview.includeStrumPattern,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.strumPattern, v)
              : null,
        ),
        SsSwitchRow(
          label: l10n.communityComposerPreviewTempo,
          value: preview.includeTempo,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.tempo, v)
              : null,
        ),
        SsSwitchRow(
          label: l10n.communityComposerPreviewStreakDays,
          value: preview.includeStreakDays,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.streakDays, v)
              : null,
        ),
        SsSwitchRow(
          label: l10n.communityComposerPreviewBestScore,
          value: preview.includeBestScore,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.bestScore, v)
              : null,
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.error});

  final PostComposerStatus status;
  final AppFailure? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    late final Color background;
    late final String text;
    switch (status) {
      case PostComposerStatus.submitting:
        background = theme.colorScheme.secondaryContainer;
        text = l10n.communityComposerSubmitting;
      case PostComposerStatus.success:
        background = theme.colorScheme.tertiaryContainer;
        text = l10n.communityComposerSuccess;
      case PostComposerStatus.failure:
        background = theme.colorScheme.errorContainer;
        // AppFailure does not carry a user-facing message — the banner
        // is the localized generic copy, and the structured
        // `error.code` is appended (also localized, so the parentheses
        // stay part of the translated sentence) for diagnostics.
        final failureCode = error?.code;
        text = failureCode != null
            ? l10n.communityComposerFailureWithCode(failureCode)
            : l10n.communityComposerFailure;
      case PostComposerStatus.editing:
        return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: background,
      child: Row(
        children: <Widget>[
          if (status == PostComposerStatus.submitting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (status == PostComposerStatus.submitting)
            const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
