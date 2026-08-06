import 'package:meta/meta.dart';

/// Safety categories ordered by severity (lowest index = most urgent).
///
/// Prompt-injection has the highest priority (index 0) because an injection
/// attempt is the strongest signal that the output is untrustworthy
/// regardless of other categories.
enum TutorSafetyCategory {
  promptInjection,
  inventedMetric,
  credentialRequest,
  cameraClaim,
  medicalRefusal,
  painResponse,
  unsafeAction,
  copyright,
  usageLimit,
  redactionRequired,
}

/// Input to the deterministic safety policy evaluation.
@immutable
final class TutorSafetyPolicyRequest {
  const TutorSafetyPolicyRequest({
    required this.outputText,
    required this.hasInjection,
    required this.hasInventedMetric,
    required this.hasCameraClaim,
    required this.isRateLimited,
    required this.isUsageExceeded,
  });

  /// The raw output text to evaluate for safety-sensitive patterns.
  final String outputText;

  /// Whether the output was produced in response to a prompt-injection attempt.
  final bool hasInjection;

  /// Whether the output contains a measuredFact/computedTrend claim with no
  /// trusted evidence (an "invented metric").
  final bool hasInventedMetric;

  /// Whether the output claims an unsupported camera-based capability.
  final bool hasCameraClaim;

  /// Whether the user has exceeded the rate limit.
  final bool isRateLimited;

  /// Whether the user has exceeded the daily usage limit.
  final bool isUsageExceeded;

  @override
  bool operator ==(Object other) =>
      other is TutorSafetyPolicyRequest &&
      outputText == other.outputText &&
      hasInjection == other.hasInjection &&
      hasInventedMetric == other.hasInventedMetric &&
      hasCameraClaim == other.hasCameraClaim &&
      isRateLimited == other.isRateLimited &&
      isUsageExceeded == other.isUsageExceeded;

  @override
  int get hashCode => Object.hash(
        outputText,
        hasInjection,
        hasInventedMetric,
        hasCameraClaim,
        isRateLimited,
        isUsageExceeded,
      );

  @override
  String toString() =>
      'TutorSafetyPolicyRequest(hasInjection: $hasInjection, '
      'hasInventedMetric: $hasInventedMetric, '
      'hasCameraClaim: $hasCameraClaim, '
      'isRateLimited: $isRateLimited, '
      'isUsageExceeded: $isUsageExceeded)';
}

/// The deterministic output of the safety policy.
@immutable
final class TutorSafetyPolicyResult {
  const TutorSafetyPolicyResult({
    this.blockedCategories = const <TutorSafetyCategory>{},
  });

  /// The set of safety categories that were triggered.
  final Set<TutorSafetyCategory> blockedCategories;

  /// True when no safety category was triggered — the output is allowed.
  bool get isAllowed => blockedCategories.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TutorSafetyPolicyResult &&
      blockedCategories.length == other.blockedCategories.length &&
      blockedCategories.containsAll(other.blockedCategories);

  @override
  int get hashCode => Object.hashAll(blockedCategories);

  @override
  String toString() =>
      'TutorSafetyPolicyResult(isAllowed: $isAllowed, '
      'blockedCategories: ${blockedCategories.length})';
}

/// Deterministic, pure safety policy for tutor output.
///
/// Maps input (output text + metadata flags) to a safety verdict. Returns
/// the strictest-matching verdict — all triggered categories are collected,
/// not just the first match.
///
/// Safety categories that are HARD blocks (output is rejected):
/// - [TutorSafetyCategory.painResponse]: AI-as-victim language
/// - [TutorSafetyCategory.medicalRefusal]: medical diagnosis/advice
/// - [TutorSafetyCategory.copyright]: copyrighted content
/// - [TutorSafetyCategory.credentialRequest]: password/API-key ask
/// - [TutorSafetyCategory.promptInjection]: injection flag
/// - [TutorSafetyCategory.inventedMetric]: invented metric flag
/// - [TutorSafetyCategory.cameraClaim]: unsupported camera capability
/// - [TutorSafetyCategory.unsafeAction]: dangerous instruction
/// - [TutorSafetyCategory.usageLimit]: rate/daily limit exceeded
/// - [TutorSafetyCategory.redactionRequired]: sensitive content detected
///
/// Prompt-injection NEVER raises tool permission; the policy only blocks.
@immutable
final class TutorSafetyPolicy {
  const TutorSafetyPolicy();

  // -- Text-pattern keywords for category detection --------------------------

  static final RegExp _painPattern = RegExp(
    r'\b(I\s+feel\s+pain|it\s+hurts|my\s+circuits|I\s+am\s+suffering|'
    r'that\s+hurts|you\s+hurt\s+me|I\s+am\s+in\s+pain)\b',
    caseSensitive: false,
  );

  static final RegExp _medicalPattern = RegExp(
    r'\b(diagnos\w+|medical\s+condition|symptom\w*|'
    r'carpal\s+tunnel|tendonitis|arthritis|'
    r'you\s+(have|may\s+have|suffer\s+from)\s+\w+\s+(syndrome|disease|disorder))\b',
    caseSensitive: false,
  );

  static final RegExp _copyrightPattern = RegExp(
    r'\bcopyrighted\b',
    caseSensitive: false,
  );

  static final RegExp _credentialPattern = RegExp(
    r'\b(password|api\s*key|access\s*token|'
    r'secret\s*key|private\s*key|your\s+credentials|'
    r'enter\s+your\s+password|provide\s+your\s+password)\b',
    caseSensitive: false,
  );

  static final RegExp _unsafeActionPattern = RegExp(
    r'\b(cut\s+(the\s+)?(guitar\s+)?strings?\s+with|'
    r'apply\s+(excessive\s+)?force\s+to|'
    r'break\s+the|snap\s+the\s+neck|'
    r'strike\s+(the\s+)?guitar)\b',
    caseSensitive: false,
  );

  static final RegExp _redactionPattern = RegExp(
    r'\b(api\s*[kK]ey\s*[=:]\s*[a-zA-Z0-9\-_]{8,}|'
    r'secret\s*[=:]\s*[a-zA-Z0-9\-_]{8,}|'
    r'sk-[a-zA-Z0-9]{8,}|'
    r'Bearer\s+[A-Za-z0-9\-._~+/]+=*)\b',
    caseSensitive: false,
  );

  // -- Evaluation ------------------------------------------------------------

  /// Evaluate the safety of the output text and metadata.
  ///
  /// Returns [TutorSafetyPolicyResult] with all triggered safety categories.
  /// An empty [TutorSafetyPolicyResult.blockedCategories] means the output
  /// is allowed.
  ///
  /// Evaluation is deterministic: the same input always produces the same
  /// output.
  TutorSafetyPolicyResult evaluate(TutorSafetyPolicyRequest request) {
    final blocked = <TutorSafetyCategory>{};

    // Flag-driven categories (highest priority first).
    if (request.hasInjection) {
      blocked.add(TutorSafetyCategory.promptInjection);
    }
    if (request.hasInventedMetric) {
      blocked.add(TutorSafetyCategory.inventedMetric);
    }
    if (request.hasCameraClaim) {
      blocked.add(TutorSafetyCategory.cameraClaim);
    }

    // Usage limits.
    if (request.isRateLimited || request.isUsageExceeded) {
      blocked.add(TutorSafetyCategory.usageLimit);
    }

    // Text-pattern categories.
    final text = request.outputText;
    if (_credentialPattern.hasMatch(text)) {
      blocked.add(TutorSafetyCategory.credentialRequest);
    }
    if (_medicalPattern.hasMatch(text)) {
      blocked.add(TutorSafetyCategory.medicalRefusal);
    }
    if (_painPattern.hasMatch(text)) {
      blocked.add(TutorSafetyCategory.painResponse);
    }
    if (_unsafeActionPattern.hasMatch(text)) {
      blocked.add(TutorSafetyCategory.unsafeAction);
    }
    if (_copyrightPattern.hasMatch(text)) {
      blocked.add(TutorSafetyCategory.copyright);
    }
    if (_redactionPattern.hasMatch(text)) {
      blocked.add(TutorSafetyCategory.redactionRequired);
    }

    return TutorSafetyPolicyResult(blockedCategories: blocked);
  }
}
