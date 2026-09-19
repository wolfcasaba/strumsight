// The write-then-drop trap, guarded on the path the controller ACTUALLY takes.
//
// ## Why this file exists
//
// `practice_history_recorder_test.dart`'s B2 group guards
// `practiceSessionRecorderProvider`, and its comment calls that "the production path
// the controller takes on every finish". MEASURED: it is not. Nothing reads that
// provider — `practiceSessionControllerProvider`'s family builds its own
// `PracticeHistoryRecorder` inline from `inputs.definition`, with the real mode,
// source and id (`practice_session_providers.dart`). So the existing cell protects a
// branch production never enters, while describing itself as protecting the live one.
//
// That is worse than no guard: a guard that names the wrong subject invites everyone
// after it to believe the live path is covered. This file covers the live path.
//
// ## What actually protects the live path
//
// The trap is a record written with placeholder metadata that the READER then drops
// (`JsonRecordException` on an unknown enum code) — a write that silently loses data.
// On the live path two different things prevent it, and each is asserted below:
//
//   1. **The type system.** `mode` and `source` on a `PracticeDefinition` are
//      `PracticeMode` and `PracticeSource` — enums whose codes are real values. No
//      enum member can BE the placeholder, so the placeholder is unreachable through
//      those two fields rather than merely unused.
//   2. **The catalogue.** `definitionId` is the one free-form field, so it is the one
//      that could collide, and no shipped definition may carry the placeholder id.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_session_providers.dart';
import 'package:strumsight/features/practice/data/builtin_practice_catalog.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';

const String _placeholderMode = 'practice.mode.unknown';
const String _placeholderSource = 'practice.source.unknown';
const String _placeholderDefinition = 'practice.definition.unknown';

void main() {
  group('the placeholder metadata is unreachable through the typed fields', () {
    test('no PracticeMode code is the placeholder', () {
      for (final mode in PracticeMode.values) {
        expect(
          mode.code,
          isNot(_placeholderMode),
          reason:
              'the live recorder takes its mode code from this enum, so a member '
              'equal to the placeholder is the only way that field could trip the '
              'reader',
        );
      }
    });

    test('no PracticeSource code is the placeholder', () {
      for (final source in PracticeSource.values) {
        expect(source.code, isNot(_placeholderSource));
      }
    });

    test('the predicate still recognises the placeholders it names', () {
      // The guard above is only meaningful if the predicate is still about these
      // three strings: a renamed placeholder would make both silently vacuous.
      expect(
        isPlaceholderPracticeMetadata(
          modeCode: _placeholderMode,
          sourceCode: 'builtin',
          definitionId: 'builtin.x',
        ),
        isTrue,
      );
      expect(
        isPlaceholderPracticeMetadata(
          modeCode: 'strumPattern',
          sourceCode: _placeholderSource,
          definitionId: 'builtin.x',
        ),
        isTrue,
      );
      expect(
        isPlaceholderPracticeMetadata(
          modeCode: 'strumPattern',
          sourceCode: 'builtin',
          definitionId: _placeholderDefinition,
        ),
        isTrue,
      );
      expect(
        isPlaceholderPracticeMetadata(
          modeCode: 'strumPattern',
          sourceCode: 'builtin',
          definitionId: 'builtin.quarterDownstrokes.v1',
        ),
        isFalse,
      );
    });
  });

  group('no shipped definition can produce a dropped record', () {
    test('every builtin definition carries real metadata', () {
      final definitions = const BuiltinPracticeCatalog().all();
      expect(
        definitions,
        isNotEmpty,
        reason: 'an empty catalogue would make this guard vacuous',
      );
      for (final definition in definitions) {
        expect(
          isPlaceholderPracticeMetadata(
            modeCode: definition.mode.code,
            sourceCode: definition.source.code,
            definitionId: definition.id,
          ),
          isFalse,
          reason:
              '${definition.id} would be written by the live recorder and then '
              'dropped by the reader — a finished session silently lost',
        );
      }
    });
  });
}
