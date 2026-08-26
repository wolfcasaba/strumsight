import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/public.dart';
import '../chord_shape.dart';
import '../providers/favorite_chords_provider.dart';
import 'chord_diagram.dart';

/// The chord library's detail view (ADR 0282 §6 / A6): a bigger diagram, the
/// fingering (spoken via [ChordDiagram]'s own semantics), related chords
/// sharing the same root — the app's real "variation" concept, since one
/// canonical shape exists per label, not multiple voicings — and the
/// practice action, which opens a lesson built around THIS chord, never the
/// library's first entry. Reached by `Navigator.push` (no new route — the
/// two migrated routes stay the only entries, R8).
class ChordDetailView extends ConsumerWidget {
  const ChordDetailView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shape = ChordShapes.forLabel(label);
    final favorites = ref.watch(favoriteChordsProvider);
    final isFavorite = favorites.contains(label);
    final related = [
      for (final other in ChordShapes.allLabels)
        if (other != label && _root(other) == _root(label)) other,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        actions: [
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
            tooltip: l10n.chordGroupFavorites,
            color: isFavorite ? AppColors.secondary : null,
            onPressed: () =>
                ref.read(favoriteChordsProvider.notifier).toggle(label),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: ChordDiagram(label: label, size: 180, showLabel: false),
            ),
            if (shape == null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  l10n.chordDiagramUnavailable(label),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (related.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                l10n.chordDetailRelated.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final other in related)
                    ActionChip(
                      label: Text(other),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChordDetailView(label: other),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('chord-detail-practice-action'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      LearnScreen(lesson: Lessons.forChordPractice(label)),
                ),
              ),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.learnPracticeThis),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _root(String label) {
    final rootLen = (label.length > 1 && (label[1] == '#' || label[1] == 'b'))
        ? 2
        : 1;
    return label.substring(0, rootLen);
  }
}
