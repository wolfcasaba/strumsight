import 'package:flutter/widgets.dart';

/// App foreground/background transitions, behind an interface (SDD Ch2, Kör 9
/// §9.4) so a test can drive "the user switched apps" without a binding and
/// without pumping platform messages.
abstract interface class AppLifecycleEvents {
  void addListener(void Function(AppLifecycleState state) listener);

  void removeListener(void Function(AppLifecycleState state) listener);

  void dispose();
}

/// True for the states where the app is no longer on screen — the microphone,
/// the wakelock and the DSP isolate must all be released here.
///
/// `inactive` is deliberately NOT included: it also fires for a transient
/// system overlay (notification shade, incoming call banner) and killing the
/// capture there would make a moment of shade-pull end the session.
bool isBackgroundLifecycleState(AppLifecycleState state) =>
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.detached;

/// The real source: the Flutter widgets binding.
final class BindingAppLifecycleEvents implements AppLifecycleEvents {
  BindingAppLifecycleEvents() {
    WidgetsBinding.instance.addObserver(_observer);
  }

  late final _observer = _LifecycleObserver(_notify);
  final List<void Function(AppLifecycleState)> _listeners = [];
  bool _disposed = false;

  @override
  void addListener(void Function(AppLifecycleState state) listener) {
    if (_disposed) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(void Function(AppLifecycleState state) listener) {
    _listeners.remove(listener);
  }

  void _notify(AppLifecycleState state) {
    // Iterate a copy: a listener may remove itself while being notified.
    for (final listener in List.of(_listeners)) {
      listener(state);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
    WidgetsBinding.instance.removeObserver(_observer);
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._onState);

  final void Function(AppLifecycleState) _onState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onState(state);
}
