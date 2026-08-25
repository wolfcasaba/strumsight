import 'package:flutter/material.dart';

/// The flicker-free launch surface (SDD Ch13 Kör 16, §5). Pure
/// [Theme]-derived colors only — never a hardcoded background — so
/// whichever theme the app resolves to, this widget never flashes an
/// unrelated color while [AppBootstrap] (or a later async boot step)
/// resolves.
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
