// R34 (audit M11) — the missing entry point of the analysis COMPARISON.
//
// `CompareAnalysesUseCase` and `AnalysisCompareScreen` have both been
// complete since E06; the measured gap was that nothing in `lib/` ever
// built an `AnalysisComparison`, so `/analysis/compare` had zero
// navigations while `analysisComparisonEnabled` was ON in the shipped
// development build. This sheet is the selection half of that entry: it
// hands back exactly TWO summaries, ordered oldest-first, and nothing else.
//
// Why a sheet and not a new screen: the Analyze home is pixel-pinned
// (`e13_r26_analysis_home_*`, `e15_r13` matrix). A modal bottom sheet adds
// no route, no matrix fixture and no §3.2 row, and the AppBar action that
// opens it renders only when the host supplies a callback — which the
// golden fixtures do not.
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/analysis_summary.dart';

/// The ordered pair the compare flow needs: [before] is the OLDER capture.
///
/// The order is derived from `createdAt`, never from tap order — "before"
/// and "after" are claims about time, and letting the tap order decide
/// would let the screen render an improvement that ran backwards.
@immutable
final class AnalysisComparePair {
  const AnalysisComparePair({required this.before, required this.after});

  final AnalysisSummary before;
  final AnalysisSummary after;
}

/// Asks the user for exactly two saved analyses.
///
/// Returns `null` when the sheet is dismissed without a confirmed pair —
/// the caller must then navigate nowhere.
Future<AnalysisComparePair?> showAnalysisComparePicker(
  BuildContext context, {
  required List<AnalysisSummary> summaries,
}) => showModalBottomSheet<AnalysisComparePair>(
  context: context,
  isScrollControlled: true,
  builder: (_) => AnalysisComparePicker(summaries: summaries),
);

/// The sheet body. Public so a widget test can pump it without a route.
final class AnalysisComparePicker extends StatefulWidget {
  const AnalysisComparePicker({required this.summaries, super.key});

  final List<AnalysisSummary> summaries;

  @override
  State<AnalysisComparePicker> createState() => _AnalysisComparePickerState();
}

class _AnalysisComparePickerState extends State<AnalysisComparePicker> {
  final Set<String> _selected = <String>{};

  static const int _requiredSelection = 2;

  bool get _isComplete => _selected.length == _requiredSelection;

  void _toggle(String documentId, bool selected) {
    setState(() {
      if (selected) {
        // A third tap must not silently replace one of the two already
        // chosen — the user would then compare a pair they never picked.
        if (_selected.length >= _requiredSelection) return;
        _selected.add(documentId);
      } else {
        _selected.remove(documentId);
      }
    });
  }

  AnalysisComparePair? _pair() {
    final chosen = <AnalysisSummary>[
      for (final summary in widget.summaries)
        if (_selected.contains(summary.documentId)) summary,
    ];
    if (chosen.length != _requiredSelection) return null;
    chosen.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return AnalysisComparePair(before: chosen.first, after: chosen.last);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.analysisComparePickerTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.analysisComparePickerHint,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final summary in widget.summaries)
                    CheckboxListTile(
                      key: Key('analysis-compare-pick-${summary.documentId}'),
                      value: _selected.contains(summary.documentId),
                      title: Text(_titleOf(summary)),
                      subtitle: Text(_formatDate(summary.createdAt)),
                      onChanged: (value) =>
                          _toggle(summary.documentId, value ?? false),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  key: const Key('analysis-compare-cancel'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(l10n.analysisComparePickerCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('analysis-compare-confirm'),
                  // Disabled — never a button that looks live and does
                  // nothing — until the pair is complete.
                  onPressed: _isComplete
                      ? () => Navigator.of(context).pop(_pair())
                      : null,
                  child: Text(l10n.analysisComparePickerConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _titleOf(AnalysisSummary summary) =>
      summary.title.isEmpty ? summary.documentId : summary.title;

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
