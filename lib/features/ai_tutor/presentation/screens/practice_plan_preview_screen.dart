import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/practice_plan_block.dart';
import '../../domain/models/practice_plan_draft.dart';
import '../../domain/services/practice_plan_validator.dart';
import '../widgets/tutor_source_sheet.dart';

class PracticePlanPreviewScreen extends StatefulWidget {
  const PracticePlanPreviewScreen({
    super.key,
    required this.draft,
    required this.validationContext,
    this.validator = const PracticePlanValidator(),
    this.onDraftChanged,
    this.onSave,
    this.onStart,
  });

  final PracticePlanDraft draft;
  final PracticePlanValidationContext validationContext;
  final PracticePlanValidator validator;
  final ValueChanged<PracticePlanDraft>? onDraftChanged;
  final ValueChanged<PracticePlanDraft>? onSave;
  final ValueChanged<PracticePlanDraft>? onStart;

  @override
  State<PracticePlanPreviewScreen> createState() =>
      _PracticePlanPreviewScreenState();
}

class _PracticePlanPreviewScreenState extends State<PracticePlanPreviewScreen> {
  late PracticePlanDraft _draft;
  late PracticePlanValidationResult _validation;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _validate();
  }

  @override
  void didUpdateWidget(covariant PracticePlanPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.draft, widget.draft) ||
        !identical(oldWidget.validationContext, widget.validationContext) ||
        !identical(oldWidget.validator, widget.validator)) {
      _draft = widget.draft;
      _validate();
    }
  }

  void _validate() {
    _validation = widget.validator.validate(
      _draft,
      context: widget.validationContext,
    );
  }

  void _applyEdit(PracticePlanDraft draft) {
    final edited = draft.copyWith(source: PracticePlanSource.userEdited);
    setState(() {
      _draft = edited;
      _validate();
    });
    widget.onDraftChanged?.call(edited);
  }

  void _changeDuration(int index, int deltaMinutes) {
    final blocks = List<PracticePlanBlock>.from(_draft.blocks);
    final block = blocks[index];
    final nextMinutes = block.duration.inMinutes + deltaMinutes;
    if (nextMinutes < 1) return;
    blocks[index] = block.copyWith(duration: Duration(minutes: nextMinutes));
    _applyEdit(
      _draft.copyWith(blocks: blocks, targetDuration: _totalDuration(blocks)),
    );
  }

  void _deleteBlock(int index) {
    final blocks = List<PracticePlanBlock>.from(_draft.blocks)..removeAt(index);
    _applyEdit(
      _draft.copyWith(blocks: blocks, targetDuration: _totalDuration(blocks)),
    );
  }

  void _moveBlock(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _draft.blocks.length) return;
    final blocks = List<PracticePlanBlock>.from(_draft.blocks);
    final item = blocks.removeAt(index);
    blocks.insert(target, item);
    _applyEdit(_draft.copyWith(blocks: blocks));
  }

  Duration _totalDuration(List<PracticePlanBlock> blocks) =>
      blocks.fold(Duration.zero, (total, block) => total + block.duration);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = sanitizeTutorDisplayText(_draft.title);
    final isValid = _validation.isValid;

    return Semantics(
      container: true,
      label: l10n.aiTutorPlanSemantics,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.aiTutorPlanPreviewTitle(title))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              Text(
                l10n.aiTutorPlanTotalDuration(_draft.targetDuration.inMinutes),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.aiTutorPlanRationale(
                  sanitizeTutorDisplayText(_draft.rationale),
                ),
              ),
              const SizedBox(height: 16),
              if (_draft.blocks.isEmpty)
                Text(l10n.aiTutorPlanEmpty)
              else
                for (var index = 0; index < _draft.blocks.length; index++)
                  _BlockEditor(
                    key: ValueKey('plan-block-${_draft.blocks[index].id}'),
                    block: _draft.blocks[index],
                    index: index,
                    count: _draft.blocks.length,
                    typeLabel: _blockTypeLabel(l10n, _draft.blocks[index].type),
                    onIncrease: () => _changeDuration(index, 1),
                    onDecrease: () => _changeDuration(index, -1),
                    onDelete: () => _deleteBlock(index),
                    onMoveUp: () => _moveBlock(index, -1),
                    onMoveDown: () => _moveBlock(index, 1),
                  ),
              if (!isValid) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  l10n.aiTutorPlanInvalid,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final code in _validation.codes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• ${_issueLabel(l10n, code)}'),
                  ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ElevatedButton(
                    key: const ValueKey('plan-save'),
                    onPressed: isValid
                        ? () => widget.onSave?.call(_draft)
                        : null,
                    child: Text(l10n.aiTutorPlanSave),
                  ),
                  FilledButton.tonal(
                    key: const ValueKey('plan-start'),
                    onPressed: isValid
                        ? () => widget.onStart?.call(_draft)
                        : null,
                    child: Text(l10n.aiTutorPlanStart),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _blockTypeLabel(AppLocalizations l10n, String type) => switch (type) {
    PracticePlanBlockType.warmup => l10n.aiTutorPlanBlockWarmup,
    PracticePlanBlockType.technique => l10n.aiTutorPlanBlockTechnique,
    PracticePlanBlockType.rhythm => l10n.aiTutorPlanBlockRhythm,
    PracticePlanBlockType.chordChange => l10n.aiTutorPlanBlockChordChange,
    PracticePlanBlockType.songRange => l10n.aiTutorPlanBlockSongRange,
    PracticePlanBlockType.speedBuilder => l10n.aiTutorPlanBlockSpeedBuilder,
    PracticePlanBlockType.freePractice => l10n.aiTutorPlanBlockFreePractice,
    PracticePlanBlockType.reflection => l10n.aiTutorPlanBlockReflection,
    PracticePlanBlockType.rest => l10n.aiTutorPlanBlockRest,
    _ => l10n.aiTutorPlanBlockUnknown,
  };

  String _issueLabel(AppLocalizations l10n, String code) => switch (code) {
    PracticePlanValidationCode.durationTargetNonPositive =>
      l10n.aiTutorPlanIssueDuration,
    PracticePlanValidationCode.durationBlockNonPositive =>
      l10n.aiTutorPlanIssueBlockDuration,
    PracticePlanValidationCode.durationMismatch =>
      l10n.aiTutorPlanIssueDurationMismatch,
    PracticePlanValidationCode.unsupportedBlockType =>
      l10n.aiTutorPlanIssueUnsupportedType,
    PracticePlanValidationCode.tempoOutOfRange => l10n.aiTutorPlanIssueTempo,
    PracticePlanValidationCode.practiceTargetMissing =>
      l10n.aiTutorPlanIssuePracticeTarget,
    PracticePlanValidationCode.songMissing => l10n.aiTutorPlanIssueSong,
    PracticePlanValidationCode.tuningMismatch => l10n.aiTutorPlanIssueTuning,
    PracticePlanValidationCode.userAvoidConflict => l10n.aiTutorPlanIssueAvoid,
    PracticePlanValidationCode.capabilityUnavailable =>
      l10n.aiTutorPlanIssueCapability,
    PracticePlanValidationCode.skillUnavailable => l10n.aiTutorPlanIssueSkill,
    _ => l10n.aiTutorPlanIssueUnknown,
  };
}

class _BlockEditor extends StatelessWidget {
  const _BlockEditor({
    super.key,
    required this.block,
    required this.index,
    required this.count,
    required this.typeLabel,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final PracticePlanBlock block;
  final int index;
  final int count;
  final String typeLabel;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.aiTutorPlanBlockSummary(typeLabel, block.duration.inMinutes),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (block.tempoBpm != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                l10n.aiTutorPlanBlockTempo(
                  sanitizeTutorDisplayText(block.tempoBpm!.toString()),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: <Widget>[
                IconButton(
                  key: ValueKey('plan-increase-${block.id}'),
                  tooltip: l10n.aiTutorPlanIncreaseDuration(typeLabel),
                  onPressed: onIncrease,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  key: ValueKey('plan-decrease-${block.id}'),
                  tooltip: l10n.aiTutorPlanDecreaseDuration(typeLabel),
                  onPressed: onDecrease,
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  key: ValueKey('plan-delete-${block.id}'),
                  tooltip: l10n.aiTutorPlanDeleteBlock(typeLabel),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
                if (index > 0)
                  IconButton(
                    key: ValueKey('plan-up-${block.id}'),
                    tooltip: l10n.aiTutorPlanMoveUp(typeLabel),
                    onPressed: onMoveUp,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                if (index < count - 1)
                  IconButton(
                    key: ValueKey('plan-down-${block.id}'),
                    tooltip: l10n.aiTutorPlanMoveDown(typeLabel),
                    onPressed: onMoveDown,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
