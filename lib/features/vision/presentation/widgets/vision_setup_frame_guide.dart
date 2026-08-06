import 'package:flutter/material.dart';

import '../../domain/vision_setup_profile.dart';

/// A deliberately simple, profile-specific framing illustration. It contains
/// no camera preview and therefore cannot retain or expose image data.
class VisionSetupFrameGuide extends StatelessWidget {
  const VisionSetupFrameGuide({super.key, required this.profile});

  final VisionSetupProfile profile;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AspectRatio(
      key: Key('vision-setup-guide-${profile.name}'),
      aspectRatio: 4 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: CustomPaint(painter: _FrameGuidePainter(profile, color)),
      ),
    );
  }
}

final class _FrameGuidePainter extends CustomPainter {
  const _FrameGuidePainter(this.profile, this.color);

  final VisionSetupProfile profile;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final width = size.width;
    final height = size.height;
    final target = switch (profile) {
      VisionSetupProfile.leftHandFocus => Rect.fromLTWH(
        width * .06,
        height * .22,
        width * .48,
        height * .56,
      ),
      VisionSetupProfile.rightHandFocus => Rect.fromLTWH(
        width * .46,
        height * .22,
        width * .48,
        height * .56,
      ),
      VisionSetupProfile.fullUpperBody => Rect.fromLTWH(
        width * .24,
        height * .08,
        width * .52,
        height * .84,
      ),
      VisionSetupProfile.practiceBalanced => Rect.fromLTWH(
        width * .12,
        height * .14,
        width * .76,
        height * .72,
      ),
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(target, const Radius.circular(12)),
      paint,
    );
    canvas.drawLine(
      Offset(target.left, target.center.dy),
      Offset(target.right, target.center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FrameGuidePainter oldDelegate) =>
      oldDelegate.profile != profile || oldDelegate.color != color;
}
