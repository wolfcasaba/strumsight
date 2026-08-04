import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/song_event_reference.dart';
import '../../domain/models/song_id.dart';
import 'song_trainer_result.dart';

/// Maps the final Practice attempt back onto revisioned song coordinates.
///
/// A missing reference is a compiler/result contract violation. Silently
/// dropping a verdict would make a measure look better than it was, so the
/// mapper fails closed instead.
abstract final class SongResultMapper {
  static SongTrainerResult map({
    required PracticeSessionResult sessionResult,
    required Map<String, SongEventReference> references,
  }) {
    final attempt = sessionResult.finalAttempt;
    if (attempt == null) {
      return SongTrainerResult(
        sessionResult: sessionResult,
        verdicts: const <SongTrainerVerdict>[],
        measureResults: const <SongMeasureTrainerResult>[],
        sectionResults: const <SongSectionTrainerResult>[],
      );
    }

    final mapped = <SongTrainerVerdict>[];
    for (final verdict in attempt.verdicts) {
      final reference =
          references[verdict.targetEventId] ??
          references[_definitionEventIdFromCompiledTarget(
            verdict.targetEventId,
          )];
      if (reference == null) {
        throw StateError(
          'Missing song event reference for ${verdict.targetEventId}.',
        );
      }
      mapped.add(SongTrainerVerdict(verdict: verdict, reference: reference));
    }

    return SongTrainerResult(
      sessionResult: sessionResult,
      verdicts: List<SongTrainerVerdict>.unmodifiable(mapped),
      measureResults: _measureResults(mapped),
      sectionResults: _sectionResults(mapped),
    );
  }

  static List<SongMeasureTrainerResult> _measureResults(
    List<SongTrainerVerdict> verdicts,
  ) {
    final byMeasure = <int, List<SongTrainerVerdict>>{};
    for (final verdict in verdicts) {
      byMeasure
          .putIfAbsent(
            verdict.reference.measureIndex,
            () => <SongTrainerVerdict>[],
          )
          .add(verdict);
    }
    final keys = byMeasure.keys.toList()..sort();
    return List<SongMeasureTrainerResult>.unmodifiable([
      for (final measure in keys)
        SongMeasureTrainerResult(
          measureIndex: measure,
          verdicts: List<SongTrainerVerdict>.unmodifiable(byMeasure[measure]!),
          averageEventScore: _average(byMeasure[measure]!),
        ),
    ]);
  }

  static List<SongSectionTrainerResult> _sectionResults(
    List<SongTrainerVerdict> verdicts,
  ) {
    final bySection = <SongSectionId?, List<SongTrainerVerdict>>{};
    for (final verdict in verdicts) {
      bySection
          .putIfAbsent(
            verdict.reference.sectionId,
            () => <SongTrainerVerdict>[],
          )
          .add(verdict);
    }
    final keys = bySection.keys.toList()
      ..sort((a, b) => (a?.value ?? '').compareTo(b?.value ?? ''));
    return List<SongSectionTrainerResult>.unmodifiable([
      for (final section in keys)
        SongSectionTrainerResult(
          sectionId: section,
          verdicts: List<SongTrainerVerdict>.unmodifiable(bySection[section]!),
          averageEventScore: _average(bySection[section]!),
        ),
    ]);
  }

  static double _average(List<SongTrainerVerdict> verdicts) =>
      verdicts.fold<double>(0, (sum, value) => sum + value.verdict.eventScore) /
      verdicts.length;

  /// `compilePracticeTarget` appends `@<loopIndex>` to authored event IDs.
  /// Source references stay keyed by the authored ID, so remove only that
  /// compiler-proven numeric suffix.
  static String _definitionEventIdFromCompiledTarget(String targetEventId) {
    final marker = targetEventId.lastIndexOf('@');
    if (marker < 0 || marker == targetEventId.length - 1) {
      return targetEventId;
    }
    final loopIndex = int.tryParse(targetEventId.substring(marker + 1));
    return loopIndex == null
        ? targetEventId
        : targetEventId.substring(0, marker);
  }
}
