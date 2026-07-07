import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analyze/widgets/timeline_view.dart';
import '../../live/model/chord.dart';
import '../../settings/providers/capo_provider.dart';
import '../model/analyzed_session.dart';

/// Full-screen view of a saved session's chord + strum timeline.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.session});

  final AnalyzedSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capo = ref.watch(capoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Chord.transposeSummary(session.title, -capo))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: TimelineView(result: session.result, capo: capo),
        ),
      ),
    );
  }
}
