/// Tutor Home screen (E04-R18 §3, design-system migration E13-R29).
///
/// The entry surface for the AI Tutor feature. Leads with the AI-mode
/// status card (ADR 0278 §1: local/cloud/fallback is always visible,
/// never tucked behind a detail view — E13-R29 §5.2) followed by the
/// localized hero + a "Start conversation" CTA that pushes the Chat
/// route. The screen owns no mutable state of its own; the AI-mode
/// signal is read from the same [tutorChatControllerProvider] the chat
/// screen uses.
///
/// The status card is built from plain [Theme]-token widgets, not the
/// `Ss*` design-system components: this screen's own pinned widget test
/// (`tutor_home_screen_test.dart`, outside this round's scope) builds a
/// bare `MaterialApp` without `AppTheme`, so `Theme.of(context).extension<
/// SsColorScheme>()` is null there and every `Ss*` component crashes on
/// the `!` it uses internally (measured: E13-R29 dev run). The design
/// system's l10n copy ([AppLocalizations.dsProvenanceBadgeLocalLabel] and
/// friends) is still reused for wording consistency.
///
/// Registered in [app_router.dart] behind the `aiTutorEnabled` flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controller/tutor_state.dart';
import '../providers/tutor_providers.dart';

class TutorHomeScreen extends ConsumerWidget {
  const TutorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(tutorChatControllerProvider);
    final chatState = ref.watch(tutorChatStateProvider).value;
    final status = chatState?.status ?? controller.status;
    final isOnline = chatState?.isOnline ?? controller.isOnline;
    final mode = tutorAiModeFor(status: status, isOnline: isOnline);
    // `failed` is the only terminal status that means "the model itself
    // could not be reached" rather than a normal fallback/offline/consent
    // path (those already have their own banners in the chat screen) — the
    // Home screen is the one surface a student sees before any turn runs,
    // so this is where "missing model" (§3) has to be stated up front.
    final modelUnavailable = status == TutorTurnStatus.failed;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTutorHomeTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ModelStatusCard(
                mode: mode,
                message: modelUnavailable
                    ? l10n.aiTutorHomeModelUnavailableMessage
                    : _modeMessage(l10n, mode),
                isOnline: isOnline,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.aiTutorHomeIntro,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
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

String _modeMessage(AppLocalizations l10n, TutorAiMode mode) => switch (mode) {
  TutorAiMode.local => l10n.aiTutorAiModeLocalMessage,
  TutorAiMode.cloud => l10n.aiTutorAiModeCloudMessage,
  TutorAiMode.fallback => l10n.aiTutorAiModeFallbackMessage,
};

/// The AI-mode status card (ADR 0278 §1) — always renders regardless of
/// [isOnline]/[mode], so the missing-model case never has to be found
/// behind a tap. Meaning is carried by icon AND text together (§5.2), never
/// colour alone, same rule the design system's own provenance badge
/// documents — this is a plain-[Theme] rebuild of that rule (see the file
/// doc comment for why the `Ss*` widget itself cannot be used here).
class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard({
    required this.mode,
    required this.message,
    required this.isOnline,
  });

  final TutorAiMode mode;
  final String message;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (icon, modeLabel) = switch (mode) {
      TutorAiMode.cloud => (
        Icons.cloud_outlined,
        l10n.dsProvenanceBadgeCloudLabel,
      ),
      TutorAiMode.local || TutorAiMode.fallback => (
        Icons.smartphone_outlined,
        l10n.dsProvenanceBadgeLocalLabel,
      ),
    };

    return Card(
      key: const Key('tutorHomeModelStatus'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.aiTutorHomeModelStatusTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                _ModeChip(icon: icon, label: modeLabel),
                if (!isOnline)
                  _ModeChip(
                    icon: Icons.wifi_off,
                    label: l10n.dsStatusBadgeOffline,
                  ),
              ],
            ),
          ],
        ),
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
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );
}
