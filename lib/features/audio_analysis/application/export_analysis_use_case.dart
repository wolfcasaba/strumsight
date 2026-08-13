import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:strumsight/core/foundation/app_failure.dart';
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
    Future<void> Function(File file, List<int> bytes)? fileWriter,
  }) : redactionPolicy = redactionPolicy ?? const RedactionPolicy(),
       codec = codec ?? const AnalysisExportCodec(),
       fileNameGenerator = fileNameGenerator ?? _defaultFileNameGenerator,
       fileWriter = fileWriter ?? _defaultFileWriter;

  final ShareService shareService;
  final Directory tempDirectory;
  final RedactionPolicy redactionPolicy;
  final AnalysisExportCodec codec;
  final String Function() fileNameGenerator;

  /// Writes [bytes] to [file]. Injectable so tests can force a write failure
  /// deterministically without relying on real disk-full/permission
  /// conditions.
  final Future<void> Function(File file, List<int> bytes) fileWriter;

  /// The redacted, allowlist-only view the preview screen renders. Pure —
  /// no I/O, so it is safe to call on every rebuild.
  AnalysisExport preview(AnalysisDocument document) =>
      redactionPolicy.apply(document);

  /// Writes the redacted export to a random-named temp file and shares it
  /// with [caption] through the existing [ShareService]. Must only be
  /// invoked after the user has confirmed the [preview].
  ///
  /// Cleanup covers the whole lifetime of the temp file, not just the share
  /// step (review MAJOR): if directory creation or the write itself fails,
  /// this method deletes whatever partial file resulted and returns a
  /// failure — the file never reaches [ShareService.shareExportFile]. Once
  /// the write succeeds, that method's own `try`/`finally` owns deleting the
  /// file on both the success and failure share outcomes; this method's
  /// contract with it is unchanged.
  Future<AppResult<void>> share({
    required AnalysisDocument document,
    required String caption,
  }) async {
    final export = redactionPolicy.apply(document);
    final json = codec.encode(export);
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}${fileNameGenerator()}.json',
    );
    try {
      if (!tempDirectory.existsSync()) {
        tempDirectory.createSync(recursive: true);
      }
      await fileWriter(file, utf8.encode(json));
    } catch (error, stackTrace) {
      if (file.existsSync()) {
        file.deleteSync();
      }
      return AppResult<void>.failure(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    await shareService.shareExportFile(file: file, caption: caption);
    return const AppResult<void>.success(null);
  }

  static Future<void> _defaultFileWriter(File file, List<int> bytes) =>
      file.writeAsBytes(bytes, flush: true);

  static String _defaultFileNameGenerator() {
    final random = math.Random.secure();
    final suffix = List<int>.generate(
      16,
      (_) => random.nextInt(16),
    ).map((n) => n.toRadixString(16)).join();
    return 'analysis-export-$suffix';
  }
}
