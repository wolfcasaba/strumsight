import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/public.dart';
import '../../progress/public.dart';
import '../../streak/public.dart';

/// The Profile Hub (UI-07, SDD Ch13 §UI-07) — personal progress, account,
/// community and settings in one place. Fully meaningful **without** an
/// account (A3, §5.3): a login wall here would break the offline-first
/// promise, so the account section only renders at all when
/// [accountEnabledProvider] is on, exactly like the legacy Settings screen.
///
/// Styled with plain Material widgets (matching `SettingsScreen`), not the
/// `core/design_system` component library — see `today_hub_screen.dart`'s
/// doc comment for why those widgets aren't safe under the app's current
/// root theme.
class ProfileHubScreen extends ConsumerWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final streak = ref.watch(streakProvider);
    final stats = PracticeStats(ref.watch(practiceLogProvider));
    final communityEnabled = ref
        .watch(appConfigProvider)
        .flags
        .communityEnabled;
    final accountEnabled = ref.watch(accountEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileHubTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _SectionLabel(l10n.profileHubProgressSectionTitle),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: l10n.progressStreak,
                    value: '${streak.current}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    label: l10n.progressSessions,
                    value: '${stats.totalSessions}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.gamificationHub),
              child: Text(l10n.profileHubAchievementsSectionTitle),
            ),
            const SizedBox(height: 24),
            if (accountEnabled)
              _AccountSection(l10n: l10n)
            else ...[
              _SectionLabel(l10n.profileHubLocalOnlyTitle),
              const SizedBox(height: 8),
              Text(
                l10n.profileHubLocalOnlyMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            _SectionLabel(l10n.profileHubCommunitySectionTitle),
            const SizedBox(height: 8),
            Text(
              communityEnabled
                  ? l10n.profileHubCommunityEnabledMessage
                  : l10n.profileHubCommunityDisabledReason,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            // A közösség BELÉPÉSI PONTJA (2026-09-05). A 13 community
            // képernyő route-jai léteztek, de a szállított felületről SEMMI
            // nem vezetett hozzájuk — a felhasználó számára ez ugyanaz,
            // mintha nem lennének. A gomb a kapu-képernyőre visz, ami a
            // feature saját belépési szűrője.
            if (communityEnabled) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('profile-hub-community-entry'),
                onPressed: () => context.go(AppRoutes.community),
                child: Text(l10n.profileHubCommunityOpen),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.profileLibrary),
              child: Text(l10n.navLibrary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.profileSettings),
              child: Text(l10n.settingsTitle),
            ),
          ],
        ),
      ),
    );
  }
}

/// The account block — only reachable when [accountEnabledProvider] is on.
/// Signed-out is a *choice* here (Sign in CTA), never a wall: every other
/// section on this screen renders regardless of this block's state.
class _AccountSection extends ConsumerWidget {
  const _AccountSection({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    if (authState.isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(l10n.profileHubAccountSectionTitle),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      );
    }

    final signedIn = authState.value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.profileHubAccountSectionTitle),
        const SizedBox(height: 8),
        Text(
          signedIn
              ? l10n.profileHubSignedInMessage
              : l10n.profileHubLocalOnlyMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        signedIn
            ? OutlinedButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).logout(),
                child: Text(l10n.profileHubSignOutCta),
              )
            : OutlinedButton(
                onPressed: () => context.go(AppRoutes.login),
                child: Text(l10n.profileHubSignInCta),
              ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
