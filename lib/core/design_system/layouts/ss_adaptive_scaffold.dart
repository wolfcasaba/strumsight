import 'package:flutter/material.dart';

import '../foundations/ss_breakpoints.dart';

/// The four responsive layout modes, resolved from [SsBreakpoints].
enum SsAdaptiveLayoutMode {
  /// `width <= SsBreakpoints.compactMax` — bottom [NavigationBar].
  compact,

  /// `SsBreakpoints.compactMax < width <= SsBreakpoints.mediumMax` — a
  /// non-extended [NavigationRail].
  medium,

  /// `SsBreakpoints.mediumMax < width < SsBreakpoints.wideMin` — an extended
  /// [NavigationRail] with visible labels.
  expanded,

  /// `width >= SsBreakpoints.wideMin` — an extended [NavigationRail]; any
  /// additional wide-only content layout is out of this primitive's scope.
  wide,
}

/// One entry of the primary navigation, data-only (no route/feature types).
@immutable
class SsAdaptiveDestination {
  const SsAdaptiveDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// A breakpoint-aware layout primitive that renders primary navigation as a
/// bottom [NavigationBar] in compact width and a [NavigationRail] from medium
/// width up, or hides it entirely when [showPrimaryNavigation] is false.
///
/// This is a pure layout primitive: it knows nothing about routes, the
/// router, or any feature — every input arrives as data (destinations,
/// selected index, a selection callback, the body, and the visibility
/// switch). The binding to routing lives in `lib/app/`.
final class SsAdaptiveScaffold extends StatelessWidget {
  const SsAdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.showPrimaryNavigation = true,
  });

  final List<SsAdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final bool showPrimaryNavigation;

  /// Resolves the [SsAdaptiveLayoutMode] for a given width, from
  /// [SsBreakpoints] tokens only.
  static SsAdaptiveLayoutMode modeForWidth(double width) {
    if (width <= SsBreakpoints.compactMax) return SsAdaptiveLayoutMode.compact;
    if (width <= SsBreakpoints.mediumMax) return SsAdaptiveLayoutMode.medium;
    if (width < SsBreakpoints.wideMin) return SsAdaptiveLayoutMode.expanded;
    return SsAdaptiveLayoutMode.wide;
  }

  @override
  Widget build(BuildContext context) {
    if (!showPrimaryNavigation) {
      return Scaffold(body: body);
    }

    final width = MediaQuery.sizeOf(context).width;
    final mode = SsAdaptiveScaffold.modeForWidth(width);

    if (mode == SsAdaptiveLayoutMode.compact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: destination.icon,
                selectedIcon: destination.selectedIcon,
                label: destination.label,
              ),
          ],
        ),
      );
    }

    final extended =
        mode == SsAdaptiveLayoutMode.expanded ||
        mode == SsAdaptiveLayoutMode.wide;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.selected,
            destinations: [
              for (final destination in destinations)
                NavigationRailDestination(
                  icon: destination.icon,
                  selectedIcon: destination.selectedIcon,
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
