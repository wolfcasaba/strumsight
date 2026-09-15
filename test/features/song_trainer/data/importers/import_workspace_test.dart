import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_limits.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_workspace.dart';

void main() {
  group('ImportWorkspace', () {
    test('removes its operation directory when closed', () async {
      final root = await Directory.systemTemp.createTemp('song-import-test-');
      addTearDown(() => root.delete(recursive: true));
      final workspace = await ImportWorkspace.open(
        root: root,
        operationId: 'operation-1',
        limits: const ImportLimits(),
      );

      final file = await workspace.createFile('source.json');
      await file.writeAsString('source');
      expect(await file.exists(), isTrue);

      await workspace.close();

      expect(await Directory(workspace.path).exists(), isFalse);
      await workspace.close();
    });

    test(
      'rejects traversal and symlink escapes before creating a file',
      () async {
        final root = await Directory.systemTemp.createTemp('song-import-test-');
        final outside = await Directory.systemTemp.createTemp('outside-');
        addTearDown(() async {
          await root.delete(recursive: true);
          await outside.delete(recursive: true);
        });
        final workspace = await ImportWorkspace.open(
          root: root,
          operationId: 'operation-2',
          limits: const ImportLimits(),
        );
        addTearDown(workspace.close);

        await expectLater(
          workspace.createFile('../escaped.json'),
          throwsA(isA<ImportWorkspaceException>()),
        );
        // The symlink half needs a filesystem that lets the test create a
        // link: on Windows without Developer Mode `Link.create` is denied
        // (ERROR_PRIVILEGE_NOT_HELD). That is a box limitation, not a
        // workspace verdict — the traversal half above still ran.
        try {
          await Link('${workspace.path}/escape').create(outside.path);
        } on FileSystemException catch (e) {
          if (!Platform.isWindows) rethrow;
          // ignore: avoid_print
          print('symlink escape cell skipped: ${e.osError?.message}');
          return;
        }
        await expectLater(
          workspace.createFile('escape/escaped.json'),
          throwsA(isA<ImportWorkspaceException>()),
        );
      },
    );

    test(
      'fails with a stable code when the workspace byte limit is exceeded',
      () async {
        final root = await Directory.systemTemp.createTemp('song-import-test-');
        addTearDown(() => root.delete(recursive: true));
        final workspace = await ImportWorkspace.open(
          root: root,
          operationId: 'operation-3',
          limits: const ImportLimits(maxWorkspaceBytes: 3),
        );
        addTearDown(workspace.close);

        await expectLater(
          workspace.writeBytes('source.json', <int>[1, 2, 3, 4]),
          throwsA(
            isA<ImportWorkspaceException>().having(
              (error) => error.code,
              'code',
              ImportLimitFailureCode.workspaceBytesExceeded,
            ),
          ),
        );
      },
    );
  });
}
