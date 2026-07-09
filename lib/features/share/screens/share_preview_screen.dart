import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../analyze/model/analyze_result.dart';
import '../share_service.dart';
import '../widgets/strum_card.dart';
import 'strum_reel_screen.dart';

/// Previews the shareable Strum Card and hands it to the OS share sheet — the
/// share → install loop entry point (docs/rag/chunks/013). The card is wrapped
/// in a [RepaintBoundary] at its native 9:16 size (scaled only for display via
/// [FittedBox]) so the captured PNG is always full resolution.
class SharePreviewScreen extends StatefulWidget {
  const SharePreviewScreen({
    super.key,
    required this.result,
    this.capo = 0,
    this.title,
    this.shareService = const ShareService(),
  });

  final AnalyzeResult result;
  final int capo;
  final String? title;
  final ShareService shareService;

  @override
  State<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends State<SharePreviewScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  Rect? _originFrom(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _shareImage(BuildContext buttonContext) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.shareService.shareCard(
        boundaryKey: _cardKey,
        result: widget.result,
        capo: widget.capo,
        sharePositionOrigin: _originFrom(buttonContext),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareText(BuildContext buttonContext) async {
    await widget.shareService.shareText(
      widget.result,
      capo: widget.capo,
      sharePositionOrigin: _originFrom(buttonContext),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: StrumCard(
                        result: widget.result,
                        capo: widget.capo,
                        title: widget.title,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                children: [
                  Builder(
                    builder: (btnCtx) => FilledButton.icon(
                      onPressed: _busy ? null : () => _shareImage(btnCtx),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.ios_share, size: 20),
                      label: Text(l10n.shareCardButton),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.movie_creation_outlined, size: 18),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StrumReelScreen(
                                result: widget.result, capo: widget.capo),
                          ),
                        ),
                        label: Text(l10n.reelButton),
                      ),
                      TextButton(
                        onPressed: () => _shareText(context),
                        child: Text(l10n.shareTextButton),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
