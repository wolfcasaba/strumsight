/// Tutor Home screen (E04-R18 §3, design-system migration E13-R29 + E15-R09).
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
/// The status card uses [SsCard] (an extension-free surface primitive) and
/// [SsSpacing] tokens, but NOT the theme-extension `Ss*` components
/// (`SsModelStatusCard`, `SsProvenanceBadge`, ...): this screen's own
/// pinned widget test (`tutor_home_screen_test.dart`, outside this
/// round's `allowed_paths` — E15-R09 §0.0.A/R3 only wires the 6 named
/// tests) builds a bare `MaterialApp` without a themed root, so
/// `Theme.of(context).extension<SsColorScheme>()` is null there and every
/// extension-consuming `Ss*` component crashes on the `!` it uses
/// internally (measured: E13-R29 dev run, reconfirmed E15-R09 — `SsCard`/
/// `SsSurface`/`SsSection` read no extension, `SsModelStatusCard`/
/// `SsProvenanceBadge`/`SsButton`/`SsEmptyState`/`SsFailureState` all do).
/// The design system's l10n copy
/// ([AppLocalizations.dsProvenanceBadgeLocalLabel]) is still reused for
/// wording consistency. Icons stay plain [Icon]s for the same reason
/// `SsIcon` resolves unmapped names (`smartphone_outlined` is not in its
/// catalog) to the visible "missing glyph" fallback mark, not a silent
/// no-op — that would be a real regression, not a safe substitution.
///
/// Registered in [app_router.dart] behind the `aiTutorEnabled` flag.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/components/surfaces/ss_card.dart';
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
              const _ModelStatusCard(),
              const SizedBox(height: SsSpacing.space6),
              Text(
                l10n.aiTutorHomeIntro,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: SsSpacing.space6),
              FilledButton.icon(
                key: const Key('tutorHomeStartCta'),
                icon: const Icon(Icons.chat),
                label: Text(l10n.aiTutorHomeStart),
                onPressed: () => context.go(AppRoutes.tutorChat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The AI-mode status card (ADR 0278 §1) — always renders, so a student
/// never has to find it behind a tap. Meaning is carried by icon AND text
/// together (§5.2), never colour alone, same rule the design system's own
/// provenance badge documents — this is an [SsCard] rebuild of that rule
/// (see the file doc comment for why neither the theme-extension `Ss*`
/// widgets nor a provider read can be used here).
class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SsCard(
      key: const Key('tutorHomeModelStatus'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.aiTutorHomeModelStatusTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            l10n.aiTutorAiModeLocalMessage,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SsSpacing.space2),
          _ModeChip(
            icon: Icons.smartphone_outlined,
            label: l10n.dsProvenanceBadgeLocalLabel,
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: SsSpacing.space1),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );
}
