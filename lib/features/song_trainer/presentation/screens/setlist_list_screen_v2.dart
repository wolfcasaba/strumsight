import 'package:flutter/material.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/setlists/setlist_controller.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_setlist.dart';

final class SetlistListScreenV2 extends StatefulWidget {
  const SetlistListScreenV2({
    super.key,
    required this.controller,
    required this.clock,
  });

  final SetlistController controller;
  final DateTime Function() clock;

  @override
  State<SetlistListScreenV2> createState() => _SetlistListScreenV2State();
}

final class _SetlistListScreenV2State extends State<SetlistListScreenV2> {
  List<SongSetlist>? _setlists;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await widget.controller.load();
    if (!mounted) return;
    switch (loaded) {
      case Success(:final value):
        setState(() => _setlists = value);
      case Failure():
        setState(() => _setlists = const <SongSetlist>[]);
    }
  }

  Future<void> _edit(SongSetlist? existing) async {
    final saved = await showModalBottomSheet<SongSetlist>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _SetlistEditorSheet(existing: existing, clock: widget.clock),
    );
    if (saved == null || !mounted) return;
    setState(() => _isSaving = true);
    final outcome = await widget.controller.save(saved);
    if (!mounted) return;
    setState(() => _isSaving = false);
    switch (outcome) {
      case Success():
        setState(() {
          final next = <SongSetlist>[...?_setlists]
            ..removeWhere((setlist) => setlist.id == saved.id)
            ..add(saved)
            ..sort((left, right) => left.name.compareTo(right.name));
          _setlists = List<SongSetlist>.unmodifiable(next);
        });
      case Failure():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).setlistV2SaveFailed),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final setlists = _setlists;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setlistV2Title)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('setlist-create'),
        onPressed: _isSaving ? null : () => _edit(null),
        icon: const Icon(Icons.playlist_add),
        label: Text(l10n.setlistV2Create),
      ),
      body: SafeArea(
        child: switch (setlists) {
          null => const Center(child: CircularProgressIndicator()),
          final values when values.isEmpty => Center(
            child: Semantics(
              liveRegion: true,
              child: Text(l10n.setlistV2Empty),
            ),
          ),
          final values => ListView.builder(
            key: const Key('setlist-list-window'),
            padding: const EdgeInsets.all(16),
            itemCount: values.length,
            itemBuilder: (context, index) {
              final setlist = values[index];
              return Card(
                child: ListTile(
                  title: Text(setlist.name),
                  subtitle: Text(l10n.setlistV2ItemCount(setlist.items.length)),
                  trailing: IconButton(
                    key: Key('setlist-edit-${setlist.id}'),
                    tooltip: l10n.setlistV2Edit,
                    onPressed: _isSaving ? null : () => _edit(setlist),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              );
            },
          ),
        },
      ),
    );
  }
}

final class _SetlistEditorSheet extends StatefulWidget {
  const _SetlistEditorSheet({required this.existing, required this.clock});

  final SongSetlist? existing;
  final DateTime Function() clock;

  @override
  State<_SetlistEditorSheet> createState() => _SetlistEditorSheetState();
}

final class _SetlistEditorSheetState extends State<_SetlistEditorSheet> {
  late final TextEditingController _name;
  late List<SongSetlistItem> _items;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _items = <SongSetlistItem>[...?widget.existing?.items];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final songId = await showDialog<String>(
      context: context,
      builder: (context) => const _SongIdDialog(),
    );
    if (songId == null || !mounted) return;
    try {
      final now = widget.clock().toUtc();
      setState(() {
        _items = <SongSetlistItem>[
          ..._items,
          SongSetlistItem(
            id: 'item-${now.microsecondsSinceEpoch}-${_items.length}',
            songId: SongId(songId),
          ),
        ];
      });
    } on ArgumentError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).setlistV2SongIdInvalid),
        ),
      );
    }
  }

  Future<void> _editOverrides(int index) async {
    final updated = await showDialog<SetlistItemOverrides>(
      context: context,
      builder: (context) =>
          _SetlistOverridesDialog(overrides: _items[index].overrides),
    );
    if (updated == null || !mounted) return;
    final old = _items[index];
    setState(() {
      final next = <SongSetlistItem>[..._items];
      next[index] = SongSetlistItem(
        id: old.id,
        songId: old.songId,
        overrides: updated,
        initialAvailability: old.initialAvailability,
      );
      _items = next;
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).setlistV2Incomplete),
        ),
      );
      return;
    }
    final now = widget.clock().toUtc();
    final existing = widget.existing;
    Navigator.of(context).pop(
      SongSetlist(
        id: existing?.id ?? 'setlist-${now.microsecondsSinceEpoch}',
        name: name,
        items: _items,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        notes: existing?.notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                widget.existing == null
                    ? l10n.setlistV2Create
                    : l10n.setlistV2Edit,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('setlist-editor-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l10n.setlistV2Name),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.setlistV2Items,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (var index = 0; index < _items.length; index++)
                ListTile(
                  key: Key('setlist-editor-item-${_items[index].id}'),
                  title: Text(_items[index].songId.value),
                  subtitle: Text(
                    l10n.setlistV2ItemSummary(
                      _items[index].overrides.speedMultiplier.toStringAsFixed(
                        1,
                      ),
                      _items[index].overrides.loopCount,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l10n.setlistV2EditOverrides,
                    onPressed: () => _editOverrides(index),
                    icon: const Icon(Icons.tune),
                  ),
                ),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: Text(l10n.setlistV2AddSong),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('setlist-editor-save'),
                onPressed: _save,
                child: Text(l10n.setlistV2Save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SongIdDialog extends StatefulWidget {
  const _SongIdDialog();

  @override
  State<_SongIdDialog> createState() => _SongIdDialogState();
}

final class _SongIdDialogState extends State<_SongIdDialog> {
  final TextEditingController _songId = TextEditingController();

  @override
  void dispose() {
    _songId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.setlistV2AddSong),
      content: TextField(
        key: const Key('setlist-editor-song-id'),
        controller: _songId,
        decoration: InputDecoration(labelText: l10n.setlistV2SongId),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.setlistV2Cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_songId.text.trim()),
          child: Text(l10n.setlistV2AddSong),
        ),
      ],
    );
  }
}

final class _SetlistOverridesDialog extends StatefulWidget {
  const _SetlistOverridesDialog({required this.overrides});

  final SetlistItemOverrides overrides;

  @override
  State<_SetlistOverridesDialog> createState() =>
      _SetlistOverridesDialogState();
}

final class _SetlistOverridesDialogState
    extends State<_SetlistOverridesDialog> {
  late final TextEditingController _speed;
  late final TextEditingController _loops;

  @override
  void initState() {
    super.initState();
    _speed = TextEditingController(
      text: widget.overrides.speedMultiplier.toString(),
    );
    _loops = TextEditingController(text: widget.overrides.loopCount.toString());
  }

  @override
  void dispose() {
    _speed.dispose();
    _loops.dispose();
    super.dispose();
  }

  void _save() {
    final speed = double.tryParse(_speed.text);
    final loops = int.tryParse(_loops.text);
    if (speed == null || speed <= 0 || loops == null || loops <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).setlistV2OverridesInvalid),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      SetlistItemOverrides(
        trackId: widget.overrides.trackId,
        range: widget.overrides.range,
        speedMultiplier: speed,
        loopCount: loops,
        countInBars: widget.overrides.countInBars,
        pauseAfter: widget.overrides.pauseAfter,
        capoOverride: widget.overrides.capoOverride,
        tuningOverrideCode: widget.overrides.tuningOverrideCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.setlistV2EditOverrides),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const Key('setlist-editor-speed'),
            controller: _speed,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.setlistV2Speed),
          ),
          TextField(
            key: const Key('setlist-editor-loops'),
            controller: _loops,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.setlistV2LoopCount),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.setlistV2Cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.setlistV2Save)),
      ],
    );
  }
}
