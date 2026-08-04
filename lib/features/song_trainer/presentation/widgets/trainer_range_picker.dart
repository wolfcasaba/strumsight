import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/trainer/song_trainer_setup_state.dart';
import '../../domain/models/trainer_range.dart';

enum _RangeKind { fullSong, section, measure, bookmark }

/// Converts accessible, inclusive measure fields into an end-exclusive domain
/// range. It never clamps an invalid selection; the controller rejects it.
final class TrainerRangePicker extends StatefulWidget {
  const TrainerRangePicker({
    required this.sections,
    required this.selection,
    required this.onSelected,
    super.key,
  });

  final List<TrainerSectionOption> sections;
  final TrainerRange selection;
  final bool Function(TrainerRange range) onSelected;

  @override
  State<TrainerRangePicker> createState() => _TrainerRangePickerState();
}

final class _TrainerRangePickerState extends State<TrainerRangePicker> {
  late _RangeKind _kind;
  String? _sectionId;
  late TextEditingController _startController;
  late TextEditingController _endController;
  var _invalidRange = false;

  @override
  void initState() {
    super.initState();
    _kind = _kindFor(widget.selection);
    _sectionId = switch (widget.selection) {
      SectionRange(:final sectionId) => sectionId.value,
      BookmarkRange(:final range) when range is SectionRange =>
        range.sectionId.value,
      _ => null,
    };
    final range = widget.selection is MeasureRange
        ? widget.selection as MeasureRange
        : null;
    _startController = TextEditingController(
      text: range == null ? '' : '${range.start + 1}',
    );
    _endController = TextEditingController(
      text: range == null ? '' : '${range.endExclusive}',
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<_RangeKind>(
          key: const Key('trainer-range-kind'),
          initialValue: _kind,
          decoration: InputDecoration(labelText: l10n.trainerRangeTitle),
          items: <DropdownMenuItem<_RangeKind>>[
            DropdownMenuItem<_RangeKind>(
              value: _RangeKind.fullSong,
              child: Text(l10n.trainerRangeFull),
            ),
            DropdownMenuItem<_RangeKind>(
              value: _RangeKind.section,
              child: Text(l10n.trainerRangeSection),
            ),
            DropdownMenuItem<_RangeKind>(
              value: _RangeKind.measure,
              child: Text(l10n.trainerRangeMeasure),
            ),
            DropdownMenuItem<_RangeKind>(
              value: _RangeKind.bookmark,
              child: Text(l10n.trainerRangeBookmark),
            ),
          ],
          onChanged: (kind) {
            if (kind == null) return;
            setState(() {
              _kind = kind;
              _invalidRange = false;
            });
            if (kind == _RangeKind.fullSong) {
              widget.onSelected(const FullSongRange());
            }
          },
        ),
        if (_kind == _RangeKind.section) _sectionSelector(l10n),
        if (_kind == _RangeKind.measure) _measureFields(l10n),
        if (_kind == _RangeKind.bookmark)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.trainerRangeBookmarkUnavailable),
          ),
      ],
    );
  }

  Widget _sectionSelector(AppLocalizations l10n) =>
      DropdownButtonFormField<String>(
        key: const Key('trainer-range-section'),
        initialValue: _sectionId,
        decoration: InputDecoration(labelText: l10n.trainerRangeSection),
        items: <DropdownMenuItem<String>>[
          for (final section in widget.sections)
            DropdownMenuItem<String>(
              value: section.id.value,
              child: Text(section.name),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          final section = widget.sections.firstWhere(
            (candidate) => candidate.id.value == id,
          );
          setState(() => _sectionId = id);
          widget.onSelected(SectionRange(section.id));
        },
      );

  Widget _measureFields(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      children: <Widget>[
        TextField(
          key: const Key('trainer-range-start'),
          controller: _startController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.trainerRangeStart),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('trainer-range-end'),
          controller: _endController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.trainerRangeEnd),
        ),
        if (_invalidRange)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.trainerRangeInvalid),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('trainer-range-apply'),
            onPressed: _applyInclusiveRange,
            child: Text(l10n.trainerRangeApply),
          ),
        ),
      ],
    ),
  );

  void _applyInclusiveRange() {
    final start = int.tryParse(_startController.text);
    final endInclusive = int.tryParse(_endController.text);
    if (start == null ||
        endInclusive == null ||
        start <= 0 ||
        endInclusive < start) {
      setState(() => _invalidRange = true);
      return;
    }
    final accepted = widget.onSelected(
      MeasureRange.fromInclusive(
        start: start - 1,
        endInclusive: endInclusive - 1,
      ),
    );
    setState(() => _invalidRange = !accepted);
  }

  _RangeKind _kindFor(TrainerRange range) => switch (range) {
    FullSongRange() => _RangeKind.fullSong,
    SectionRange() => _RangeKind.section,
    MeasureRange() => _RangeKind.measure,
    BookmarkRange() => _RangeKind.bookmark,
  };
}
