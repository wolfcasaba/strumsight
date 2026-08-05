import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';

import '../../../../tool/build_tutor_knowledge_manifest.dart';

const _codec = KnowledgeCodec();

void main() {
  late Directory temporaryDirectory;
  late _KnowledgeFixture fixture;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'strumsight-knowledge-test-',
    );
    fixture = _KnowledgeFixture(temporaryDirectory);
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('buildTutorKnowledgeManifest', () {
    test('rejects duplicate document IDs with a distinct stable code', () {
      fixture.writeDocument(_document(id: 'shared-id', locale: 'en'));
      fixture.writeDocument(_document(id: 'shared-id', locale: 'hu'));

      expect(
        fixture.build,
        throwsA(
          isA<KnowledgeManifestException>().having(
            (error) => error.code,
            'code',
            KnowledgeManifestErrorCode.duplicateId,
          ),
        ),
      );
    });

    test('rejects a missing license with a distinct stable code', () {
      final document = _document(id: 'no-license', locale: 'en');
      final map = _documentMap(document)..remove('license');
      fixture.writeRaw('en/no-license.json', jsonEncode(map));

      expect(
        fixture.build,
        throwsA(
          isA<KnowledgeManifestException>().having(
            (error) => error.code,
            'code',
            KnowledgeManifestErrorCode.missingLicense,
          ),
        ),
      );
    });

    test('rejects a content hash mismatch with a distinct stable code', () {
      final document = _document(id: 'bad-hash', locale: 'en');
      final map = _documentMap(document)
        ..['body'] = 'The source content was changed after approval.';
      fixture.writeRaw('en/bad-hash.json', jsonEncode(map));

      expect(
        fixture.build,
        throwsA(
          isA<KnowledgeManifestException>().having(
            (error) => error.code,
            'code',
            KnowledgeManifestErrorCode.hashMismatch,
          ),
        ),
      );
    });

    test('rejects corrupt content with a distinct stable code', () {
      fixture.writeRaw('en/corrupt.json', '{ this is not JSON');

      expect(
        fixture.build,
        throwsA(
          isA<KnowledgeManifestException>().having(
            (error) => error.code,
            'code',
            KnowledgeManifestErrorCode.corruptContent,
          ),
        ),
      );
    });

    test(
      'includes only explicitly approved documents in production output',
      () {
        fixture.writeDocument(_document(id: 'approved', locale: 'en'));
        fixture.writeDocument(
          _document(
            id: 'review-needed',
            locale: 'hu',
            status: KnowledgeApprovalStatus.reviewNeeded,
          ),
        );
        fixture.writeDocument(
          _document(
            id: 'rejected',
            locale: 'en',
            status: KnowledgeApprovalStatus.rejected,
          ),
        );

        fixture.build();

        final manifest = fixture.manifestMap();
        final documents = manifest['documents']! as List<Object?>;
        expect(documents, hasLength(1));
        expect((documents.single! as Map<String, Object?>)['id'], 'approved');
      },
    );

    test('writes a bit-identical manifest when built twice', () {
      fixture.writeDocument(_document(id: 'z-document', locale: 'en'));
      fixture.writeDocument(_document(id: 'a-document', locale: 'hu'));

      fixture.build();
      final first = fixture.manifestFile.readAsBytesSync();
      fixture.build();
      final second = fixture.manifestFile.readAsBytesSync();

      expect(first, equals(second));
    });

    test(
      'the committed manifest is locked to its content and chunk hashes',
      () {
        final output = File('${temporaryDirectory.path}/rebuilt-manifest.json');
        buildTutorKnowledgeManifest(
          contentRoot: Directory('assets/tutor_knowledge'),
          outputFile: output,
        );

        expect(
          output.readAsBytesSync(),
          equals(
            File('assets/tutor_knowledge/manifest.json').readAsBytesSync(),
          ),
        );
      },
    );

    test('the committed pack covers every required topic in both locales', () {
      final output = File('${temporaryDirectory.path}/committed-manifest.json');
      buildTutorKnowledgeManifest(
        contentRoot: Directory('assets/tutor_knowledge'),
        outputFile: output,
      );

      final manifest =
          jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
      final documents = (manifest['documents'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final coverage = <String>{
        for (final document in documents)
          '${document['locale']}:${document['skill']}',
      };

      for (final locale in <String>['en', 'hu']) {
        for (final skill in KnowledgeSkill.values) {
          expect(coverage, contains('$locale:${skill.name}'));
        }
      }
    });
  });
}

final class _KnowledgeFixture {
  _KnowledgeFixture(Directory temporaryDirectory)
    : contentRoot = Directory('${temporaryDirectory.path}/tutor_knowledge')
        ..createSync();

  final Directory contentRoot;

  File get manifestFile => File('${contentRoot.path}/manifest.json');

  void build() {
    buildTutorKnowledgeManifest(
      contentRoot: contentRoot,
      outputFile: manifestFile,
    );
  }

  Map<String, Object?> manifestMap() => Map<String, Object?>.from(
    jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>,
  );

  void writeDocument(KnowledgeDocument document) {
    writeRaw(
      '${document.locale}/${document.id}.json',
      utf8.decode(_codec.encodeDocument(document)),
    );
  }

  void writeRaw(String relativePath, String contents) {
    final file = File('${contentRoot.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }
}

KnowledgeDocument _document({
  required String id,
  required String locale,
  KnowledgeApprovalStatus status = KnowledgeApprovalStatus.approved,
}) {
  const title = 'Keep a steady pulse';
  const body =
      'Count four even beats before playing.\n\nKeep the motion small and relaxed.';
  return KnowledgeDocument(
    schemaVersion: KnowledgeDocument.currentSchemaVersion,
    id: id,
    locale: locale,
    skill: KnowledgeSkill.rhythm,
    difficulty: KnowledgeDifficulty.beginner,
    license: 'CC0-1.0',
    version: 1,
    status: status,
    title: title,
    body: body,
    contentHash: KnowledgeCodec.contentHashForDocument(
      title: title,
      body: body,
    ),
  );
}

Map<String, Object?> _documentMap(KnowledgeDocument document) =>
    Map<String, Object?>.from(
      jsonDecode(utf8.decode(_codec.encodeDocument(document)))
          as Map<String, dynamic>,
    );
