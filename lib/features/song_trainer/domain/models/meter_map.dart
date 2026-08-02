import 'song_section.dart';

final class Meter {
  Meter(this.numerator, this.denominator) {
    if (numerator <= 0 ||
        denominator <= 0 ||
        denominator & (denominator - 1) != 0) {
      throw SongStructureValidationException('meter.invalid');
    }
  }
  final int numerator;
  final int denominator;
  int get beatsPerMeasure => numerator * 4 ~/ denominator;
  @override
  bool operator ==(Object other) =>
      other is Meter &&
      other.numerator == numerator &&
      other.denominator == denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
}

final class MeterChange {
  const MeterChange({required this.atMeasure, required this.meter});
  final int atMeasure;
  final Meter meter;
}

final class MeterMap {
  MeterMap(Iterable<MeterChange> changes)
    : changes = List.unmodifiable(changes) {
    if (this.changes.any(
      (change) =>
          change.atMeasure < 0 ||
          change.meter.numerator <= 0 ||
          change.meter.denominator <= 0 ||
          change.meter.denominator & (change.meter.denominator - 1) != 0,
    )) {
      throw SongStructureValidationException('meter.invalid');
    }
    if (this.changes.isEmpty || this.changes.first.atMeasure != 0) {
      throw SongStructureValidationException('meterMap.firstBoundary.invalid');
    }
    for (var i = 1; i < this.changes.length; i++) {
      if (this.changes[i].atMeasure <= this.changes[i - 1].atMeasure) {
        throw SongStructureValidationException('meterMap.boundaries.invalid');
      }
    }
  }
  factory MeterMap.constant(Meter meter) =>
      MeterMap([MeterChange(atMeasure: 0, meter: meter)]);
  final List<MeterChange> changes;
}
