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

/// Full-screen view of a saved session's chord + strum timeline.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.session});

  final AnalyzedSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capo = ref.watch(capoProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(Chord.transposeSummary(session.title, -capo)),
        actions: [
          if (session.result.strums.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.school_outlined),
              tooltip: l10n.learnPracticeThis,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LearnScreen(
                    lesson: Lessons.fromAnalyze(session.result,
                        name: session.title),
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
                  result: session.result,
                  capo: capo,
                  title: session.title,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: TimelineView(result: session.result, capo: capo),
        ),
      ),
    );
  }
}
