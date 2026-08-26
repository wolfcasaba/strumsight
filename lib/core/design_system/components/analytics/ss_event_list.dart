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
/// §3: "bejárható esemény-lista alternatíva"). The height is fixed (not
/// `shrinkWrap: true`) on purpose: `shrinkWrap` forces `ListView` to lay out
/// every child up front to measure its own extent, which defeats
/// virtualisation for exactly the large-fixture case this round exists to
/// fix. A fixed height plus a fixed [rowExtent] means [ListView.builder]
/// only ever builds the rows inside the viewport plus its cache extent,
/// independent of [rows].length.
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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: SizedBox(
        height: height,
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
