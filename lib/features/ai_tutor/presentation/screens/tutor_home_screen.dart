/// Tutor Home screen (E04-R18 §3, design-system migration E13-R29 + E15-R09,
/// javító kör #1 §0.0.B/R10).
///
/// The entry surface for the AI Tutor feature. Leads with the AI-mode
/// status card (ADR 0278 §1: local/cloud/fallback is always visible,
/// never tucked behind a detail view — E13-R29 §5.2) followed by the
/// localized hero + a "Start conversation" CTA that pushes the Chat
/// route.
///
/// The card states `local` unconditionally rather than reading
/// [tutorChatControllerProvider] (contrast [TutorChatScreen], which reads
/// it): `test/app/navigation/adaptive_scaffold_test.dart` — a pinned test
/// outside this round's scope (§0.0/B9) — renders this screen as one of
/// several shell destinations WITHOUT overriding the tutor providers, so a
/// Riverpod read here throws (`tutorOrchestratorProvider` has no default,
/// by design — measured: E13-R29 dev run). `local` is also the honest
/// answer today regardless: production wires only
/// `LocalTutorModelGatewayStub` (see `tutor_providers.dart`), so there is
/// no live signal to show before a conversation exists anyway — the
/// per-turn local/cloud/fallback/offline nuance lives on the Chat screen,
/// which already has a real turn to describe.
///
/// The status card now uses the theme-extension `Ss*` components
/// ([SsModelStatusCard], [SsProvenanceBadge] via it, [SsButton] for the
/// CTA): this screen's own pinned widget test
/// (`tutor_home_screen_test.dart`) wires a `theme: SsLightTheme.data()`
/// root (§0.0.B/R10), matching every other harness in this round, so
/// `Theme.of(context).extension<SsColorScheme>()` resolves there. NOTE
/// (§0.0.B/R11 — corrects a mismeasurement from the first migration pass):
/// [SsCard]/[SsSurface] are NOT extension-free — both resolve
/// `Theme.of(context).extension<SsColorScheme>()!`/`<SsThemeBehavior>()!`
/// via `SsElevation.resolve` (measured: `ss_card.dart` → `ss_surface.dart`
/// → `ss_elevation.dart`). Only [SsSection] reads no extension. Icons stay
/// plain [Icon]s for the same reason `SsIcon` resolves unmapped names
/// (`smartphone_outlined` is not in its catalog) to the visible "missing
/// glyph" fallback mark, not a silent no-op — that would be a real
/// regression, not a safe substitution.
///
/// Registered in [app_router.dart] behind the `aiTutorEnabled` flag.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/components/actions/ss_button.dart';
import '../../../../core/design_system/components/ai/ss_model_status_card.dart';
import '../../../../core/design_system/components/ai/ss_provenance_badge.dart';
import '../../../../core/design_system/foundations/ss_spacing.dart';
import '../../../../l10n/app_localizations.dart';

class TutorHomeScreen extends StatelessWidget {
  const TutorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTutorHomeTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SsSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SsModelStatusCard(
                key: const Key('tutorHomeModelStatus'),
                l10n: l10n,
                title: l10n.aiTutorHomeModelStatusTitle,
                message: l10n.aiTutorAiModeLocalMessage,
                provenance: SsProvenanceKind.local,
              ),
              const SizedBox(height: SsSpacing.space6),
              Text(
                l10n.aiTutorHomeIntro,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: SsSpacing.space6),
              SsButton(
                key: const Key('tutorHomeStartCta'),
                icon: Icons.chat,
                label: l10n.aiTutorHomeStart,
                onPressed: () => context.go(AppRoutes.tutorChat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
