import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One row of [SsEventList]. [label] is the already-localised visible text;
/// [semanticLabel] is read by assistive tech and may carry more detail than
/// [label] shows on screen (matching the existing per-item semantics pattern
/// this widget replaces).
final class SsEventListRow {
  const SsEventListRow({
    required this.id,
    required this.label,
    required this.semanticLabel,
    this.onTap,
  });

  final String id;
  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;
}

/// Bounded-height, lazily-built, navigable alternative to a chart (ADR 0286
/// §3: "bejárható esemény-lista alternatíva"). The height is capped at
/// [height] (not `shrinkWrap: true`) on purpose: `shrinkWrap` forces
/// `ListView` to lay out every child up front to measure its own extent,
/// which defeats virtualisation for exactly the large-fixture case this
/// round exists to fix. The cap plus a fixed [rowExtent] means
/// [ListView.builder] only ever builds the rows inside the viewport plus its
/// cache extent, independent of [rows].length — a short [rows] simply gets a
/// shorter box (`rows.length * rowExtent`) instead of leaving dead space
/// below it.
final class SsEventList extends StatelessWidget {
  const SsEventList({
    super.key,
    required this.rows,
    required this.semanticLabel,
    this.height = 220,
    this.rowExtent = 48,
    this.scrollableKey,
  });

  final List<SsEventListRow> rows;
  final String semanticLabel;
  final double height;
  final double rowExtent;

  /// Exposed so tests can target this exact scrollable when the widget is
  /// nested inside another scrollable.
  final Key? scrollableKey;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    // Capped by content so a short row count doesn't leave dead space below
    // it up to [height]; the cap is an upper bound only, so a large [rows]
    // still stops growing at [height] and stays lazily built by
    // [ListView.builder] below.
    final boundedHeight = math.min(height, rows.length * rowExtent);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: SizedBox(
        height: boundedHeight,
        child: ListView.builder(
          key: scrollableKey,
          itemExtent: rowExtent,
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Semantics(
              key: ValueKey('event-list-row-${row.id}'),
              container: true,
              label: row.semanticLabel,
              child: InkWell(
                onTap: row.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // The Text's own implicit semantics label would
                    // otherwise merge into the explicit [row.semanticLabel]
                    // above by concatenation — doubling the label whenever
                    // the two carry the same sentence (the common case).
                    // Only the Text's label is excluded; InkWell's tap
                    // action still surfaces on the row's Semantics node.
                    child: ExcludeSemantics(
                      child: Text(
                        row.label,
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
