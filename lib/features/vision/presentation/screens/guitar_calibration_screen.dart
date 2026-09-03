/// The manual guitar-geometry calibration screen (SDD Ch6 §13.3, E05-R11,
/// ADR 0181).
///
/// Three responsibilities delegated from the controller:
///
/// 1. Bind the editor to the R07 [PreviewFit] so every preview-space
///    pointer event maps through `toNormalized()` (§5.2 BLOCKER if violated).
/// 2. Wire the toolbar actions to the controller:
///    - **Reset** (clears the draft edits back to the initial seed).
///    - **Recalibrate** (destroys the persisted bundle; explicit confirm).
///    - **Save** (gated on `state.canSave`; manual §5.1).
/// 3. Surface the entry-staleness banner (R5 Recalibrate-entry — all five
///    reasons) so an existing-but-stale record still surfaces why.
/// 4. Toggle the precision (magnified) preview without writing a screenshot
///    to disk (ADR 0178 / 0183).
///
/// The controller is keyed by a runtime context — a single
/// [GuitarCalibrationContext] is declared at module scope and used by the
/// screen, the canvas, and any other family member that needs the same
/// draft state. The widget tree never recomputes the family key.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../../../core/camera/preview_fit.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/calibration/calibration_validity.dart';
import '../../domain/vision_setup_profile.dart';
import '../providers/guitar_calibration_providers.dart';
import '../widgets/guitar_anchor_editor.dart';
import '../widgets/guitar_geometry_preview.dart';

/// The single runtime context the editor binds to. The provider lives
/// in `guitar_calibration_providers.dart` so tests can override it.
class GuitarCalibrationScreen extends ConsumerStatefulWidget {
  const GuitarCalibrationScreen({super.key});

  @override
  ConsumerState<GuitarCalibrationScreen> createState() =>
      _GuitarCalibrationScreenState();
}

class _GuitarCalibrationScreenState
    extends ConsumerState<GuitarCalibrationScreen> {
  bool _precisionMode = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final context_ = ref.watch(guitarCalibrationRuntimeContextProvider);
    final state = ref.watch(guitarCalibrationControllerProvider(context_));
    final controller = ref.read(
      guitarCalibrationControllerProvider(context_).notifier,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.guitarCalibrationTitle),
        actions: [
          IconButton(
            key: const Key('guitar-calibration-precision-toggle'),
            tooltip: l10n.guitarCalibrationPrecisionToggle,
            icon: Icon(_precisionMode ? Icons.zoom_out : Icons.zoom_in),
            onPressed: () {
              setState(() {
                _precisionMode = !_precisionMode;
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SsSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.hasEntryStaleness)
                _EntryBanner(reason: state.entryEvaluationReason!, l10n: l10n),
              const SizedBox(height: SsSpacing.space3),
              _GeometryCanvas(precisionMode: _precisionMode),
              const SizedBox(height: SsSpacing.space3),
              _QualityScorePanel(state: state, l10n: l10n),
              const SizedBox(height: SsSpacing.space4),
              _Toolbar(
                state: state,
                onReset: () => _confirmReset(controller, l10n),
                onRecalibrate: state.hasPersistedRecord
                    ? () => _confirmRecalibrate(controller, l10n)
                    : null,
                onSave: () async {
                  final outcome = await controller.saveIfValid();
                  if (!mounted) return;
                  _showSaveSnackbar(outcome, l10n, state);
                },
                l10n: l10n,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(
    GuitarCalibrationController controller,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.guitarCalibrationResetTitle),
        content: Text(l10n.guitarCalibrationResetBody),
        actions: [
          TextButton(
            key: const Key('guitar-calibration-reset-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('guitar-calibration-reset-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.guitarCalibrationResetAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    controller.resetDraft();
  }

  Future<void> _confirmRecalibrate(
    GuitarCalibrationController controller,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.guitarCalibrationRecalibrateTitle),
        content: Text(l10n.guitarCalibrationRecalibrateBody),
        actions: [
          TextButton(
            key: const Key('guitar-calibration-recalibrate-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('guitar-calibration-recalibrate-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.guitarCalibrationRecalibrateAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.recalibrate();
  }

  void _showSaveSnackbar(
    GuitarCalibrationSaveOutcome outcome,
    AppLocalizations l10n,
    GuitarCalibrationState state,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final text = switch (outcome) {
      GuitarCalibrationSaveOutcome.saved => l10n.guitarCalibrationSaveSuccess,
      GuitarCalibrationSaveOutcome.blocked => l10n.guitarCalibrationSaveBlocked,
      GuitarCalibrationSaveOutcome.writeFailed =>
        l10n.guitarCalibrationSaveFailed,
      GuitarCalibrationSaveOutcome.none => l10n.commonClose,
    };
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

class _GeometryCanvas extends ConsumerWidget {
  const _GeometryCanvas({required this.precisionMode});

  final bool precisionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final context_ = ref.watch(guitarCalibrationRuntimeContextProvider);
    final state = ref.watch(guitarCalibrationControllerProvider(context_));
    final controller = ref.read(
      guitarCalibrationControllerProvider(context_).notifier,
    );
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;
    final viewport = PreviewRect(
      left: 0,
      top: 0,
      width: size.width - 32,
      height: precisionMode ? 360.0 : 240.0,
    );
    final uprightSize = UprightSize(
      width: viewport.width,
      height: viewport.height,
    );
    final fit = PreviewFit(
      imageSize: uprightSize,
      viewport: viewport,
      mode: PreviewFitMode.fit,
    );
    // Mirror parity (R07): the front camera presents a mirrored preview,
    // so a rightward drag should map to a decreasing normalised x. The
    // [PreviewFit] handles the math; the editor + preview only need the
    // boolean.
    final mirrorPreview = context_.camera == VisionCameraPreference.front;
    return Semantics(
      label: l10n.guitarCalibrationCanvasSemantic,
      child: Stack(
        children: [
          GuitarGeometryPreview(
            fit: fit,
            nut: state.nutAnchor,
            bridge: state.bridgeAnchor,
            neckPolygon: state.neckPolygon,
            mirrorPreview: mirrorPreview,
          ),
          GuitarAnchorEditor(
            fit: fit,
            nut: state.nutAnchor,
            bridge: state.bridgeAnchor,
            neckPolygon: state.neckPolygon,
            semanticsNutLabel: l10n.guitarCalibrationAnchorNutSemantic,
            semanticsBridgeLabel: l10n.guitarCalibrationAnchorBridgeSemantic,
            mirrorPreview: mirrorPreview,
            onAnchorChanged: (role, p) {
              controller.moveAnchor(role, p);
            },
            onPolygonVertexChanged: (i, p) =>
                controller.movePolygonVertex(i, p),
          ),
        ],
      ),
    );
  }
}

class _QualityScorePanel extends StatelessWidget {
  const _QualityScorePanel({required this.state, required this.l10n});

  final GuitarCalibrationState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).extension<SsTypography>()!;
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return SsCard(
      key: const Key('guitar-calibration-quality'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.guitarCalibrationQualityScore(state.qualityScore),
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space1),
          Text(
            l10n.guitarCalibrationQualityExplain,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.onReset,
    required this.onRecalibrate,
    required this.onSave,
    required this.l10n,
  });

  final GuitarCalibrationState state;
  final VoidCallback onReset;
  final VoidCallback? onRecalibrate;
  final VoidCallback onSave;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // A3 (§0.0/R5): at 1.5/2.0 textScale three side-by-side buttons overflow
    // a phone-width Row — Wrap lets the third button drop to its own line
    // instead, same buttons, same order, no clipped content.
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: SsSpacing.space2,
      runSpacing: SsSpacing.space2,
      children: [
        SsButton(
          key: const Key('guitar-calibration-reset-button'),
          variant: SsButtonVariant.tertiary,
          label: l10n.guitarCalibrationResetAction,
          onPressed: onReset,
        ),
        SsButton(
          key: const Key('guitar-calibration-save-button'),
          label: l10n.guitarCalibrationSaveAction,
          onPressed: state.canSave ? onSave : null,
        ),
        SsButton(
          key: const Key('guitar-calibration-recalibrate-button'),
          variant: SsButtonVariant.tertiary,
          label: l10n.guitarCalibrationRecalibrateAction,
          onPressed: onRecalibrate,
        ),
      ],
    );
  }
}

class _EntryBanner extends StatelessWidget {
  const _EntryBanner({required this.reason, required this.l10n});

  final CalibrationInvalidationReason reason;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final message = _messageFor(reason, l10n);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Container(
      key: Key('guitar-calibration-entry-staleness-${reason.name}'),
      padding: const EdgeInsets.all(SsSpacing.space3),
      decoration: BoxDecoration(
        // MINOR-2 (E15-R11 review): the icon paints at full-opacity danger
        // on top of this blended background — at 0.12 alpha the light-theme
        // blend measures 2.85:1, below the 3.0 non-text threshold
        // (tool/ui_contrast_check.dart). 0.05 keeps the tint visible while
        // measuring 3.09:1 light / 4.89:1 dark.
        color: colors.danger.withValues(alpha: 0.05),
        border: Border.all(color: colors.danger),
        borderRadius: BorderRadius.circular(SsRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: colors.danger),
          const SizedBox(width: SsSpacing.space2),
          Expanded(
            child: Text(
              message,
              style: typography.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  static String _messageFor(
    CalibrationInvalidationReason reason,
    AppLocalizations l10n,
  ) => switch (reason) {
    CalibrationInvalidationReason.cameraDeviceChanged =>
      l10n.guitarCalibrationEntryCamera,
    CalibrationInvalidationReason.orientationChanged =>
      l10n.guitarCalibrationEntryOrientation,
    CalibrationInvalidationReason.zoomChangedBeyondTolerance =>
      l10n.guitarCalibrationEntryZoom,
    CalibrationInvalidationReason.timestampExpired =>
      l10n.guitarCalibrationEntryTimestamp,
    CalibrationInvalidationReason.degenerateGeometry =>
      l10n.guitarCalibrationEntryGeometry,
  };
}
