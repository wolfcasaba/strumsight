import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/app/config/app_config.dart';

import '../../domain/analysis_document.dart';
import '../../domain/analysis_capability.dart';
import '../../domain/analysis_metric.dart';

/// Versioned, structurally distinct skill evidence; it is not a PracticeEntry.
final class AnalysisSkillEvidence {
  const AnalysisSkillEvidence({
    required this.documentId,
    required this.sourceVersion,
    required this.skill,
    required this.confidence,
  });

  final String documentId;
  final String sourceVersion;
  final String skill;
  final double confidence;
}

/// Emits one stable skill-evidence record for each Analysis document identity.
final class ProgressEvidenceAdapter {
  final Set<String> _creditedDocumentIds = <String>{};

  AnalysisSkillEvidence? credit(AnalysisDocument document) {
    if (!_creditedDocumentIds.add(document.id)) return null;
    final timing = document.metrics.firstWhere(
      (metric) => metric.id.startsWith('timing.'),
      orElse: () => _fallbackMetric(document),
    );
    return AnalysisSkillEvidence(
      documentId: document.id,
      sourceVersion: 'analysis-document.v${document.schemaVersion}',
      skill: timing.id.startsWith('timing.') ? 'timing' : 'general',
      confidence: timing.confidence,
    );
  }
}

AnalysisMetricResult _fallbackMetric(AnalysisDocument document) {
  if (document.metrics.isEmpty) {
    return AnalysisMetricResult(
      id: 'timing.mean_absolute_error.v1',
      version: 1,
      status: CapabilityStatus.unavailable,
      confidence: 0,
      unit: 'none',
      sampleCount: 0,
      evidence: const <String>[],
      unavailableReason: CapabilityUnavailableReason.insufficientEvents,
    );
  }
  return document.metrics.first;
}

abstract interface class ProgressEvidenceAdapterFactory {
  ProgressEvidenceAdapter create();
}

final class _DefaultProgressEvidenceAdapterFactory
    implements ProgressEvidenceAdapterFactory {
  const _DefaultProgressEvidenceAdapterFactory();

  @override
  ProgressEvidenceAdapter create() => ProgressEvidenceAdapter();
}

final progressEvidenceAdapterFactoryProvider =
    Provider<ProgressEvidenceAdapterFactory>(
      (_) => const _DefaultProgressEvidenceAdapterFactory(),
    );

/// Progress evidence is dormant with the Practice integration flag OFF.
final progressEvidenceAdapterProvider =
    Provider.autoDispose<ProgressEvidenceAdapter?>((ref) {
      if (!ref
          .watch(appConfigProvider)
          .flags
          .analysisPracticeIntegrationEnabled) {
        return null;
      }
      return ref.watch(progressEvidenceAdapterFactoryProvider).create();
    });
