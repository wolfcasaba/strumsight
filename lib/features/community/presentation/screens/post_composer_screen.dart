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
/// **Média csatolása (javító sáv R27).** A "Attach media" gomb R21 óta
/// a ``communityMediaEnabled`` flag mögött áll; R12 és R27 között
/// csak egy őszinte „később" snackbart mutatott, mert nem volt mit
/// hívnia. R27 óta VAN: a gomb képet választ, azonnal feltölti
/// (``POST /community/media``), és a keletkező azonosítót a
/// piszkozatba teszi, tehát egy app-újraindítás után is megvan.
///
/// A gomb HELYE és megjelenése bájtra változatlan — a golden-képek
/// (``e13_r33``) a flaggel BEKAPCSOLVA készültek, és csatolmány nélkül
/// a képernyő pontosan ugyanaz marad: a csatolmány-lista, a hiba- és a
/// korlát-üzenet KIZÁRÓLAG akkor jelenik meg, ha van mit mutatniuk.
///
/// A ``communityMediaEnabled`` a szállított buildekben továbbra is
/// KIKAPCSOLT (``feature_flags.dart``; a nyitott R-SEC-01 /
/// R-PRIV-01 tételek közül a threat model A6.2.5 CSAM-hash és
/// moderátori SLA fele szervezeti döntés, nem kód) — a teljes út
/// viszont kész és a flaggel bekapcsolva tesztelt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/post_composer_controller.dart';
import '../../domain/entities/community_media.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';
import '../widgets/community_media_tile.dart';
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
    final mediaEnabled = ref.watch(
      appConfigProvider.select((cfg) => cfg.flags.communityMediaEnabled),
    );

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
            onRemoveMediaPressed: _onRemoveMediaPressed,
            mediaEnabled: mediaEnabled,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
        ),
      ),
    );
  }

  void _onAttachMediaPressed() {
    ref.read(postComposerControllerProvider.notifier).attachMedia();
  }

  void _onRemoveMediaPressed(String mediaPublicId) {
    ref
        .read(postComposerControllerProvider.notifier)
        .removeMedia(mediaPublicId);
  }
}

enum _PreviewFlag { chordTimeline, strumPattern, tempo, streakDays, bestScore }

/// Egy megjelenítendő csatolmány: az azonosító mindig megvan, a leíró nem.
typedef _AttachmentEntry = ({
  String publicId,
  CommunityMediaAttachment? descriptor,
});

/// A szerkesztőben MEGJELENÍTENDŐ csatolmányok, stabil sorrendben.
///
/// Két forrásból áll össze, és a sorrend nem esetleges:
///
/// 1. a [PostComposerState.mediaIds] — ezek mennek ki a poszttal,
///    csatolási sorrendben. Egy VISSZATÖLTÖTT piszkozatnál csak az
///    azonosító van meg (a szervernek nincs „leíró egy azonosítóhoz"
///    végpontja), ilyenkor a `descriptor` `null`, és a csempe egy
///    semleges „csatolva" arcot rajzol — kitalált `ready` állapot
///    helyett;
/// 2. utánuk azok a leírók, amelyek NEM kerültek a listába: az
///    elutasított feltöltések. Ezeket meg KELL mutatni, különben a
///    felhasználó annyit lát, hogy „nem történt semmi", és nem tudja
///    meg, miért.
List<_AttachmentEntry> _attachmentTiles(PostComposerState state) {
  final entries = <_AttachmentEntry>[
    for (final id in state.mediaIds)
      (publicId: id, descriptor: state.mediaDescriptors[id]),
  ];
  final attached = state.mediaIds.toSet();
  for (final descriptor in state.mediaDescriptors.values) {
    if (attached.contains(descriptor.publicId)) continue;
    entries.add((publicId: descriptor.publicId, descriptor: descriptor));
  }
  return entries;
}

/// Egy csatolmány sora a szerkesztőben.
class _AttachedMedia extends StatelessWidget {
  const _AttachedMedia({required this.entry, required this.onRemove});

  final _AttachmentEntry entry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final descriptor = entry.descriptor;
    if (descriptor == null) {
      return _RestoredAttachment(publicId: entry.publicId, onRemove: onRemove);
    }
    return CommunityMediaTile(
      key: Key('composer-media-${entry.publicId}'),
      media: descriptor,
      onRemove: onRemove,
    );
  }
}

/// Egy visszatöltött piszkozat csatolmánya, leíró nélkül.
///
/// SZÁNDÉKOSAN semleges: nem állítja, hogy kész, és nem rajzol
/// képet — a kliens ebben a pillanatban csak annyit tud, hogy a
/// poszthoz tartozik egy azonosító.
class _RestoredAttachment extends StatelessWidget {
  const _RestoredAttachment({required this.publicId, required this.onRemove});

  final String publicId;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: Key('composer-media-restored-$publicId'),
      leading: const Icon(Icons.attachment),
      title: Text(l10n.communityComposerMediaSectionLabel),
      trailing: IconButton(
        tooltip: l10n.communityMediaRemove,
        icon: const Icon(Icons.close),
        onPressed: onRemove,
      ),
    );
  }
}

/// Egy soros üzenet a csatolás körül (hiba vagy korlát).
class _MediaNotice extends StatelessWidget {
  const _MediaNotice({super.key, required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: isError ? theme.colorScheme.error : null,
      ),
    );
  }
}

class _ComposerBody extends StatelessWidget {
  const _ComposerBody({
    required this.state,
    required this.bodyController,
    required this.onBodyChanged,
    required this.onAudienceChanged,
    required this.onToggleField,
    required this.onSubmit,
    required this.onAttachMediaPressed,
    required this.onRemoveMediaPressed,
    required this.mediaEnabled,
  });

  final PostComposerState state;
  final TextEditingController bodyController;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<CommunityAudience> onAudienceChanged;
  final void Function(_PreviewFlag flag, bool value) onToggleField;
  final VoidCallback onSubmit;
  final VoidCallback onAttachMediaPressed;
  final ValueChanged<String> onRemoveMediaPressed;

  /// ``communityMediaEnabled`` (R21, audit MI5). Rendering the
  /// attach-media affordance while the flag is off would promise a
  /// capability the build does not have — the server would answer the
  /// framework's bare 404, since the media router is not even mounted —
  /// so the whole affordance is dropped instead of merely being
  /// disabled.
  final bool mediaEnabled;

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
    // A média-blokk három feltétele, KISZÁMÍTVA — a `canSubmit` mintája.
    // A widget-fában maradó, összetett kifejezés csak nehezebben
    // olvasható, és a `_attachmentTiles` kétszeri hívását is hozná.
    final atMediaLimit = state.mediaIds.length >= kCommunityMaxMediaPerPost;
    final canAttachMedia =
        !state.isSubmitting && !state.isAttachingMedia && !atMediaLimit;
    final attachments = _attachmentTiles(state);

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
                  if (mediaEnabled) ...<Widget>[
                    const SizedBox(height: 16),
                    SsButton(
                      key: const Key('composer-attach-media'),
                      variant: SsButtonVariant.secondary,
                      icon: Icons.attach_file,
                      label: l10n.communityComposerAttachMedia,
                      // A korlát ELÉRÉSEKOR tiltott, nem rejtett: egy
                      // eltűnő gomb azt sugallná, hogy a csatolás
                      // elromlott, holott csak betelt a négy hely.
                      onPressed: canAttachMedia ? onAttachMediaPressed : null,
                    ),
                    // MINDEN további média-widget FELTÉTELES: csatolmány,
                    // hiba és korlát nélkül a képernyő bájtra ugyanaz,
                    // mint R21 óta (a golden-képek e13_r33 a flaggel
                    // BEKAPCSOLVA készültek).
                    if (state.mediaError != null) ...<Widget>[
                      const SizedBox(height: 8),
                      _MediaNotice(
                        key: const Key('composer-media-error'),
                        text: l10n.communityComposerMediaUploadFailed,
                        isError: true,
                      ),
                    ],
                    if (atMediaLimit) ...<Widget>[
                      const SizedBox(height: 8),
                      _MediaNotice(
                        key: const Key('composer-media-limit'),
                        text: l10n.communityComposerMediaLimitReached,
                        isError: false,
                      ),
                    ],
                    if (attachments.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _SectionLabel(
                        label: l10n.communityComposerMediaSectionLabel,
                      ),
                      const SizedBox(height: 8),
                      for (final entry in attachments) ...<Widget>[
                        _AttachedMedia(
                          entry: entry,
                          onRemove: state.isSubmitting
                              ? null
                              : () => onRemoveMediaPressed(entry.publicId),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
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
