// The words the file-import boundary says when it produced no audio (R26).
//
// Kept next to the capture screens rather than inside the use case. The use
// case returns a TYPED outcome (`AudioFileImportOutcome`) and stays free of
// `AppLocalizations`; which sentence a given failure deserves is a
// presentation decision, and putting it here is what lets the use-case tests
// assert on codes instead of on English.

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/import_audio_file_use_case.dart';
import '../../data/input/input_limits.dart';

/// The sentence to show for [outcome], or null when there is nothing to say
/// (the user cancelled, or the import succeeded and the run has started).
///
/// Every branch names the REAL reason. A single "import failed" string would
/// be the same dead end the pre-R26 "not available yet" snackbar was: the
/// user could not tell a 70 MB file from an MP3 from a corrupt header.
String? analysisImportMessage(
  AppLocalizations l10n,
  AudioFileImportOutcome outcome,
) => switch (outcome) {
  AudioFileImportCancelled() || AudioFileImportReady() => null,
  AudioFileImportUnsupported() => l10n.analysisImportUnsupportedFormat,
  AudioFileImportFailed(:final failure) => _failureMessage(l10n, failure),
};

String _failureMessage(AppLocalizations l10n, AppFailure failure) =>
    switch (failure.code) {
      FailureCode.audioFileTooLarge => l10n.analysisImportFileTooLarge(
        InputLimits.maxFileBytes ~/ InputLimits.bytesPerMebibyte,
      ),
      FailureCode.audioClipTooShort => l10n.analysisImportClipTooShort,
      FailureCode.audioClipTooLong => l10n.analysisImportClipTooLong(
        InputLimits.maxDuration.inMinutes,
      ),
      // A `.wav` whose fmt chunk says MP3/24-bit/ADPCM is the same dead end
      // for the user as choosing an `.mp3` outright: the container cannot be
      // decoded on this device, and the fix is the same conversion.
      FailureCode.audioUnsupportedFormat ||
      FailureCode.audioUnsupportedBitDepth ||
      FailureCode.audioInvalidRiff ||
      FailureCode.audioInvalidSampleRate ||
      FailureCode.audioUnsupportedChannelCount =>
        l10n.analysisImportUnsupportedFormat,
      _ => l10n.analysisImportUnreadable,
    };
