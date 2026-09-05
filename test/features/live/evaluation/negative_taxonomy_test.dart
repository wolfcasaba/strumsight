import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/negative_taxonomy.dart';

void main() {
  const parser = NegativeTaxonomyParser();

  Map<String, Object?> taxonomyJson(int categoryCount) => <String, Object?>{
    'schemaVersion': '1',
    'categories': [
      for (var i = 0; i < categoryCount; i++)
        {
          'id': 'category$i',
          'label': 'Category $i',
          'description': 'test category $i',
        },
    ],
  };

  group(
    'minimum category count is inclusive at 10 (acceptance 1, ADR 0521 D7)',
    () {
      test('9 categories (below the threshold) is rejected', () {
        expect(
          () => parser.parse(taxonomyJson(9)),
          throwsA(
            isA<NegativeTaxonomyException>().having(
              (e) => e.kind,
              'kind',
              NegativeTaxonomyErrorKind.tooFewCategories,
            ),
          ),
        );
      });

      test('exactly 10 categories (on the threshold) is accepted', () {
        final taxonomy = parser.parse(taxonomyJson(10));
        expect(taxonomy.categories, hasLength(10));
      });

      test('11 categories (above the threshold) is accepted', () {
        final taxonomy = parser.parse(taxonomyJson(11));
        expect(taxonomy.categories, hasLength(11));
      });
    },
  );

  group('unknown category (acceptance 2, ADR 0521 D7)', () {
    final taxonomy = parser.parse(taxonomyJson(10));

    test('NegativeTaxonomy.categoryById throws a typed exception, not null '
        'and not a bare StateError', () {
      expect(
        () => taxonomy.categoryById('doesNotExist'),
        throwsA(
          isA<NegativeTaxonomyException>().having(
            (e) => e.kind,
            'kind',
            NegativeTaxonomyErrorKind.unknownCategory,
          ),
        ),
      );
    });

    test('parsing a fixture-annotation segment with an unknown categoryId '
        'throws the same typed exception, never falling into an "other" '
        'bucket', () {
      final sampleJson = <String, Object?>{
        'schemaVersion': '1',
        'segments': [
          {
            'id': 'seg-1',
            'categoryId': 'notInTaxonomy',
            'startMs': 0,
            'endMs': 1000,
          },
        ],
      };
      expect(
        () => parser.parseSample(sampleJson, taxonomy),
        throwsA(
          isA<NegativeTaxonomyException>().having(
            (e) => e.kind,
            'kind',
            NegativeTaxonomyErrorKind.unknownCategory,
          ),
        ),
      );
    });

    test('a segment naming a real category parses cleanly', () {
      final sampleJson = <String, Object?>{
        'schemaVersion': '1',
        'segments': [
          {
            'id': 'seg-1',
            'categoryId': 'category0',
            'startMs': 0,
            'endMs': 1000,
            'sourceRef': 'external://log#1',
          },
        ],
      };
      final sample = parser.parseSample(sampleJson, taxonomy);
      expect(sample.segments.single.categoryId, 'category0');
      expect(sample.segments.single.sourceRef, 'external://log#1');
    });
  });

  group('duplicate category ids are rejected', () {
    test('two categories sharing an id is a typed error', () {
      final json = taxonomyJson(10);
      (json['categories']! as List)[1] = {
        'id': 'category0',
        'label': 'dup',
        'description': 'dup',
      };
      expect(
        () => parser.parse(json),
        throwsA(
          isA<NegativeTaxonomyException>().having(
            (e) => e.kind,
            'kind',
            NegativeTaxonomyErrorKind.duplicateCategoryId,
          ),
        ),
      );
    });
  });

  group('typed schema/shape errors', () {
    test('unsupported schemaVersion is typed, not silently accepted', () {
      expect(
        () => parser.parse({'schemaVersion': '99', 'categories': <Object?>[]}),
        throwsA(
          isA<NegativeTaxonomyException>().having(
            (e) => e.kind,
            'kind',
            NegativeTaxonomyErrorKind.unknownSchemaVersion,
          ),
        ),
      );
    });

    test('an unknown top-level field is a typed unknownField rejection', () {
      final json = taxonomyJson(10);
      json['extra'] = true;
      expect(
        () => parser.parse(json),
        throwsA(
          isA<NegativeTaxonomyException>().having(
            (e) => e.kind,
            'kind',
            NegativeTaxonomyErrorKind.unknownField,
          ),
        ),
      );
    });
  });

  group('the shipped taxonomy and CI fixture', () {
    test(
      'negative_taxonomy.json parses to at least 10 unique categories',
      () async {
        final source = await File(
          'evaluation/recognition/negative_taxonomy.json',
        ).readAsString();
        final taxonomy = parser.parseJsonString(source);
        expect(
          taxonomy.categories.length,
          greaterThanOrEqualTo(minimumNegativeTaxonomyCategoryCount),
        );
        expect(
          taxonomy.categories.map((c) => c.id).toSet().length,
          taxonomy.categories.length,
        );
      },
    );

    test('negative_taxonomy_sample.json fixture parses and every segment '
        'names a real category from the shipped taxonomy', () async {
      final taxonomySource = await File(
        'evaluation/recognition/negative_taxonomy.json',
      ).readAsString();
      final taxonomy = parser.parseJsonString(taxonomySource);
      final sampleSource = await File(
        'evaluation/recognition/fixtures/negative_taxonomy_sample.json',
      ).readAsString();
      final sample = parser.parseSampleJsonString(sampleSource, taxonomy);
      expect(sample.segments, isNotEmpty);
      for (final segment in sample.segments) {
        expect(
          taxonomy.categories.map((c) => c.id),
          contains(segment.categoryId),
        );
      }
    });
  });
}
