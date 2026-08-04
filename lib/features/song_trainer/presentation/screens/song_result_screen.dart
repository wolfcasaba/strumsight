// Song Trainer result screen.
//
// Brief §6 acceptance: "Chord/direction/note verdict, accessible measure
// heatmap, problem range retry és next section működik."

import 'package:flutter/material.dart';

import '../../application/trainer/song_trainer_result.dart';
import '../widgets/measure_heatmap.dart';

/// Post-session result screen for the Song Trainer coach.
final class SongResultScreen extends StatelessWidget {
  const SongResultScreen({
    super.key,
    required this.result,
    this.onRetry,
    this.onNextSection,
  });

  final SongTrainerResult result;
  final VoidCallback? onRetry;
  final VoidCallback? onNextSection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Song Trainer result')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            MeasureHeatmap(
              measureResults: result.measureResults,
              sectionResults: result.sectionResults,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('song-result-retry'),
              onPressed: onRetry,
              child: const Text('Retry problem range'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('song-result-next-section'),
              onPressed: onNextSection,
              child: const Text('Next section'),
            ),
          ],
        ),
      ),
    );
  }
}
