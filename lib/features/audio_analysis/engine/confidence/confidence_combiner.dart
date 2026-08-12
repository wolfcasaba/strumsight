import 'dart:math' as math;

/// Deterministic result of combining independent confidence factors.
final class ConfidenceCombination {
  const ConfidenceCombination({
    required this.confidence,
    required this.hardGateOpen,
  });

  final double confidence;
  final bool hardGateOpen;
}

/// Combines independent evidence without hiding one weak factor in an average.
///
/// The geometric mean gives signal quality, model confidence and alignment
/// equal influence while making one weak factor materially lower the result.
/// A closed hard gate (insufficient events or unavailable model) publishes no
/// confidence at all. Zero factors are clipped to [minimumFactor] only in the
/// geometric calculation so its logarithm remains defined.
final class ConfidenceCombiner {
  ConfidenceCombiner({this.minimumFactor = 1e-6}) {
    if (!minimumFactor.isFinite || minimumFactor <= 0 || minimumFactor > 1) {
      throw ArgumentError.value(
        minimumFactor,
        'minimumFactor',
        'must be finite and in (0, 1]',
      );
    }
  }

  final double minimumFactor;

  ConfidenceCombination combine(
    List<double> factors, {
    bool hardGateOpen = true,
  }) {
    if (factors.isEmpty ||
        factors.any((value) => !value.isFinite || value < 0 || value > 1)) {
      throw ArgumentError('Confidence factors must be finite and in [0, 1].');
    }
    if (!hardGateOpen) {
      return const ConfidenceCombination(confidence: 0, hardGateOpen: false);
    }
    final logSum = factors.fold<double>(
      0,
      (sum, factor) => sum + math.log(math.max(minimumFactor, factor)),
    );
    return ConfidenceCombination(
      confidence: math.exp(logSum / factors.length).clamp(0.0, 1.0),
      hardGateOpen: true,
    );
  }
}
