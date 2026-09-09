import 'package:flutter/material.dart';

import '../../../../core/music/strum.dart';
import '../../../../l10n/app_localizations.dart';

final class SongEventEditor extends StatefulWidget {
  const SongEventEditor({
    required this.measureCount,
    required this.onAddChord,
    required this.onApplyPattern,
    required this.onAddNote,
    required this.onSetTempo,
    required this.onSetMeter,
    super.key,
  });

  final int measureCount;
  final void Function(int measureIndex, String symbol) onAddChord;
  final void Function(int measureIndex, List<StrumDirection>) onApplyPattern;
  final void Function(int measureIndex, int midiPitch) onAddNote;
  final void Function(int measureIndex, int bpm) onSetTempo;
  final void Function(int measureIndex, int numerator, int denominator)
  onSetMeter;

  @override
  State<SongEventEditor> createState() => _SongEventEditorState();
}

final class _SongEventEditorState extends State<SongEventEditor> {
  var _measureIndex = 0;
  var _chord = 'C';
  var _note = '60';
  var _tempo = '120';
  var _meterNumerator = '4';
  var _meterDenominator = '4';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedMeasure = _measureIndex.clamp(0, widget.measureCount - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<int>(
          key: const Key('song-editor-measure'),
          initialValue: selectedMeasure,
          decoration: InputDecoration(labelText: l10n.songEditorEventMeasure),
          items: <DropdownMenuItem<int>>[
            for (var index = 0; index < widget.measureCount; index++)
              DropdownMenuItem<int>(value: index, child: Text('${index + 1}')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _measureIndex = value);
          },
        ),
        TextFormField(
          key: const Key('song-editor-chord'),
          initialValue: _chord,
          decoration: InputDecoration(labelText: l10n.songEditorChordField),
          onChanged: (value) => _chord = value,
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            OutlinedButton(
              key: const Key('song-editor-add-chord'),
              onPressed: _chord.trim().isEmpty
                  ? null
                  : () => widget.onAddChord(selectedMeasure, _chord.trim()),
              child: Text(l10n.songEditorAddChord),
            ),
            OutlinedButton(
              onPressed: () => widget.onApplyPattern(
                selectedMeasure,
                const <StrumDirection>[StrumDirection.down, StrumDirection.up],
              ),
              child: Text(l10n.songEditorApplyPattern),
            ),
          ],
        ),
        TextFormField(
          key: const Key('song-editor-note'),
          initialValue: _note,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.songEditorNoteField),
          onChanged: (value) => _note = value,
        ),
        OutlinedButton(
          key: const Key('song-editor-add-note'),
          onPressed: () {
            final pitch = int.tryParse(_note);
            if (pitch != null) widget.onAddNote(selectedMeasure, pitch);
          },
          child: Text(l10n.songEditorAddNote),
        ),
        TextFormField(
          key: const Key('song-editor-tempo'),
          initialValue: _tempo,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.songEditorTempoField),
          onChanged: (value) => _tempo = value,
        ),
        OutlinedButton(
          key: const Key('song-editor-set-tempo'),
          onPressed: () {
            final bpm = int.tryParse(_tempo);
            if (bpm != null && bpm > 0) {
              widget.onSetTempo(selectedMeasure, bpm);
            }
          },
          child: Text(l10n.songEditorSetTempo),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextFormField(
                key: const Key('song-editor-meter-numerator'),
                initialValue: _meterNumerator,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.songEditorMeterNumerator,
                ),
                onChanged: (value) => _meterNumerator = value,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('song-editor-meter-denominator'),
                initialValue: _meterDenominator,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.songEditorMeterDenominator,
                ),
                onChanged: (value) => _meterDenominator = value,
              ),
            ),
          ],
        ),
        OutlinedButton(
          key: const Key('song-editor-set-meter'),
          onPressed: () {
            final numerator = int.tryParse(_meterNumerator);
            final denominator = int.tryParse(_meterDenominator);
            if (numerator != null &&
                numerator > 0 &&
                denominator != null &&
                denominator > 0 &&
                denominator & (denominator - 1) == 0) {
              widget.onSetMeter(selectedMeasure, numerator, denominator);
            }
          },
          child: Text(l10n.songEditorSetMeter),
        ),
      ],
    );
  }
}
