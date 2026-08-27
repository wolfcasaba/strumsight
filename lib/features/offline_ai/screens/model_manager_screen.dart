import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../model/offline_model.dart';
import '../providers/offline_model_controller.dart';
import '../theme/offline_ai_theme_scope.dart';

/// The offline AI model manager (§3, §5.1 ADR 0292): download / verify /
/// activate / rollback / storage states for the on-device detection model.
/// Below the integrity threshold there is NO activation path at all — not
/// even behind a warning (A6); this is the screen the round's mandatory
/// real-violation probe (§10) is run against.
class ModelManagerScreen extends ConsumerWidget {
  const ModelManagerScreen({super.key, this.modelId = 'strumsight-detector'});

  final String modelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(offlineModelControllerProvider);
    final controller = ref.read(offlineModelControllerProvider.notifier);

    return OfflineAiThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.modelManagerTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              SsModelStatusCard(
                l10n: l10n,
                title: l10n.modelManagerSourceLabel(modelId),
                provenance: SsProvenanceKind.local,
                message: _messageFor(l10n, state),
              ),
              const SizedBox(height: 20),
              _ActionArea(
                key: const Key('modelManagerActionArea'),
                state: state,
                onCheck: () => controller.checkAndActivate(modelId),
                onRollback: controller.rollback,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _messageFor(AppLocalizations l10n, OfflineModelUiState state) {
    return switch (state.phase) {
      OfflineModelPhase.notChecked => l10n.modelManagerStatusNotChecked,
      OfflineModelPhase.checking => l10n.modelManagerStatusChecking,
      OfflineModelPhase.blockedIntegrity => l10n.modelManagerStatusBlocked,
      OfflineModelPhase.active =>
        '${l10n.modelManagerStatusActive} · '
            '${l10n.modelManagerVersionLabel(state.active?.version ?? '')}',
      OfflineModelPhase.activeWithRollback =>
        '${l10n.modelManagerStatusActiveWithPrevious} · '
            '${l10n.modelManagerVersionLabel(state.active?.version ?? '')}',
    };
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({
    super.key,
    required this.state,
    required this.onCheck,
    required this.onRollback,
  });

  final OfflineModelUiState state;
  final VoidCallback onCheck;
  final VoidCallback onRollback;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (state.phase == OfflineModelPhase.blockedIntegrity) {
      // The "below threshold" cell (A6): no activation control is rendered
      // here at all — not disabled, ABSENT — so there is no path, warned-
      // through or otherwise, to activate an asset that failed verification.
      final colors = Theme.of(context).extension<SsColorScheme>()!;
      final typography = Theme.of(context).extension<SsTypography>()!;
      return Column(
        key: const Key('modelManagerBlockedIntegrity'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: [
              Icon(Icons.gpp_bad_outlined, color: colors.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.modelManagerStatusBlocked,
                  style: typography.titleMedium.copyWith(color: colors.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.modelManagerIntegrityBlockedMessage,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        SsButton(
          key: const Key('modelManagerCheck'),
          label: l10n.modelManagerCheckAction,
          loading: state.phase == OfflineModelPhase.checking,
          onPressed: state.phase == OfflineModelPhase.checking ? null : onCheck,
        ),
        if (state.phase == OfflineModelPhase.activeWithRollback)
          SsButton(
            key: const Key('modelManagerRollback'),
            variant: SsButtonVariant.secondary,
            label: l10n.modelManagerRollbackAction,
            onPressed: onRollback,
          ),
      ],
    );
  }
}
