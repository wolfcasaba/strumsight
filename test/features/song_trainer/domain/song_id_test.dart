import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';

void main() {
  group('SongId validation', () {
    test('accepts a non-empty trimmed identifier', () {
      final id = SongId('song-001');
      expect(id.value, 'song-001');
    });

    test('rejects empty and whitespace-only identifiers', () {
      expect(() => SongId(''), throwsA(isA<SongIdValidationException>()));
      expect(() => SongId('   '), throwsA(isA<SongIdValidationException>()));
      expect(() => SongId('\t\n'), throwsA(isA<SongIdValidationException>()));
    });

    test('trims surrounding whitespace before storing', () {
      final id = SongId('  song-7  ');
      expect(id.value, 'song-7');
    });

    test('accepts length at the boundary and rejects one above', () {
      final maxLength = SongId.maxLength;
      final boundary = 'a' * (maxLength - 1);
      final max = 'a' * maxLength;
      final over = 'a' * (maxLength + 1);
      expect(SongId(boundary).value.length, maxLength - 1);
      expect(SongId(max).value.length, maxLength);
      expect(() => SongId(over), throwsA(isA<SongIdValidationException>()));
    });

    test('rejects identifiers with characters that are not filename-safe', () {
      for (final forbidden in <String>[
        'song/01',
        'song\\01',
        'song:01',
        'song*01',
        'song?01',
        'song"01',
        'song<01',
        'song>01',
        'song|01',
        'song\x0001',
        'song\x001f',
      ]) {
        expect(
          () => SongId(forbidden),
          throwsA(isA<SongIdValidationException>()),
          reason: 'SongId must reject "$forbidden"',
        );
      }
    });

    test('accepts common filename-safe characters', () {
      const candidates = <String>[
        'song-1',
        'song_1',
        'song.1',
        'Song 01',
        'simple_id',
        'CamelCaseID',
        '12345',
      ];
      for (final value in candidates) {
        expect(
          SongId(value).value,
          value,
          reason: 'expected "$value" accepted',
        );
      }
    });
  });

  group('SongId equality and hashing', () {
    test('equal identifiers are value-equal and share a hash', () {
      final a = SongId('song-001');
      final b = SongId('song-001');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different identifiers are not equal', () {
      final a = SongId('song-001');
      final b = SongId('song-002');
      expect(a, isNot(equals(b)));
    });

    test('rejects non-SongId comparisons without throwing', () {
      final a = SongId('song-001');
      expect(a, isNot(equals('song-001' as Object)));
      expect(a, isNot(equals(42 as Object)));
      expect(a, isNot(equals(<String>['song-001'] as Object)));
    });
  });

  group('SongId safe-filename mapping', () {
    test('produces a deterministic non-empty file slug', () {
      final id = SongId('Song 01');
      final a = id.safeFilename();
      final b = id.safeFilename();
      expect(a, isNotEmpty);
      expect(a, equals(b));
      expect(a.contains(' '), isFalse);
    });

    test('does not modify the underlying identifier', () {
      final id = SongId('Song 01');
      id.safeFilename();
      id.safeFilename();
      expect(id.value, 'Song 01');
    });

    test('is stable for trimmed and untrimmed inputs with the same value', () {
      final trimmed = SongId('song-01');
      final padded = SongId('  song-01  ');
      expect(trimmed.safeFilename(), equals(padded.safeFilename()));
    });

    test('safe filename never contains filesystem separators', () {
      final ok = SongId('Song 01');
      final slug = ok.safeFilename();
      expect(slug.contains('/'), isFalse);
      expect(slug.contains('\\'), isFalse);
    });

    test('safe filename strips trailing hyphens', () {
      // Trailing hyphens and trailing spaces collapse to the cleaned
      // inner content — the trailing trim loop in [safeFilename] is
      // exercised by these inputs.
      expect(SongId('test-').safeFilename(), 'test');
      expect(SongId('test ').safeFilename(), 'test');
    });

    test(
      'safe filename validator falls back to a stable slug for unusable inputs',
      () {
        // The validator accepts only filename chars + space; a value that
        // contains only spaces is rejected at trim-time, but the static
        // safeFilename map is callable directly with an unusable input and
        // must still emit a non-empty stable slug.
        final slug = SongIdValidator.safeFilename('   ');
        expect(slug, isNotEmpty);
        expect(slug.startsWith('song-'), isTrue);
      },
    );
  });

  group('Typed ID subclasses share the same contract', () {
    test('SongSectionId trims and rejects empty and over-long values', () {
      expect(
        () => SongSectionId(''),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(
        () => SongSectionId('   '),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(
        () => SongSectionId('a' * (SongId.maxLength + 1)),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(SongSectionId(' x ').value, 'x');
    });

    test('SongTrackId trims and rejects empty and over-long values', () {
      expect(() => SongTrackId(''), throwsA(isA<SongIdValidationException>()));
      expect(
        () => SongTrackId('   '),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(
        () => SongTrackId('a' * (SongId.maxLength + 1)),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(SongTrackId(' x ').value, 'x');
    });

    test('SongEventId trims and rejects empty and over-long values', () {
      expect(() => SongEventId(''), throwsA(isA<SongIdValidationException>()));
      expect(
        () => SongEventId('   '),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(
        () => SongEventId('a' * (SongId.maxLength + 1)),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(SongEventId(' x ').value, 'x');
    });

    test('SongAssetId trims and rejects empty and over-long values', () {
      expect(() => SongAssetId(''), throwsA(isA<SongIdValidationException>()));
      expect(
        () => SongAssetId('   '),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(
        () => SongAssetId('a' * (SongId.maxLength + 1)),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(SongAssetId(' x ').value, 'x');
    });

    test('SongMarkerId trims and rejects empty and over-long values', () {
      expect(() => SongMarkerId(''), throwsA(isA<SongIdValidationException>()));
      expect(
        () => SongMarkerId('   '),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(
        () => SongMarkerId('a' * (SongId.maxLength + 1)),
        throwsA(isA<SongIdValidationException>()),
      );
      expect(SongMarkerId(' x ').value, 'x');
    });

    test('every typed ID rejects forbidden characters', () {
      for (final value in <String>['a/b', 'a\\b', 'a:b', 'a*b']) {
        expect(
          () => SongSectionId(value),
          throwsA(isA<SongIdValidationException>()),
        );
        expect(
          () => SongTrackId(value),
          throwsA(isA<SongIdValidationException>()),
        );
        expect(
          () => SongEventId(value),
          throwsA(isA<SongIdValidationException>()),
        );
        expect(
          () => SongAssetId(value),
          throwsA(isA<SongIdValidationException>()),
        );
        expect(
          () => SongMarkerId(value),
          throwsA(isA<SongIdValidationException>()),
        );
      }
    });

    test(
      'typed IDs of different kinds are not equal even with the same value',
      () {
        final asset = SongAssetId('x');
        final marker = SongMarkerId('x');
        expect(asset, isNot(equals(marker)));
      },
    );

    test('every typed ID is value-equal and hash-stable', () {
      final a = SongAssetId('asset-1');
      final b = SongAssetId('asset-1');
      final c = SongAssetId('asset-2');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('SongSourceType stability', () {
    test('round-trips every enum value through its stable code', () {
      for (final value in SongSourceType.values) {
        final resolved = songSourceTypeFromCode(value.code);
        expect(resolved, same(value));
      }
    });

    test('returns null for an unknown source code without guessing', () {
      expect(songSourceTypeFromCode('not-a-source'), isNull);
      expect(songSourceTypeFromCode(''), isNull);
    });
  });
}
