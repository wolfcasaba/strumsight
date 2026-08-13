import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/export/analysis_export_codec.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/export/analysis_export.dart';
import 'package:strumsight/features/audio_analysis/domain/export/redaction_policy.dart';
import 'package:strumsight/features/share/public.dart';

/// Builds the redacted export preview and, only after the caller confirms
/// it, shares it through the existing [ShareService] (ADR 0247).
///
/// [share] never runs before [preview] has been shown to the user — that
/// ordering is enforced by the presentation layer (`AnalysisExportScreen`),
/// which only calls [share] from an explicit confirm action. This use case
/// itself performs no network I/O: the temp export file is written to the
/// caller-supplied, app-private [tempDirectory] and handed to the existing
/// share service, which owns deleting it (success or failure alike).
final class ExportAnalysisUseCase {
  ExportAnalysisUseCase({
    required this.shareService,
    required this.tempDirectory,
    RedactionPolicy? redactionPolicy,
    AnalysisExportCodec? codec,
    String Function()? fileNameGenerator,
  }) : redactionPolicy = redactionPolicy ?? const RedactionPolicy(),
       codec = codec ?? const AnalysisExportCodec(),
       fileNameGenerator = fileNameGenerator ?? _defaultFileNameGenerator;

  final ShareService shareService;
  final Directory tempDirectory;
  final RedactionPolicy redactionPolicy;
  final AnalysisExportCodec codec;
  final String Function() fileNameGenerator;

  /// The redacted, allowlist-only view the preview screen renders. Pure —
  /// no I/O, so it is safe to call on every rebuild.
  AnalysisExport preview(AnalysisDocument document) =>
      redactionPolicy.apply(document);

  /// Writes the redacted export to a random-named temp file and shares it
  /// with [caption] through the existing [ShareService]. Must only be
  /// invoked after the user has confirmed the [preview].
  Future<AppResult<void>> share({
    required AnalysisDocument document,
    required String caption,
  }) async {
    final export = redactionPolicy.apply(document);
    final json = codec.encode(export);
    if (!tempDirectory.existsSync()) {
      tempDirectory.createSync(recursive: true);
    }
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}${fileNameGenerator()}.json',
    );
    await file.writeAsBytes(utf8.encode(json), flush: true);
    await shareService.shareExportFile(file: file, caption: caption);
    return const AppResult<void>.success(null);
  }

  static String _defaultFileNameGenerator() {
    final random = math.Random.secure();
    final suffix = List<int>.generate(
      16,
      (_) => random.nextInt(16),
    ).map((n) => n.toRadixString(16)).join();
    return 'analysis-export-$suffix';
  }
}
