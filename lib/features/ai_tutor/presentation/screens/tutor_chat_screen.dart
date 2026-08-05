/// Tutor Chat screen (E04-R18 §3 + §6).
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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/controller/tutor_state.dart';
import '../../domain/models/tutor_content_block.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_message.dart';
import '../providers/tutor_providers.dart';
import '../widgets/tutor_banners.dart';
import '../widgets/tutor_composer.dart';
import '../widgets/tutor_message_bubble.dart';

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
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(l10n.aiTutorChatTitle),
          actions: <Widget>[
            if (status.isActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: messages[index],
                        ),
                      ),
              ),
              if (status == TutorTurnStatus.streaming)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      label: l10n.aiTutorChatStreamingSemantics,
                      liveRegion: true,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
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

class _BannerSlot extends StatelessWidget {
  const _BannerSlot({required this.kind, required this.controller});

  final TutorBannerKind kind;
  final TutorChatController controller;

  @override
  Widget build(BuildContext context) {
    return TutorBanner(kind: kind, onRetry: controller.retry);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 48),
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.aiTutorChatEmptyTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.aiTutorChatEmptyBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
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
    return TutorMessageBubble(message: message);
  }
}
