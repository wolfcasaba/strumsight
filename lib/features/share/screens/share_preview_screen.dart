import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../analyze/public.dart';
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

  // A7 (§5.5, ADR 0292): the card is minimal by default — the title only
  // leaves the device once the user explicitly turns this on. Never
  // pre-checked from `widget.title` being non-null.
  bool _includeTitle = false;

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
        title: widget.title,
        includeTitle: _includeTitle,
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
      title: widget.title,
      includeTitle: _includeTitle,
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
                        showTitle: _includeTitle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: _RedactionSummary(
                includeTitle: _includeTitle,
                hasTitle: (widget.title ?? '').trim().isNotEmpty,
                onIncludeTitleChanged: (v) => setState(() => _includeTitle = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  Builder(
                    builder: (btnCtx) => SsButton(
                      label: l10n.shareCardButton,
                      icon: Icons.ios_share,
                      loading: _busy,
                      onPressed: _busy ? null : () => _shareImage(btnCtx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SsButton(
                        variant: SsButtonVariant.tertiary,
                        icon: Icons.movie_creation_outlined,
                        label: l10n.reelButton,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StrumReelScreen(
                              result: widget.result,
                              capo: widget.capo,
                            ),
                          ),
                        ),
                      ),
                      SsButton(
                        variant: SsButtonVariant.tertiary,
                        label: l10n.shareTextButton,
                        onPressed: () => _shareText(context),
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

/// The itemized "what leaves the device" list (A7): the three core fields are
/// always shared (no toggle — the card is useless without them) and are
/// listed, not just implied; the session title is the one expandable field,
/// off by default. Disabled+hidden entirely when there is no title to offer,
/// so the row never dangles asking to include something that doesn't exist.
class _RedactionSummary extends StatelessWidget {
  const _RedactionSummary({
    required this.includeTitle,
    required this.hasTitle,
    required this.onIncludeTitleChanged,
  });

  final bool includeTitle;
  final bool hasTitle;
  final ValueChanged<bool> onIncludeTitleChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return SsSection(
      title: l10n.shareRedactionTitle,
      child: SsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(colors, l10n.shareRedactionChords),
            _item(colors, l10n.shareRedactionStrumPattern),
            _item(colors, l10n.shareRedactionTempo),
            if (hasTitle) ...[
              const SizedBox(height: 4),
              SsSwitchRow(
                key: const Key('shareIncludeTitleToggle'),
                label: l10n.shareRedactionIncludeTitle,
                subtitle: l10n.shareRedactionIncludeTitleHint,
                value: includeTitle,
                onChanged: onIncludeTitleChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(SsColorScheme colors, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(Icons.check_circle_outline, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}
