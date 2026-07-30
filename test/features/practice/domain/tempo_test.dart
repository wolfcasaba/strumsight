import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('Tempo validation', () {
    test('accepts the closed 30.0 through 300.0 BPM boundaries', () {
      expect(const Tempo(30.0).validate(), isEmpty);
      expect(const Tempo(300.0).validate(), isEmpty);
      expect(const Tempo(120.0).validate(), isEmpty);
    });

    test('reports finite values outside the range without clamping', () {
      const below = Tempo(29.999);
      const above = Tempo(300.001);

      expect(below.bpm, 29.999);
      expect(above.bpm, 300.001);
      expect(below.validate().map((failure) => failure.code), [
        PracticeValidationCode.tempoBpmOutOfRange,
      ]);
      expect(above.validate().map((failure) => failure.code), [
        PracticeValidationCode.tempoBpmOutOfRange,
      ]);
    });

    test('reports NaN and infinities as not finite', () {
      for (final bpm in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(Tempo(bpm).validate().map((failure) => failure.code), [
          PracticeValidationCode.tempoBpmNotFinite,
        ]);
      }
    });
  });

  group('Tempo value semantics', () {
    test('uses BPM as its value identity', () {
      const tempo = Tempo(120.0);
      const sameValue = Tempo(120.0);

      expect(tempo, sameValue);
      expect(tempo.hashCode, sameValue.hashCode);
      expect(tempo, isNot(const Tempo(121.0)));
      expect(tempo.toString(), 'Tempo(120.0 BPM)');
    });
  });
}
