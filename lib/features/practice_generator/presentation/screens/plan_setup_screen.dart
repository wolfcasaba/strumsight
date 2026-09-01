import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final state = widget.controller.state;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planSetupTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SsSpacing.space5),
          children: [
            Text(
              l10n.planSetupStep(state.currentStep + 1, 5),
              style: typography.labelLarge.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: SsSpacing.space4),
            if (state.isRestoring)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: SsSpacing.space6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SsSkeleton(width: 220, height: 24),
                      SizedBox(height: SsSpacing.space3),
                      SsSkeleton(width: 260, height: 16),
                    ],
                  ),
                ),
              )
            else ...[
              _stepBody(context, state),
              if (state.hasHardConflict) ...[
                const SizedBox(height: SsSpacing.space3),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.planSetupConflict,
                    key: const Key('plan-setup-conflict'),
                    style: typography.bodyMedium.copyWith(color: colors.danger),
                  ),
                ),
              ],
              if (state.persistenceFailed) ...[
                const SizedBox(height: SsSpacing.space3),
                Text(
                  l10n.planSetupNoDraft,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: SsSpacing.space6),
              Row(
                children: [
                  if (state.currentStep > 0)
                    SsButton(
                      key: const Key('plan-setup-back'),
                      variant: SsButtonVariant.tertiary,
                      onPressed: widget.controller.back,
                      label: l10n.planSetupBack,
                    ),
                  const Spacer(),
                  SsButton(
                    key: const Key('plan-setup-next'),
                    onPressed: state.hasHardConflict
                        ? null
                        : () => widget.controller.next(),
                    label: state.currentStep == 4
                        ? l10n.planSetupFinish
                        : l10n.planSetupNext,
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final titleStyle = typography.titleLarge.copyWith(
      color: colors.textPrimary,
    );
    final request = state.request;
    switch (state.currentStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.planSetupGoalTitle, style: titleStyle),
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
            Text(l10n.planSetupAvailabilityTitle, style: titleStyle),
            AvailabilityEditor(
              days: request?.availability.days ?? const [],
              onChanged: widget.controller.setAvailability,
              referenceDate: widget.controller.clock(),
            ),
            SsButton(
              key: const Key('plan-setup-unknown'),
              variant: SsButtonVariant.tertiary,
              onPressed: () => widget.controller.setAvailability(const []),
              label: l10n.planSetupUnknown,
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
            Text(l10n.planSetupComfortTitle, style: titleStyle),
            const SizedBox(height: SsSpacing.space3),
            // Raw TextField, not SsTextField (§0.0.A/R4 exception): this
            // field takes unbounded multi-line comfort notes
            // (`maxLines: null`), a shape SsTextField's non-nullable
            // `int maxLines` parameter cannot express — swapping it would
            // silently cap the learner's free text to one line (§5.1, no
            // behavior loss).
            TextField(
              key: const Key('plan-comfort-free-text'),
              controller: _comfortController,
              maxLines: null,
              decoration: InputDecoration(
                hintText: l10n.planSetupComfortHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: widget.controller.setComfortText,
            ),
            const SizedBox(height: SsSpacing.space1),
            Semantics(
              key: const Key('plan-comfort-safety-hint'),
              label: l10n.practicePrivacyDiscomfortSafetyBody,
              child: Text(
                l10n.practicePrivacyDiscomfortSafetyBody,
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            SsButton(
              key: const Key('plan-setup-unknown'),
              variant: SsButtonVariant.tertiary,
              onPressed: () {
                _comfortController.clear();
                widget.controller.setComfortText('');
              },
              label: l10n.planSetupUnknown,
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: typography.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: SsSpacing.space3),
        SsButton(
          variant: SsButtonVariant.secondary,
          onPressed: onChoice,
          label: choice,
        ),
        SsButton(
          key: const Key('plan-setup-unknown'),
          variant: SsButtonVariant.tertiary,
          onPressed: onUnknown,
          label: l10n.planSetupUnknown,
        ),
      ],
    );
  }
}
