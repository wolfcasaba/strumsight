import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../analyze/model/analyze_result.dart';
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
  Future<void> shareCard({
    required GlobalKey boundaryKey,
    required AnalyzeResult result,
    int capo = 0,
    Rect? sharePositionOrigin,
  }) async {
    final png = await capturePng(boundaryKey);
    final caption = ShareContent.caption(result, capo: capo);
    if (png == null) {
      // Fall back to a text-only share rather than failing silently.
      await shareText(result, capo: capo, sharePositionOrigin: sharePositionOrigin);
      return;
    }
    final file = await _writeTemp(png, ShareContent.fileName(result));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: caption,
      subject: 'My StrumSight practice',
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  /// Share just the caption text (no image) — the always-available path.
  Future<void> shareText(
    AnalyzeResult result, {
    int capo = 0,
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(ShareParams(
      text: ShareContent.caption(result, capo: capo),
      subject: 'My StrumSight practice',
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  Future<File> _writeTemp(Uint8List bytes, String name) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
