import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/song_event_reference.dart';
import '../../domain/models/song_id.dart';

/// One Practice verdict enriched with its stable song coordinates.
final class SongTrainerVerdict {
  const SongTrainerVerdict({required this.verdict, required this.reference});

  final PracticeVerdict verdict;
  final SongEventReference reference;
}

/// Aggregated result for one measure in the final scored attempt.
final class SongMeasureTrainerResult {
  SongMeasureTrainerResult({
    required this.measureIndex,
    required List<SongTrainerVerdict> verdicts,
    required this.averageEventScore,
  }) : verdicts = List<SongTrainerVerdict>.unmodifiable(verdicts);

  final int measureIndex;
  final List<SongTrainerVerdict> verdicts;
  final double averageEventScore;
}

/// Aggregated result for one section in the final scored attempt.
final class SongSectionTrainerResult {
  SongSectionTrainerResult({
    required this.sectionId,
    required List<SongTrainerVerdict> verdicts,
    required this.averageEventScore,
  }) : verdicts = List<SongTrainerVerdict>.unmodifiable(verdicts);

  final SongSectionId? sectionId;
  final List<SongTrainerVerdict> verdicts;
  final double averageEventScore;
}

/// Practice result projected onto the song's revisioned event coordinates.
final class SongTrainerResult {
  SongTrainerResult({
    required this.sessionResult,
    required List<SongTrainerVerdict> verdicts,
    required List<SongMeasureTrainerResult> measureResults,
    required List<SongSectionTrainerResult> sectionResults,
  }) : verdicts = List<SongTrainerVerdict>.unmodifiable(verdicts),
       measureResults = List<SongMeasureTrainerResult>.unmodifiable(
         measureResults,
       ),
       sectionResults = List<SongSectionTrainerResult>.unmodifiable(
         sectionResults,
       );

  final PracticeSessionResult sessionResult;
  final List<SongTrainerVerdict> verdicts;
  final List<SongMeasureTrainerResult> measureResults;
  final List<SongSectionTrainerResult> sectionResults;
}
