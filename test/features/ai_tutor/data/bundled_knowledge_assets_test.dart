import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/asset_knowledge_repository.dart';

/// E18-R01 emulator finding F1: `pubspec.yaml` declared only
/// `assets/tutor_knowledge/`, and a Flutter directory entry is NOT recursive —
/// the APK shipped `manifest.json` alone, every `en/` and `hu/` document was
/// missing, and each device start fell back with
/// `tutorKnowledge.indexLoad.assetReadFailure`.
///
/// The existing knowledge tests read the DISK (`tool/build_tutor_knowledge_
/// manifest.dart`), which is why none of them caught it. This guard reads the
/// COMPILED asset bundle the way the device does: `flutter test` builds the
/// declared assets into the bundle behind `rootBundle`, so an undeclared
/// document fails here exactly as it fails on the phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every document the on-disk manifest lists is readable from the COMPILED '
    'asset bundle',
    () async {
      final manifest =
          jsonDecode(
                File('assets/tutor_knowledge/manifest.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      final documents = (manifest['documents']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(documents, isNotEmpty);

      for (final document in documents) {
        final sourcePath = document['sourcePath']! as String;
        final assetPath =
            '${AssetKnowledgeRepository.defaultAssetRoot}/$sourcePath';
        final bundled = await rootBundle.loadString(assetPath);
        expect(
          bundled,
          File('assets/tutor_knowledge/$sourcePath').readAsStringSync(),
          reason: '$assetPath is declared on disk but differs in the bundle',
        );
      }
    },
  );

  test(
    'the production repository loads the full index from the bundle — no '
    'fallback code',
    () async {
      final result = await AssetKnowledgeRepository.fromRootBundle()
          .loadIndex();

      expect(result.errorCode, isNull);
      expect(result.isFallback, isFalse);
      final manifest =
          jsonDecode(
                File('assets/tutor_knowledge/manifest.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      final documentIds = {
        for (final entry in result.index.entries) entry.document.id,
      };
      final manifestIds = {
        for (final document
            in (manifest['documents']! as List<Object?>)
                .cast<Map<String, Object?>>())
          document['id']! as String,
      };
      expect(documentIds, manifestIds);
    },
  );
}
