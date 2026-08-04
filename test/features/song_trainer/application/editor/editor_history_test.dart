import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/editor/editor_command.dart';
import 'package:strumsight/features/song_trainer/application/editor/editor_history.dart';

import 'song_editor_controller_test.dart' show document;

void main() {
  test(
    'bounded history evicts oldest command and clears redo after a new edit',
    () {
      final first = document('one');
      final second = document('two');
      final third = document('three');
      final history = EditorHistory(limit: 2)
        ..record(
          DocumentEditorCommand(label: 'one', before: first, after: second),
        )
        ..record(
          DocumentEditorCommand(label: 'two', before: second, after: third),
        )
        ..record(
          DocumentEditorCommand(label: 'three', before: third, after: first),
        );

      expect(history.undoCount, 2);
      expect(history.takeUndo()!.label, 'three');
      expect(history.canRedo, isTrue);
      history.record(
        DocumentEditorCommand(
          label: 'replacement',
          before: third,
          after: second,
        ),
      );
      expect(history.canRedo, isFalse);

      history.dispose();
      expect(history.canUndo, isFalse);
      expect(history.undoCount, 0);
    },
  );
}
