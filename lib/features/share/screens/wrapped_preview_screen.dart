import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../model/weekly_recap.dart';
import '../share_content.dart';
import '../share_service.dart';
import '../widgets/wrapped_card.dart';

/// Preview + share of the weekly "Strum Wrapped" recap card (chunk 017 rec #5
/// — the Wrapped-style recap is the category's strongest install hook).
/// Mirrors the lesson-score preview: native-size capture via RepaintBoundary
/// inside a FittedBox.
class WrappedPreviewScreen extends StatefulWidget {
  const WrappedPreviewScreen({
    super.key,
    required this.recap,
    required this.weekLabel,
    required this.today,
    this.shareService = const ShareService(),
  });

  final WeeklyRecap recap;
  final String weekLabel;
  final int today;
  final ShareService shareService;

  @override
  State<WrappedPreviewScreen> createState() => _WrappedPreviewScreenState();
}

class _WrappedPreviewScreenState extends State<WrappedPreviewScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _share(BuildContext buttonContext) async {
    if (_busy) return;
    setState(() => _busy = true);
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      await widget.shareService.shareImage(
        boundaryKey: _cardKey,
        caption: ShareContent.wrappedCaption(
          minutes: widget.recap.minutes,
          daysPracticed: widget.recap.daysPracticed,
          strokes: widget.recap.strokes,
          streak: widget.recap.streak,
          averageAccuracy: widget.recap.averageAccuracy,
        ),
        fileName: ShareContent.wrappedFileName(widget.today),
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.wrappedTitle)),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: WrappedCard(
                      recap: widget.recap,
                      weekLabel: widget.weekLabel,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: _busy ? null : () => _share(buttonContext),
                  icon: const Icon(Icons.ios_share),
                  label: Text(l10n.shareCardButton),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
