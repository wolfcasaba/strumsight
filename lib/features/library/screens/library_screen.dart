import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/model/chord.dart';
import '../../settings/providers/capo_provider.dart';
import '../model/analyzed_session.dart';
import '../providers/library_providers.dart';

/// The Library: saved analyses, offline. Tap to reopen, swipe to delete.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final async = ref.watch(libraryProvider);
    final capo = ref.watch(capoProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.navLibrary,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 30,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(l10n.libraryIntro,
                      style: TextStyle(color: palette.muted)),
                ),
                data: (sessions) => sessions.isEmpty
                    ? _EmptyState(text: l10n.libraryIntro)
                    : ListView.separated(
                        itemCount: sessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _SessionCard(
                          session: sessions[i],
                          capo: capo,
                          onDelete: () => ref
                              .read(libraryProvider.notifier)
                              .delete(sessions[i].id),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined, size: 56, color: palette.muted),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                height: 1.45,
                color: palette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onDelete,
    this.capo = 0,
  });

  final AnalyzedSession session;
  final VoidCallback onDelete;
  final int capo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        onDelete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.libraryDeleted)),
        );
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.primary),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/library/session', extra: session),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Chord.transposeSummary(session.title, -capo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmtDate(session.createdAt)}  ·  '
                      '${l10n.analyzeStrumsSummary(session.result.downCount, session.result.upCount)}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
