/// Tutor Chat composer (E04-R18 §5.1).
///
/// A bottom-anchored text field + send button. The composer is its own
/// `ConsumerStatefulWidget` so the local `TextEditingController` lives
/// here and the parent screen does not own the draft state — the
/// `TutorChatController` does. When the controller's draft changes
/// from elsewhere (e.g. `send()` clears it), the composer listens to
/// the state stream and syncs the text controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../providers/tutor_providers.dart';

class TutorComposer extends ConsumerStatefulWidget {
  const TutorComposer({super.key});

  @override
  ConsumerState<TutorComposer> createState() => _TutorComposerState();
}

class _TutorComposerState extends ConsumerState<TutorComposer> {
  late final TextEditingController _textController;
  String _lastSeenDraft = '';

  @override
  void initState() {
    super.initState();
    final controller = ref.read(tutorChatControllerProvider);
    _textController = TextEditingController(text: controller.draft);
    _lastSeenDraft = controller.draft;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _syncDraftIfChanged(String next) {
    if (next == _lastSeenDraft) return;
    _lastSeenDraft = next;
    if (_textController.text == next) return;
    _textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(tutorChatControllerProvider);
    final chatState = ref.watch(tutorChatStateProvider).value;
    final status = chatState?.status ?? controller.status;
    final draft = chatState?.draft ?? controller.draft;
    final canSend = !status.isActive && draft.trim().isNotEmpty;

    // After the controller clears its draft (send / cancel / reset),
    // the local text field must follow. We only sync when the
    // controller-driven draft differs from what we last rendered.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncDraftIfChanged(draft),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: (value) {
                  _lastSeenDraft = value;
                  controller.setDraft(value);
                },
                onSubmitted: (_) {
                  if (canSend) controller.send();
                },
                decoration: InputDecoration(
                  hintText: l10n.aiTutorChatComposerHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: l10n.aiTutorChatSendSemantics,
              icon: const Icon(Icons.send),
              onPressed: canSend ? controller.send : null,
            ),
          ],
        ),
      ),
    );
  }
}
