import 'package:flutter/material.dart';

import '../../analyze/widgets/timeline_view.dart';
import '../model/analyzed_session.dart';

/// Full-screen view of a saved session's chord + strum timeline.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.session});

  final AnalyzedSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(session.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: TimelineView(result: session.result),
        ),
      ),
    );
  }
}
