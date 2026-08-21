import 'package:flutter/material.dart';

import '../../foundations/ss_typography.dart';

/// Renders a complete chord label that scales down only when width requires it.
final class SsChordHeroText extends StatelessWidget {
  const SsChordHeroText({required this.chordName, super.key});

  final String chordName;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).extension<SsTypography>();
    assert(
      typography != null,
      'SsChordHeroText requires an SsTypography theme.',
    );
    final mediaQuery = MediaQuery.of(context);
    final style = typography!.displayChordForViewport(
      viewportWidth: mediaQuery.size.width,
    );

    return Semantics(
      label: chordName,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          chordName,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}
