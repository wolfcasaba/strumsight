/// The Practice feature's Setup screen (E02-R12, ADR 0078).
///
/// This screen edits a [`PracticeSessionConfig`] for one [PracticeDefinition]
/// (resolved by id from the catalog). The validation surface is the
/// domain's [`PracticeSessionConfig.validate`]; the UI never carries its
/// own copy of any min/max. The Start action emits a [`PreparePractice`]
/// command through [`practicePrepareSinkProvider`]; Kör 13 swaps the
/// production sink for the real session controller.
///
/// What lives here:
///   * Localized field labels, controls, and the Start CTA (A4, A8);
///   * Mode-specific visibility — Free Practice hides scoring options,
///     Rhythm-only hides the chord hint, the rest show the scoring profile
///     (A5);
///   * Domain-derived limits (BPM 30..300, count-in 0..4, loop 1..32) — no
///     hand-rolled copy of those numbers anywhere (A4 red-flag guard);
///   * A "command sent" snackbar after a valid Start, no navigation
///     (Kör 13 brings the session route).
///
/// What does NOT live here:
///   * No clock, timing primitive, matcher, or scorer — A9 guard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/practice_setup_controller.dart';
import '../../domain/model/meter.dart';
import '../../domain/model/practice_definition.dart';
import '../../domain/model/practice_mode.dart';
import '../../domain/model/practice_validation.dart';
import '../../domain/model/tempo.dart';
import '../../application/practice_catalog_controller.dart';
import '../practice_route_args.dart';
import '../widgets/practice_mode_card.dart';

/// Resolves the definition id from the route. Reads the URI through the
/// `GoRouter` (no `BuildContext`-based state). Returns a structured
/// [PracticeSetupArgs] — never throws, never returns null.
PracticeSetupArgs _readArgs(BuildContext context) {
  final router = GoRouter.of(context);
  final id = router.routeInformationProvider.value.uri.queryParameters['id'];
  return parsePracticeSetupArgs(id);
}

/// The Setup screen.
class PracticeSetupScreen extends ConsumerWidget {
  const PracticeSetupScreen({super.key, this.argsOverride});

  /// Test-only override. When non-null, the screen uses this arg shape
  /// instead of reading from `GoRouter.state`. Production callers leave
  /// this null.
  final PracticeSetupArgs? argsOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final args = argsOverride ?? _readArgs(context);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => _backToHub(context)),
        title: Text(l10n.practiceSetupTitle),
      ),
      body: SafeArea(
        child: switch (args.request) {
          PracticeSetupRequest.hasId => _resolveAndBuild(
            context,
            ref,
            args.definitionId!,
          ),
          PracticeSetupRequest.missing ||
          PracticeSetupRequest.blank => _RouteError(
            message: args.localizeMissing(l10n),
            onBack: () => _backToHub(context),
          ),
        },
      ),
    );
  }

  Widget _resolveAndBuild(
    BuildContext context,
    WidgetRef ref,
    String definitionId,
  ) {
    final l10n = AppLocalizations.of(context);
    final repository = ref.watch(practiceCatalogRepositoryProvider);
    final definition = repository.byId(definitionId);
    if (definition == null) {
      return _RouteError(
        message: l10n.practiceErrorDefinitionNotFound,
        onBack: () => _backToHub(context),
      );
    }
    final controller = ref.watch(practiceSetupControllerProvider(definition));
    return _SetupForm(definition: definition, controller: controller);
  }

  void _backToHub(BuildContext context) {
    context.go(AppRoutes.practiceHub);
  }
}

class _RouteError extends StatelessWidget {
  const _RouteError({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.practiceRouteErrorTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onBack,
            child: Text(l10n.practiceRouteErrorBack),
          ),
        ],
      ),
    );
  }
}

class _SetupForm extends ConsumerStatefulWidget {
  const _SetupForm({required this.definition, required this.controller});

  final PracticeDefinition definition;
  final PracticeSetupState controller;

  @override
  ConsumerState<_SetupForm> createState() => _SetupFormState();
}

class _SetupFormState extends ConsumerState<_SetupForm> {
  /// Local copy of the seeded `effectiveTempo` — the slider needs a
  /// continuous value; the controller only sees the rounded bpm on
  /// `onChangeEnd`.
  double? _bpmDraft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(practiceSetupControllerProvider(widget.definition));
    final controller = ref.read(
      practiceSetupControllerProvider(widget.definition).notifier,
    );
    final config = state.config;
    final bpm = _bpmDraft ?? config.effectiveTempo.bpm;
    final failures = state.failures;
    final canStart = state.isValid;
    final firstFailure = failures.isEmpty ? null : failures.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _SectionLabel(practiceDefinitionDisplayTitle(l10n, widget.definition)),
        const SizedBox(height: 4),
        Text(
          practiceModeLabel(l10n, widget.definition.mode),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        _BpmField(
          bpm: bpm,
          onChanged: (v) => setState(() => _bpmDraft = v),
          onChangeEnd: (v) {
            controller.setTempoBpm(v);
            setState(() => _bpmDraft = null);
          },
        ),
        const SizedBox(height: 16),
        _IntStepperField(
          label: l10n.practiceSetupCountInLabel,
          help: l10n.practiceSetupCountInHelp,
          value: config.countInBars,
          onChanged: controller.setCountInBars,
        ),
        const SizedBox(height: 16),
        _IntStepperField(
          label: l10n.practiceSetupLoopLabel,
          help: l10n.practiceSetupLoopHelp,
          value: config.loopCount,
          onChanged: controller.setLoopCount,
        ),
        const SizedBox(height: 16),
        _MeterReadout(meter: widget.definition.meter),
        const SizedBox(height: 16),
        _ToggleRow(
          label: l10n.practiceSetupMetronomeLabel,
          value: config.metronomeEnabled,
          onChanged: controller.setMetronomeEnabled,
        ),
        _ToggleRow(
          label: l10n.practiceSetupAccentLabel,
          value: config.accentEnabled,
          onChanged: controller.setAccentEnabled,
        ),
        if (widget.definition.mode != PracticeMode.rhythmOnly)
          _ToggleRow(
            label: l10n.practiceSetupChordHintLabel,
            value: config.expectedChordHintEnabled,
            onChanged: controller.setChordHintEnabled,
          ),
        if (widget.definition.mode != PracticeMode.freePractice) ...[
          const SizedBox(height: 12),
          _ScoringProfileReadout(
            label: l10n.practiceSetupScoringProfileLabel,
            profileId: widget.definition.scoringProfile.id,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: canStart
              ? () {
                  if (controller.start()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.practiceSetupStarted),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.practiceSetupStart),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        if (firstFailure != null) ...[
          const SizedBox(height: 12),
          _ValidationMessage(failure: firstFailure),
        ],
      ],
    );
  }
}

/// The localized message for one [PracticeValidationFailure]. Only the
/// codes the Setup screen can currently produce are mapped; new codes land
/// here when their UI surface exists.
String _localizeFailure(AppLocalizations l10n, PracticeValidationFailure f) {
  switch (f.code) {
    case PracticeValidationCode.tempoBpmOutOfRange:
      return l10n.practiceErrorTempoBpmOutOfRange;
    case PracticeValidationCode.configCountInBarsOutOfRange:
      return l10n.practiceErrorConfigCountInBarsOutOfRange;
    case PracticeValidationCode.configLoopCountOutOfRange:
      return l10n.practiceErrorConfigLoopCountOutOfRange;
  }
  return f.message;
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage({required this.failure});

  final PracticeValidationFailure failure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _localizeFailure(l10n, failure),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
    );
  }
}

class _BpmField extends StatelessWidget {
  const _BpmField({
    required this.bpm,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double bpm;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.practiceSetupBpmLabel,
      value: '${bpm.round()} ${l10n.practiceSetupBpmUnit}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.practiceSetupBpmLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${bpm.round()} ${l10n.practiceSetupBpmUnit}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: bpm.clamp(Tempo.minimumBpm, Tempo.maximumBpm),
            min: Tempo.minimumBpm,
            max: Tempo.maximumBpm,
            divisions: (Tempo.maximumBpm - Tempo.minimumBpm).round(),
            label: '${bpm.round()}',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          Text(
            l10n.practiceSetupBpmHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _IntStepperField extends StatelessWidget {
  const _IntStepperField({
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String help;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: '$value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => onChanged(value - 1),
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: '-1',
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onChanged(value + 1),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '+1',
              ),
            ],
          ),
          Text(help, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _MeterReadout extends StatelessWidget {
  const _MeterReadout({required this.meter});

  final Meter meter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.practiceSetupMeterLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${meter.beatsPerBar}/${meter.beatUnit}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ScoringProfileReadout extends StatelessWidget {
  const _ScoringProfileReadout({required this.label, required this.profileId});

  final String label;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text(profileId, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      value: value,
      onChanged: onChanged,
    );
  }
}
