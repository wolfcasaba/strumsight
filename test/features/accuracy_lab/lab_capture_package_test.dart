import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/accuracy_lab/public.dart';

void main() {
  group('LabTaskCatalog — 15-20 range validation (ADR 0358 D6)', () {
    test('14 tasks is rejected', () {
      expect(
        () => LabTaskCatalog.validated(_tasksOfLength(14)),
        throwsA(isA<LabTaskRangeException>()),
      );
    });

    test('15 tasks is accepted (inclusive lower bound)', () {
      final catalog = LabTaskCatalog.validated(_tasksOfLength(15));
      expect(catalog.tasks, hasLength(15));
    });

    test('21 tasks is rejected', () {
      expect(
        () => LabTaskCatalog.validated(_tasksOfLength(21)),
        throwsA(isA<LabTaskRangeException>()),
      );
    });

    test('the standard catalog covers all six families and validates', () {
      final catalog = LabTaskCatalog.standard();
      expect(
        catalog.tasks.length,
        inInclusiveRange(LabTaskCatalog.minTasks, LabTaskCatalog.maxTasks),
      );
      expect(
        catalog.tasks.map((task) => task.family).toSet(),
        equals(LabTaskFamily.values.toSet()),
      );
    });
  });

  group(
    'LabCapturePackage — JSON round trip and determinism (ADR 0358 D3)',
    () {
      test('round trip through JSON is lossless', () {
        final original = _samplePackage();
        final decoded = LabCapturePackage.fromJson(
          jsonDecode(original.toCanonicalJson()) as Map<String, Object?>,
        );

        expect(decoded.toCanonicalJson(), equals(original.toCanonicalJson()));
        expect(decoded.packageId, original.packageId);
        expect(decoded.capturedAt, original.capturedAt);
        expect(decoded.consentVersion, original.consentVersion);
        expect(decoded.device.modelName, original.device.modelName);
        expect(decoded.events.length, original.events.length);
      });

      test('the same input produces byte-identical output twice', () {
        final first = _samplePackage().toCanonicalJson();
        final second = _samplePackage().toCanonicalJson();
        expect(first, equals(second));
      });

      test('canonical encoding is independent of source key order', () {
        final package = _samplePackage();
        final canonical = package.toCanonicalJson();

        // Same content as package.toJson(), but every map's keys are
        // inserted in a different order. Canonical encoding must still
        // produce byte-identical output — this is the cell that turns RED
        // if the recursive key sort in canonicalJsonEncode is disabled.
        final reorderedDevice = <String, Object?>{
          'appVersion': package.device.appVersion,
          'channelCount': package.device.channelCount,
          'modelName': package.device.modelName,
          'osVersion': package.device.osVersion,
          'sampleRate': package.device.sampleRate,
        };
        final reorderedTop = <String, Object?>{
          'events': [for (final event in package.events) event.toJson()],
          'device': reorderedDevice,
          'consentVersion': package.consentVersion,
          'capturedAt': package.capturedAt.toUtc().toIso8601String(),
          'packageId': package.packageId,
          'schemaVersion': labCapturePackageSchemaVersion,
        };

        expect(canonicalJsonEncode(reorderedTop), equals(canonical));
      });

      test(
        'unknown schemaVersion throws a typed error, not a silent default',
        () {
          final json =
              jsonDecode(_samplePackage().toCanonicalJson())
                  as Map<String, Object?>;
          final withUnknownVersion = <String, Object?>{
            ...json,
            'schemaVersion': 999,
          };

          expect(
            () => LabCapturePackage.fromJson(withUnknownVersion),
            throwsA(isA<LabCapturePackageSchemaVersionException>()),
          );
        },
      );
    },
  );

  group(
    'LabCapturePackage — closed keyset (ADR 0358 D2, docs/LESSONS.md L260)',
    () {
      test('serialized keyset equals the documented allowlist', () {
        final json =
            jsonDecode(_samplePackage().toCanonicalJson())
                as Map<String, Object?>;
        final keys = _collectKeysRecursively(json);

        expect(keys, equals(_allowedKeys));
      });

      test('a unique value placed in one field appears only in that field', () {
        const canary = 'CANARY-9f3c1a';
        final package = _samplePackage(modelName: 'Pixel $canary');
        final json = package.toCanonicalJson();

        expect(canary.allMatches(json).length, 1);
        final decoded = jsonDecode(json) as Map<String, Object?>;
        final device = decoded['device']! as Map<String, Object?>;
        expect(device['modelName'], contains(canary));
      });
    },
  );
}

const _allowedKeys = <String>{
  'schemaVersion',
  'packageId',
  'capturedAt',
  'consentVersion',
  'device',
  'events',
  'modelName',
  'osVersion',
  'sampleRate',
  'channelCount',
  'appVersion',
  'taskId',
  'family',
  'startSeconds',
  'endSeconds',
};

Set<String> _collectKeysRecursively(Object? value) {
  final keys = <String>{};
  void visit(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        keys.add(entry.key as String);
        visit(entry.value);
      }
    } else if (node is List) {
      for (final item in node) {
        visit(item);
      }
    }
  }

  visit(value);
  return keys;
}

List<LabTask> _tasksOfLength(int length) => List.generate(
  length,
  (index) => LabTask(
    id: 'task_$index',
    family: LabTaskFamily.values[index % LabTaskFamily.values.length],
    targetDurationSeconds: 5,
  ),
);

LabCapturePackage _samplePackage({String modelName = 'Pixel 9'}) =>
    LabCapturePackage(
      packageId: 'pkg-001',
      capturedAt: DateTime.utc(2026, 9, 4, 12),
      consentVersion: 'v1',
      device: LabDeviceMetadata(
        modelName: modelName,
        osVersion: 'Android 15',
        sampleRate: 44100,
        channelCount: 1,
        appVersion: '1.0.0',
      ),
      events: const [
        LabCaptureEvent(
          taskId: 'silence_room',
          family: LabTaskFamily.silence,
          startSeconds: 0,
          endSeconds: 10,
        ),
        LabCaptureEvent(
          taskId: 'chord_e_major_open',
          family: LabTaskFamily.singleChord,
          startSeconds: 10,
          endSeconds: 16,
        ),
      ],
    );
