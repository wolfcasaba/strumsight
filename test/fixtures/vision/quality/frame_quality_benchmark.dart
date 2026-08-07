import 'dart:io';
import 'dart:typed_data';

import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/vision/domain/quality/frame_quality_assessor.dart';
import 'package:strumsight/features/vision/domain/quality/quality_thresholds.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';

void main() {
  const width = 640;
  const height = 480;
  const iterations = 100;
  final pixels = Uint8List.fromList(
    List<int>.generate(
      width * height,
      (index) => ((index ~/ width) + (index % width)).isEven ? 80 : 180,
    ),
  );
  final assessor = FrameQualityAssessor(
    thresholds: const QualityThresholds.defaultV1(),
  );
  final frame = GrayscaleFrame(width: width, height: height, luminance: pixels);

  for (var index = 0; index < 20; index += 1) {
    assessor.assess(
      frame,
      profile: VisionSetupProfile.practiceBalanced,
      roi: const NormalizedRect.full(),
    );
  }

  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index += 1) {
    assessor.assess(
      frame,
      profile: VisionSetupProfile.practiceBalanced,
      roi: const NormalizedRect.full(),
    );
  }
  stopwatch.stop();
  final averageMicroseconds = stopwatch.elapsedMicroseconds / iterations;
  stderr.writeln(
    'frame_quality_640x480_average_us='
    '${averageMicroseconds.toStringAsFixed(2)} '
    'iterations=$iterations downsample_factor=4',
  );
}
