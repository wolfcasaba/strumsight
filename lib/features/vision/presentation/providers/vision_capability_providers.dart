import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this device can run the Vision camera pipeline at all.
///
/// `application/vision_setup_controller.dart` has no capability signal today
/// (measured, §0.0/B4): its only producer of the audio-only step is the
/// user-initiated `skip()`. This presentation-level, test-overridable
/// provider lets the setup screen offer the audio-only alternative to an
/// unsupported device without waiting for the user to find the skip action
/// themselves (A6).
enum VisionDeviceCapability { supported, unsupported }

final visionDeviceCapabilityProvider = Provider<VisionDeviceCapability>(
  (ref) => VisionDeviceCapability.supported,
);
