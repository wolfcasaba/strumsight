import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../share/public.dart';
import '../model/lesson.dart';
import '../model/lesson_progress.dart';
import '../widgets/lesson_score_card.dart';

/// Preview + share of a completed-lesson score card (Learn → viral loop,
/// chunks 013/014). Card captured at native 9:16 via a [RepaintBoundary] inside
/// a [FittedBox].
class LessonScorePreviewScreen extends StatefulWidget {
  const LessonScorePreviewScreen({
    super.key,
    required this.lesson,
    required this.accuracy,
    required this.maxCombo,
    required this.hits,
    required this.total,
    this.shareService = const ShareService(),
  });

  final Lesson lesson;
  final double accuracy;
  final int maxCombo;
  final int hits;
  final int total;
  final ShareService shareService;

  @override
  State<LessonScorePreviewScreen> createState() =>
      _LessonScorePreviewScreenState();
}

class _LessonScorePreviewScreenState extends State<LessonScorePreviewScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _share(BuildContext buttonContext) async {
    if (_busy) return;
    setState(() => _busy = true);
    final stars = LessonProgress.stars(widget.accuracy);
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      await widget.shareService.shareImage(
        boundaryKey: _cardKey,
        caption: ShareContent.lessonCaption(
          lessonName: widget.lesson.name,
          accuracy: widget.accuracy,
          stars: stars,
          maxCombo: widget.maxCombo,
        ),
        fileName: ShareContent.lessonFileName(widget.lesson.id),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stars = LessonProgress.stars(widget.accuracy);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(SsSpacing.space5),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: LessonScoreCard(
                        lessonName: widget.lesson.name,
                        accuracy: widget.accuracy,
                        stars: stars,
                        maxCombo: widget.maxCombo,
                        hits: widget.hits,
                        total: widget.total,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SsSpacing.space5,
                SsSpacing.space1,
                SsSpacing.space5,
                SsSpacing.space4,
              ),
              child: Builder(
                builder: (btnCtx) => SizedBox(
                  height: 52,
                  child: SsButton(
                    label: l10n.shareCardButton,
                    icon: Icons.ios_share,
                    loading: _busy,
                    onPressed: () => _share(btnCtx),
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
