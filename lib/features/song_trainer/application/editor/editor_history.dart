import 'editor_command.dart';

/// Bounded command history. A new edit after undo deliberately discards redo.
final class EditorHistory {
  EditorHistory({this.limit = defaultLimit}) : assert(limit > 0);

  static const int defaultLimit = 100;

  final int limit;
  final List<EditorCommand> _undo = <EditorCommand>[];
  final List<EditorCommand> _redo = <EditorCommand>[];
  var _disposed = false;

  bool get canUndo => !_disposed && _undo.isNotEmpty;
  bool get canRedo => !_disposed && _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  void record(EditorCommand command) {
    if (_disposed) return;
    _undo.add(command);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  EditorCommand? takeUndo() {
    if (!canUndo) return null;
    final command = _undo.removeLast();
    _redo.add(command);
    return command;
  }

  EditorCommand? takeRedo() {
    if (!canRedo) return null;
    final command = _redo.removeLast();
    _undo.add(command);
    return command;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _undo.clear();
    _redo.clear();
  }
}
