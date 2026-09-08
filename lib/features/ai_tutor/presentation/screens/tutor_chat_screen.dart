/// Tutor Chat screen (E04-R18 §3 + §6, design-system migration E15-R09).
///
/// A virtualized message list + composer + banners. The screen is a
/// pure `ConsumerWidget`; all state lives in [TutorChatController].
///
/// Streaming-batching: the screen renders a single `Semantics` node
/// with label "Generating response" while the controller is in the
/// streaming state — the screen reader announces the bubble once per
/// turn, not once per token. Scroll-anchoring: a new bubble that
/// exceeds the viewport pushes the list to the bottom.
///
/// Raw-HTML / unknown-block safety: the bubble renders unknown blocks
/// verbatim inside a monospaced panel (see `tutor_message_bubble.dart`).
/// The screen never passes raw text through a HTML parser.
///
/// Unlike [TutorHomeScreen], this screen's own pinned widget test
/// (`tutor_chat_screen_test.dart`) IS on the E15-R09 `allowed_paths` list
/// and its bare `MaterialApp` is wired with `theme: SsLightTheme.data()`
/// (§0.0.A/R3) — so the AI-mode indicator below safely uses the
/// theme-extension `SsProvenanceBadge` instead of a plain-[Theme] rebuild.
///
/// The streaming pill next to it is [SsSkeleton] (a small `SsRadius.pill`
/// circle), not a raw [CircularProgressIndicator] — javító kör #1,
/// §0.0.B/R13: §5.2 names a raw spinner as an unacceptable weakening, and
/// [SsSkeleton] is this design system's one loading primitive.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controller/tutor_state.dart';
import '../../domain/models/tutor_content_block.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_message.dart';
import '../providers/tutor_providers.dart';
import '../widgets/tutor_banners.dart';
import '../widgets/tutor_composer.dart';
import '../widgets/tutor_message_bubble.dart';
import '../widgets/tutor_source_sheet.dart';

/// The Chat's way back (2026-09-07 audit).
///
/// The screen is reached two ways: PUSHED from the Tutor Home (a route to
/// pop back to) and via a `/tutor/chat` deep link, which leaves nothing to
/// pop. There the bare `maybePop` this button used to call silently
/// no-ops — a back arrow that does nothing at all. The fallback goes to
/// the Tutor Home, which is registered under the very same `aiTutorEnabled`
/// gate as this screen, so it can never point at an unregistered path.
Future<void> _leaveChat(BuildContext context) async {
  final navigator = Navigator.of(context);
  final router = GoRouter.maybeOf(context);
  final popped = await navigator.maybePop();
  if (popped || router == null) return;
  router.go(AppRoutes.tutorHome);
}

class TutorChatScreen extends ConsumerStatefulWidget {
  const TutorChatScreen({super.key});

  @override
  ConsumerState<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends ConsumerState<TutorChatScreen> {
  final ScrollController _scrollController = ScrollController();
  late final TutorChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(tutorChatControllerProvider);
    // The controller is a `ChangeNotifier`-like seam — when it
    // notifies (test fakes call `notifyListeners()` after `addMessage`,
    // and the production controller does the same from `_emit()`),
    // we rebuild so the freshly appended message renders without
    // waiting for the `StreamProvider` microtask round-trip.
    if (_controller is Listenable) {
      (_controller as Listenable).addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    if (_controller is Listenable) {
      (_controller as Listenable).removeListener(_onControllerChanged);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    // Scroll-anchoring: when a new bubble arrives or the streaming
    // text grows, push the list to the bottom on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= position.pixels) return;
    position.jumpTo(position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final chatState = ref.watch(tutorChatStateProvider).value;

    final status = chatState?.status ?? controller.status;
    final responseText = chatState?.responseText ?? controller.responseText;
    final banners = chatState?.banners ?? controller.banners;
    final isOnline = chatState?.isOnline ?? controller.isOnline;
    final aiMode = tutorAiModeFor(status: status, isOnline: isOnline);
    final visibleMessages = chatState?.messages ?? controller.messages;
    final messages = <_ChatBubble>[
      for (final message in visibleMessages) _ChatBubble.fromMessage(message),
      if (status == TutorTurnStatus.streaming)
        _ChatBubble.fromStreamingText(
          responseText,
          keyId: TutorMessageId('streaming'),
        ),
    ];

    return Semantics(
      container: true,
      label: l10n.aiTutorChatScreenSemantics,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _leaveChat(context),
          ),
          title: Text(l10n.aiTutorChatTitle),
          actions: <Widget>[
            // Always visible regardless of turn status (ADR 0278 §1,
            // E13-R29 §5.2) — this is the screen-level anchor; the
            // streaming indicator below repeats it at message level.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SsSpacing.space2),
              child: _AiModeIndicator(mode: aiMode),
            ),
            if (status.isActive)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SsSpacing.space2,
                ),
                child: TextButton.icon(
                  onPressed: controller.cancel,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(l10n.aiTutorChatCancel),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              for (final kind in banners)
                _BannerSlot(kind: kind, controller: controller),
              Expanded(
                child: messages.isEmpty
                    ? _EmptyState(scrollController: _scrollController)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: SsSpacing.space4,
                          vertical: SsSpacing.space3,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: SsSpacing.space2,
                          ),
                          child: messages[index],
                        ),
                      ),
              ),
              if (status == TutorTurnStatus.streaming)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SsSpacing.space4,
                    vertical: SsSpacing.space1,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      label: l10n.aiTutorChatStreamingSemantics,
                      liveRegion: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SsSkeleton(
                            width: 12,
                            height: 12,
                            radius: SsRadius.pill,
                          ),
                          const SizedBox(width: SsSpacing.space2),
                          _AiModeIndicator(mode: aiMode),
                        ],
                      ),
                    ),
                  ),
                ),
              const TutorComposer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the consent banner's call to action goes (2026-09-08 re-audit,
/// MAJOR M3).
///
/// [TutorBanner] has always rendered a "Grant consent" button for
/// [TutorBannerKind.consent], but the chat screen never passed
/// `onConsent` — so that [TextButton] was built with a null `onPressed`
/// and was PERMANENTLY DISABLED. The student was told, on the one screen
/// where it matters, that model use is not granted, and given a greyed-out
/// button as the way to fix it.
///
/// The destination is the app's single consent surface, the Tutor Privacy
/// screen, whose `tutorConsentAxisModelUse` switch is the only thing in
/// `lib/**` that calls `TutorConsentController.grantModelUse` — the banner
/// deliberately does NOT grant consent by itself: ADR 0132 §1/§3 requires
/// the student to read the axis and decide, not to tap a chat banner.
///
/// `push`, not `go`: the student returns to the conversation they were
/// already in. The route is registered under the very same `aiTutorEnabled`
/// gate as this screen (`app_router.dart`), so it can never be an
/// unregistered path.
void _openConsent(BuildContext context) {
  GoRouter.maybeOf(context)?.push(AppRoutes.tutorPrivacy);
}

class _BannerSlot extends StatelessWidget {
  const _BannerSlot({required this.kind, required this.controller});

  final TutorBannerKind kind;
  final TutorChatController controller;

  @override
  Widget build(BuildContext context) {
    return TutorBanner(
      kind: kind,
      onRetry: controller.retry,
      onConsent: () => _openConsent(context),
    );
  }
}

/// The "no messages yet" prompt. NOT [SsEmptyState]: that component
/// requires a caller-supplied `onAction` (ADR 0277 §5 — an empty state must
/// name a next step), but this screen's real next step is typing in the
/// always-visible [TutorComposer] below, not a button this widget could
/// wire up itself (§0.0.A/R6 exception class — same as the E15-R04/R06/
/// R07/R08 precedent). Still fully token-styled via [SsColorScheme]/
/// [SsTypography]/[SsSpacing], never a bare [Theme] read.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(SsSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: SsSpacing.space12),
          Icon(Icons.chat_bubble_outline, size: 48, color: colors.brand),
          const SizedBox(height: SsSpacing.space3),
          Text(
            l10n.aiTutorChatEmptyTitle,
            textAlign: TextAlign.center,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            l10n.aiTutorChatEmptyBody,
            textAlign: TextAlign.center,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble._(this.message);

  final TutorMessage message;

  factory _ChatBubble.fromMessage(TutorMessage message) =>
      _ChatBubble._(message);

  factory _ChatBubble.fromStreamingText(
    String text, {
    required TutorMessageId keyId,
  }) {
    final createdAt = DateTime.now().toUtc();
    return _ChatBubble._(
      TutorMessage(
        id: keyId,
        role: TutorMessageRole.tutor,
        createdAt: createdAt,
        sequence: 0,
        deliveryState: TutorMessageDeliveryState.streaming,
        blocks: <TutorContentBlock>[
          if (text.isEmpty)
            TutorTextBlock(text: ' ')
          else
            TutorTextBlock(text: text),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TutorMessageBubble(
      message: message,
      // M13 (R33) — the rendered source line is what opens the evidence
      // sheet. `showTutorSourceSheet` had no `lib/**` caller before
      // this: the citation was drawn and could not be inspected.
      onSourceTap: (block) => showTutorSourceSheet(
        context,
        TutorSourceSheet.forSourceBlock(
          title: block.title,
          reference: block.reference,
        ),
      ),
    );
  }
}

/// The AI-mode indicator (ADR 0278 §1, E13-R29 §5.2) — an [SsProvenanceBadge]
/// (safe here: see the file doc comment on why this screen, unlike
/// [TutorHomeScreen], can use theme-extension `Ss*` components). Fallback
/// reuses the local badge (the fallback path answers FROM the local model)
/// plus an explicit trailing notice — meaning is carried by icon+text
/// together, never colour alone (same rule [SsProvenanceBadge] itself
/// documents).
class _AiModeIndicator extends StatelessWidget {
  const _AiModeIndicator({required this.mode});

  final TutorAiMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provenance = switch (mode) {
      TutorAiMode.cloud => SsProvenanceKind.cloud,
      TutorAiMode.local || TutorAiMode.fallback => SsProvenanceKind.local,
    };
    if (mode != TutorAiMode.fallback) {
      return SsProvenanceBadge(l10n: l10n, kind: provenance);
    }
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    // §0.0.B/R14 (measured via the committed textScaler 2.0 cells): this
    // widget renders inside `AppBar.actions`, which lays each action out at
    // its OWN natural width before the title claims the remainder — an
    // ambient constraint neither [SsProvenanceBadge]'s own internal
    // `Flexible` nor a `Flexible` wrapped around the trailing text here can
    // see through, since both are non-flexible siblings free to claim
    // whatever width they naturally need first (measured: `RenderFlex
    // overflowed by 1187 pixels`, en, textScaler 2.0, before either bound
    // existed). Bounding EACH piece's own width directly — not via the
    // Row's flex negotiation — clips both deterministically regardless of
    // locale or the ambient constraint.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: SsProvenanceBadge(l10n: l10n, kind: provenance),
        ),
        const SizedBox(width: SsSpacing.space1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 90),
          child: Text(
            l10n.aiTutorAiModeFallbackMessage,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
