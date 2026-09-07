import 'package:flutter/material.dart';

/// The flicker-free launch surface (SDD Ch13 Kör 16, §5). Pure
/// [Theme]-derived colors only — never a hardcoded background — so
/// whichever theme the app resolves to, this widget never flashes an
/// unrelated color while [AppBootstrap] (or a later async boot step)
/// resolves.
///
/// **Not on the boot path today (R21, audit MI9):** `lib/` holds ZERO
/// references to this widget. `main` awaits [AppBootstrap] BEFORE its
/// first `runApp`, so nothing Flutter-side is mounted while boot runs and
/// there is no frame for this surface to fill; the pre-`runApp` gap is
/// covered by the platform launch theme instead. The widget is kept
/// because it is the contract the theme-safety cells measure (the
/// `e13_r16` golden + `bootstrap_routing_test.dart`) — read it as the
/// reference launch surface a later async boot step would adopt, NOT as
/// a screen the app shows today.
class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('launch-screen-background'),
      color: scheme.surface,
      child: Center(child: CircularProgressIndicator(color: scheme.primary)),
    );
  }
}
