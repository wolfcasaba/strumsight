import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/providers/nudge_enabled_provider.dart';
import '../l10n/app_localizations.dart';

/// The bottom-navigation shell hosting the four top-level tabs. The current
/// tab's screen is rendered as [child]; switching tabs disposes the previous
/// screen (so the Live engine + wakelock stop when you leave Live).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = ['/live', '/analyze', '/learn', '/library', '/settings'];

  int get _index {
    final i = _tabs.indexWhere((t) => widget.location.startsWith(t));
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    // One-shot startup reconcile of the daily-reminder toggle (round 82):
    // a force-stop clears the scheduled alarm and a system-settings revoke
    // kills delivery — verify + re-arm so the persisted ON never lies.
    // Post-frame so localisation is available for the notification texts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ref
          .read(nudgeEnabledProvider.notifier)
          .reconcile(title: l10n.nudgeTitle, body: l10n.nudgeBody);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final child = widget.child;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.mic_none_outlined),
            selectedIcon: const Icon(Icons.mic),
            label: l10n.navLive,
          ),
          NavigationDestination(
            icon: const Icon(Icons.multitrack_audio_outlined),
            selectedIcon: const Icon(Icons.multitrack_audio),
            label: l10n.navAnalyze,
          ),
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: l10n.navLearn,
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_music_outlined),
            selectedIcon: const Icon(Icons.library_music),
            label: l10n.navLibrary,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
