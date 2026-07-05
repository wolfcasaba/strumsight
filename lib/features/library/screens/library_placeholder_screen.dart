import 'package:flutter/material.dart';

import '../../../core/widgets/coming_soon_view.dart';
import '../../../l10n/app_localizations.dart';

/// Library (saved sessions) ships in v2; this is its empty state.
class LibraryPlaceholderScreen extends StatelessWidget {
  const LibraryPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ComingSoonView(
      icon: Icons.library_music_outlined,
      title: l10n.navLibrary,
      body: l10n.libraryIntro,
    );
  }
}
