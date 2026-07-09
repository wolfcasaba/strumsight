import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../chord_shape.dart';
import '../widgets/chord_diagram.dart';

/// A browsable chord dictionary: every fingering we know, grouped by type, with
/// a search box. A handy reference tool for learners (RAG chunk 014).
class ChordLibraryScreen extends StatefulWidget {
  const ChordLibraryScreen({super.key});

  @override
  State<ChordLibraryScreen> createState() => _ChordLibraryScreenState();
}

class _ChordLibraryScreenState extends State<ChordLibraryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _grouped(_query);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chordLibraryTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.chordLibrarySearch,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                child: Text(
                  _groupLabel(l10n, entry.key).toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 12,
                children: [
                  for (final label in entry.value)
                    SizedBox(
                      width: 96,
                      child: ChordDiagram(label: label, size: 76),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Group labels into major / minor / seventh / suspended for pedagogy,
  /// filtered by a case-insensitive [query].
  static Map<_Group, List<String>> _grouped(String query) {
    final q = query.toLowerCase();
    final out = {for (final g in _Group.values) g: <String>[]};
    for (final label in ChordShapes.allLabels) {
      if (q.isNotEmpty && !label.toLowerCase().contains(q)) continue;
      out[_classify(label)]!.add(label);
    }
    out.removeWhere((_, v) => v.isEmpty);
    return out;
  }

  static _Group _classify(String label) {
    if (label.contains('sus')) return _Group.suspended;
    if (label.contains('7')) return _Group.seventh;
    // Minor triad: a trailing 'm' that isn't part of 'maj'/'m7' (7ths handled).
    final quality = label.replaceAll(RegExp(r'^[A-G]#?'), '');
    if (quality == 'm') return _Group.minor;
    return _Group.major;
  }

  static String _groupLabel(AppLocalizations l10n, _Group g) => switch (g) {
        _Group.major => l10n.chordGroupMajor,
        _Group.minor => l10n.chordGroupMinor,
        _Group.seventh => l10n.chordGroupSeventh,
        _Group.suspended => l10n.chordGroupSuspended,
      };
}

enum _Group { major, minor, seventh, suspended }
