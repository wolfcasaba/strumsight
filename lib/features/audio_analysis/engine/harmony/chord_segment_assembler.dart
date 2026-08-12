import '../../domain/analysis_segment.dart';
import '../../domain/harmony/chord_frame_evidence.dart';
import 'chord_label_normalizer.dart';

/// Versioned chord segmentation settings. The defaults preserve V1 exactly.
final class ChordSegmentationPolicy {
  const ChordSegmentationPolicy({
    this.minimumSegment = Duration.zero,
    this.mergeTransientSegments = false,
    this.transientMergeWindow = Duration.zero,
    this.closeOnNoChord = false,
  });

  final Duration minimumSegment;
  final bool mergeTransientSegments;
  final Duration transientMergeWindow;
  final bool closeOnNoChord;
}

/// Builds V2 chord segments from decoder frame evidence.
final class ChordSegmentAssembler {
  const ChordSegmentAssembler({this.normalizer = const ChordLabelNormalizer()});

  final ChordLabelNormalizer normalizer;

  List<ChordSegment> assemble({
    required List<ChordFrameEvidence> frames,
    required Duration clipDuration,
    ChordSegmentationPolicy policy = const ChordSegmentationPolicy(),
  }) {
    if (clipDuration.isNegative) {
      throw ArgumentError.value(clipDuration, 'clipDuration');
    }
    if (policy.minimumSegment.isNegative) {
      throw ArgumentError.value(policy.minimumSegment, 'minimumSegment');
    }
    if (policy.transientMergeWindow.isNegative) {
      throw ArgumentError.value(
        policy.transientMergeWindow,
        'transientMergeWindow',
      );
    }
    _validateFrames(frames, clipDuration);

    final raw = <_OpenSegment>[];
    _OpenSegment? open;
    for (final frame in frames) {
      final label = frame.topLabel == null
          ? null
          : normalizer.normalize(frame.topLabel!);
      if (label == null) {
        if (policy.closeOnNoChord && open != null) {
          raw.add(open.close(frame.time));
          open = null;
        } else {
          open?.add(frame);
        }
        continue;
      }
      if (open == null) {
        open = _OpenSegment(label, frame.time)..add(frame);
      } else if (open.label == label) {
        open.add(frame);
      } else {
        raw.add(open.close(frame.time));
        open = _OpenSegment(label, frame.time)..add(frame);
      }
    }
    if (open != null) raw.add(open.close(clipDuration));

    final mergeThreshold =
        policy.mergeTransientSegments &&
            policy.transientMergeWindow > policy.minimumSegment
        ? policy.transientMergeWindow
        : policy.minimumSegment;
    final merged = mergeThreshold > Duration.zero
        ? _mergeShortSegments(raw, mergeThreshold)
        : raw;
    return List<ChordSegment>.unmodifiable(
      merged.map((segment) => segment.toChordSegment()),
    );
  }

  /// Combines DSP and ML only when its caller passes the experimental flag.
  /// Flag-off returns the original DSP objects to make parity byte-for-byte.
  List<ChordSegment> fuse({
    required List<ChordSegment> dsp,
    required List<ChordSegment> ml,
    required bool enabled,
  }) {
    if (!enabled) return dsp;
    if (dsp.length != ml.length) return dsp;
    return List<ChordSegment>.unmodifiable(<ChordSegment>[
      for (var index = 0; index < dsp.length; index++)
        _fuseSegment(dsp[index], ml[index]),
    ]);
  }

  static void _validateFrames(
    List<ChordFrameEvidence> frames,
    Duration clipDuration,
  ) {
    Duration? previous;
    for (final frame in frames) {
      if (frame.time > clipDuration) {
        throw ArgumentError.value(frame.time, 'frame.time', 'outside clip');
      }
      if (previous != null && frame.time < previous) {
        throw ArgumentError('Frames must be monotonic.');
      }
      previous = frame.time;
    }
  }

  static List<_OpenSegment> _mergeShortSegments(
    List<_OpenSegment> raw,
    Duration minimumSegment,
  ) {
    if (minimumSegment == Duration.zero) return raw;
    final segments = List<_OpenSegment>.of(raw);
    var index = 0;
    while (index < segments.length) {
      final current = segments[index];
      if (current.duration >= minimumSegment || segments.length == 1) {
        index++;
        continue;
      }
      if (index > 0) {
        segments[index - 1] = segments[index - 1].extendTo(current.end);
        segments.removeAt(index);
        index--;
      } else {
        segments[1] = segments[1].extendFrom(current.start);
        segments.removeAt(0);
      }
    }
    return segments;
  }

  static ChordSegment _fuseSegment(ChordSegment dsp, ChordSegment ml) {
    if (dsp.label == ml.label) return dsp;
    final winning = dsp.confidence >= ml.confidence ? dsp : ml;
    final other = identical(winning, dsp) ? ml : dsp;
    return ChordSegment(
      id: winning.id,
      label: winning.label,
      start: winning.start,
      end: winning.end,
      confidence: winning.confidence * other.confidence,
      source: DecoderSource.fused,
      confidenceSource: ChordConfidenceSource.heuristic,
      modelManifestId: winning.modelManifestId ?? other.modelManifestId,
    );
  }
}

final class _OpenSegment {
  _OpenSegment(this.label, this.start);

  final String label;
  final Duration start;
  Duration? _end;
  final List<ChordFrameEvidence> _frames = <ChordFrameEvidence>[];

  Duration get end => _end!;
  Duration get duration => end - start;

  void add(ChordFrameEvidence frame) => _frames.add(frame);

  _OpenSegment close(Duration end) {
    _end = end;
    return this;
  }

  _OpenSegment extendTo(Duration value) => _OpenSegment(label, start)
    .._end = value
    .._frames.addAll(_frames);

  _OpenSegment extendFrom(Duration value) => _OpenSegment(label, value)
    .._end = end
    .._frames.addAll(_frames);

  ChordSegment toChordSegment() {
    var weightedConfidence = 0.0;
    var confidenceWeight = 0;
    for (var index = 0; index < _frames.length; index++) {
      final frame = _frames[index];
      if (frame.topLabel == null || frame.topConfidence == null) continue;
      final nextTime = index + 1 == _frames.length
          ? end
          : _frames[index + 1].time;
      final weight = (nextTime - frame.time).inMicroseconds;
      if (weight <= 0) continue;
      weightedConfidence += frame.topConfidence! * weight;
      confidenceWeight += weight;
    }
    final confidence = confidenceWeight == 0
        ? 0.0
        : weightedConfidence / confidenceWeight;
    final source = _frames.isEmpty ? DecoderSource.dsp : _frames.last.source;
    String? manifestId;
    for (final frame in _frames) {
      if (frame.modelManifestId != null) {
        manifestId = frame.modelManifestId;
        break;
      }
    }
    return ChordSegment(
      label: label,
      start: start,
      end: end,
      confidence: confidence,
      source: source,
      confidenceSource: ChordConfidenceSource.heuristic,
      modelManifestId: manifestId,
    );
  }
}
