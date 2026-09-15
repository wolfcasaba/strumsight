import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/streak_provider.dart';

/// A compact "🔥 N" pill showing the current practice streak; tap → the streak
/// screen. Lives in the Live header — a persistent, glanceable habit cue.
/// The flame is an [SsFlame] (Ch18 spec §11): it ignites once when the
/// count grows — the moment today's practice is credited — and is static
/// otherwise.
class StreakBadge extends ConsumerWidget {
  const StreakBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final l10n = AppLocalizations.of(context);
    final active = streak.current > 0;
    final color = active ? AppColors.primary : context.palette.muted;
    return Semantics(
      button: true,
      label: l10n.streakTooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(AppRoutes.streak),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SsFlame(
                lit: active,
                color: AppColors.primary,
                dimColor: context.palette.muted,
                size: SsFlameSize.small,
                ignition: streak.current,
              ),
              const SizedBox(width: 3),
              Text(
                '${streak.current}',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
