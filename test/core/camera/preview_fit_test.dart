import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/camera/preview_fit.dart';

void main() {
  const viewport = PreviewRect(left: 10, top: 20, width: 200, height: 200);

  test('aspect fit has a letterbox offset for non-matching aspect ratios', () {
    final fit = PreviewFit(
      imageSize: const UprightSize(width: 400, height: 200),
      viewport: viewport,
      mode: PreviewFitMode.fit,
    );

    expect(fit.contentRect.left, 10);
    expect(fit.contentRect.top, 70);
    expect(fit.contentRect.width, 200);
    expect(fit.contentRect.height, 100);
    expect(fit.cropRect, const NormalizedRect.full());
  });

  test('aspect fill has a measured crop for non-matching aspect ratios', () {
    final fill = PreviewFit(
      imageSize: const UprightSize(width: 400, height: 200),
      viewport: viewport,
      mode: PreviewFitMode.fill,
    );

    expect(fill.contentRect.left, -90);
    expect(fill.contentRect.top, 20);
    expect(fill.contentRect.width, 400);
    expect(fill.contentRect.height, 200);
    expect(fill.cropRect.left, closeTo(0.25, 1e-12));
    expect(fill.cropRect.right, closeTo(0.75, 1e-12));
  });

  test('matching aspect ratio has no offset or crop in either mode', () {
    for (final mode in PreviewFitMode.values) {
      final layout = PreviewFit(
        imageSize: const UprightSize(width: 300, height: 300),
        viewport: viewport,
        mode: mode,
      );

      expect(layout.contentRect, viewport);
      expect(layout.cropRect, const NormalizedRect.full());
    }
  });

  test('preview mirror happens after normalization in preview space', () {
    final layout = PreviewFit(
      imageSize: const UprightSize(width: 100, height: 100),
      viewport: const PreviewRect(left: 10, top: 20, width: 200, height: 200),
      mode: PreviewFitMode.fit,
    );

    const normalized = NormalizedPoint(0.25, 0.75);
    final plain = layout.toPreview().apply(normalized);
    final mirrored = layout.toPreview(mirrorPreview: true).apply(normalized);

    expect(plain, const PreviewPoint(60, 170));
    expect(mirrored, const PreviewPoint(160, 170));
  });

  test('front preview mirroring cannot alter the model input space', () {
    final layout = PreviewFit(
      imageSize: const UprightSize(width: 100, height: 100),
      viewport: const PreviewRect(left: 0, top: 0, width: 200, height: 200),
      mode: PreviewFitMode.fit,
    );

    const normalized = NormalizedPoint(0.25, 0.75);

    expect(layout.toModelInput().apply(normalized), normalized);
    expect(
      layout.toPreview(mirrorPreview: true).apply(normalized),
      const PreviewPoint(150, 150),
    );
  });

  test('preview point inverse stays within the normalized source range', () {
    final layout = PreviewFit(
      imageSize: const UprightSize(width: 400, height: 200),
      viewport: viewport,
      mode: PreviewFitMode.fill,
    );

    final normalized = layout.toNormalized().apply(const PreviewPoint(10, 20));

    expect(normalized.x, inInclusiveRange(0, 1));
    expect(normalized.y, inInclusiveRange(0, 1));
  });
}
