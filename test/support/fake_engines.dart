import 'dart:async';

import 'package:music_theory/features/live/engine/strum_engine.dart';
import 'package:music_theory/features/live/model/live_frame.dart';

/// A timer-free StrumEngine for widget tests: emit frames on demand so
/// `pumpAndSettle` never hangs on a periodic timer.
class FakeStrumEngine implements StrumEngine {
  final _controller = StreamController<LiveFrame>.broadcast();

  @override
  Stream<LiveFrame> get frames => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void emit(LiveFrame frame) => _controller.add(frame);
}
