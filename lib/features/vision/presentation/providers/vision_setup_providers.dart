import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/vision_setup_controller.dart';

/// The route-owned setup state. Tests override its core dependencies instead
/// of the controller, preserving the production ownership boundary.
final visionSetupControllerProvider =
    NotifierProvider<VisionSetupController, VisionSetupState>(
      VisionSetupController.new,
    );
