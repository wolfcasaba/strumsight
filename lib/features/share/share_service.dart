import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../analyze/public.dart';
import 'share_content.dart';

/// Captures the on-screen Strum Card (a [RepaintBoundary]) to a PNG and hands
/// it to the OS share sheet with the viral caption. Keeps all IO/platform work
/// out of the widgets so the card + caption stay pure and testable.
class ShareService {
  const ShareService();

  /// Render the boundary behind [boundaryKey] to PNG bytes. Returns null if the
  /// boundary isn't laid out yet (caller should ensure a frame has painted).
  Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    final obj = boundaryKey.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    final ui.Image image = await obj.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Capture the card and open the share sheet with the image + caption.
  /// [sharePositionOrigin] anchors the sheet on iPad (ignored elsewhere).
  /// [title]/[includeTitle] mirror [ShareContent.caption] — off by default
  /// (A7).
  Future<void> shareCard({
    required GlobalKey boundaryKey,
    required AnalyzeResult result,
    int capo = 0,
    String? title,
    bool includeTitle = false,
    Rect? sharePositionOrigin,
  }) {
    final caption = ShareContent.caption(
      result,
      capo: capo,
      title: title,
      includeTitle: includeTitle,
    );
    return shareImage(
      boundaryKey: boundaryKey,
      caption: caption,
      fileName: ShareContent.fileName(result),
      fallbackText: caption,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Generic: capture any [RepaintBoundary] to PNG and share it with [caption].
  /// Falls back to a text-only share (of [fallbackText] ?? [caption]) if the
  /// boundary can't be captured, rather than failing silently.
  Future<void> shareImage({
    required GlobalKey boundaryKey,
    required String caption,
    required String fileName,
    String? fallbackText,
    Rect? sharePositionOrigin,
  }) async {
    final png = await capturePng(boundaryKey);
    if (png == null) {
      await SharePlus.instance.share(
        ShareParams(
          text: fallbackText ?? caption,
          subject: 'StrumSight',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return;
    }
    final file = await _writeTemp(png, fileName);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: caption,
        subject: 'StrumSight',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Share just the caption text (no image) — the always-available path.
  Future<void> shareText(
    AnalyzeResult result, {
    int capo = 0,
    String? title,
    bool includeTitle = false,
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: ShareContent.caption(
          result,
          capo: capo,
          title: title,
          includeTitle: includeTitle,
        ),
        subject: 'My StrumSight practice',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<File> _writeTemp(Uint8List bytes, String name) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Share an arbitrary caller-produced [file] with [caption] (ADR 0247
  /// §Döntés 2, E06-R27 brief §5.8 — the export/share H3 self-heal
  /// contract). The caller (e.g. `ExportAnalysisUseCase`) owns building the
  /// file's contents; this method owns its post-share lifecycle: [file] is
  /// deleted whether the share succeeds or throws, so a hard failure never
  /// strands a redacted export on disk. This is the ONLY way a non-image,
  /// non-text payload leaves the app through [ShareService] — the existing
  /// [shareCard] / [shareImage] / [shareText] are unchanged by this method.
  Future<void> shareExportFile({
    required File file,
    required String caption,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          text: caption,
          subject: subject ?? 'StrumSight',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
