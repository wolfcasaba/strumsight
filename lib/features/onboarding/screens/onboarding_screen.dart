import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../onboarding_provider.dart';

/// First-run onboarding: three glanceable pages that teach the moat (↓/↑),
/// tease the streak, and prime the mic permission before dropping into Live.
/// Minimal by design (Simply Guitar's lesson: a few taps, then play). Growth =
/// activation — convert every viral install into an active user (chunk 013).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.onDone});

  /// Where to go when finished; defaults to the Live tab (overridable in tests).
  final VoidCallback? onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _finish({bool requestMic = false}) async {
    if (_finishing) return;
    _finishing = true;
    if (requestMic) {
      try {
        await Permission.microphone.request();
      } catch (_) {
        // Best-effort priming; the Live screen re-requests if still ungranted.
      }
    }
    await ref.read(onboardingSeenProvider.notifier).complete();
    if (!mounted) return;
    (widget.onDone ?? () => context.go('/live'))();
  }

  void _next(int lastIndex) {
    if (_page >= lastIndex) {
      _finish(requestMic: true);
    } else {
      _pager.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = <_Page>[
      _Page(
        icon: Icons.music_note,
        title: l10n.onboardTitle1,
        body: l10n.onboardBody1,
      ),
      _Page(
        icon: Icons.swap_vert,
        title: l10n.onboardTitle2,
        body: l10n.onboardBody2,
        showArrows: true,
      ),
      _Page(
        icon: Icons.local_fire_department,
        title: l10n.onboardTitle3,
        body: l10n.onboardBody3,
      ),
    ];
    final last = pages.length - 1;
    final onLast = _page == last;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(l10n.onboardSkip),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => pages[i],
              ),
            ),
            _Dots(count: pages.length, active: _page),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: FilledButton(
                onPressed: () => _next(last),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: Text(onLast ? l10n.onboardStart : l10n.onboardNext),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.showArrows = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showArrows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showArrows)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_downward, size: 64, color: AppColors.primary),
                SizedBox(width: 12),
                Icon(Icons.arrow_upward,
                    size: 64, color: AppColors.confidenceHigh),
              ],
            )
          else
            Icon(icon, size: 84, color: AppColors.primary),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == active ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == active
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      );
}
