import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/public.dart';
import '../../progress/public.dart';
import '../../streak/public.dart';

/// The Profile Hub (UI-07, SDD Ch13 §UI-07) — personal progress, account,
/// community and settings in one place. Fully meaningful **without** an
/// account (A3, §5.3): a login wall here would break the offline-first
/// promise, so the account section only renders at all when
/// [accountEnabledProvider] is on, exactly like the legacy Settings screen.
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
            SsSection(
              title: l10n.profileHubProgressSectionTitle,
              child: Row(
                children: [
                  Expanded(
                    child: SsMetricCard(
                      label: l10n.progressStreak,
                      value: streak.current,
                      unit: '',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SsMetricCard(
                      label: l10n.progressSessions,
                      value: stats.totalSessions,
                      unit: '',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SsButton(
              label: l10n.profileHubAchievementsSectionTitle,
              variant: SsButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.gamificationHub),
            ),
            const SizedBox(height: 24),
            if (accountEnabled)
              _AccountSection(l10n: l10n)
            else
              SsSection(
                title: l10n.profileHubLocalOnlyTitle,
                child: Text(
                  l10n.profileHubLocalOnlyMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 24),
            SsSection(
              title: l10n.profileHubCommunitySectionTitle,
              child: Text(
                communityEnabled
                    ? l10n.profileHubCommunityEnabledMessage
                    : l10n.profileHubCommunityDisabledReason,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),
            SsButton(
              label: l10n.navLibrary,
              variant: SsButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.profileLibrary),
            ),
            const SizedBox(height: 12),
            SsButton(
              label: l10n.settingsTitle,
              variant: SsButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.profileSettings),
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
      return SsSection(
        title: l10n.profileHubAccountSectionTitle,
        child: const SsSkeleton(width: double.infinity, height: 48),
      );
    }

    final signedIn = authState.value != null;

    return SsSection(
      title: l10n.profileHubAccountSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            signedIn
                ? l10n.profileHubSignedInMessage
                : l10n.profileHubLocalOnlyMessage,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          signedIn
              ? SsButton(
                  label: l10n.profileHubSignOutCta,
                  variant: SsButtonVariant.secondary,
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                )
              : SsButton(
                  label: l10n.profileHubSignInCta,
                  variant: SsButtonVariant.secondary,
                  onPressed: () => context.go(AppRoutes.login),
                ),
        ],
      ),
    );
  }
}
