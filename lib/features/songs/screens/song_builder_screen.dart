import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../chords/public.dart';
import '../../../core/music/strum.dart';
import '../model/song.dart';
import '../providers/songs_provider.dart';
import '../../metronome/public.dart';
import '../theory/strum_patterns.dart';
import '../widgets/progression_picker.dart';
import '../widgets/strum_pattern_editor.dart';

/// Create or edit a user song: name → chord progression → ↓/↑ strum pattern →
/// tempo. Saving persists it (Songs list) and it becomes a fully playable,
/// scorable Learn lesson.
class SongBuilderScreen extends ConsumerStatefulWidget {
  const SongBuilderScreen({super.key, this.existing});

  final Song? existing;

  @override
  ConsumerState<SongBuilderScreen> createState() => _SongBuilderScreenState();
}

class _SongBuilderScreenState extends ConsumerState<SongBuilderScreen> {
  late final TextEditingController _name;
  late List<String> _chords;
  late List<StrumDirection?> _pattern;
  late int _bpm;
  late int _beatsPerBar;

  /// Case-insensitive label filter for the add-chord picker (audit U5).
  String _chordQuery = '';
  // Clamped to the slider's range so a tapped tempo is always representable.
  final TapTempo _tapTempo = TapTempo(minBpm: 50, maxBpm: 180);

  // A gentle default so a brand-new song is instantly playable: downs on beats.
  static const _defaultPattern = <StrumDirection?>[
    StrumDirection.down, null, StrumDirection.down, null, //
    StrumDirection.down, null, StrumDirection.down, null,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _chords = [...?e?.chords];
    _pattern = e != null ? [...e.pattern] : [..._defaultPattern];
    _bpm = e?.bpm ?? 90;
    _beatsPerBar = e?.beatsPerBar ?? 4;
  }

  /// Switch metre, resizing the pattern to one bar of the new one (round
  /// 116): the kept prefix preserves the user's work; extra slots are rests.
  void _setMeter(int beatsPerBar) {
    if (beatsPerBar == _beatsPerBar) return;
    final slots = beatsPerBar * 2;
    setState(() {
      _beatsPerBar = beatsPerBar;
      _pattern = [
        for (var i = 0; i < slots; i++)
          i < _pattern.length ? _pattern[i] : null,
      ];
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _chords.isNotEmpty &&
      _pattern.any((d) => d != null);

  /// Chord labels grouped by quality, filtered by a case-insensitive
  /// [query]. Mirrors `ChordLibraryScreen._grouped`/`_classify` (same rules,
  /// so the two pickers group identically); the shared classifier belongs in
  /// `features/chords` once a round may touch that feature.
  static Map<_ChordGroup, List<String>> _groupedChords(String query) {
    final q = query.toLowerCase();
    final out = {for (final g in _ChordGroup.values) g: <String>[]};
    for (final label in ChordShapes.allLabels) {
      if (q.isNotEmpty && !label.toLowerCase().contains(q)) continue;
      out[_classify(label)]!.add(label);
    }
    out.removeWhere((_, labels) => labels.isEmpty);
    return out;
  }

  /// Total over `ChordShapes.allLabels`: `sus` and `7` are read off the
  /// suffix, a bare trailing `m` (never `maj`, never the `b` of a flat root)
  /// is the minor triad, and everything else — including slash and `add`
  /// shapes — is a major.
  static _ChordGroup _classify(String label) {
    if (label.contains('sus')) return _ChordGroup.suspended;
    if (label.contains('7')) return _ChordGroup.seventh;
    final quality = label.replaceAll(RegExp(r'^[A-G]#?'), '');
    if (quality == 'm') return _ChordGroup.minor;
    return _ChordGroup.major;
  }

  static String _groupLabel(AppLocalizations l10n, _ChordGroup group) =>
      switch (group) {
        _ChordGroup.major => l10n.chordGroupMajor,
        _ChordGroup.minor => l10n.chordGroupMinor,
        _ChordGroup.seventh => l10n.chordGroupSeventh,
        _ChordGroup.suspended => l10n.chordGroupSuspended,
      };

  Future<void> _suggest() async {
    final chords = await showProgressionPicker(context);
    if (chords != null && chords.isNotEmpty) {
      setState(() => _chords = [..._chords, ...chords]);
    }
  }

  Future<void> _save() async {
    final ctrl = ref.read(songsProvider.notifier);
    if (widget.existing != null) {
      await ctrl.update(
        widget.existing!.copyWith(
          name: _name.text.trim(),
          chords: _chords,
          pattern: _pattern,
          bpm: _bpm,
          beatsPerBar: _beatsPerBar,
        ),
      );
    } else {
      await ctrl.add(
        name: _name.text.trim(),
        chords: _chords,
        pattern: _pattern,
        bpm: _bpm,
        beatsPerBar: _beatsPerBar,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chordGroups = _groupedChords(_chordQuery);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? l10n.songNewTitle : l10n.songEditTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.songName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 26),

            Row(
              children: [
                Expanded(child: _Label(l10n.songProgression)),
                TextButton.icon(
                  onPressed: _suggest,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(l10n.songSuggest),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_chords.isEmpty)
              Text(
                l10n.songProgressionHint,
                style: TextStyle(color: Theme.of(context).hintColor),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _chords.length; i++)
                    InputChip(
                      label: Text(_chords[i]),
                      onDeleted: () => setState(() => _chords.removeAt(i)),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              l10n.songAddChord,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            // Audit U5 — the picker used to be one unstructured grid of every
            // shape we have a diagram for. It is now filterable and grouped by
            // quality, exactly like the Chord library's picker: `_classify`
            // covers every label in `ChordShapes.allLabels`, so there is no
            // "other" bucket to fall into. Chip labels (and therefore the
            // finders the existing tests use) are unchanged.
            TextField(
              key: const Key('song-builder-chord-filter'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.chordLibrarySearch,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _chordQuery = v.trim()),
            ),
            for (final entry in chordGroups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
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
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final label in entry.value)
                    ActionChip(
                      label: Text(label),
                      onPressed: () => setState(() => _chords.add(label)),
                    ),
                ],
              ),
            ],
            // A filter that matches nothing must say so, not leave a blank gap.
            if (chordGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  l10n.chordLibraryNoResults(_chordQuery),
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ),
            const SizedBox(height: 28),

            Row(
              children: [
                Expanded(child: _Label(l10n.songStrumPattern)),
                // Time-signature notation is universal — deliberately not
                // localized (like chord labels).
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 4, label: Text('4/4')),
                    ButtonSegment(value: 3, label: Text('3/4')),
                  ],
                  selected: {_beatsPerBar},
                  onSelectionChanged: (s) => _setMeter(s.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.songStrumPatternHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final preset in StrumPatternPreset.forMeter(_beatsPerBar))
                  ActionChip(
                    label: Text(preset.name),
                    onPressed: () =>
                        setState(() => _pattern = [...preset.pattern]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            StrumPatternEditor(
              pattern: _pattern,
              onChanged: (p) => setState(() => _pattern = p),
            ),
            const SizedBox(height: 28),

            _Label(l10n.songTempo),
            Row(
              children: [
                // Tap the tempo of the track you're writing along to
                // (round 103, same tool as the metronome's).
                IconButton.filledTonal(
                  tooltip: l10n.metronomeTap,
                  icon: const Icon(Icons.touch_app_outlined),
                  onPressed: () {
                    final bpm = _tapTempo.tap(DateTime.now());
                    if (bpm != null) setState(() => _bpm = bpm);
                  },
                ),
                Expanded(
                  child: Slider(
                    value: _bpm.toDouble(),
                    min: 50,
                    max: 180,
                    divisions: 130,
                    label: '$_bpm',
                    onChanged: (v) => setState(() => _bpm = v.round()),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    l10n.songBpm(_bpm),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _valid ? _save : null,
        backgroundColor: _valid
            ? AppColors.primary
            : Theme.of(context).disabledColor,
        icon: const Icon(Icons.check),
        label: Text(l10n.songSave),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.2,
        color: AppColors.primary,
      ),
    );
  }
}

/// Quality buckets for the add-chord picker (audit U5). `ChordShape` carries
/// no quality field, so the bucket is derived from the label suffix.
enum _ChordGroup { major, minor, seventh, suspended }
