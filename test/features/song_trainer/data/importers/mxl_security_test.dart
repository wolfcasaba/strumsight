import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_limits.dart';
import 'package:strumsight/features/song_trainer/data/importers/mxl_archive_reader.dart';

void main() {
  group('MxlArchiveReader', () {
    test('rejects traversal, absolute, duplicate and nested archive paths', () {
      const reader = MxlArchiveReader();
      const limits = ImportLimits(
        maxArchiveEntryCount: 2,
        maxExtractedBytes: 8,
      );

      expect(
        reader.validateEntryPaths(<MxlArchiveEntry>[
          MxlArchiveEntry('../score.xml', <int>[1]),
        ], limits).failureCode,
        MxlImportFailureCode.invalidEntryPath,
      );
      expect(
        reader.validateEntryPaths(<MxlArchiveEntry>[
          MxlArchiveEntry('/score.xml', <int>[1]),
        ], limits).failureCode,
        MxlImportFailureCode.invalidEntryPath,
      );
      expect(
        reader.validateEntryPaths(<MxlArchiveEntry>[
          MxlArchiveEntry('score.xml', <int>[1]),
          MxlArchiveEntry('score.xml', <int>[2]),
        ], limits).failureCode,
        MxlImportFailureCode.duplicateEntryPath,
      );
      expect(
        reader.validateEntryPaths(<MxlArchiveEntry>[
          MxlArchiveEntry('nested.mxl', <int>[1]),
        ], limits).failureCode,
        MxlImportFailureCode.nestedArchive,
      );
    });

    test(
      'enforces archive count and extracted-byte boundaries inclusively',
      () {
        const reader = MxlArchiveReader();
        const limits = ImportLimits(
          maxArchiveEntryCount: 2,
          maxExtractedBytes: 4,
        );

        expect(
          reader.validateEntryPaths(<MxlArchiveEntry>[
            MxlArchiveEntry('a.xml', <int>[1]),
            MxlArchiveEntry('b.xml', <int>[2, 3, 4]),
          ], limits).failureCode,
          isNull,
        );
        expect(
          reader.validateEntryPaths(<MxlArchiveEntry>[
            MxlArchiveEntry('a.xml', <int>[1]),
            MxlArchiveEntry('b.xml', <int>[2]),
            MxlArchiveEntry('c.xml', <int>[3]),
          ], limits).failureCode,
          ImportLimitFailureCode.archiveEntryCountExceeded,
        );
        expect(
          reader.validateEntryPaths(<MxlArchiveEntry>[
            MxlArchiveEntry('a.xml', <int>[], byteLength: 5),
          ], limits).failureCode,
          ImportLimitFailureCode.extractedBytesExceeded,
        );
      },
    );

    test('reads only the container-selected score after entry validation', () {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'META-INF/container.xml',
            '<container><rootfiles><rootfile full-path="score.xml"/></rootfiles></container>',
          ),
        )
        ..addFile(ArchiveFile.string('score.xml', '<score-partwise/>'));
      final bytes = ZipEncoder().encode(archive);

      final result = const MxlArchiveReader().read(
        bytes,
        const ImportLimits(maxArchiveEntryCount: 2, maxExtractedBytes: 128),
      );

      expect(result.failureCode, isNull);
      expect(utf8.decode(result.scoreBytes!), '<score-partwise/>');
    });

    test('rejects an unsafe directory entry in a real archive', () {
      final archive = Archive()
        ..addFile(ArchiveFile.directory('../'))
        ..addFile(
          ArchiveFile.string(
            'META-INF/container.xml',
            '<container><rootfiles><rootfile full-path="score.xml"/></rootfiles></container>',
          ),
        )
        ..addFile(ArchiveFile.string('score.xml', '<score-partwise/>'));

      final result = const MxlArchiveReader().read(
        ZipEncoder().encode(archive),
        const ImportLimits(maxArchiveEntryCount: 3, maxExtractedBytes: 128),
      );

      expect(result.failureCode, MxlImportFailureCode.invalidEntryPath);
    });

    test(
      'rejects the committed malicious and extracted-limit MXL fixtures',
      () async {
        final malicious = await File(
          'test/fixtures/song_trainer/mxl/malicious_path.mxl',
        ).readAsBytes();
        final extractedLimit = await File(
          'test/fixtures/song_trainer/mxl/extracted_limit.mxl',
        ).readAsBytes();

        expect(
          const MxlArchiveReader()
              .read(malicious, const ImportLimits())
              .failureCode,
          MxlImportFailureCode.invalidEntryPath,
        );
        expect(
          const MxlArchiveReader()
              .read(extractedLimit, const ImportLimits(maxExtractedBytes: 128))
              .failureCode,
          ImportLimitFailureCode.extractedBytesExceeded,
        );
      },
    );
  });
}
