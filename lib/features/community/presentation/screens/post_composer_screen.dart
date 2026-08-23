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
/// **Strings:** the composer labels are kept in this file as
/// constants. ARB entries for the composer live in a future round's
/// scope — the Kör 12 allowed-paths covers the screen file only;
/// touching ``lib/l10n/**`` would be a scope violation. The labels
/// stay here so a future i18n round picks them up without a screen
/// rewrite.
///
/// **Média placeholder (brief §3 / Kör 18):** the composer ships a
/// stub "Attach media" placeholder button that does NOT upload
/// anything yet — it is the explicit Kör 12 boundary. The button is
/// wired to surface a non-fatal snackbar so the user sees the
/// affordance and knows it is "later" rather than broken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../application/controllers/post_composer_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';

/// Composer-screen labels. Kept here (not in the ARB) because the
/// l10n catalogue for the composer is a future round's scope; a
/// later round moves these to ``lib/l10n/features/community_en.arb``
/// in lockstep with the screen.
abstract final class _ComposerLabels {
  static const String title = 'Új poszt';
  static const String bodyLabel = 'Szöveg';
  static const String bodyHint = 'Mit szeretnél megosztani?';
  static const String attachMedia = 'Média csatolása';
  static const String mediaLater = 'A média csatolása később érhető el.';
  static const String audienceLabel = 'Kik láthatják';
  static const String previewLabel = 'Megosztott mezők';
  static const String publish = 'Közzététel';
  static const String submitting = 'Közzététel…';
  static const String success = 'Sikeresen közzétéve.';
  static const String failure = 'A poszt nem került elküldésre — próbáld újra.';
  static const String discard = 'Elvetés';

  static const String audiencePublic = 'Nyilvános';
  static const String audienceFollowers = 'Követők';
  static const String audiencePrivate = 'Privát';

  static const String previewChordTimeline = 'Akkord-idővonal';
  static const String previewStrumPattern = 'Strumminta';
  static const String previewTempo = 'Tempó';
  static const String previewStreakDays = 'Aktív napok';
  static const String previewBestScore = 'Legjobb pontszám';
}

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

    return Scaffold(
      appBar: AppBar(
        title: const Text(_ComposerLabels.title),
        actions: <Widget>[
          IconButton(
            tooltip: _ComposerLabels.discard,
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
    );
  }

  void _onAttachMediaPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(_ComposerLabels.mediaLater),
        duration: Duration(seconds: 2),
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
                  const _SectionLabel(label: _ComposerLabels.bodyLabel),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyController,
                    enabled: !state.isSubmitting,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: kCommunityPostBodyMaxLength,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: _ComposerLabels.bodyHint,
                    ),
                    onChanged: onBodyChanged,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: const Text(_ComposerLabels.attachMedia),
                    onPressed: state.isSubmitting ? null : onAttachMediaPressed,
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel(label: _ComposerLabels.audienceLabel),
                  const SizedBox(height: 8),
                  _AudienceSelector(
                    audience: state.audience,
                    enabled: !state.isSubmitting,
                    onChanged: onAudienceChanged,
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel(label: _ComposerLabels.previewLabel),
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
            child: FilledButton(
              onPressed: canSubmit ? onSubmit : null,
              child: const Text(_ComposerLabels.publish),
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
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final value in CommunityAudience.values)
          ChoiceChip(
            label: Text(_audienceLabel(value)),
            selected: audience == value,
            onSelected: enabled ? (_) => onChanged(value) : null,
          ),
      ],
    );
  }

  String _audienceLabel(CommunityAudience value) {
    switch (value) {
      case CommunityAudience.public:
        return _ComposerLabels.audiencePublic;
      case CommunityAudience.followers:
        return _ComposerLabels.audienceFollowers;
      case CommunityAudience.private:
        return _ComposerLabels.audiencePrivate;
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
    return Column(
      children: <Widget>[
        SwitchListTile(
          title: const Text(_ComposerLabels.previewChordTimeline),
          value: preview.includeChordTimeline,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.chordTimeline, v)
              : null,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text(_ComposerLabels.previewStrumPattern),
          value: preview.includeStrumPattern,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.strumPattern, v)
              : null,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text(_ComposerLabels.previewTempo),
          value: preview.includeTempo,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.tempo, v)
              : null,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text(_ComposerLabels.previewStreakDays),
          value: preview.includeStreakDays,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.streakDays, v)
              : null,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text(_ComposerLabels.previewBestScore),
          value: preview.includeBestScore,
          onChanged: enabled
              ? (v) => onToggleField(_PreviewFlag.bestScore, v)
              : null,
          contentPadding: EdgeInsets.zero,
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
    late final Color background;
    late final String text;
    switch (status) {
      case PostComposerStatus.submitting:
        background = theme.colorScheme.secondaryContainer;
        text = _ComposerLabels.submitting;
      case PostComposerStatus.success:
        background = theme.colorScheme.tertiaryContainer;
        text = _ComposerLabels.success;
      case PostComposerStatus.failure:
        background = theme.colorScheme.errorContainer;
        // AppFailure does not carry a user-facing message — the
        // composer maps the failure code via the ARB in a future
        // round. For now the screen surfaces a generic banner; the
        // structured `error.code` is logged for diagnostics.
        final failureCode = error?.code;
        text = failureCode != null
            ? '${_ComposerLabels.failure} ($failureCode)'
            : _ComposerLabels.failure;
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
