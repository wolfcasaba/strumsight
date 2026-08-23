import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/public.dart';
import '../core/notifications/nudge_service.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/providers/nudge_enabled_provider.dart';
import '../l10n/app_localizations.dart';
import 'routing/adaptive_shell_routes.dart';
import 'routing/app_route.dart';

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
  int get _index {
    final i = AppRoutes.shellTabs.indexWhere(
      (tab) => widget.location.startsWith(tab),
    );
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
          .reconcile(
            copyFor: (v) => switch (v) {
              NudgeCopyVariant.friday => (
                title: l10n.nudgeTitleFriday,
                body: l10n.nudgeBodyFriday,
              ),
              NudgeCopyVariant.weekend => (
                title: l10n.nudgeTitleWeekend,
                body: l10n.nudgeBodyWeekend,
              ),
              _ => (title: l10n.nudgeTitle, body: l10n.nudgeBody),
            },
          );
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
        onDestinationSelected: (i) => context.go(AppRoutes.shellTabs[i]),
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

/// The adaptive five-area shell (Today/Practice/Songs/Coach/Profile,
/// E13-R08, ADR 0275), reachable only behind `adaptiveShellEnabled`. Every
/// destination's label comes from an existing [AppLocalizations] key —
/// there are no dedicated navigation strings yet (brief §0.0 D10).
///
/// TODO(E13-R16): dedicated nav ARB keys once l10n is in scope.
class AdaptiveHomeShell extends StatelessWidget {
  const AdaptiveHomeShell({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  final StatefulNavigationShell navigationShell;
  final String location;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsAdaptiveScaffold(
      showPrimaryNavigation: !isStageRoute(location),
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: navigationShell.goBranch,
      body: navigationShell,
      destinations: [
        SsAdaptiveDestination(
          icon: const Icon(Icons.today_outlined),
          selectedIcon: const Icon(Icons.today),
          label: l10n.todayPlanTitle,
        ),
        SsAdaptiveDestination(
          icon: const Icon(Icons.fitness_center_outlined),
          selectedIcon: const Icon(Icons.fitness_center),
          label: l10n.practiceHubTitle,
        ),
        SsAdaptiveDestination(
          icon: const Icon(Icons.library_music_outlined),
          selectedIcon: const Icon(Icons.library_music),
          label: l10n.songLibraryTitle,
        ),
        SsAdaptiveDestination(
          icon: const Icon(Icons.smart_toy_outlined),
          selectedIcon: const Icon(Icons.smart_toy),
          label: l10n.aiTutorHomeTitle,
        ),
        SsAdaptiveDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon: const Icon(Icons.person),
          label: l10n.tutorProfileTitle,
        ),
      ],
    );
  }
}
