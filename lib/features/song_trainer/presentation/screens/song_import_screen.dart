import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../widgets/guitar_pro_conversion_guidance.dart';

/// Route-ready entry point for the import guidance UI.
final class SongImportScreen extends StatelessWidget {
  const SongImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songImportTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: const GuitarProConversionGuidance(),
        ),
      ),
    );
  }
}
