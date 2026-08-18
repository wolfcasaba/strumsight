import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../controller/plan_setup_controller.dart';
import '../widgets/availability_editor.dart';
import '../widgets/practice_goal_picker.dart';

/// Five-step, locally resumable plan-input wizard.
class PlanSetupScreen extends StatefulWidget {
  const PlanSetupScreen({required this.controller, super.key});

  final PlanSetupController controller;

  @override
  State<PlanSetupScreen> createState() => _PlanSetupScreenState();
}

class _PlanSetupScreenState extends State<PlanSetupScreen> {
  late final TextEditingController _comfortController;

  @override
  void initState() {
    super.initState();
    _comfortController = TextEditingController();
    widget.controller.addListener(_onStateChanged);
    Future<void>.microtask(widget.controller.restore);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PlanSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onStateChanged);
    widget.controller.addListener(_onStateChanged);
    Future<void>.microtask(widget.controller.restore);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _comfortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.controller.state;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planSetupTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l10n.planSetupStep(state.currentStep + 1, 5),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 16),
            if (state.isRestoring)
              const Center(child: CircularProgressIndicator())
            else ...[
              _stepBody(context, state),
              if (state.hasHardConflict) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.planSetupConflict,
                    key: const Key('plan-setup-conflict'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (state.persistenceFailed) ...[
                const SizedBox(height: 12),
                Text(l10n.planSetupNoDraft),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  if (state.currentStep > 0)
                    TextButton(
                      key: const Key('plan-setup-back'),
                      onPressed: widget.controller.back,
                      child: Text(l10n.planSetupBack),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('plan-setup-next'),
                    onPressed: state.hasHardConflict
                        ? null
                        : () => widget.controller.next(),
                    child: Text(
                      state.currentStep == 4
                          ? l10n.planSetupFinish
                          : l10n.planSetupNext,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context, PlanSetupState state) {
    final l10n = AppLocalizations.of(context);
    final request = state.request;
    switch (state.currentStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.planSetupGoalTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            PracticeGoalPicker(
              selected: request?.goals.isEmpty ?? true
                  ? null
                  : request!.goals.single.type,
              onChanged: widget.controller.selectGoal,
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.planSetupAvailabilityTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            AvailabilityEditor(
              days: request?.availability.days ?? const [],
              onChanged: widget.controller.setAvailability,
              referenceDate: widget.controller.clock(),
            ),
            TextButton(
              key: const Key('plan-setup-unknown'),
              onPressed: () => widget.controller.setAvailability(const []),
              child: Text(l10n.planSetupUnknown),
            ),
          ],
        );
      case 2:
        return _choiceStep(
          context,
          l10n.planSetupEquipmentTitle,
          l10n.planSetupEquipmentGuitar,
          () => widget.controller.setEquipment('acousticGuitar'),
          () => widget.controller.setEquipment(null),
        );
      case 3:
        return _choiceStep(
          context,
          l10n.planSetupPreferenceTitle,
          l10n.planSetupPreferenceShortSessions,
          () => widget.controller.setPreference('shortSessions'),
          () => widget.controller.setPreference(null),
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.planSetupComfortTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('plan-comfort-free-text'),
              controller: _comfortController,
              maxLines: null,
              decoration: InputDecoration(hintText: l10n.planSetupComfortHint),
              onChanged: widget.controller.setComfortText,
            ),
            TextButton(
              key: const Key('plan-setup-unknown'),
              onPressed: () {
                _comfortController.clear();
                widget.controller.setComfortText('');
              },
              child: Text(l10n.planSetupUnknown),
            ),
          ],
        );
    }
  }

  Widget _choiceStep(
    BuildContext context,
    String title,
    String choice,
    VoidCallback onChoice,
    VoidCallback onUnknown,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onChoice, child: Text(choice)),
        TextButton(
          key: const Key('plan-setup-unknown'),
          onPressed: onUnknown,
          child: Text(l10n.planSetupUnknown),
        ),
      ],
    );
  }
}
