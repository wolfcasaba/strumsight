import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../analyze/widgets/timeline_view.dart';
import '../../learn/model/lesson.dart';
import '../../learn/screens/learn_screen.dart';
import '../../live/model/chord.dart';
import '../../settings/providers/capo_provider.dart';
import '../../share/screens/share_preview_screen.dart';
import '../model/analyzed_session.dart';
import '../providers/library_providers.dart';

/// Full-screen view of a saved session's chord + strum timeline.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.session});

  final AnalyzedSession session;

  Future<void> _rename(
      BuildContext context, WidgetRef ref, AnalyzedSession live) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: live.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.libraryRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.songSave),
          ),
        ],
      ),
    );
    if (name != null) {
      await ref.read(libraryProvider.notifier).rename(live.id, name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capo = ref.watch(capoProvider);
    final l10n = AppLocalizations.of(context);
    // A rename must show immediately: prefer the LIVE copy from the library
    // over the (immutable) route argument.
    final sessions = ref.watch(libraryProvider).value;
    final live = sessions?.firstWhere((s) => s.id == session.id,
            orElse: () => session) ??
        session;
    return Scaffold(
      appBar: AppBar(
        title: Text(Chord.transposeSummary(live.title, -capo)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.libraryRename,
            onPressed: () => _rename(context, ref, live),
          ),
          if (live.result.strums.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.school_outlined),
              tooltip: l10n.learnPracticeThis,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LearnScreen(
                    lesson: Lessons.fromAnalyze(live.result,
                        name: live.title),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.actionShare,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SharePreviewScreen(
                  result: live.result,
                  capo: capo,
                  title: live.title,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: TimelineView(result: live.result, capo: capo),
        ),
      ),
    );
  }
}
