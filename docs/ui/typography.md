# Typography

Use `SsTypography` from the active design-system `ThemeData` extension. Its
scale tokens distinguish chord display, score, headings, body text, labels,
and metrics.

Use the hierarchy in this order when a screen has a visible title:

1. `headlineLarge` for the screen title.
2. `headlineMedium` for a major section.
3. `titleLarge` or `titleMedium` for a card or list item title.
4. `bodyLarge` or `bodyMedium` for supporting copy.

Wrap a visible screen or section heading in `Semantics(header: true, ...)`.
Metric values use the metric tokens and `SsTypography.metricLabel` so their
unit remains attached to the value. `SsChordHeroText` preserves its full chord
label and accepts the platform text scale.
