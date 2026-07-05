import 'package:flutter/material.dart';

import '../../../core/widgets/coming_soon_view.dart';
import '../../../l10n/app_localizations.dart';

/// Analyze (recorded/MP4 → timeline) ships in v2; this is its empty state.
class AnalyzePlaceholderScreen extends StatelessWidget {
  const AnalyzePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ComingSoonView(
      icon: Icons.multitrack_audio,
      title: l10n.navAnalyze,
      body: l10n.analyzeIntro,
    );
  }
}
