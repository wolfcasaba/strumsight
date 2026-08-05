import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';

void main() {
  test(
    'removes raw audio, paths, credentials, and imported lyrics without truncating content',
    () {
      final result = const ContextRedactor().redact(
        TutorContextField.available(
          key: TutorContextFieldKey.analyze,
          values: <String, Object?>{
            'pcmSamples': <Object?>[0, 1, -1],
            'recordingPath': '/private/recordings/take.wav',
            'accessToken': 'should-never-leave-device',
            'importedLyrics':
                'complete copyrighted lyrics must not be retained',
            'songTitle': 'Safe title metadata',
          },
          provenance: ContextProvenance(
            sourceFeature: ContextSourceFeature.analyze,
            schemaVersion: 'analyze.v1',
          ),
        ),
      );

      expect(result.field.values, <String, Object?>{
        'songTitle': 'Safe title metadata',
      });
      expect(
        result.report.entries.map((entry) => entry.reason),
        containsAll(<ContextOmissionReason>[
          ContextOmissionReason.rawAudio,
          ContextOmissionReason.absolutePath,
          ContextOmissionReason.credential,
          ContextOmissionReason.importedLyrics,
        ]),
      );
      expect(
        result.field.values.toString(),
        isNot(contains('lyrics must not')),
      );
    },
  );

  test('applies redaction before returning an assembled snapshot', () {
    final snapshot = const TutorContextAssembler().assemble(
      requestId: 'redaction-request',
      createdAt: DateTime.utc(2026, 8, 5),
      purpose: ContextPurpose.songHelp,
      fields: <TutorContextField>[
        TutorContextField.available(
          key: TutorContextFieldKey.analyze,
          values: <String, Object?>{
            'recordingPath': '/private/recordings/take.wav',
            'bpm': 120,
          },
          provenance: ContextProvenance(
            sourceFeature: ContextSourceFeature.analyze,
            schemaVersion: 'analyze.v1',
          ),
        ),
      ],
    );

    expect(snapshot.fields.single.values, <String, Object?>{'bpm': 120});
    expect(
      snapshot.redactionReport.entries.single.reason,
      ContextOmissionReason.absolutePath,
    );
  });
}
